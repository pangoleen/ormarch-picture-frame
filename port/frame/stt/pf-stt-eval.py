#!/usr/bin/env python3
"""Compare speech models on the frame with the same WAV files (16 kHz mono).
Prints one tab-separated line for each file: engine, file, audio seconds, decode seconds, text.
Usage: pf-stt-eval.py <zipformer|moonshine|moonshine2|parakeet> <model-dir> <threads> file.wav ..."""
import glob
import struct
import sys
import time
import wave

import sherpa_onnx

engine, model, threads, files = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
t0 = time.time()
if engine == "zipformer":
    rec = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=f"{model}/tokens.txt", encoder=f"{model}/encoder-epoch-99-avg-1.int8.onnx",
        decoder=f"{model}/decoder-epoch-99-avg-1.onnx", joiner=f"{model}/joiner-epoch-99-avg-1.int8.onnx",
        num_threads=threads, sample_rate=16000, feature_dim=80, decoding_method="greedy_search")
elif engine == "moonshine":
    pick = lambda name: sorted(glob.glob(f"{model}/{name}*.onnx"))[0]
    rec = sherpa_onnx.OfflineRecognizer.from_moonshine(
        preprocessor=pick("preprocess"), encoder=pick("encode"), uncached_decoder=pick("uncached_decode"),
        cached_decoder=pick("cached_decode"), tokens=f"{model}/tokens.txt", num_threads=threads)
elif engine == "moonshine2":
    rec = sherpa_onnx.OfflineRecognizer.from_moonshine_v2(
        encoder=glob.glob(f"{model}/encoder_model*")[0], decoder=glob.glob(f"{model}/decoder_model*")[0],
        tokens=f"{model}/tokens.txt", num_threads=threads)
elif engine == "parakeet":
    rec = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
        model=f"{model}/model.int8.onnx", tokens=f"{model}/tokens.txt", num_threads=threads)
else:
    sys.exit(__doc__)
print(f"# {engine}: load {time.time() - t0:.1f} s, threads {threads}", flush=True)
for path in files:
    with wave.open(path) as w:
        rate, frames = w.getframerate(), w.getnframes()
        samples = [v / 32768.0 for v in struct.unpack(f"<{frames}h", w.readframes(frames))]
    t0 = time.time()
    stream = rec.create_stream()
    if engine == "zipformer":
        stream.accept_waveform(rate, [0.0] * (rate // 2) + samples + [0.0] * (rate // 2))
        stream.input_finished()
        while rec.is_ready(stream):
            rec.decode_stream(stream)
        text = rec.get_result(stream)
    else:
        stream.accept_waveform(rate, samples)
        rec.decode_stream(stream)
        text = stream.result.text
    print(f"{engine}\t{path.split('/')[-1]}\t{frames / rate:.1f}\t{time.time() - t0:.1f}\t{text.strip()}", flush=True)
