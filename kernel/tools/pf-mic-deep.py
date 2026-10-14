#!/usr/bin/env python3
"""PF1007L deep microphone test. Run on the frame as root, with PipeWire stopped and the capture
routes in the device tree. Needs no person: the frame's own speaker is the sound source.

For each input of the A33 analog codec (MIC1, MIC2, PHONE pins, and "none" as the control) it records
while the speaker plays five loud tones, then it toggles the two microphone bias supplies during a
recording (a fitted capsule gives a large step, an empty input gives none).
The PHONE inputs have no mainline control, so the two ADC mixer registers are written directly
through the PRCM register port. Output: /tmp/deep_*.wav and /tmp/deep_times.txt.

WARNING: these direct writes are not locked against the kernel driver. In the one run on the frame a
value landed in a wrong register and two recordings were spoiled (docs/experiments.md E067). Check the
register dump after a run and reboot. Do not use it on a frame in daily use.
"""
import mmap
import os
import struct
import subprocess
import time

PRCM_PAGE, ADDA = 0x01F01000, 0x5C0
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mem = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=PRCM_PAGE)
rd = lambda: struct.unpack_from("<I", mem, ADDA)[0]
wr = lambda v: struct.pack_into("<I", mem, ADDA, v)


def adda_read(addr):
    v = rd() | (1 << 28)
    wr(v)
    wr((v & ~(0x1F << 16)) | (addr << 16))
    return rd() & 0xFF


def adda_write(addr, value):
    v = rd() | (1 << 28)
    v = (v & ~(0x1F << 16)) | (addr << 16)
    wr(v)
    v = (v & ~(0xFF << 8)) | (value << 8)
    wr(v)
    wr(v | (1 << 24))
    wr(v & ~(1 << 24))


def mixer(name, value):
    subprocess.run(["amixer", "-q", "-c0", "cset", f"name={name}", value], check=False)


def record(path, seconds):
    return subprocess.Popen(["arecord", "-q", "-D", "hw:0,0", "-f", "S16_LE", "-r", "16000", "-c", "2",
                             "-d", str(seconds), path], stderr=subprocess.DEVNULL)


for name, value in (("AIF1 Slot 0 Digital ADC Capture Switch", "off,off"), ("AIF1 Data Digital ADC Capture Switch", "on,on"),
                    ("Mixer Capture Switch", "off,off"), ("Mixer Reversed Capture Switch", "off,off"),
                    ("Mic1 Boost Volume", "7"), ("Mic2 Boost Volume", "7"), ("ADC Gain Capture Volume", "7"),
                    ("ADC Capture Volume", "160,160"), ("AIF1 AD0 Capture Volume", "160,160"),
                    ("AIF1 Slot 0 Digital DAC Playback Switch", "on,on"), ("Headphone Playback Volume", "55"),
                    # Line In stays on in every run: it keeps the ADC path powered and it is quiet.
                    ("Line In Capture Switch", "on,on"), ("Mic1 Capture Switch", "on,on"), ("Mic2 Capture Switch", "on,on")):
    mixer(name, value)

times = open("/tmp/deep_times.txt", "w")
# ADC mixer source bits: 6 MIC1, 5 MIC2, 4 PHONEP-PHONEN, 3 PHONE single, 2 LINE IN.
CONFIGS = [("none", 0x04), ("mic1", 0x44), ("mic2", 0x24), ("phone", 0x1C), ("all", 0x7C)]
for label, bits in CONFIGS:
    rec = record(f"/tmp/deep_{label}.wav", 8)
    time.sleep(0.8)
    adda_write(0x0C, bits)
    adda_write(0x0D, bits)
    got = (adda_read(0x0C), adda_read(0x0D), adda_read(0x0A), adda_read(0x0B), adda_read(0x0F))
    times.write(f"{label}: 0c={got[0]:02x} 0d={got[1]:02x} 0a={got[2]:02x} 0b={got[3]:02x} 0f={got[4]:02x}\n")
    subprocess.run(["aplay", "-q", "-D", "hw:0,0", "/tmp/deep_tones.wav"], stderr=subprocess.DEVNULL)
    rec.wait()
    time.sleep(1.5)

# Bias toggles, no sound. MIC1 with MBIAS (0x0b bit 6), then MIC2 with HBIAS (0x0b bit 7).
for label, bits, bias_bit in (("bias_mic1", 0x44, 6), ("bias_mic2", 0x24, 7)):
    rec = record(f"/tmp/deep_{label}.wav", 7)
    start = time.time()
    time.sleep(0.8)
    adda_write(0x0C, bits)
    adda_write(0x0D, bits)
    base = adda_read(0x0B)
    marks = []
    for step in range(4):
        time.sleep(1.2)
        value = base & ~(1 << bias_bit) if step % 2 == 0 else base
        adda_write(0x0B, value)
        marks.append(f"{time.time() - start:.2f}s->{value:02x}")
    adda_write(0x0B, base)
    times.write(f"{label}: base 0b={base:02x} toggles {' '.join(marks)}\n")
    rec.wait()
    time.sleep(1.5)
times.close()
