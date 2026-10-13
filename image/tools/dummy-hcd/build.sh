#!/usr/bin/env bash
# TEST ONLY. Build dummy_hcd.ko (the kernel's loopback USB host + device controller)
# for linux-armv7 7.2.10-1. The stock kernel does not ship it (CONFIG_USB_DUMMY_HCD is
# not set). The QEMU test loads it to give the gadget a controller, so that the same
# kernel enumerates the frame's gadget as a USB host would. It is NOT in the card image.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
IMAGE="menci/archlinuxarm@sha256:3ede3a01ca0e0dc89fb6a539be60d836ff0b2aed724832dc5cefd00d22b5f04e"   # base-devel, as wifi/build.sh
KPKG="linux-armv7-headers-7.2.10-1-armv7h.pkg.tar.xz"
KPKG_SHA256="c8a042ff54f94acf44db1bfa1a61083e2403008b81a349b71705728c2f9f6b04"
SRC_URL="https://raw.githubusercontent.com/gregkh/linux/v7.2.10/drivers/usb/gadget/udc/dummy_hcd.c"
SRC_SHA256="7dd400f2b1723e23ec38721ab76787b0250c597b4401adeeb3e0e9ee4b239e57"
W="$HERE/work/dummy"; mkdir -p "$W"
[ -f "$W/dummy_hcd.c" ] || curl -fsL -o "$W/dummy_hcd.c" "$SRC_URL"
echo "$SRC_SHA256  $W/dummy_hcd.c" | shasum -a 256 -c - >/dev/null
PK="$ROOT/refs/aic/pkgcache/$KPKG"; [ -f "$PK" ] || PK="$ROOT/refs/kernel/pkgcache/$KPKG"
[ -f "$PK" ] || { mkdir -p "$HERE/cache"; PK="$HERE/cache/$KPKG"; [ -f "$PK" ] || curl -fL -o "$PK" "http://mirror.archlinuxarm.org/armv7h/core/$KPKG"; }
echo "$KPKG_SHA256  $PK" | shasum -a 256 -c - >/dev/null
echo 'obj-m := dummy_hcd.o' > "$W/Kbuild"
docker run --rm --platform linux/arm/v7 -v "$W":/src -v "$(dirname "$PK")":/pkg:ro -e KPKG="$KPKG" "$IMAGE" bash -euo pipefail -c '
	pacman -U --noconfirm --disable-sandbox "/pkg/$KPKG" >/dev/null
	K=/usr/lib/modules/$(ls /usr/lib/modules)/build
	cp -r /src /tmp/b && cd /tmp/b
	make -C "$K" M="$PWD" modules > /src/build.log 2>&1 || { tail -20 /src/build.log; exit 1; }
	cp dummy_hcd.ko /src/
	modinfo dummy_hcd.ko | grep -E "^(vermagic|depends|description)"
'
shasum -a 256 "$W/dummy_hcd.ko"
