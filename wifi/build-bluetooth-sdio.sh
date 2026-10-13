#!/usr/bin/env bash
# Isolated SDIO Bluetooth experiment. Does not touch the normal Wi-Fi build
# or the frame. Uses the same pinned inputs and Radxa patches as build.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLONE="$ROOT/refs/aic/radxa-pkg_aic8800"
BUILD="$ROOT/refs/aic/build-bluetooth-sdio"
OUT="$ROOT/wifi/out/bluetooth-sdio"
LOGS="$ROOT/wifi/logs/bluetooth-sdio"
COMMIT=e9e43ed79c50483080e9bcdfb08caeeb869d7191
DRV=src/SDIO/driver_fw/driver
HPKG=linux-armv7-headers-7.2.10-1-armv7h.pkg.tar.xz
IMAGE=menci/archlinuxarm@sha256:3ede3a01ca0e0dc89fb6a539be60d836ff0b2aed724832dc5cefd00d22b5f04e
mkdir -p "$OUT" "$LOGS"
rm -rf "$BUILD"
mkdir -p "$BUILD"
git -C "$CLONE" archive "$COMMIT" "$DRV" debian/patches | tar -x -C "$BUILD"
git -C "$BUILD" init -q
while read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    if rg -q "^\+\+\+ .*${DRV}/" "$BUILD/debian/patches/$p"; then
        git -C "$BUILD" apply --whitespace=nowarn --include="${DRV}/*" "debian/patches/$p"
    fi
done < "$BUILD/debian/patches/series"
# A modern-kernel fix for the optional SDIO Bluetooth path, if needed.
if [ -f "$ROOT/wifi/bluetooth-sdio.patch" ]; then
    git -C "$BUILD" apply "$ROOT/wifi/bluetooth-sdio.patch"
fi
echo "c8a042ff54f94acf44db1bfa1a61083e2403008b81a349b71705728c2f9f6b04  $ROOT/refs/aic/pkgcache/$HPKG" | shasum -a 256 -c -
docker run --rm --platform linux/arm/v7 \
    -v "$BUILD:/src" -v "$ROOT/refs/aic/pkgcache:/pkg:ro" \
    -v "$OUT:/out" -v "$LOGS:/logs" -e HPKG="$HPKG" -e DRV="$DRV" \
    "$IMAGE" bash -euo pipefail -c '
        pacman -U --noconfirm --disable-sandbox "/pkg/$HPKG" >/dev/null
        K=/usr/lib/modules/7.2.10-1-armv7-ARCH/build
        cd "/src/$DRV/aic8800"
        make -j10 -C "$K" M="$PWD" CONFIG_SDIO_BT=y modules 2>&1 | tee /logs/build.log
        cp aic8800_bsp/aic8800_bsp.ko aic8800_fdrv/aic8800_fdrv.ko /out/
        modinfo /out/aic8800_fdrv.ko | tee /logs/modinfo.txt
    '
(cd "$OUT" && shasum -a 256 ./*.ko > SHA256SUMS)
echo "Isolated SDIO-BT modules: $OUT"
