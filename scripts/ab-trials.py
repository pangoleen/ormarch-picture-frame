#!/usr/bin/env python3
"""A/B trials for the U-Boot `ums` drop on the PF1007L. No sudo. Nothing is written to the frame.

Each trial loads a build over FEL and measures how long its USB gadget lives. The boot scripts
arm the hardware watchdog, so the frame comes back in FEL by itself when `ums` ends (E041).

Usage (from the project root):
  python3 -I -u scripts/ab-trials.py G 5 600      # 5 trials of build G, at most 600 s each
  python3 -I -u scripts/ab-trials.py --adopt 14:34:41 G 4 600
        # a build G run is already up since that time: watch it first, then run 4 more trials

Results are appended to dumps/raw/ab-trials.log.
"""

import importlib.util
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fc", ROOT / "scripts/frame-check.py")
fc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fc)
LOG = ROOT / "dumps/raw/ab-trials.log"


def emit(text):
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {text}"
    print(line, flush=True)
    with open(LOG, "a") as handle:
        handle.write(line + "\n")


def wait_for_fel(seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if fc.usb_state().endswith("FEL") and fc.fel_version():
            return True
        time.sleep(2)
    return False


def end_run():
    """Make a live `ums` end: eject its disks; the patch ends `ums` after 60 s with no command."""
    for disk, *_ in fc.ums_disks():
        subprocess.run(["diskutil", "eject", disk], capture_output=True)
    return wait_for_fel(150)


def watch(letter, started, cap, gadget_at=None):
    while time.time() - started < cap:
        state = fc.usb_state()
        if "gadget" in state and gadget_at is None:
            gadget_at = time.time() - started
        if state.endswith("FEL") and time.time() - started > 8:
            total = time.time() - started
            seen = f"gadget up after {gadget_at:.0f} s" if gadget_at is not None else "gadget NEVER seen"
            emit(f"build {letter}: {seen}; back in FEL after {total:.0f} s "
                 f"(ums ended about {max(total - 17, 0):.0f} s after the start)")
            return True
        time.sleep(1)
    emit(f"build {letter}: gadget still up at the cap of {cap} s. Ending the run by an eject.")
    if not end_run():
        emit("the frame did not come back in FEL after the eject. STOP.")
        return False
    return True


def trial(letter, cap):
    if not wait_for_fel(60):
        emit("not in FEL. STOP.")
        return False
    folder = fc.build_dir(letter)
    started = time.time()
    result = fc.fel("-p", "uboot", str(folder / "u-boot-sunxi-with-spl.bin"),
                    "write", "0x43100000", str(folder / "ums-readonly.scr"))
    if result.returncode != 0:
        emit(f"sunxi-fel failed: {result.stderr.strip()}. STOP.")
        return False
    return watch(letter, started, cap)


def main():
    args = sys.argv[1:]
    adopt = None
    if args[:1] == ["--adopt"]:
        adopt, args = args[1], args[2:]
    letter, count, cap = args[0].upper(), int(args[1]), int(args[2])
    emit(f"=== {count} trials of build {letter}, cap {cap} s" + (f", first adopt the run up since {adopt}" if adopt else ""))
    if adopt:
        today = time.strftime("%Y-%m-%d ")
        started = time.mktime(time.strptime(today + adopt, "%Y-%m-%d %H:%M:%S"))
        if not watch(letter, started, cap, gadget_at=0):
            return
    for number in range(1, count + 1):
        emit(f"trial {number} of build {letter}")
        if not trial(letter, cap):
            return
    emit("=== done")


if __name__ == "__main__":
    main()
