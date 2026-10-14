#!/usr/bin/env python3
"""PF1007L microphone test with prompts on the frame's own screen. Run as root in a terminal there.

It tells the person when to be quiet and when to clap, tap or speak, shows a live level bar for the
two codec microphone inputs (left = MIC1, right = MIC2) and the light sensor value, and ends with a
verdict for each round. The four rounds repeat until the window is closed. Log: /tmp/pf-mic-test.log. Needs the test device tree with the capture routes.
"""
import mmap
import os
import struct
import subprocess
import sys
import time

ROUNDS = [("BLOW gently into the corner hole", 5), ("TAP on the corner hole with a fingernail", 4),
          ("SPEAK with your mouth close to the corner hole", 5), ("CLAP your hands", 4)]
GREEN, RED, YELLOW, BOLD, OFF = "\033[1;32m", "\033[1;31m", "\033[1;33m", "\033[1m", "\033[0m"

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mem = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x01C22000)
struct.pack_into("<I", mem, 0x800, 0x00C00041)       # vendor LRADC mode (light sensor)
rec = subprocess.Popen(["arecord", "-q", "-D", "hw:0,0", "-f", "S16_LE", "-r", "16000", "-c", "2", "-t", "raw"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
log = open("/tmp/pf-mic-test.log", "a")
log.write(f"--- run {time.strftime('%H:%M:%S')}\n")


def sample():
    """0.2 s of audio: peak-to-peak of MIC1 and MIC2, and the light value."""
    raw = rec.stdout.read(3200 * 4)
    data = struct.unpack(f"<{len(raw) // 2}h", raw) if raw else (0, 0)
    left, right = data[0::2], data[1::2]
    return max(left) - min(left), max(right) - min(right), struct.unpack_from("<I", mem, 0x80C)[0] & 0x3F


def bar(value, full=6000, width=40):
    filled = min(value * width // full, width)
    return "[" + "#" * filled + " " * (width - filled) + "]"


def phase(title, colour, seconds, verdicts):
    peak1 = peak2 = 0
    end = time.time() + seconds
    while time.time() < end:
        m1, m2, light = sample()
        peak1, peak2 = max(peak1, m1), max(peak2, m2)
        left = end - time.time()
        # One write for the whole picture, cursor home and clear-to-end-of-line: no full clear, no flicker.
        rows = [f"{BOLD}PF1007L microphone test{OFF}", "", f"{colour}{title}{OFF}   {left:3.0f} s", "",
                f"MIC1 {m1:6d} {bar(m1)}", f"MIC2 {m2:6d} {bar(m2)}", f"LIGHT {light:2d}    {bar(light, 63)}", ""] + verdicts
        sys.stdout.write("\033[H" + "".join(row + "\033[K\n" for row in rows) + "\033[J")
        sys.stdout.flush()
    return peak1, peak2


time.sleep(0.3)
for _ in range(5):
    sample()                                        # drop the start click
run = 0
while True:
    run += 1
    verdicts = [f"Run {run}"]
    for number, (action, seconds) in enumerate(ROUNDS, 1):
        quiet1, quiet2 = phase(f"Round {number} of {len(ROUNDS)}: be QUIET", YELLOW, 3, verdicts)
        phase(f"Get ready to: {action}", YELLOW, 3, verdicts)
        loud1, loud2 = phase(f">>> NOW: {action} <<<", GREEN, seconds, verdicts)
        heard = max(loud1 / max(quiet1, 1), loud2 / max(quiet2, 1)) > 5 and max(loud1, loud2) > 400
        text = (f"Round {number} ({action}): quiet {quiet1}/{quiet2}, action {loud1}/{loud2} -> "
                + (f"{GREEN}HEARD{OFF}" if heard else f"{RED}nothing heard{OFF}"))
        verdicts.append(text)
        log.write(f"run {run} " + text + "\n")
        log.flush()
    phase("Run done. The next run starts by itself. Close this window to stop.", BOLD, 20, verdicts)
