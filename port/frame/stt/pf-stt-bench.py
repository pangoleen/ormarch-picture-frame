#!/usr/bin/env python3
"""Speed test of the streaming speech model on the frame: decode a WAV file as a live stream would,
print the text, the real-time factor (decode time / audio time; under 1 keeps up with speech) and
the memory use. Usage: pf-stt-bench.py <model-dir> <file.wav> [threads ...]"""
import resource
import struct
import sys
import time
import wave

import sherpa_onnx

import os

model, path = sys.argv[1], sys.argv[2]
threads = [int(t) for t in sys.argv[3:]] or [1, 2, 3, 4]
ENC = os.environ.get("PF_STT_ENCODER", "encoder-epoch-99-avg-1.int8.onnx")   # or the .onnx float file
with wave.open(path) as w:
    rate, frames = w.getframerate(), w.getnframes()
    samples = [v / 32768.0 for v in struct.unpack(f"<{frames}h", w.readframes(frames))]
seconds = frames / rate
print(f"encoder: {ENC}")
print(f"audio: {path.split('/')[-1]}, {seconds:.1f} s at {rate} Hz")
for n in threads:
    t0 = time.time()
    rec = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=f"{model}/tokens.txt",
        encoder=f"{model}/{ENC}",
        decoder=f"{model}/decoder-epoch-99-avg-1.onnx",
        joiner=f"{model}/joiner-epoch-99-avg-1.int8.onnx",
        num_threads=n, sample_rate=16000, feature_dim=80, decoding_method="greedy_search")
    load = time.time() - t0
    stream = rec.create_stream()
    t0 = time.time()
    step = rate // 5                                   # 0.2 s pieces, as a microphone would give
    for start in range(0, len(samples), step):
        stream.accept_waveform(rate, samples[start:start + step])
        while rec.is_ready(stream):
            rec.decode_stream(stream)
    stream.accept_waveform(rate, [0.0] * (rate // 2))  # tail padding
    stream.input_finished()
    while rec.is_ready(stream):
        rec.decode_stream(stream)
    spent = time.time() - t0
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024
    print(f"threads={n}: load {load:.1f} s, decode {spent:.1f} s, RTF {spent / seconds:.2f}, peak RSS {rss} MiB")
    print(f"   text: {rec.get_result(stream)}")
