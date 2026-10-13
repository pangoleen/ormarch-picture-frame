#!/usr/bin/env bash
# Build the boot-card kernel artifacts for the PF1007L frame from a clean state:
#
#   kernel/out/panel-jadard-jd9365da-h3.ko     patched panel driver, out-of-tree module
#   kernel/out/sun8i-a33-pf1007l.dtb           board DTB (SD card, no serial console)
#   kernel/out/sun8i-a33-pf1007l-uart0-sd.dtb  debug DTB (UART0 on the SD pins, FEL boot)
#   kernel/out/SHA256SUMS
#
# for the STOCK Arch Linux ARM kernel linux-armv7 7.2.10-1 (no kernel build).
#
# Run on the Mac:   kernel/build.sh
# Needs:            bash, git, curl, shasum, tar, python3, docker (linux/arm/v7 emulation).
# Writes only to:   refs/kernel/ (git-ignored cache and build tree), kernel/out/,
#                   kernel/logs/, kernel/patches/v7.2.10/.
# It does not use sudo. It does not touch USB devices or the frame.
#
# The module build and the DTB build run in an Arch Linux ARM armv7 container
# under QEMU user emulation, with the compiler and the dtc of the stock kernel.
# Same method and same three traps as wifi/build.sh (see wifi/README.md section 3).
set -euo pipefail

# ---- pinned inputs ---------------------------------------------------------
KTAG="v7.2.10"                       # source of linux-armv7 7.2.10-1
# Each source file is fetched by tag and checked against kernel/sources-v7.2.10.sha256.
# The hashes in that file were taken from the kernel.org release tarball
# linux-7.2.10.tar.xz, SHA-256 2feaa70453e91f541be6a5c9078d8168e081af45a3d9718054850538cff2ebf3
# (equal to the line in https://cdn.kernel.org/pub/linux/kernel/v7.x/sha256sums.asc).
KSRC_URL_1="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/%s?h=${KTAG}"
KSRC_URL_2="https://raw.githubusercontent.com/gregkh/linux/${KTAG}/%s"

# menci/archlinuxarm:base-devel-20261012.38214418911 (image index digest), as in wifi/build.sh
IMAGE="menci/archlinuxarm@sha256:3ede3a01ca0e0dc89fb6a539be60d836ff0b2aed724832dc5cefd00d22b5f04e"

KPKGVER="7.2.10-1"
KREL="7.2.10-1-armv7-ARCH"
HPKG="linux-armv7-headers-${KPKGVER}-armv7h.pkg.tar.xz"
HPKG_SHA256="c8a042ff54f94acf44db1bfa1a61083e2403008b81a349b71705728c2f9f6b04"
KPKG="linux-armv7-${KPKGVER}-armv7h.pkg.tar.xz"       # only for the controls (stock DTB, stock vermagic)
KPKG_SHA256="b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca"
MIRROR="http://mirror.archlinuxarm.org/armv7h/core"     # the mirror redirects: curl -L

JOBS="${JOBS:-10}"

# ---- paths -----------------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KDIR="$ROOT/kernel"
REFS="$ROOT/refs/kernel"
SRC="$REFS/linux-7.2.10"            # pinned v7.2.10 files (only the files that are necessary)
CACHE="$REFS/pkgcache"
BUILD="$REFS/build"                 # clean build tree, made again on each run
OUT="$KDIR/out"
LOGS="$KDIR/logs"
MANIFEST="$KDIR/sources-v7.2.10.sha256"
MOD="panel-jadard-jd9365da-h3"
PANEL_C="drivers/gpu/drm/panel/$MOD.c"
PATCH="$KDIR/patches/v7.2.10/0001-drm-panel-jadard-jd9365da-h3-add-pf1007l-panel.patch"

mkdir -p "$SRC" "$CACHE" "$OUT" "$LOGS"

# ---- 1. v7.2.10 source files -------------------------------------------------
while read -r _ f; do
	[ -n "$f" ] || continue
	if [ ! -f "$SRC/$f" ]; then
		mkdir -p "$(dirname "$SRC/$f")"
		# shellcheck disable=SC2059
		curl -fsSL --max-time 120 -o "$SRC/$f" "$(printf "$KSRC_URL_1" "$f")" ||
			curl -fsSL --max-time 120 -o "$SRC/$f" "$(printf "$KSRC_URL_2" "$f")"
		echo "fetched $f"
	fi
done < "$MANIFEST"
( cd "$SRC" && shasum -a 256 -c "$MANIFEST" > "$LOGS/sources-check.log" ) ||
	{ cat "$LOGS/sources-check.log"; echo "FAIL: a v7.2.10 source file does not have the pinned hash" >&2; exit 1; }
echo "v7.2.10 sources: $(grep -c ': OK$' "$LOGS/sources-check.log") files have the pinned hash"
# Two links that the kernel tree has (they are links in git, so they are made here).
mkdir -p "$SRC/scripts/dtc/include-prefixes"
ln -sfn ../../../include/dt-bindings "$SRC/scripts/dtc/include-prefixes/dt-bindings"
ln -sfn ../../uapi/linux/input-event-codes.h "$SRC/include/dt-bindings/input/linux-event-codes.h"

# ---- 2. stock kernel packages --------------------------------------------------
fetch_pkg() {	# $1 = file, $2 = sha256
	[ -f "$CACHE/$1" ] || curl -fL --max-time 600 -o "$CACHE/$1" "$MIRROR/$1"
	echo "$2  $CACHE/$1" | shasum -a 256 -c -
}
fetch_pkg "$HPKG" "$HPKG_SHA256"
fetch_pkg "$KPKG" "$KPKG_SHA256"

# ---- 3. clean build tree -----------------------------------------------------------
rm -rf "$BUILD"
mkdir -p "$BUILD/panel" "$BUILD/dts" "$BUILD/dtb" "$BUILD/stock" "$BUILD/applycheck/$(dirname "$PANEL_C")"

# 3a. panel driver = v7.2.10 file + our generated entry
BASE=v7.2.10 sh "$KDIR/tools/regen_patch.sh" --out-driver "$BUILD/panel/$MOD.c" > "$LOGS/regen-patch.log"
grep -E '^(CHECK|base:)' "$LOGS/regen-patch.log"
# Control: the patch file, applied with git to the pristine v7.2.10 file, gives the same driver.
# A private git directory makes `git apply` use paths relative to it (trap 3 of wifi/README.md).
cp "$SRC/$PANEL_C" "$BUILD/applycheck/$PANEL_C"
git -C "$BUILD/applycheck" init -q
git -C "$BUILD/applycheck" apply "$PATCH"
cmp "$BUILD/applycheck/$PANEL_C" "$BUILD/panel/$MOD.c"
echo "patch file applies to v7.2.10 with git apply and gives the built driver source"
printf 'obj-m := %s.o\n' "$MOD" > "$BUILD/panel/Kbuild"

# 3b. device trees
cp "$KDIR"/dts/*.dts "$BUILD/dts/"

# 3c. controls from the stock kernel package: one DTB and one module of the same subsystem
tar -xJf "$CACHE/$KPKG" -C "$BUILD/stock" \
	boot/dtbs/sun8i-a33-ga10h-v1.1.dtb \
	"usr/lib/modules/$KREL/kernel/drivers/gpu/drm/panel/panel-lvds.ko" \
	"usr/lib/modules/$KREL/kernel/drivers/gpu/drm/sun4i/sun6i_mipi_dsi.ko"
if tar -tJf "$CACHE/$KPKG" | grep -q "/$MOD\.ko"; then
	echo "NOTE: the stock package ships $MOD.ko. Ours must go to updates/ to replace it." | tee "$LOGS/stock-has-module.txt"
else
	echo "stock package has no $MOD.ko (CONFIG_DRM_PANEL_JADARD_JD9365DA_H3 is not set): ours is an addition"
fi

# ---- 4. build in the armv7 container ----------------------------------------------
# --disable-sandbox: pacman's Landlock sandbox does not work under QEMU user emulation (trap 1).
# -j on the outer make (trap 2).
docker run --rm --platform linux/arm/v7 \
	-v "$BUILD:/src" -v "$SRC:/linux:ro" -v "$CACHE:/pkg:ro" -v "$OUT:/out" -v "$LOGS:/logs" \
	-v "$MANIFEST:/manifest:ro" \
	-e HPKG="$HPKG" -e JOBS="$JOBS" -e MOD="$MOD" -e KREL="$KREL" \
	"$IMAGE" bash -euo pipefail -c '
		pacman -U --noconfirm --disable-sandbox "/pkg/$HPKG" >/dev/null
		[ "$(ls /usr/lib/modules)" = "$KREL" ]
		K=/usr/lib/modules/$KREL/build
		STOCK=/src/stock/usr/lib/modules/$KREL/kernel/drivers/gpu/drm

		# -- 4a. the pinned dt-bindings headers are the headers of the stock kernel
		n=0
		while read -r _ f; do
			case "$f" in include/dt-bindings/*) cmp "/linux/$f" "$K/$f"; n=$((n + 1)) ;; esac
		done < /manifest
		echo "dt-bindings: $n pinned headers are byte-equal to the copies in linux-armv7-headers"

		# -- 4b. panel module
		cd /src/panel
		{
			echo "container: $(uname -m), $(gcc --version | head -1)"
			echo "headers:   $(pacman -Q linux-armv7-headers), kernel release $KREL"
			make -j"$JOBS" -C "$K" M="$PWD" modules
		} 2>&1 | tee /logs/panel-build.log
		cp "$MOD.ko" /out/

		{
			echo "=== $MOD.ko"
			file -b "/out/$MOD.ko"
			modinfo "/out/$MOD.ko" | grep -Ev "^filename:"
			echo
			echo "--- vermagic"
			ours=$(modinfo -F vermagic "/out/$MOD.ko")
			for s in "$STOCK/panel/panel-lvds.ko" "$STOCK/sun4i/sun6i_mipi_dsi.ko"; do
				theirs=$(modinfo -F vermagic "$s")
				[ "$ours" = "$theirs" ] && r=EQUAL || r=DIFFERENT
				echo "$r  ours [$ours]  stock $(basename "$s") [$theirs]"
			done
			echo
			echo "--- our compatible in the alias list"
			modinfo -F alias "/out/$MOD.ko" | grep -c "yhk,zr789-sq9365-101" | sed "s/^/alias lines with yhk,zr789-sq9365-101: /"
			echo
			echo "--- symbols"
			nm -u "/out/$MOD.ko" | awk "{print \$2}" | sort -u > /tmp/undef
			cut -f2 "$K/Module.symvers" | sort -u > /tmp/exported
			echo "undefined symbols: $(wc -l < /tmp/undef); not exported by the stock kernel: $(comm -23 /tmp/undef /tmp/exported | wc -l)"
			comm -23 /tmp/undef /tmp/exported
			modprobe --dump-modversions "/out/$MOD.ko" | awk "{print \$2\" \"\$1}" | sort > /tmp/mv
			awk -F"\t" "{print \$2\" \"\$1}" "$K/Module.symvers" | sort > /tmp/ks
			echo "symbol CRC entries: $(wc -l < /tmp/mv); CRC mismatch or missing: $(comm -23 /tmp/mv /tmp/ks | wc -l)"
			comm -23 /tmp/mv /tmp/ks
			echo
			echo "--- where each undefined symbol comes from (vmlinux = built in, no module dependency)"
			awk -F"\t" "NR==FNR {u[\$1]=1; next} (\$2 in u) {print \$3}" /tmp/undef "$K/Module.symvers" | sort | uniq -c
		} 2>&1 | tee /logs/panel-modinfo.txt
		grep -q "^EQUAL .*panel-lvds" /logs/panel-modinfo.txt
		grep -q "alias lines with yhk,zr789-sq9365-101: [1-9]" /logs/panel-modinfo.txt
		if grep -Eq "(not exported by the stock kernel|CRC mismatch or missing): [1-9]" /logs/panel-modinfo.txt ||
		   grep -q "^DIFFERENT" /logs/panel-modinfo.txt; then
			echo "FAIL: vermagic, unresolved symbols or CRC mismatch" >&2
			exit 1
		fi

		# -- 4c. device trees, with the dtc of the stock kernel and the kernel command lines
		DTC=$K/scripts/dtc/dtc
		INC=/linux/scripts/dtc/include-prefixes
		ALW=/linux/arch/arm/boot/dts/allwinner
		# cmd_dtc of scripts/Makefile.dtbs (v7.2.10). $1 = source, $2 = output, $3 = dtc flags, $4... = cpp flags
		dtb() {
			src=$1; out=$2; flags=$3; shift 3
			gcc -E -nostdinc -I "$INC" -I "$ALW" -undef -D__DTS__ -x assembler-with-cpp "$@" -o "$out.pp" "$src"
			# shellcheck disable=SC2086
			"$DTC" -o "$out" -b 0 -i "$(dirname "$src")/" -i "$INC" $flags "$out.pp"
		}
		# Arch Linux ARM builds its DTBs with `make DTC_FLAGS="-@" dtbs`. The command-line value
		# replaces the -Wno-... list of the Makefile, so the stock flags are: -@ and the dtc defaults.
		STOCKFLAGS="-@"
		# W=1 of the kernel build adds one check. The -Wno-... list is already gone (see above).
		W1="-@ -Wunique_unit_address_if_enabled"
		# W=2 adds strict name checks. Upstream .dtsi files and standard property names
		# (dr_mode, usb0_vbus_power-supply, ldo_io0 ...) fail them, so W=2 is a report only.
		W2="$W1 -Wnode_name_chars_strict -Wproperty_name_chars_strict -Wunique_unit_address"
		{
			echo "dtc: $("$DTC" --version)   (scripts/dtc/dtc of linux-armv7-headers $KREL)"
			echo
			echo "== CONTROL: upstream sun8i-a33-ga10h-v1.1.dts, stock flags"
			dtb "$ALW/sun8i-a33-ga10h-v1.1.dts" /src/dtb/control-ga10h.dtb "$STOCKFLAGS" 2>&1 | sed "s/Warning/(control) warning/"
			if cmp /src/dtb/control-ga10h.dtb /src/stock/boot/dtbs/sun8i-a33-ga10h-v1.1.dtb; then
				echo "CONTROL PASS: byte-equal to boot/dtbs/sun8i-a33-ga10h-v1.1.dtb of linux-armv7 $KREL"
			else
				echo "CONTROL FAIL: not equal to the stock DTB"
			fi
			for v in sun8i-a33-pf1007l sun8i-a33-pf1007l-uart0-sd; do
				echo
				echo "== $v.dts, stock flags (the artifact)"
				dtb "/src/dts/$v.dts" "/out/$v.dtb" "$STOCKFLAGS"
				rm -f "/out/$v.dtb.pp"
				echo "   $(wc -c < "/out/$v.dtb") bytes"
				echo "== $v.dts, W=1 checks (result not kept)"
				dtb "/src/dts/$v.dts" "/src/dtb/$v.w1.dtb" "$W1"
				cmp "/out/$v.dtb" "/src/dtb/$v.w1.dtb" && echo "   same bytes as the artifact"
			done
			echo
			echo "== compile check of the other switches, W=1 checks (results not kept)"
			for sw in PF1007L_ENABLE_EMMC PF1007L_CPU_DVFS_DCDC3 PF1007L_WIFI_PWRSEQ_TWO_PINS PF1007L_UART0_ON_PB_PINS; do
				echo "-- -D$sw"
				dtb /src/dts/sun8i-a33-pf1007l.dts "/src/dtb/check-$sw.dtb" "$W1" "-D$sw"
			done
			echo "-- all four"
			dtb /src/dts/sun8i-a33-pf1007l.dts /src/dtb/check-all.dtb "$W1" \
				-DPF1007L_ENABLE_EMMC -DPF1007L_CPU_DVFS_DCDC3 -DPF1007L_WIFI_PWRSEQ_TWO_PINS -DPF1007L_UART0_ON_PB_PINS
			echo "-- -DPF1007L_UART0_ON_PB_PINS -DPF1007L_UART0_ON_SD_PINS must stop with #error"
			if dtb /src/dts/sun8i-a33-pf1007l.dts /src/dtb/check-bad.dtb "$W1" \
				-DPF1007L_UART0_ON_PB_PINS -DPF1007L_UART0_ON_SD_PINS 2>/dev/null; then
				echo "FAIL: the two UART switches together did not stop the build"
			else
				echo "OK: stopped"
			fi
		} 2>&1 | tee /logs/dtb-build.log
		if grep -Eq "CONTROL FAIL|^FAIL|Warning|ERROR|rror:" /logs/dtb-build.log; then
			echo "FAIL: DTB control, warning or error. See kernel/logs/dtb-build.log" >&2
			exit 1
		fi
		{
			echo "W=2 strict name checks. Report only: the build does not stop on these."
			for v in sun8i-a33-pf1007l sun8i-a33-pf1007l-uart0-sd; do
				echo "== $v.dts"
				dtb "/src/dts/$v.dts" "/src/dtb/$v.w2.dtb" "$W2"
			done
		} > /logs/dtb-w2.log 2>&1
		echo "W=2 (report only): $(grep -c Warning /logs/dtb-w2.log) warnings, $(grep Warning /logs/dtb-w2.log | grep -c "^/src/dts/") from the board file. See kernel/logs/dtb-w2.log"
	'

# ---- 5. rule checks on the two DTBs (project rules, see kernel/tools/check_dtb.py) ----
{
	python3 -I "$KDIR/tools/check_dtb.py" --variant default "$OUT/sun8i-a33-pf1007l.dtb"
	python3 -I "$KDIR/tools/check_dtb.py" --variant uart0-sd "$OUT/sun8i-a33-pf1007l-uart0-sd.dtb"
} | tee "$LOGS/dtb-rules.log"

# ---- 6. hashes ---------------------------------------------------------------------
( cd "$OUT" && shasum -a 256 "$MOD.ko" sun8i-a33-pf1007l.dtb sun8i-a33-pf1007l-uart0-sd.dtb > SHA256SUMS && cat SHA256SUMS )
echo "Done. Artifacts: $OUT   Logs: $LOGS"
