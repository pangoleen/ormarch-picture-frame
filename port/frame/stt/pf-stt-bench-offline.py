#!/usr/bin/env python3
"""Speed test of a whole-utterance (not streaming) model on the frame: Moonshine through sherpa-onnx.
Prints the text, the decode time and the real-time factor. Usage: pf-stt-bench-offline.py <model-dir> <file.wav> [threads ...]"""
import glob
import resource
import struct
import sys
import time
import wave

import sherpa_onnx

model, path = sys.argv[1], sys.argv[2]
threads = [int(t) for t in sys.argv[3:]] or [2, 3]
pick = lambda name: sorted(glob.glob(f"{model}/{name}*.onnx"))[0]
with wave.open(path) as w:
    rate, frames = w.getframerate(), w.getnframes()
    samples = [v / 32768.0 for v in struct.unpack(f"<{frames}h", w.readframes(frames))]
seconds = frames / rate
print(f"audio: {path.split('/')[-1]}, {seconds:.1f} s")
for n in threads:
    t0 = time.time()
    rec = sherpa_onnx.OfflineRecognizer.from_moonshine(
        preprocessor=pick("preprocess"), encoder=pick("encode"), uncached_decoder=pick("uncached_decode"),
        cached_decoder=pick("cached_decode"), tokens=f"{model}/tokens.txt", num_threads=n)
    load = time.time() - t0
    t0 = time.time()
    stream = rec.create_stream()
    stream.accept_waveform(rate, samples)
    rec.decode_stream(stream)
    spent = time.time() - t0
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024
    print(f"threads={n}: load {load:.1f} s, decode {spent:.1f} s, RTF {spent / seconds:.2f}, peak RSS {rss} MiB")
    print(f"   text: {stream.result.text}")
