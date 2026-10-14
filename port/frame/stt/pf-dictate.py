#!/usr/bin/env python3
"""pf-dictate: dictation on the PF1007L with a local speech model (sherpa-onnx).

Two engines (PF_DICTATE_ENGINE):
  moonshine  (default) a whole-utterance model, chosen by the files in the model folder: Moonshine v2
             or v1, or a NeMo CTC model such as Parakeet 110M. It decodes each piece of speech at a
             pause: accurate, with capitals and punctuation. Moonshine v2 tiny needs about 0.8 s for
             each second of speech on the frame.
  zipformer  streaming Zipformer 20M. Text while you talk, but poor on natural speech (E068).

The frame has no microphone (E062-E067), so the sound comes in over the network: this program
listens on a TCP port for raw audio (16 kHz, mono, signed 16-bit) and types the recognized text
into the focused Wayland window (ydotool, or wtype as the fallback). Recognition runs on the frame only.

Send audio from a Mac:   ffmpeg -f avfoundation -i ":default" -ar 16000 -ac 1 -f s16le tcp://10.55.0.1:5055
Usage: pf-dictate.py <model-dir> [listen-address] [port]
The last utterance is kept in /tmp/pf-dictate-last.wav (memory only) for model comparisons.
"""
import os
import socket
import ctypes
import gc
import glob
import json
import struct
import subprocess
import sys
import threading
import time
import wave

import sherpa_onnx

model = sys.argv[1]
address = sys.argv[2] if len(sys.argv) > 2 else "10.55.0.1"     # the USB link only, not Wi-Fi
port = int(sys.argv[3]) if len(sys.argv) > 3 else 5055
RATE = 16000


def say(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


YDOTOOL_SOCKET = f"/run/user/{os.getuid()}/.ydotool_socket"
KEY_DELAY = os.environ.get("PF_DICTATE_KEY_DELAY", "8")
KEY_HOLD = os.environ.get("PF_DICTATE_KEY_HOLD", "4")


def type_text(text):
    """Type into the focused window. ydotool (a daemon with a fixed virtual keyboard) is fast.
    wtype is the fallback, but each call makes the compositor load a new key map: on this CPU that
    cost 10 s for a 17 s clip (E068)."""
    if not text or os.environ.get("PF_DICTATE_NO_TYPE"):
        return
    if os.path.exists(YDOTOOL_SOCKET):
        # 8 ms + 4 ms for each key. At 2 + 2 ms one sentence lost 19 characters in a row (E068):
        # the kernel's event buffer overflows when the compositor stalls for more than about 0.1 s.
        subprocess.run(["ydotool", "type", "-d", KEY_DELAY, "-H", KEY_HOLD, "--", text], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["wtype", "--", text], check=False)


ENGINE = os.environ.get("PF_DICTATE_ENGINE", "moonshine")
THREADS = int(os.environ.get("PF_DICTATE_THREADS", "3"))
IDLE_UNLOAD = int(os.environ.get("PF_DICTATE_IDLE_UNLOAD", "900"))
PAUSE_FRAMES = int(float(os.environ.get("PF_DICTATE_PAUSE", "0.6")) * 10)   # pause that ends a piece, in 0.1 s
# Moonshine v2 in sherpa-onnx 1.13.8 fails on 10 s and more; the others take longer pieces.
# A shorter piece gives text sooner but less context; 6 s keeps the lag at about one phrase (E073).
MAX_PIECE = float(os.environ.get("PF_DICTATE_MAX_PIECE", "6"))


def notify(text):
    subprocess.run(["notify-send", "-t", "2500", "Dictation", text], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


STATE_FILE = f"/run/user/{os.getuid()}/pf-dictate.state"
status = {"state": "idle", "busy": False, "text": "", "conn": None}


def publish(**changes):
    """Write the state for the bar widget (frame.dictation) and tell the sender what happened."""
    status.update(changes)
    line = json.dumps({k: status[k] for k in ("state", "busy", "text")})
    try:
        with open(STATE_FILE, "w") as f:
            f.write(line + "\n")
    except OSError:
        pass
    conn = status["conn"]
    if conn is not None:
        try:
            conn.sendall((line + "\n").encode())
        except OSError:
            pass


def keep_last(pcm):
    with wave.open("/tmp/pf-dictate-last.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)


def serve_moonshine(server):
    """Moonshine decodes whole pieces of speech. Cut the stream at each pause (or after 8 s; the v2
    model in sherpa-onnx 1.13.8 fails on 10 s and more) and type each piece when it is done. With a
    real-time factor under 1 the text follows the speech phrase by phrase."""

    def load():
        if glob.glob(f"{model}/encoder_model*"):                     # Moonshine v2 (.ort files)
            return sherpa_onnx.OfflineRecognizer.from_moonshine_v2(
                encoder=glob.glob(f"{model}/encoder_model*")[0], decoder=glob.glob(f"{model}/decoder_model*")[0],
                tokens=f"{model}/tokens.txt", num_threads=THREADS)
        elif os.path.exists(f"{model}/model.int8.onnx"):             # NeMo CTC, for example Parakeet 110M
            return sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
                model=f"{model}/model.int8.onnx", tokens=f"{model}/tokens.txt", num_threads=THREADS)
        else:                                                        # Moonshine v1 (four .onnx files)
            pick = lambda name: sorted(glob.glob(f"{model}/{name}*.onnx"))[0]
            return sherpa_onnx.OfflineRecognizer.from_moonshine(
                preprocessor=pick("preprocess"), encoder=pick("encode"), uncached_decoder=pick("uncached_decode"),
                cached_decoder=pick("cached_decode"), tokens=f"{model}/tokens.txt", num_threads=THREADS)

    # The model takes about 100 MiB. Load it at the first stream and drop it after IDLE_UNLOAD seconds
    # with no stream, so that an unused dictation service costs the 1 GB frame almost nothing.
    state = {"recognizer": None}
    loading = threading.Lock()

    def get_recognizer():
        with loading:
            if state["recognizer"] is None:
                previous = status["state"]
                publish(state="loading")
                start = time.time()
                recognizer = load()
                # The first decode after a load reads the model pages from the SD card and is slow.
                warm = recognizer.create_stream()
                warm.accept_waveform(RATE, [0.0] * RATE)
                recognizer.decode_stream(warm)
                state["recognizer"] = recognizer
                publish(state="listening" if previous == "listening" or status["conn"] else "idle")
                say(f"model loaded and warmed in {time.time() - start:.1f} s")
            return state["recognizer"]

    def decode(pcm):
        start = time.time()
        recognizer = get_recognizer()
        publish(busy=True)
        samples = struct.unpack(f"<{len(pcm) // 2}h", pcm)
        gain = min(16000.0 / max(max(abs(v) for v in samples), 1), 20.0) / 32768.0   # quiet input
        stream = recognizer.create_stream()
        stream.accept_waveform(RATE, [v * gain for v in samples])
        recognizer.decode_stream(stream)
        text = stream.result.text.strip()
        if text:
            type_text(text + " ")
        publish(busy=False, text=text)
        say(f"piece {len(pcm) / 2 / RATE:.1f} s, text after {time.time() - start:.1f} s: {text}")

    FRAME = RATE * 2 // 10                                       # bytes in 0.1 s
    say(f"ready (moonshine): waiting for audio on {address}:{port}")
    publish(state="idle")                                        # the bar widget needs the file to exist
    server.settimeout(60)
    last_use = time.time()
    while True:
        try:
            conn, peer = server.accept()
        except socket.timeout:
            if state["recognizer"] is not None and time.time() - last_use > IDLE_UNLOAD:
                state["recognizer"] = None
                gc.collect()
                try:
                    ctypes.CDLL("libc.so.6").malloc_trim(0)
                except OSError:
                    pass
                publish(state="idle")
                say("model unloaded (idle)")
            continue
        conn.settimeout(None)
        say(f"audio stream from {peer[0]}")
        publish(state="listening", conn=conn, text="")
        threading.Thread(target=get_recognizer, daemon=True).start()   # load while the person talks
        buf = bytearray()
        ended = threading.Event()

        def reader():
            while True:
                data = conn.recv(65536)
                if not data:
                    break
                buf.extend(data)
            ended.set()

        threading.Thread(target=reader, daemon=True).start()
        begin = time.time()
        piece_start = scan = 0
        speech = False
        quiet = 0
        history = []                                             # level of every 0.1 s frame so far
        levels = []                                              # (end offset, level) of the frames in this piece
        while True:
            while scan + FRAME <= len(buf):
                frame = struct.unpack(f"<{FRAME // 2}h", bytes(buf[scan:scan + FRAME]))
                scan += FRAME
                rms = (sum(v * v for v in frame) / len(frame)) ** 0.5
                levels.append((scan, rms))
                history.append(rms)
                # The threshold follows this speaker and this microphone: a quarter of the way from
                # the noise level to the speech level (E072: a quiet Mac microphone gave speech at
                # RMS 200-360 and pauses at 40-80, so a fixed threshold of 250 cut sentences apart).
                ranked = sorted(history)
                floor = ranked[len(ranked) // 10]
                loud = ranked[(len(ranked) * 9) // 10]
                threshold = max(floor * 2.0, floor + 0.25 * (loud - floor), 40.0)
                if rms > threshold:
                    speech, quiet = True, 0
                else:
                    quiet += 1
                length = (scan - piece_start) / 2 / RATE
                if speech and quiet >= PAUSE_FRAMES:             # a clear pause ends the piece
                    decode(bytes(buf[piece_start:scan]))
                    piece_start, speech, quiet, levels = scan, False, 0, []
                elif speech and length >= MAX_PIECE:             # size limit: cut at the quietest of the last 2.5 s
                    cut = min(levels[-25:], key=lambda item: item[1])[0]
                    decode(bytes(buf[piece_start:cut]))
                    levels = [item for item in levels if item[0] > cut]
                    piece_start = cut
                elif not speech and length > 1.0:                # drop silence, keep 0.3 s lead-in
                    piece_start = scan - 3 * FRAME
                    levels = levels[-3:]
            if ended.is_set() and scan + FRAME > len(buf):
                break
            time.sleep(0.05)
        if speech:
            publish(state="finishing")
            decode(bytes(buf[piece_start:len(buf) - len(buf) % 2]))
        publish(state="idle", busy=False)
        status["conn"] = None
        conn.close()
        total = len(buf) / 2 / RATE
        keep_last(bytes(buf[:len(buf) - len(buf) % 2]))
        say(f"stream ended: {total:.1f} s of audio, finished {time.time() - begin - total:.1f} s after its end")
        last_use = time.time()


def serve_zipformer(server):
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=f"{model}/tokens.txt",
        encoder=f"{model}/encoder-epoch-99-avg-1.int8.onnx",
        decoder=f"{model}/decoder-epoch-99-avg-1.onnx",
        joiner=f"{model}/joiner-epoch-99-avg-1.int8.onnx",
        num_threads=THREADS, sample_rate=RATE, feature_dim=80, decoding_method="greedy_search",
        enable_endpoint_detection=True,
        rule1_min_trailing_silence=2.4, rule2_min_trailing_silence=1.0, rule3_min_utterance_length=30)
    say(f"ready (zipformer): waiting for audio on {address}:{port}")
    while True:
        conn, peer = server.accept()
        say(f"audio stream from {peer[0]}")
        stream = recognizer.create_stream()
        stream.accept_waveform(RATE, [0.0] * (RATE // 2))      # lead-in: the model drops words without it
        typed = ""
        got = 0
        start = time.time()
        last_typed = 0.0
        pending = b""
        kept = b""
        open_stream = True
        while open_stream:
            # Collect at least 0.3 s of audio for each step: fewer, larger steps cost less.
            while len(pending) < RATE * 2 * 3 // 10:
                data = conn.recv(8192)
                if not data:
                    open_stream = False
                    break
                pending += data
            usable = len(pending) - len(pending) % 2
            samples = struct.unpack(f"<{usable // 2}h", pending[:usable])
            kept += pending[:usable]
            pending = pending[usable:]
            got += len(samples)
            stream.accept_waveform(RATE, [v / 32768.0 for v in samples])
            if not open_stream:
                stream.accept_waveform(RATE, [0.0] * (RATE // 2))   # tail padding, then flush
                stream.input_finished()
            while recognizer.is_ready(stream):
                recognizer.decode_stream(stream)
            text = recognizer.get_result(stream).lower()
            endpoint = open_stream and recognizer.is_endpoint(stream)
            # Type in bursts, not for each letter: each call starts a process.
            if text.startswith(typed) and (endpoint or not open_stream or time.time() - last_typed > 0.4):
                type_text(text[len(typed):])
                typed = text
                last_typed = time.time()
            if endpoint:
                if typed:
                    type_text(". ")
                    say(f"sentence: {typed}")
                recognizer.reset(stream)
                typed = ""
        if typed:
            say(f"sentence: {typed}")
        conn.close()
        keep_last(kept)
        lag = time.time() - start - got / RATE
        say(f"stream ended: {got / RATE:.1f} s of audio, finished {lag:.1f} s after its end")


say(f"loading the model ({ENGINE}) ...")
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((address, port))
server.listen(1)
(serve_moonshine if ENGINE == "moonshine" else serve_zipformer)(server)
