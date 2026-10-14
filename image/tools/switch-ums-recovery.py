#!/usr/bin/env python3
"""Switch only the PF1007L SD boot loader between read-only and writable UMS recovery.

Usage (macOS; requires sudo for enable/disable):
  python3 -I image/tools/switch-ums-recovery.py check diskN <exact-card-bytes>
  sudo python3 -I image/tools/switch-ums-recovery.py enable diskN <exact-card-bytes>
  sudo python3 -I image/tools/switch-ums-recovery.py disable diskN <exact-card-bytes>

EXPERIMENTAL: writable recovery enumerated and accepted a FAT-file write after
a physical replug. Software reboot/reset did not reliably re-enumerate it.
See docs/audio-recovery.md for the current rollback procedure.

The command writes a sector-aligned boot region at the Allwinner offset (8 KiB) on a
physical microSD card in a card reader.  It refuses the frame's USB-recovery
disk and every internal, non-removable, write-protected, incorrectly sized,
or unexpected boot-loader disk.  It never addresses eMMC: the U-Boot binary
has only MMC0 enabled, and UMS exports only that removable SD card.

The normal build remains read-only.  ``enable`` is an owner opt-in for cases
where a failed boot must be repaired through the frame's USB-recovery disk.
"""

from __future__ import annotations

import hashlib
import os
import plistlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UBOOT = ROOT / "image" / "work" / "uboot"
READ_ONLY = UBOOT / "u-boot-pf1007l-L.bin"
WRITABLE = UBOOT / "u-boot-pf1007l-L-rw-recovery.bin"
BACKUPS = UBOOT / "recovery-switch-backups"
OFFSET = 8 * 1024
SECTOR = 512
EMMC_BYTES = 15_634_268_160


def stop(message: str) -> None:
    raise SystemExit(f"STOP: {message}")


def info(identifier: str) -> dict:
    return plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", identifier]))


def check_card(identifier: str, expected_size: int) -> dict:
    if not re.fullmatch(r"disk\d+", identifier):
        stop("pass a whole disk such as disk12, not a partition or path")
    meta = info(identifier)
    if meta.get("Internal", True):
        stop("the disk is internal")
    if not meta.get("RemovableMedia") and not meta.get("Removable"):
        stop("the disk is not removable")
    if not meta.get("WholeDisk"):
        stop("the identifier is not a whole disk")
    if meta.get("TotalSize") != expected_size:
        stop(f"size {meta.get('TotalSize')} != expected {expected_size}")
    if expected_size == EMMC_BYTES:
        stop("this is the known eMMC size; never write it")
    if re.fullmatch(r"UMS disk \d+", str(meta.get("MediaName", ""))):
        stop("this is the frame's USB-recovery disk, not a card in a reader")
    if meta.get("BusProtocol") not in ("USB", "Secure Digital"):
        stop(f"unexpected bus {meta.get('BusProtocol')!r}")
    if not meta.get("WritableMedia", False):
        stop("the card is write-protected")
    return meta


def read_file(path: Path) -> bytes:
    if not path.is_file():
        stop(f"missing {path.relative_to(ROOT)}; see docs/audio-recovery.md before rebuilding")
    data = path.read_bytes()
    if not data:
        stop(f"invalid U-Boot artifact {path.name}")
    if data[4:12] != b"eGON.BT0":
        stop(f"{path.name} has no Allwinner boot header")
    return data


def current_loader(identifier: str, length: int) -> bytes:
    fd = os.open(f"/dev/r{identifier}", os.O_RDONLY)
    try:
        result = os.pread(fd, length, OFFSET)
    finally:
        os.close(fd)
    if len(result) != length:
        stop("short read from card boot area")
    return result


def name(data: bytes, ro: bytes, rw: bytes) -> str:
    if data == ro:
        return "read-only"
    if data == rw:
        return "writable"
    return "unexpected"


def unmount(identifier: str) -> None:
    subprocess.check_call(["diskutil", "unmountDisk", identifier])


def write_loader(identifier: str, original: bytes, target: bytes) -> None:
    BACKUPS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = BACKUPS / f"{identifier}-{stamp}-at-8KiB.bin"
    backup.write_bytes(original)
    unmount(identifier)
    fd = os.open(f"/dev/r{identifier}", os.O_WRONLY)
    try:
        written = os.pwrite(fd, target, OFFSET)
        if written != len(target):
            stop(f"short write: {written} of {len(target)} bytes")
        os.fsync(fd)
    finally:
        os.close(fd)
    actual = current_loader(identifier, len(target))
    if actual != target:
        stop("readback differs; do not boot the card")
    print(f"wrote and verified {len(target)} bytes at 8 KiB; backup: {backup.relative_to(ROOT)}")


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in ("check", "enable", "disable"):
        raise SystemExit(__doc__)
    action, identifier = sys.argv[1:3]
    try:
        expected_size = int(sys.argv[3].replace(",", "").replace("_", ""))
    except ValueError:
        stop("card size must be an integer number of bytes")

    ro = read_file(READ_ONLY)
    rw = read_file(WRITABLE)
    # A raw device is sector-addressed.  Pad both binaries to a shared sector
    # boundary, including the 64-byte size difference between these builds.
    region_size = (max(len(ro), len(rw)) + SECTOR - 1) // SECTOR * SECTOR
    ro_region = ro + b"\0" * (region_size - len(ro))
    rw_region = rw + b"\0" * (region_size - len(rw))
    meta = check_card(identifier, expected_size)
    actual = current_loader(identifier, region_size)
    state = name(actual, ro_region, rw_region)
    print(f"card: {identifier}, {meta.get('MediaName')!r}, {expected_size} bytes; loader: {state}")
    print(f"current SHA-256: {hashlib.sha256(actual).hexdigest()}")
    if action == "check":
        if state == "unexpected":
            stop("boot loader does not match the verified project binary")
        return
    if os.geteuid() != 0:
        stop("enable/disable needs sudo")
    if action == "enable":
        if state != "read-only":
            stop("enable requires the verified read-only loader")
        write_loader(identifier, actual, rw_region)
    else:
        if state != "writable":
            stop("disable requires the verified writable-recovery loader")
        write_loader(identifier, actual, ro_region)


if __name__ == "__main__":
    main()
