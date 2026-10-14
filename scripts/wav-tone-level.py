#!/usr/bin/env python3
"""Print level figures for stereo 16-bit WAV files: RMS, peak, clipping share and the level of
one tone (Goertzel) against two control frequencies. Pure Python; use it for the audio loopback tests.

Usage: python3 -I scripts/wav-tone-level.py <tone-hz> file.wav [file.wav ...]
"""
import math
import struct
import sys
import wave


def goertzel(samples, freq, rate):
    w = 2 * math.pi * freq / rate
    c = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in samples:
        s1, s2 = v + c * s1 - s2, s1
    return math.sqrt(max(s1 * s1 + s2 * s2 - c * s1 * s2, 0)) / (len(samples) / 2)


def main():
    tone = float(sys.argv[1])
    for path in sys.argv[2:]:
        with wave.open(path) as w:
            rate, frames = w.getframerate(), w.getnframes()
            raw = w.readframes(frames)
        count = len(raw) // 4
        if count < rate // 2:
            print(f"{path.split('/')[-1]:20s} too short ({count} frames)")
            continue
        data = struct.unpack(f"<{count * 2}h", raw[: count * 4])
        skip = rate // 10
        for name, ch in (("L", data[0::2][skip:]), ("R", data[1::2][skip:])):
            mean = sum(ch) / len(ch)
            ac = [v - mean for v in ch]
            rms = math.sqrt(sum(v * v for v in ac) / len(ac))
            clip = sum(1 for v in ch if abs(v) >= 32760) / len(ch)
            print(f"{path.split('/')[-1]:20s} {name} rms={rms:8.1f} min={min(ch):6d} max={max(ch):6d} "
                  f"clip={clip:5.1%} tone={goertzel(ac, tone, rate):8.1f} "
                  f"ctl0.7x={goertzel(ac, tone * 0.7, rate):6.1f} ctl1.5x={goertzel(ac, tone * 1.5, rate):6.1f}")


if __name__ == "__main__":
    main()
