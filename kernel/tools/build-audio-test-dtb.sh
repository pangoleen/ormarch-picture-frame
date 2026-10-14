#!/bin/sh
# SPDX-License-Identifier: GPL-2.0+
# Make the isolated PF1007L sound-test DTB from an existing known-good DTB.
# This script is deliberately local: it never writes a frame or any block
# device.  The result should be copied to a new /boot/dtbs test filename.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
base=${1:?usage: $0 BASE-BLUETOOTH.DTB OUTPUT.DTB [OVERLAY.DTSO]}
out=${2:?usage: $0 BASE-BLUETOOTH.DTB OUTPUT.DTB [OVERLAY.DTSO]}
overlay=${3:-$root/kernel/dts/pf1007l-audio-card.dtso}
test -f "$overlay" || { echo "overlay not found: $overlay" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pf1007l-audio.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

dtc -@ -I dts -O dtb -o "$tmp/audio.dtbo" "$overlay"
fdtoverlay -i "$base" -o "$out" "$tmp/audio.dtbo"

# Guard against the unsafe experiment that previously broke the SD boot. The
# overlay must not add an amplifier GPIO claim; compare because a historical
# base DTB might have its own unrelated node.
base_amp=$(dtc -I dtb -O dts "$base" | grep -c 'speaker-amp-hog' || true)
out_amp=$(dtc -I dtb -O dts "$out" | grep -c 'speaker-amp-hog' || true)
if [ "$base_amp" != "$out_amp" ]; then
	echo "refusing audio test DTB: overlay added an amplifier GPIO claim" >&2
	rm -f "$out"
	exit 1
fi

echo "built $out from $(basename "$base")"
