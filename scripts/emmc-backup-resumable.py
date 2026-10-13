#!/usr/bin/env python3
"""Back up the PF1007L eMMC in chunks, through the read-only U-Boot `ums` disk (macOS).

A drop of the USB disk loses one chunk, not the whole run. Run it again to resume.
It only reads the disk. The guards are the ones of Wes Bos's emmc-macos.py.

Usage (with sudo, because /dev/rdiskN needs root):
  sudo python3 -I scripts/emmc-backup-resumable.py backup   diskN <exact-bytes> <out-dir>
       python3 -I scripts/emmc-backup-resumable.py status   <out-dir>
       python3 -I scripts/emmc-backup-resumable.py assemble <out-dir>
       python3 -I scripts/emmc-backup-resumable.py compare  <out-dir> <control-file>

backup    reads each 256 MiB chunk two times, compares the two reads, rejects 0xCC
          filler, then stores the chunk and its SHA-256 in manifest.json.
status    shows which chunks are done.
assemble  checks every chunk against the manifest, then writes a33-emmc-full.img,
          a33-emmc-full.img.gz and a33-emmc-full.sha256 (the names Wes's tools use).
compare   checks that <control-file> equals the start of the backup.
"""

import gzip
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

CHUNK = 256 * 1024 * 1024
BLOCK = 4 * 1024 * 1024
FILLER_RUN = 4096


def fail(message):
    sys.exit(f"STOP: {message}")


def open_disk(identifier, expected_size):
    if not re.fullmatch(r"disk\d+", identifier):
        fail("pass a whole disk like disk4, not a partition")
    info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", identifier]))
    if not re.fullmatch(r"UMS disk \d+", info.get("MediaName", "")):
        fail(f"unexpected media name {info.get('MediaName')!r}; expected U-Boot's 'UMS disk N'")
    if info.get("TotalSize") != expected_size:
        fail(f"size {info.get('TotalSize')} != expected {expected_size}")
    if info.get("Internal", True) or info.get("BusProtocol") != "USB":
        fail("not an external USB disk")
    if info.get("WritableMedia", True):
        fail("disk is writable; the read-only U-Boot build is not the one running")
    subprocess.check_call(["diskutil", "unmountDisk", identifier])
    return f"/dev/r{identifier}"


def load_manifest(out_dir, size=None):
    path = out_dir / "manifest.json"
    if path.exists():
        manifest = json.loads(path.read_text())
        if size is not None and manifest["size"] != size:
            fail(f"manifest is for a disk of {manifest['size']} bytes, not {size}")
        return manifest
    if size is None:
        fail(f"no manifest.json in {out_dir}")
    return {"size": size, "chunk": CHUNK, "chunks": {}}


def save_manifest(out_dir, manifest):
    tmp = out_dir / "manifest.json.tmp"
    with open(tmp, "w") as handle:
        json.dump(manifest, handle, indent=1, sort_keys=True)
        handle.flush()
        os.fsync(handle.fileno())
    tmp.rename(out_dir / "manifest.json")


def chunk_ranges(size):
    return [(index, offset, min(CHUNK, size - offset))
            for index, offset in enumerate(range(0, size, CHUNK))]


def chunk_path(out_dir, index):
    return out_dir / f"chunk-{index:04d}.bin"


def read_range(fd, offset, length, sink=None):
    """Read [offset, offset+length) from the raw disk. Return (sha256, 0xCC run count)."""
    digest, filler, done = hashlib.sha256(), 0, 0
    while done < length:
        block = os.pread(fd, min(BLOCK, length - done), offset + done)
        if not block:
            raise OSError(f"short read at byte {offset + done}")
        digest.update(block)
        filler += block.count(b"\xcc" * FILLER_RUN)
        if sink:
            sink.write(block)
        done += len(block)
    return digest.hexdigest(), filler


def backup(identifier, size, out_dir):
    if os.geteuid() != 0:
        fail("run with sudo")
    raw_path = open_disk(identifier, size)
    out_dir.mkdir(parents=True, exist_ok=True)
    os.umask(0o077)
    manifest = load_manifest(out_dir, size)
    ranges = chunk_ranges(size)
    todo = [r for r in ranges if str(r[0]) not in manifest["chunks"]]
    print(f"{len(ranges) - len(todo)} of {len(ranges)} chunks are done. {len(todo)} to read.")

    fd = os.open(raw_path, os.O_RDONLY)
    started, read_bytes = time.time(), 0
    try:
        for index, offset, length in todo:
            partial = out_dir / f"chunk-{index:04d}.partial"
            try:
                with open(partial, "wb") as sink:
                    first, filler = read_range(fd, offset, length, sink)
                    sink.flush()
                    os.fsync(sink.fileno())
                second, _ = read_range(fd, offset, length)
            except OSError as error:
                partial.unlink(missing_ok=True)
                fail(f"the disk left at chunk {index} ({error}). Nothing of this chunk is kept. "
                     f"Replug the frame, load U-Boot again, then run this command again: it resumes here.")
            if filler:
                partial.unlink()
                fail(f"0xCC filler found in chunk {index}; this may not be real flash data")
            if first != second:
                partial.unlink()
                fail(f"chunk {index}: the two reads differ. The reads are not stable.")
            stored = hashlib.sha256()
            with open(partial, "rb") as handle:
                for block in iter(lambda: handle.read(BLOCK), b""):
                    stored.update(block)
            if stored.hexdigest() != first:
                partial.unlink()
                fail(f"chunk {index}: the file on the backup disk differs from the read")
            partial.rename(chunk_path(out_dir, index))
            manifest["chunks"][str(index)] = {"offset": offset, "length": length, "sha256": first}
            save_manifest(out_dir, manifest)
            read_bytes += 2 * length
            rate = read_bytes / max(time.time() - started, 0.001) / 1e6
            left = (len(todo) - todo.index((index, offset, length)) - 1) * 2 * CHUNK / 1e6 / max(rate, 0.01)
            print(f"  chunk {index + 1:3d}/{len(ranges)} ok  {rate:5.1f} MB/s  about {left / 60:4.0f} min left", flush=True)
    finally:
        os.close(fd)
    print("All chunks are read two times and stored. Next: the `assemble` command.")


def verify_chunks(out_dir, manifest):
    """Check every chunk file against the manifest. Return the SHA-256 of the whole image."""
    whole = hashlib.sha256()
    for index, offset, length in chunk_ranges(manifest["size"]):
        entry = manifest["chunks"].get(str(index))
        if not entry:
            fail(f"chunk {index} is missing; run `backup` again")
        digest, done = hashlib.sha256(), 0
        with open(chunk_path(out_dir, index), "rb") as handle:
            for block in iter(lambda: handle.read(BLOCK), b""):
                digest.update(block)
                whole.update(block)
                done += len(block)
        if done != length or digest.hexdigest() != entry["sha256"]:
            fail(f"chunk {index} does not match the manifest")
    return whole.hexdigest()


def status(out_dir):
    manifest = load_manifest(out_dir)
    ranges = chunk_ranges(manifest["size"])
    done = [r for r in ranges if str(r[0]) in manifest["chunks"]]
    print(f"{len(done)} of {len(ranges)} chunks done ({sum(r[2] for r in done)} of {manifest['size']} bytes).")
    missing = [r[0] for r in ranges if str(r[0]) not in manifest["chunks"]]
    if missing:
        print("First missing chunk:", missing[0])


def assemble(out_dir):
    manifest = load_manifest(out_dir)
    image, gzip_path = out_dir / "a33-emmc-full.img", out_dir / "a33-emmc-full.img.gz"
    for path in (image, gzip_path):
        if path.exists():
            fail(f"{path.name} already exists; refusing to overwrite")
    os.umask(0o077)
    expected = verify_chunks(out_dir, manifest)
    print("Every chunk matches the manifest. Whole-image SHA-256 is computed.")
    partial = out_dir / "a33-emmc-full.img.partial"
    with open(partial, "wb") as target:
        for index, _, _ in chunk_ranges(manifest["size"]):
            with open(chunk_path(out_dir, index), "rb") as source:
                shutil.copyfileobj(source, target, BLOCK)
        target.flush()
        os.fsync(target.fileno())
    check = hashlib.sha256()
    with open(partial, "rb") as source, gzip.open(gzip_path, "xb", compresslevel=6) as target:
        for block in iter(lambda: source.read(BLOCK), b""):
            check.update(block)
            target.write(block)
    if check.hexdigest() != expected or partial.stat().st_size != manifest["size"]:
        fail("the assembled image differs from the chunks")
    readback = hashlib.sha256()
    with gzip.open(gzip_path, "rb") as handle:
        for block in iter(lambda: handle.read(BLOCK), b""):
            readback.update(block)
    if readback.hexdigest() != expected:
        fail("gzip readback differs")
    partial.rename(image)
    (out_dir / "a33-emmc-full.sha256").write_text(f"{expected}  {image.name}\n")
    print(f"Verified full eMMC backup: {image} ({manifest['size']} bytes). The SHA-256 is in a33-emmc-full.sha256.")
    print("Keep it private. The chunk files can be deleted when a second copy of the gzip exists.")


def compare(out_dir, control):
    manifest = load_manifest(out_dir)
    left, position = control.stat().st_size, 0
    with open(control, "rb") as handle:
        for index, offset, length in chunk_ranges(manifest["size"]):
            if left <= 0:
                break
            if str(index) not in manifest["chunks"]:
                fail(f"chunk {index} is not in the backup yet")
            with open(chunk_path(out_dir, index), "rb") as chunk:
                while left > 0:
                    mine = chunk.read(min(BLOCK, left))
                    if not mine:
                        break
                    theirs = handle.read(len(mine))
                    if mine != theirs:
                        bad = next(i for i, (a, b) in enumerate(zip(mine, theirs)) if a != b)
                        fail(f"difference at byte {position + bad}")
                    position += len(mine)
                    left -= len(mine)
    print(f"Equal: the first {position} bytes of the backup are the control file.")


def main():
    args = sys.argv[1:]
    if len(args) == 4 and args[0] == "backup":
        backup(args[1], int(args[2]), Path(args[3]))
    elif len(args) == 2 and args[0] == "status":
        status(Path(args[1]))
    elif len(args) == 2 and args[0] == "assemble":
        assemble(Path(args[1]))
    elif len(args) == 3 and args[0] == "compare":
        compare(Path(args[1]), Path(args[2]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
