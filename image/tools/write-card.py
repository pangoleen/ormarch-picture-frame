#!/usr/bin/env python3
"""Write image/out/pf1007l-sd.img to a MicroSD card on macOS, with guards.

Usage (from the project root; the write needs sudo):
  python3 -I image/tools/write-card.py check diskN <exact-bytes>      # no sudo, no write
  sudo python3 -I image/tools/write-card.py write diskN <exact-bytes>

<exact-bytes> is the card's byte count from `diskutil info diskN` ("Disk Size").
It guards against a disk number that changed after an unplug or replug.

The script refuses the disk when one of these is true:
  - it is not a whole, external, removable USB disk
  - its size is not exactly <exact-bytes>
  - its size is the size of the frame's eMMC (15,634,268,160 bytes)
  - it is smaller than the image, or larger than 64 GiB
  - it is the FEL stub card (the stub is at 8 KiB) - use a SECOND card
  - the image does not match image/out/pf1007l-sd.img.sha256
After the write it reads the card back and compares the SHA-256.
"""

import hashlib
import os
import plistlib
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
IMAGE = HERE.parent / "out" / "pf1007l-sd.img"
IMAGE_SUM = HERE.parent / "out" / "pf1007l-sd.img.sha256"
EMMC_BYTES = 15_634_268_160          # the frame's eMMC as U-Boot `ums` shows it (E018)
MAX_BYTES = 64 * 1024**3
FEL_STUB_SHA256 = "2ccec08a026840571f3804671ba72afae840db27112a43f2b1f122075bc808bc"
FEL_STUB_OFFSET = 8192
FEL_STUB_SIZE = 8192
CHUNK = 4 * 1024 * 1024


def fail(message):
    sys.exit(f"STOP: {message}")


def disk_info(identifier):
    return plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", identifier]))


def check_disk(identifier, expected_size, image_size):
    if not identifier.startswith("disk") or not identifier[4:].isdigit():
        fail("pass a whole disk like disk4, not a partition and not a path")
    info = disk_info(identifier)
    if info.get("Internal", True):
        fail("the disk is not external")
    if not info.get("RemovableMedia") and not info.get("Removable"):
        fail("the disk is not removable media")
    if info.get("BusProtocol") not in ("USB", "Secure Digital"):
        fail(f"unexpected bus: {info.get('BusProtocol')}")
    if not info.get("WholeDisk"):
        fail("not a whole disk")
    size = info.get("TotalSize")
    if size != expected_size:
        fail(f"the disk has {size} bytes, you gave {expected_size}")
    if size == EMMC_BYTES:
        fail("this is the size of the frame's eMMC. This script never writes it.")
    if size < image_size:
        fail(f"the card ({size} bytes) is smaller than the image ({image_size} bytes)")
    if size > MAX_BYTES:
        fail("the disk is larger than 64 GiB: not a card for this project")
    if "UMS" in str(info.get("MediaName", "")) or "download gadget" in str(info.get("IORegistryEntryName", "")):
        fail("this is a disk that U-Boot shows over USB, not a card in a reader")
    print(f"disk: {identifier}, {size} bytes, {info.get('MediaName')!r}, bus {info.get('BusProtocol')}")
    return info


def image_digest():
    if not IMAGE.is_file() or not IMAGE_SUM.is_file():
        fail("no image: run image/build.sh first")
    expected = IMAGE_SUM.read_text().split()[0]
    digest = hashlib.sha256()
    with open(IMAGE, "rb") as handle:
        while block := handle.read(CHUNK):
            digest.update(block)
    if digest.hexdigest() != expected:
        fail("the image does not match pf1007l-sd.img.sha256")
    print(f"image: {IMAGE.stat().st_size} bytes, SHA-256 {expected}")
    return expected


def refuse_fel_stub(raw_path):
    fd = os.open(raw_path, os.O_RDONLY)
    try:
        # Raw devices need whole sectors: read 16 KiB from the start.
        head = os.pread(fd, FEL_STUB_OFFSET + FEL_STUB_SIZE, 0)
    finally:
        os.close(fd)
    stub = head[FEL_STUB_OFFSET:FEL_STUB_OFFSET + FEL_STUB_SIZE]
    if hashlib.sha256(stub).hexdigest() == FEL_STUB_SHA256:
        fail("this is the FEL stub card. Keep it. Use a second card for this image.")
    if stub[4:12] == b"eGON.BT0":
        print("note: the card already has an Allwinner boot header at 8 KiB (not the FEL stub). It will be replaced.")


def unmount(identifier):
    subprocess.check_call(["diskutil", "unmountDisk", identifier])
    for line in subprocess.check_output(["mount"], text=True).splitlines():
        if line.startswith(f"/dev/{identifier}s") or line.startswith(f"/dev/{identifier} "):
            fail(f"still mounted: {line}")


def write(raw_path, image_size):
    start = time.time()
    done = 0
    src = open(IMAGE, "rb")
    fd = os.open(raw_path, os.O_WRONLY)
    try:
        while block := src.read(CHUNK):
            if len(block) % 512:
                block += b"\0" * (512 - len(block) % 512)
            if os.write(fd, block) != len(block):
                fail(f"short write at byte {done}")
            done += len(block)
            if done % (256 * 1024 * 1024) < CHUNK:
                rate = done / max(time.time() - start, 0.1) / 1e6
                print(f"  written {done // 2**20} of {image_size // 2**20} MiB, {rate:.1f} MB/s", flush=True)
        os.fsync(fd)
    finally:
        os.close(fd)
        src.close()
    print(f"write done: {done} bytes in {time.time() - start:.0f} s")


def verify(raw_path, image_size, expected):
    digest = hashlib.sha256()
    left = image_size
    fd = os.open(raw_path, os.O_RDONLY)
    try:
        while left:
            block = os.read(fd, min(CHUNK, left))
            if not block:
                fail("short read from the card")
            digest.update(block)
            left -= len(block)
    finally:
        os.close(fd)
    if digest.hexdigest() != expected:
        fail("readback SHA-256 differs from the image. Do not use this card. Write it again or use another card.")
    print("readback: the card holds the image, SHA-256 equal")


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("check", "write"):
        sys.exit(__doc__)
    action, identifier = sys.argv[1], sys.argv[2]
    try:
        expected_size = int(sys.argv[3].replace(",", "").replace("_", ""))
    except ValueError:
        fail("the size must be a number of bytes")
    image_size = IMAGE.stat().st_size if IMAGE.is_file() else fail("no image: run image/build.sh first")
    if image_size % 512:
        fail("the image size is not a multiple of 512")
    check_disk(identifier, expected_size, image_size)
    expected = image_digest()
    if action == "check":
        print("check passed (the FEL stub test needs sudo and runs before the write). Nothing was written.")
        return
    if os.geteuid() != 0:
        fail("the write needs sudo")
    unmount(identifier)
    raw_path = f"/dev/r{identifier}"
    refuse_fel_stub(raw_path)
    # The disk can change between the check and the write: check it again.
    check_disk(identifier, expected_size, image_size)
    print(f"writing {IMAGE.name} to {raw_path} ...")
    write(raw_path, image_size)
    verify(raw_path, image_size, expected)
    subprocess.call(["diskutil", "eject", identifier])
    print("OK. The card is ejected. Put it in the frame (power off first).")


if __name__ == "__main__":
    main()
