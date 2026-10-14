#!/usr/bin/env python3
"""Push-to-talk from the Mac to the frame, with no start delay.

The microphone stays open while this program runs (ffmpeg, one process). Sound goes to the frame
only between two presses of Enter, and the last 0.4 s before the first press are sent too, so the
first word is not cut. A level bar shows that the microphone hears you. The speech model runs on
the frame (port/frame/stt/pf-dictate.py) and types into the window that has the focus there.

Usage: python3 scripts/mac-dictate.py ["Microphone name"]
  List the names:  ffmpeg -f avfoundation -list_devices true -i ""
"""
import array
import collections
import json
import os
import socket
import subprocess
import sys
import threading
import time

MIC = sys.argv[1] if len(sys.argv) > 1 else "MacBook Pro Microphone"
FRAME = (os.environ.get("PF_FRAME", "10.55.0.1"), int(os.environ.get("PF_PORT", "5055")))
CHUNK = 1600 * 2                      # 0.1 s of 16 kHz mono 16-bit
PRE_ROLL = 4                          # chunks kept from before the key press
RED, GREEN, DIM, OFF = "\033[1;31m", "\033[1;32m", "\033[2m", "\033[0m"

mic = subprocess.Popen(
    ["ffmpeg", "-loglevel", "error", "-f", "avfoundation", "-i", f":{MIC}",
     "-ar", "16000", "-ac", "1", "-f", "s16le", "-"],
    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
recent = collections.deque(maxlen=PRE_ROLL)
lock = threading.Lock()
state = {"link": None, "level": 0, "sent": 0, "alive": True}


def pump():
    while True:
        data = mic.stdout.read(CHUNK)
        if not data:
            state["alive"] = False
            return
        samples = array.array("h", data)
        state["level"] = max(abs(min(samples)), max(samples)) if samples else 0
        with lock:
            if state["link"] is None:
                recent.append(data)
            else:
                try:
                    state["link"].sendall(data)
                    state["sent"] += len(data)
                except OSError:
                    state["link"] = None


def meter(stop):
    while not stop.is_set():
        bars = min(state["level"] * 20 // 4000, 20)
        seconds = state["sent"] / 32000
        # One short line, redrawn in place: it must fit a narrow terminal.
        sys.stdout.write(f"\r\033[K  {RED}● REC{OFF} {seconds:4.1f}s [{'#' * bars}{' ' * (20 - bars)}] Enter=stop")
        sys.stdout.flush()
        time.sleep(0.15)


def frame_events(sock):
    """Print what the frame reports: loading, transcribing, and each typed phrase."""
    shown = {"state": None, "busy": False}
    for line in sock.makefile("r", encoding="utf-8", errors="replace"):
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("state") == "loading" and shown["state"] != "loading":
            sys.stdout.write("\r\033[K  frame: loading the model ...\n")
        if event.get("busy") and not shown["busy"]:
            sys.stdout.write("\r\033[K  frame: transcribing ...\n")
        if not event.get("busy") and shown["busy"] and event.get("text"):
            sys.stdout.write(f"\r\033[K  {GREEN}typed:{OFF} {event['text']}\n")
        shown.update(state=event.get("state"), busy=event.get("busy"))
        sys.stdout.flush()


threading.Thread(target=pump, daemon=True).start()
time.sleep(1.0)
if not state["alive"]:
    print(f"The microphone '{MIC}' did not open:")
    print(mic.stderr.read().decode(errors="replace").strip()[-600:])
    print("Check System Settings > Privacy & Security > Microphone for this terminal app,")
    print('or name another microphone: ffmpeg -f avfoundation -list_devices true -i ""')
    sys.exit(1)
print(f"Microphone: {MIC}  ->  frame {FRAME[0]}:{FRAME[1]}")
try:
    socket.create_connection(FRAME, timeout=3).close()      # makes the frame load its model now
    print("The frame loads its speech model now (about 10 s). Focus a text window on the frame.")
except OSError as error:
    print(f"The frame does not answer on {FRAME[0]}:{FRAME[1]}: {error}")
    sys.exit(1)

try:
    while True:
        input(f"\n{GREEN}▶ Press Enter, then talk{OFF} (Ctrl+C to quit) ")
        if not state["alive"]:
            print("The microphone stopped.")
            break
        sock = socket.create_connection(FRAME, timeout=3)
        with lock:
            state["sent"] = 0
            for data in recent:
                sock.sendall(data)
            recent.clear()
            state["link"] = sock
        stop = threading.Event()
        threading.Thread(target=meter, args=(stop,), daemon=True).start()
        reports = threading.Thread(target=frame_events, args=(sock,), daemon=True)
        reports.start()
        input()
        stop.set()
        with lock:
            state["link"] = None
        sys.stdout.write(f"\r\033[K  sent {state['sent'] / 32000:.1f} s of sound; the frame finishes the last phrase ...\n")
        sock.shutdown(socket.SHUT_WR)              # end of sound; the frame still sends its last report
        reports.join(timeout=40)                   # ends when the frame closes the connection
        sock.close()
        print("  done.")
except (KeyboardInterrupt, EOFError):
    print()
finally:
    mic.terminate()
