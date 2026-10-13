#!/usr/bin/env python3
"""Checks for the PF1007L frame in FEL mode. No sudo. Nothing is written to the eMMC.

Usage (from the project root):
  python3 -I scripts/frame-check.py fel               # is the frame in FEL? print the chip line
  python3 -I scripts/frame-check.py memtest C         # DRAM test with the SPL of build C
  python3 -I scripts/frame-check.py memtest E nospl   # the same test, when the SPL ran before (after `stay`)
  python3 -I scripts/frame-check.py stay E 5          # run the SPL of build E, then check FEL each 5 s for 5 minutes
  python3 -I scripts/frame-check.py axp E 15          # run the SPL, then log the power chip's registers (read only)
  python3 -I scripts/frame-check.py load C            # start read-only U-Boot build C, list its disks
  python3 -I scripts/frame-check.py diag F 20         # load build F, make read load, and on a reset read U-Boot's log
  python3 -I scripts/frame-check.py readlog           # in FEL after a watchdog reset: read U-Boot's log from SRAM
  python3 -I scripts/frame-check.py watch             # log USB changes of the frame, one line per change

Builds: A (ZQ 15291, 8-bit), B (ZQ 15291, 4-bit), C (ZQ 31739, 8-bit), D (ZQ 31739, 4-bit),
E (= C + the vendor supply voltages: DCDC1 3.3 V, DCDC2 1.2 V, ALDO1 3.3 V),
F (= E + the diagnostics of wesbos issue #24: console log in SRAM, watchdog, read retries),
G (= the binary of F with a boot script that does NOT ignore CTRL+C; an A/B test).
ZQ 31739 is the value in this frame's own boot0. See docs/experiments.md E023/E024.

memtest runs only the SPL (DRAM setup), then uses FEL to write random data to DRAM,
copy it inside the frame, read it back and compare. It needs a fresh FEL start
(cable out, cable in) before it.
"""

import hashlib
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIAG = ROOT / "refs/photo-frame-dashboard/diagnostics"
FEL = DIAG / "sunxi-tools/sunxi-fel"
BUILDS = {"A": "a33-uboot-out", "B": "a33-uboot-out-4bit", "C": "a33-uboot-out-C", "D": "a33-uboot-out-D",
          "E": "a33-uboot-out-E", "F": "a33-uboot-out-F", "G": "a33-uboot-out-F-noctrlc"}
DRAM_BASE, DRAM_SIZE = 0x40000000, 0x40000000  # 1 GiB expected
MIB = 1024 * 1024


def fail(message):
    sys.exit(f"STOP: {message}")


def now():
    return time.strftime("%H:%M:%S")


def fel(*args, timeout=180):
    return subprocess.run([str(FEL), *args], capture_output=True, text=True, timeout=timeout)


def fel_read(address, length, path, piece=256 * 1024):
    """Read DRAM in 256 KiB pieces. sunxi-fel receives one read in a single USB transfer with a
    10 s limit, and FEL on the A33 gives about 190 kB/s, so a 2 MiB read times out and puts the
    FEL protocol out of step (E033)."""
    with open(path, "wb") as out:
        for offset in range(0, length, piece):
            part = Path(str(path) + ".part")
            result = fel("read", hex(address + offset), str(min(piece, length - offset)), str(part))
            if result.returncode != 0:
                return result
            out.write(part.read_bytes())
    return result


def fel_version():
    result = fel("version", timeout=15)
    return result.stdout.strip() if result.returncode == 0 else None


def build_dir(letter):
    if letter not in BUILDS:
        fail(f"unknown build {letter!r}; use one of {', '.join(BUILDS)}")
    path = DIAG / BUILDS[letter]
    if not (path / "u-boot-sunxi-with-spl.bin").exists():
        fail(f"{path} has no U-Boot binary")
    return path


def require_fel():
    version = fel_version()
    if not version:
        fail("the frame is not in FEL. Cable out, check that the stub card is in, cable in.")
    print(f"{now()} FEL: {version}")
    if "soc=00001667(A33)" not in version:
        fail("this is not the A33 answer that we expect")


def usb_state():
    """Return a short text for the frame's USB identity, or 'absent'."""
    tree = subprocess.run(["ioreg", "-p", "IOUSB", "-l", "-w0"], capture_output=True, text=True).stdout
    blocks = re.split(r"\n(?=\s*[|+ ]*\+-o )", tree)
    for block in blocks:
        if '"idVendor" = 7994' in block:
            product = re.search(r'"idProduct" = (\d+)', block)
            name = re.search(r'"USB Product Name" = "([^"]*)"', block)
            pid = int(product.group(1)) if product else 0
            label = {0xEFE8: "FEL", 0x1000: "Android", 0x1002: "Android+ADB"}.get(pid, name.group(1) if name else "?")
            return f"1f3a:{pid:04x} {label}"
        if '"USB Product Name" = "USB download gadget"' in block:
            return "U-Boot gadget (ums)"
    return "absent"


def ums_disks():
    listing = subprocess.run(["diskutil", "list", "-plist", "external", "physical"], capture_output=True).stdout
    found = []
    for disk in plistlib.loads(listing).get("WholeDisks", []):
        info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", disk]))
        if re.fullmatch(r"UMS disk \d+", info.get("MediaName", "")):
            found.append((disk, info["MediaName"], info["TotalSize"], not info.get("WritableMedia", True)))
    return found


def cmd_fel():
    require_fel()


def cmd_memtest(letter, run_spl=True):
    binary = build_dir(letter) / "u-boot-sunxi-with-spl.bin"
    require_fel()
    if run_spl:
        print(f"{now()} run the SPL of build {letter} (DRAM setup only)")
        result = fel("spl", str(binary))
        if result.returncode != 0:
            fail(f"sunxi-fel spl failed: {result.stderr.strip()}")
        if not fel_version():
            fail("the frame did not return to FEL after the SPL. The DRAM setup probably failed.")
        print(f"{now()} the SPL returned to FEL")
    else:
        print(f"{now()} no SPL run: the SPL of build {letter} ran before, in this power cycle")

    errors = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        # Test 1: a different random block at 5 addresses. Write all, then read all.
        # A wrong DRAM size shows here as two addresses that hold the same data.
        addresses = [0x42000000, 0x50000000, 0x60000000, 0x70000000, 0x7F000000]
        blocks = {}
        started = time.time()
        for address in addresses:
            data = os.urandom(2 * MIB)
            (tmp / "w.bin").write_bytes(data)
            if fel("write", hex(address), str(tmp / "w.bin")).returncode != 0:
                fail(f"FEL write failed at {address:#x}")
            blocks[address] = hashlib.sha256(data).hexdigest()
        for address in addresses:
            result = fel_read(address, 2 * MIB, tmp / "r.bin")
            if result.returncode != 0:
                fail(f"FEL read failed at {address:#x}: {result.stderr.strip()} (USB state: {usb_state()})")
            ok = hashlib.sha256((tmp / "r.bin").read_bytes()).hexdigest() == blocks[address]
            errors += not ok
            print(f"  {address:#010x}  2 MiB  {'ok' if ok else 'DIFFERENT'}")
        rate = 2 * len(addresses) * 2 * MIB / (time.time() - started) / 1e3
        print(f"{now()} test 1 done ({rate:.0f} kB/s over FEL)")

        # Test 2: copy an 8 MiB random block through 24 places inside the frame, then read the last.
        data = os.urandom(8 * MIB)
        (tmp / "w.bin").write_bytes(data)
        want = hashlib.sha256(data).hexdigest()
        source = 0x44000000
        if fel("write", hex(source), str(tmp / "w.bin")).returncode != 0:
            fail("FEL write failed for test 2")
        for hop in range(1, 25):
            target = 0x44000000 + hop * 0x02000000  # 32 MiB steps, up to 0x74000000
            if fel("memmove", hex(target), hex(source), hex(8 * MIB)).returncode != 0 or not fel_version():
                fail(f"copy {hop} to {target:#x} failed or the frame left FEL")
            source = target
        if fel_read(source, 8 * MIB, tmp / "r.bin").returncode != 0:
            fail("FEL read failed for test 2")
        ok = hashlib.sha256((tmp / "r.bin").read_bytes()).hexdigest() == want
        errors += not ok
        print(f"  24 copies of 8 MiB across the DRAM: {'ok' if ok else 'DIFFERENT'}")

    print(f"{now()} MEMTEST build {letter}: {'PASS' if not errors else f'FAIL ({errors} blocks differ)'}")
    sys.exit(1 if errors else 0)


def cmd_stay(letter, minutes):
    """Run only the SPL, then ask FEL for its version each 5 s. FEL does not use the DRAM,
    so a hang here points to the clocks or the supply voltages that the SPL sets, or to power."""
    binary = build_dir(letter) / "u-boot-sunxi-with-spl.bin"
    require_fel()
    started = time.time()
    result = fel("spl", str(binary))
    if result.returncode != 0:
        fail(f"sunxi-fel spl failed: {result.stderr.strip()}")
    print(f"{now()} the SPL of build {letter} ran. Now a FEL check each 5 s for {minutes} min.")
    deadline = started + minutes * 60
    while time.time() < deadline:
        try:
            alive = fel_version() is not None
        except subprocess.TimeoutExpired:
            alive = False
        if not alive:
            print(f"{now()} STAY build {letter}: FAIL. FEL stopped {time.time() - started:.0f} s after the SPL. "
                  f"USB state: {usb_state()}")
            sys.exit(1)
        time.sleep(5)
    print(f"{now()} STAY build {letter}: PASS. FEL answered for {minutes} min after the SPL.")


RSB = 0x01F03400          # R_RSB controller of the A33
AXP_RT_ADDR = 0x2D        # runtime address that U-Boot's SPL gives the AXP223
AXP_ONCE = [0x00, 0x01, 0x02, 0x03, 0x10, 0x12, 0x13, 0x21, 0x22, 0x23, 0x24, 0x25, 0x30, 0x31, 0x32,
            0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x82, 0x84, 0x8F,
            0x90, 0x92, 0x94]
AXP_POLL = [0x00, 0x01, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x56, 0x57, 0x7A, 0x7B, 0x7C, 0x7D, 0x90, 0x94]


def axp_read(register):
    """Read one AXP register over RSB with FEL readl/writel. Read only: no PMIC write.
    The SPL must have run before (it sets up the RSB pins, clock and the runtime address)."""
    result = fel("writel", hex(RSB + 0x0C), "0x7",                       # clear old status flags
                 "writel", hex(RSB + 0x30), hex(AXP_RT_ADDR << 16),
                 "writel", hex(RSB + 0x10), hex(register),
                 "writel", hex(RSB + 0x2C), "0x8b",                      # RSB_CMD_BYTE_READ
                 "writel", hex(RSB + 0x00), "0x80",                      # RSB_CTRL_START_TRANS
                 "readl", hex(RSB + 0x0C), "readl", hex(RSB + 0x1C), timeout=20)
    if result.returncode != 0:
        return None
    status, data = (int(line, 16) for line in result.stdout.split()[:2])
    if status & 0x7 != 0x1:                                              # transfer over, no error
        return -status
    return data & 0xFF


def cmd_axp(letter, minutes):
    """Run the SPL, then log AXP223 registers until the time ends or the frame stops."""
    binary = build_dir(letter) / "u-boot-sunxi-with-spl.bin"
    require_fel()
    started = time.time()
    result = fel("spl", str(binary))
    if result.returncode != 0:
        fail(f"sunxi-fel spl failed: {result.stderr.strip()}")
    log = ROOT / "dumps/raw/axp-telemetry.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "a") as handle:
        def emit(text):
            print(text, flush=True)
            handle.write(text + "\n")
            handle.flush()
        emit(f"# {time.strftime('%Y-%m-%d %H:%M:%S')} SPL of build {letter} ran; AXP registers over RSB (hex)")
        once = {register: axp_read(register) for register in AXP_ONCE}
        emit("once " + " ".join(f"{r:02x}={'??' if v is None else (f'{v:02x}' if v >= 0 else f'ERR{-v:x}')}"
                                for r, v in once.items()))
        deadline = started + minutes * 60
        while time.time() < deadline:
            values = {register: axp_read(register) for register in AXP_POLL}
            elapsed = time.time() - started
            if all(v is None for v in values.values()):
                emit(f"{now()} t={elapsed:5.0f}s  NO ANSWER. USB state: {usb_state()}")
                emit(f"AXP build {letter}: the frame stopped {elapsed:.0f} s after the SPL")
                sys.exit(1)
            text = " ".join(f"{r:02x}={'??' if v is None else (f'{v:02x}' if v >= 0 else f'ERR{-v:x}')}"
                            for r, v in values.items())
            temp = ""
            if values.get(0x56) is not None and values.get(0x57) is not None and values[0x56] >= 0:
                raw = (values[0x56] << 4) | (values[0x57] & 0x0F)
                temp = f"  die-temp raw={raw} (about {raw * 0.1 - 267:.0f} C if the AXP22x formula applies)"
            emit(f"{now()} t={elapsed:5.0f}s  {text}{temp}")
            time.sleep(4)
        emit(f"AXP build {letter}: still alive after {minutes} min")


def cmd_load(letter):
    folder = build_dir(letter)
    require_fel()
    print(f"{now()} load build {letter}")
    result = fel("-v", "-p", "uboot", str(folder / "u-boot-sunxi-with-spl.bin"),
                 "write", "0x43100000", str(folder / "ums-readonly.scr"))
    if result.returncode != 0:
        fail(f"sunxi-fel failed: {result.stderr.strip()}")
    deadline = time.time() + 60
    while time.time() < deadline:
        disks = ums_disks()
        if len(disks) >= 2:
            break
        time.sleep(2)
    else:
        fail(f"no two UMS disks after 60 s. USB state: {usb_state()}")
    print(f"{now()} U-Boot is up. USB state: {usb_state()}")
    for disk, name, size, read_only in disks:
        print(f"  {disk}  {name}  {size} bytes  read-only: {'yes' if read_only else 'NO'}")
    if not all(read_only for *_, read_only in disks):
        fail("a disk is writable. Do not continue.")
    emmc = [d for d in disks if d[2] == 15634268160]
    if len(emmc) == 1:
        print(f"\nThe eMMC is {emmc[0][0]}. Backup command (needs your password):\n"
              f"  sudo python3 -I {ROOT}/scripts/emmc-backup-resumable.py backup {emmc[0][0]} 15634268160 "
              f"/Volumes/FRAME_BACKUP/omarchy-frame-backups/run2")


def read_sram_log():
    """Read build F's console log from SRAM A2 (0x48000, 16 KiB). Needs FEL, before a new U-Boot load."""
    out = ROOT / "dumps/raw" / f"uboot-sram-log-{time.strftime('%H%M%S')}.bin"
    out.parent.mkdir(parents=True, exist_ok=True)
    result = fel("read", "0x48000", "0x4000", str(out), timeout=60)
    if result.returncode != 0:
        print(f"{now()} the SRAM log read failed: {result.stderr.strip()}")
        return
    data = out.read_bytes()
    text = "".join(chr(b) if b in (10, 13) or 32 <= b < 127 else "" for b in data).replace("\r", "\n")
    lines = [line for line in text.split("\n") if line.strip()]
    print(f"{now()} U-Boot console log from SRAM ({len(lines)} lines, raw file {out.name}):")
    for line in lines[-70:]:
        print("   | " + line[:160])


def read_load(stop):
    """Make eMMC and USB read traffic with no sudo: read the files of the FAT volumes that macOS
    mounted read-only from the frame, with the file cache off. Nothing is stored."""
    import fcntl
    total = 0
    while not stop["flag"]:
        roots = [Path("/Volumes/Volumn"), Path("/Volumes/FELCARD")]
        files = [f for r in roots if r.is_dir() for f in r.rglob("*") if f.is_file()]
        if not files:
            time.sleep(2)
            continue
        for path in files:
            if stop["flag"]:
                break
            try:
                fd = os.open(path, os.O_RDONLY)
                fcntl.fcntl(fd, 48, 1)                      # F_NOCACHE
                while True:
                    block = os.read(fd, 1024 * 1024)
                    if not block:
                        break
                    total += len(block)
                os.close(fd)
            except OSError:
                time.sleep(1)
        stop["bytes"] = total


def cmd_diag(letter, minutes):
    import threading
    cmd_load(letter)
    stop = {"flag": False, "bytes": 0}
    threading.Thread(target=read_load, args=(stop,), daemon=True).start()
    started, last, gone_since = time.time(), None, None
    while time.time() - started < minutes * 60:
        state = usb_state()
        if state != last:
            print(f"{now()} t={time.time() - started:4.0f}s  USB: {state}  (read load so far: {stop['bytes'] >> 20} MiB)", flush=True)
            last = state
        if state.endswith("FEL"):
            stop["flag"] = True
            print(f"{now()} DIAG: the frame came back in FEL by itself (watchdog reset). Not a power loss.")
            read_sram_log()
            return
        if state == "absent":
            gone_since = gone_since or time.time()
            if time.time() - gone_since > 45:
                stop["flag"] = True
                print(f"{now()} DIAG: no USB device for 45 s. The watchdog did not bring FEL back: "
                      f"power loss, or a state that the watchdog cannot leave.")
                return
        else:
            gone_since = None
        time.sleep(2)
    stop["flag"] = True
    print(f"{now()} DIAG: build {letter} stayed up for {minutes} min with {stop['bytes'] >> 20} MiB of read load.")


def cmd_watch():
    log = ROOT / "dumps/raw/usb-watch.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    last = None
    with open(log, "a") as handle:
        while True:
            state = usb_state()
            if state != last:
                line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {state}"
                print(line, flush=True)
                handle.write(line + "\n")
                handle.flush()
                last = state
            time.sleep(1)


def main():
    args = sys.argv[1:]
    if args == ["fel"]:
        cmd_fel()
    elif len(args) in (2, 3) and args[0] == "memtest" and args[2:] in ([], ["nospl"]):
        cmd_memtest(args[1].upper(), run_spl=len(args) == 2)
    elif len(args) == 3 and args[0] == "stay":
        cmd_stay(args[1].upper(), float(args[2]))
    elif len(args) == 3 and args[0] == "axp":
        cmd_axp(args[1].upper(), float(args[2]))
    elif len(args) == 3 and args[0] == "diag":
        cmd_diag(args[1].upper(), float(args[2]))
    elif args == ["readlog"]:
        require_fel()
        read_sram_log()
    elif len(args) == 2 and args[0] == "load":
        cmd_load(args[1].upper())
    elif args == ["watch"]:
        cmd_watch()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
