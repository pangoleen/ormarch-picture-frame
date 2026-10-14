#!/usr/bin/env python3
"""PF1007L sensor hunt, live view. Run on the frame as root, in a terminal on the frame's own screen.

Shows four times a second:
  LIGHT  the raw value of the A33 key-voltage converter (LRADC0, 0..63), which the vendor driver
         sunxi-keyboard.ko reports as the light sensor
  MIC1 / MIC2  the peak level of the two codec microphone inputs (left = MIC1, right = MIC2)
Every line also goes to /tmp/pf-hunt-live.log. Needs the test device tree with the capture routes.
"""
import mmap
import os
import struct
import subprocess
import sys
import time

VENDOR_CTRL = 0x00C00041  # what sunxi-keyboard.ko writes: enable, hold, both channels

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mem = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x01C22000)
struct.pack_into("<I", mem, 0x800, VENDOR_CTRL)

rec = subprocess.Popen(
    ["arecord", "-q", "-D", "hw:0,0", "-f", "S16_LE", "-r", "16000", "-c", "2", "-t", "raw"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
log = open("/tmp/pf-hunt-live.log", "a")
chunk = 4000 * 4  # 0.25 s of stereo 16-bit
lo, hi = 63, 0
start = time.time()
while True:
    raw = rec.stdout.read(chunk) if rec.poll() is None else b""
    if raw:
        data = struct.unpack(f"<{len(raw) // 2}h", raw)
        left, right = data[0::2], data[1::2]
        m1 = max(left) - min(left)
        m2 = max(right) - min(right)
    else:
        m1 = m2 = -1
        time.sleep(0.25)
    light = struct.unpack_from("<I", mem, 0x80C)[0] & 0x3F
    lo, hi = min(lo, light), max(hi, light)
    bar = "#" * min(max(m1, m2) // 200, 40)
    line = f"{time.time() - start:6.1f}s  LIGHT {light:2d} (seen {lo}..{hi})   MIC1 {m1:5d}  MIC2 {m2:5d}  {bar}"
    print(line, flush=True)
    log.write(line + "\n")
    log.flush()
