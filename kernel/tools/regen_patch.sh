#!/bin/sh
# Regenerate the panel patch from the dumps. Run from any directory.
# Read-only on dumps/ and refs/. No device access.
#
#   BASE=v7.2.10 sh kernel/tools/regen_patch.sh   (default)
#       base = the driver of Linux v7.2.10, the source of the stock Arch Linux
#       ARM kernel linux-armv7 7.2.10-1. Writes kernel/patches/v7.2.10/0001-*.patch.
#       This is the patch that kernel/build.sh builds.
#   BASE=master sh kernel/tools/regen_patch.sh
#       base = mainline master 24a19b95 (refs/linux-snippets). Writes
#       kernel/patches/0001-*.patch. For upstream work only.
#
# The generated C block is the same for the two bases. Only the patch context
# and the line numbers are different. The master patch does NOT apply to
# v7.2.10 (see kernel/README.md section 9).
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BASE=${BASE:-v7.2.10}
NAME=0001-drm-panel-jadard-jd9365da-h3-add-pf1007l-panel.patch
case "$BASE" in
v7.2.10)
	DRIVER=${DRIVER:-"$ROOT/refs/kernel/linux-7.2.10/drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c"}
	OUT_PATCH=${OUT_PATCH:-"$ROOT/kernel/patches/v7.2.10/$NAME"}
	STATE='Base: Linux v7.2.10. Built as an out-of-tree module against
linux-armv7-headers 7.2.10-1 (kernel/build.sh). Not tested on hardware.
Do not send upstream as is.'
	;;
master)
	DRIVER=${DRIVER:-"$ROOT/refs/linux-snippets/panel-jadard-jd9365da-h3.c"}
	OUT_PATCH=${OUT_PATCH:-"$ROOT/kernel/patches/$NAME"}
	STATE='DRAFT - base: mainline master 24a19b95. This variant is not compiled.
Not tested on hardware. Do not send upstream as is.'
	;;
*)
	echo "BASE must be v7.2.10 or master" >&2
	exit 2
	;;
esac
if [ ! -f "$DRIVER" ]; then
	echo "driver source not found: $DRIVER (run kernel/build.sh, it fetches the pinned v7.2.10 files)" >&2
	exit 1
fi
mkdir -p "$(dirname "$OUT_PATCH")"
echo "base: $BASE   driver: $DRIVER"
exec python3 "$ROOT/kernel/tools/gen_jd9365_init.py" \
	--seq "$ROOT/dumps/panel/sq9365_init_sequence.txt" \
	--fex "$ROOT/dumps/sys_config.fex" \
	--driver "$DRIVER" \
	--patch-state "$STATE" \
	--post-init-delay-ms 150 \
	--desc-extra '.reset_before_power_off_vcioo = true,' \
	--desc-extra '.vcioo_to_lp11_delay_ms = 50,' \
	--desc-extra '.lp11_to_reset_delay_ms = 25,' \
	--delays-state 'set from dumps/panel/power-sequence.md (vendor lcd.ko, read in
  disassembly, not measured). vcioo_to_lp11_delay_ms = 50 and
  lp11_to_reset_delay_ms = 25 give 80 ms from supplies-on to reset-low (the
  common code adds 5 ms), as the vendor does. reset_before_power_off_vcioo =
  true: the vendor sets reset low before it removes the supplies. The 150 ms
  delay at the end of the init function is from the vendor code, not from the
  table. Differences that stay (common code of this driver): one reset pulse
  (vendor: two), 0x28 + 0x10 at power-off (vendor: none), sleep-out and
  display-on with no parameter byte (vendor: one zero parameter).' \
	--compare \
	--out-patch "$OUT_PATCH" \
	"$@"
