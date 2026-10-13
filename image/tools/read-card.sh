#!/bin/sh
# Show the boot evidence on the card. The card is in the Mac's reader, or the frame
# is in "USB disk mode". Read-only.   image/tools/read-card.sh [/Volumes/PFBOOT]
V=${1:-/Volumes/PFBOOT}
[ -d "$V/pf" ] || { echo "no $V/pf: is the PFBOOT volume mounted?"; exit 1; }
echo "== uboot.env (U-Boot, each start)";   cat "$V/pf/uboot.env"
echo "== linux-ok.env (Linux, when the Mac configured USB)"; cat "$V/pf/linux-ok.env" 2>/dev/null || echo "(none)"
echo "== markers of the last start";        ls "$V/pf/stage" 2>/dev/null | tr '\n' ' '; echo
echo "== stages.log (last 40 lines)";       tail -n 40 "$V/pf/stages.log"
echo "== logs: $V/pf/last/"; ls -la "$V/pf/last" 2>/dev/null
