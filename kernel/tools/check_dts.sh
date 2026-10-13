#!/bin/sh
# Fast syntax check of the board DTS files on the Mac: C preprocessor + dtc.
# Needs: clang and dtc (Homebrew). Reads the pinned Linux v7.2.10 include tree in
# refs/kernel/linux-7.2.10 (kernel/build.sh fetches it). Writes only to OUT
# (default: a temporary directory). No device access.
#
# This is a SYNTAX check for work on the DTS. It uses the Homebrew dtc, not the dtc
# of the stock kernel. The artifacts come from kernel/build.sh. The schema check is
# kernel/tools/dtbs_check.sh.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
K="$ROOT/refs/kernel/linux-7.2.10"
[ -f "$K/arch/arm/boot/dts/allwinner/sun8i-a33.dtsi" ] || { echo "run kernel/build.sh first (it fetches the v7.2.10 files)" >&2; exit 1; }
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
rc=0
check() {	# $1 = dts file name, $2... = extra cpp flags (one flag per argument)
	dts=$1; shift
	name=$(basename "$dts" .dts)$(echo "$*" | tr -d ' ' | tr -c 'A-Za-z0-9_\n' '_')
	echo "== $dts $*"
	clang -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp "$@" \
		-I "$K/scripts/dtc/include-prefixes" -I "$K/arch/arm/boot/dts/allwinner" \
		-I "$ROOT/kernel/dts" \
		"$ROOT/kernel/dts/$dts" -o "$OUT/$name.pp.dts"
	if dtc -@ -I dts -O dtb -o "$OUT/$name.dtb" "$OUT/$name.pp.dts" 2> "$OUT/$name.log"; then
		echo "dtc: OK ($(wc -c < "$OUT/$name.dtb" | tr -d ' ') bytes), $(grep -c 'Warning' "$OUT/$name.log" || true) warning(s)"
	else
		echo "dtc: FAILED"; rc=1
	fi
	sed 's/^/  /' "$OUT/$name.log"
}
check sun8i-a33-pf1007l.dts
check sun8i-a33-pf1007l-uart0-sd.dts
check sun8i-a33-pf1007l.dts -DPF1007L_ENABLE_EMMC
check sun8i-a33-pf1007l.dts -DPF1007L_CPU_DVFS_DCDC3
check sun8i-a33-pf1007l.dts -DPF1007L_WIFI_PWRSEQ_TWO_PINS
check sun8i-a33-pf1007l.dts -DPF1007L_UART0_ON_PB_PINS
echo "output: $OUT"
exit $rc
