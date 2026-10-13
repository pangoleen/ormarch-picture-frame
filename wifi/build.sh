#!/usr/bin/env bash
# Build the out-of-tree AIC8800 SDIO Wi-Fi driver for 32-bit ARM (armv7h)
# against the Arch Linux ARM `linux-armv7` kernel headers.
#
# Run on the Mac:   wifi/build.sh
# Needs:            git, curl, shasum, docker (OrbStack) with linux/arm/v7 emulation.
# Writes only to:   refs/aic/ (git-ignored clones, cache, build tree) and wifi/out/, wifi/logs/.
# It does not use sudo. It does not touch USB devices.
#
# The build runs in an Arch Linux ARM armv7 container under QEMU user emulation.
# A clean build takes about 2 minutes on an Apple M-series Mac (10 jobs).
set -euo pipefail

# ---- pinned inputs ---------------------------------------------------------
BASE_REPO="https://github.com/radxa-pkg/aic8800"
BASE_COMMIT="e9e43ed79c50483080e9bcdfb08caeeb869d7191"   # 2026-10-12, release 5.0+git20260123.5f7be68d-10

# menci/archlinuxarm:base-devel-20261012.38214418911 (image index digest)
IMAGE="menci/archlinuxarm@sha256:3ede3a01ca0e0dc89fb6a539be60d836ff0b2aed724832dc5cefd00d22b5f04e"

KPKGVER="${KPKGVER:-7.2.10-1}"                          # linux-armv7-headers package version
KPKG="linux-armv7-headers-${KPKGVER}-armv7h.pkg.tar.xz"
KPKG_URL="http://mirror.archlinuxarm.org/armv7h/core/${KPKG}"   # the mirror redirects: curl -L
KPKG_SHA256_7_2_10_1="c8a042ff54f94acf44db1bfa1a61083e2403008b81a349b71705728c2f9f6b04"

JOBS="${JOBS:-10}"

# ---- paths -----------------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIFI="$ROOT/wifi"
REFS="$ROOT/refs/aic"
CLONE="$REFS/radxa-pkg_aic8800"
CACHE="$REFS/pkgcache"
BUILD="$REFS/build"                 # clean build tree, made again on each run
DRV="src/SDIO/driver_fw/driver"     # driver path in the Radxa repository
OUT="$WIFI/out"
LOGS="$WIFI/logs"

mkdir -p "$REFS" "$CACHE" "$OUT" "$LOGS"

# ---- 1. source at the pinned commit ----------------------------------------
if [ ! -d "$CLONE/.git" ]; then
	git init -q "$CLONE"
	git -C "$CLONE" remote add origin "$BASE_REPO"
fi
if ! git -C "$CLONE" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null; then
	git -C "$CLONE" fetch -q --depth 1 origin "$BASE_COMMIT"
fi

# ---- 2. clean build tree ----------------------------------------------------
rm -rf "$BUILD"
mkdir -p "$BUILD"
git -C "$CLONE" archive "$BASE_COMMIT" "$DRV" debian/patches | tar -x -C "$BUILD"
# A private git directory makes `git apply` use paths relative to $BUILD.
git -C "$BUILD" init -q
git -C "$BUILD" add -A
git -C "$BUILD" -c user.name=build -c user.email=build@localhost commit -q -m "vendor tree at $BASE_COMMIT"

# ---- 3. Radxa patch series, SDIO files only ---------------------------------
# Two USB-only patches in the series do not apply at this commit (CRLF files).
# They do not touch the SDIO driver, so only the SDIO hunks are applied here.
applied=0
while read -r p; do
	case "$p" in ''|'#'*) continue ;; esac
	if grep -q "^+++ .*${DRV}/" "$BUILD/debian/patches/$p"; then
		git -C "$BUILD" apply --whitespace=nowarn --include="${DRV}/*" "debian/patches/$p"
		applied=$((applied + 1))
	fi
done < "$BUILD/debian/patches/series"
echo "Radxa patches applied to the SDIO driver: $applied"

# ---- 4. project patches (wifi/patches/*.patch), if there are any ------------
shopt -s nullglob
for p in "$WIFI"/patches/*.patch; do
	git -C "$BUILD" apply --whitespace=nowarn "$p"
	echo "project patch applied: $(basename "$p")"
done
shopt -u nullglob

# ---- 5. kernel headers package ----------------------------------------------
if [ ! -f "$CACHE/$KPKG" ]; then
	curl -fL -o "$CACHE/$KPKG" "$KPKG_URL"
fi
if [ "$KPKGVER" = "7.2.10-1" ]; then
	echo "$KPKG_SHA256_7_2_10_1  $CACHE/$KPKG" | shasum -a 256 -c -
fi

# ---- 6. build in the armv7 container ----------------------------------------
# --disable-sandbox: pacman's Landlock sandbox does not work under QEMU user emulation.
docker run --rm --platform linux/arm/v7 \
	-v "$BUILD:/src" -v "$CACHE:/pkg:ro" -v "$OUT:/out" -v "$LOGS:/logs" \
	-e KPKG="$KPKG" -e JOBS="$JOBS" -e DRV="$DRV" \
	"$IMAGE" bash -euo pipefail -c '
		pacman -U --noconfirm --disable-sandbox "/pkg/$KPKG" >/dev/null
		KREL=$(ls /usr/lib/modules)
		K=/usr/lib/modules/$KREL/build
		cd "/src/$DRV/aic8800"
		{
			echo "container: $(uname -m), $(gcc --version | head -1)"
			echo "headers:   $(pacman -Q linux-armv7-headers 2>/dev/null), kernel release $KREL"
			make -j"$JOBS" -C "$K" M="$PWD" modules
		} 2>&1 | tee /logs/build.log
		cp aic8800_bsp/aic8800_bsp.ko aic8800_fdrv/aic8800_fdrv.ko aic8800_btlpm/aic8800_btlpm.ko /out/

		# checks: vermagic, aliases, unresolved symbols, symbol CRCs
		{
			for m in aic8800_bsp aic8800_fdrv aic8800_btlpm; do
				echo "=== $m.ko"
				file -b "/out/$m.ko"
				modinfo "/out/$m.ko" | grep -Ev "^(parm|filename):|^ "
				nm -u "/out/$m.ko" | awk "{print \$2}" | sort -u > /tmp/undef
				cut -f2 "$K/Module.symvers" Module.symvers | sort -u > /tmp/exported
				echo "undefined symbols: $(wc -l < /tmp/undef); not exported by kernel or aic8800_bsp: $(comm -23 /tmp/undef /tmp/exported | wc -l)"
				comm -23 /tmp/undef /tmp/exported
				modprobe --dump-modversions "/out/$m.ko" | awk "{print \$2\" \"\$1}" | sort > /tmp/mv
				awk -F"\t" "{print \$2\" \"\$1}" "$K/Module.symvers" Module.symvers | sort > /tmp/ks
				echo "symbol CRC entries: $(wc -l < /tmp/mv); CRC mismatch or missing: $(comm -23 /tmp/mv /tmp/ks | wc -l)"
			done
		} 2>&1 | tee /logs/modinfo.txt
		if grep -Eq "(not exported by kernel or aic8800_bsp|CRC mismatch or missing): [1-9]" /logs/modinfo.txt; then
			echo "FAIL: unresolved symbols or CRC mismatch" >&2
			exit 1
		fi
	'

( cd "$OUT" && shasum -a 256 ./*.ko > SHA256SUMS && cat SHA256SUMS )
echo "Done. Modules: $OUT   Logs: $LOGS"
