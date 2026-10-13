#!/bin/sh
# Set the frame's clock from the Mac (the frame has no clock battery).
#   image/tools/frame-set-clock.sh [frame|frame-mdns]
HERE=$(cd "$(dirname "$0")/.." && pwd)
host=${1:-frame}
ssh -F "$HERE/secrets/ssh_config" "$host" "sudo date -u -s @$(date +%s) && sudo touch /var/lib/systemd/timesync/clock; date"
