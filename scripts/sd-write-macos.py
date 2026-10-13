#!/usr/bin/env python3
"""Write a boot image to a microSD card on macOS, with guards, then read it back and compare.

Usage (with sudo, because /dev/rdiskN needs root):
  sudo python3 -I scripts/sd-write-macos.py write <image-file> diskN <exact-card-bytes>

<exact-card-bytes> is the card size from `diskutil info diskN` (Disk Size, in bytes). It guards
against a disk number that changed. The script refuses:
  - a disk whose size is not exactly that number,
  - an internal disk, a disk that is not on USB, a disk that is not removable media,
  - the frame's own disks (media name "UMS disk N") and the FEL stub card (15,939,928,064 bytes),
  - an image that is larger than the card.
It writes the whole image, reads the same bytes back from the card, and compares the SHA-256.
"""

import hashlib
import os
import plistlib
import re
import subprocess
import sys
import time
from pathlib import Path

BLOCK = 4 * 1024 * 1024
FEL_STUB_CARD_BYTES = 15939928064


def fail(message):
    sys.exit(f"STOP: {message}")


def check_card(identifier, expected_size, image_size):
    if not re.fullmatch(r"disk\d+", identifier):
        fail("pass a whole disk like disk4, not a partition")
    info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", identifier]))
    name = info.get("MediaName", "")
    if re.fullmatch(r"UMS disk \d+", name):
        fail(f"{identifier} is a disk of the photo frame ({name!r}). Never write to it.")
    if info.get("TotalSize") != expected_size:
        fail(f"size {info.get('TotalSize')} != expected {expected_size}")
    if expected_size == FEL_STUB_CARD_BYTES:
        fail("this is the size of the FEL stub card. Use the second card.")
    if info.get("Internal", True):
        fail("disk is internal")
    if info.get("BusProtocol") != "USB":
        fail(f"unexpected protocol {info.get('BusProtocol')}")
    if not info.get("RemovableMedia") and not info.get("Removable"):
        fail("disk is not removable media")
    if not info.get("WholeDisk"):
        fail("not a whole disk")
    if not info.get("WritableMedia", False):
        fail("the card is write-protected")
    if image_size > expected_size:
        fail(f"the image ({image_size} bytes) is larger than the card ({expected_size} bytes)")
    print(f"Card: {identifier}, {name!r}, {expected_size} bytes. Image: {image_size} bytes.")
    subprocess.check_call(["diskutil", "unmountDisk", identifier])
    for line in subprocess.check_output(["mount"], text=True).splitlines():
        if line.startswith(f"/dev/{identifier}s") or line.startswith(f"/dev/{identifier} "):
            fail(f"still mounted: {line}")
    return f"/dev/r{identifier}"


def copy_and_hash(image, raw_path, size):
    digest, done, started = hashlib.sha256(), 0, time.time()
    fd = os.open(raw_path, os.O_WRONLY)
    try:
        with open(image, "rb") as source:
            while done < size:
                block = source.read(min(BLOCK, size - done))
                if not block:
                    fail(f"the image ended early at byte {done}")
                if len(block) % 512:
                    block += b"\0" * (512 - len(block) % 512)
                written = os.pwrite(fd, block, done)
                if written != len(block):
                    fail(f"short write at byte {done}")
                digest.update(block)
                done += len(block)
                rate = done / max(time.time() - started, 0.001) / 1e6
                print(f"\r  write: {min(done, size) * 100 // size:3d}%  {rate:5.1f} MB/s", end="", flush=True)
        os.fsync(fd)
    finally:
        os.close(fd)
    print()
    return digest.hexdigest(), done


def read_hash(raw_path, length):
    digest, done, started = hashlib.sha256(), 0, time.time()
    fd = os.open(raw_path, os.O_RDONLY)
    try:
        while done < length:
            block = os.pread(fd, min(BLOCK, length - done), done)
            if not block:
                fail(f"short read at byte {done}")
            digest.update(block)
            done += len(block)
            rate = done / max(time.time() - started, 0.001) / 1e6
            print(f"\r  read back: {done * 100 // length:3d}%  {rate:5.1f} MB/s", end="", flush=True)
    finally:
        os.close(fd)
    print()
    return digest.hexdigest()


def main():
    if len(sys.argv) != 5 or sys.argv[1] != "write":
        sys.exit(__doc__)
    if os.geteuid() != 0:
        fail("run with sudo")
    image, identifier, expected_size = Path(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    if not image.is_file():
        fail(f"no image file at {image}")
    image_size = image.stat().st_size
    raw_path = check_card(identifier, expected_size, image_size)
    written_hash, written = copy_and_hash(image, raw_path, image_size)
    back_hash = read_hash(raw_path, written)
    if back_hash != written_hash:
        fail("the card does not hold what was written. Do not use this card.")
    subprocess.call(["diskutil", "eject", identifier])
    print(f"Written and verified: {written} bytes on {identifier}. SHA-256 of the written bytes: {written_hash}")
    print("The card is ejected. Take it out of the reader.")


if __name__ == "__main__":
    main()
