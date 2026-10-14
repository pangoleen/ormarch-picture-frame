#!/bin/bash
# Push-to-talk from the Mac to the frame: press Enter, talk, press Enter again.
# The Mac only sends its microphone sound over the USB link. The speech model runs on the frame
# (port/frame/stt/pf-dictate.py) and types the text into the focused window there.
#
# Usage: scripts/mac-dictate.sh ["Microphone name"]
#   List the names:  ffmpeg -f avfoundation -list_devices true -i ""
MIC="${1:-MacBook Pro Microphone}"
FRAME="${PF_FRAME:-10.55.0.1}"
PORT="${PF_PORT:-5055}"
command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed (brew install ffmpeg)"; exit 1; }
echo "Microphone: $MIC  ->  frame $FRAME:$PORT"
while true; do
  read -r -p "Press Enter and talk (Ctrl+C to quit) " _ || exit 0
  ffmpeg -loglevel error -f avfoundation -i ":$MIC" -ar 16000 -ac 1 -f s16le "tcp://$FRAME:$PORT" </dev/null &
  pid=$!
  read -r -p "  ... listening. Press Enter to stop " _
  kill -INT "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done
