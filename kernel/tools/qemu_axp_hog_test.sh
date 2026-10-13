#!/usr/bin/env bash
# Emulator test of ONE device-tree construct of the board DTS: a "gpio-hog" node
# in the AXP22x GPIO controller ("x-powers,axp221-gpio"), as used for the Wi-Fi
# power switch (AXP GPIO0). Not the frame.
#
#   kernel/tools/qemu_axp_hog_test.sh
#
# Why: the binding schema of v7.2.10 (gpio/x-powers,axp209-gpio.yaml) does not
# list hog nodes, so dt-schema reports our node. The question is whether the
# stock kernel accepts the node and drives the pin, or whether the node stops the
# AXP GPIO driver.
#
# Machine: qemu-system-arm -M bpim2u (Banana Pi M2 Ultra, Allwinner R40, with an
# emulated AXP221 PMIC on I2C). Kernel: the stock zImage of linux-armv7 7.2.10-1.
# DTB: the stock sun8i-r40-bananapi-m2-ultra.dtb, and a copy with our hog node.
#   run A (control): stock DTB           -> no hog, GPIO0 control register unchanged
#   run B:           stock DTB + hog     -> hog line present, register = output high
# Limits: the emulated AXP221 is a register store on I2C. Our board has an AXP223
# on RSB. The GPIO driver code is the same (pinctrl-axp209.c, axp22x_data).
#
# Needs: qemu-system-arm, dtc, curl, shasum, tar, cpio. No sudo, no USB.
# Writes only to refs/kernel/qemu-hog/ and kernel/logs/.
set -euo pipefail

KPKG="linux-armv7-7.2.10-1-armv7h.pkg.tar.xz"
BBPKG="busybox-1.36.1-4-armv7h.pkg.tar.xz"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="$ROOT/refs/kernel/pkgcache"
W="$ROOT/refs/kernel/qemu-hog"
LOG="$ROOT/kernel/logs/qemu-axp-hog-bpim2u.log"
DTB=sun8i-r40-bananapi-m2-ultra

( cd "$CACHE" && shasum -a 256 -c "$ROOT/kernel/tools/qemu_loadtest.sha256" )
echo "b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca  $CACHE/$KPKG" | shasum -a 256 -c -

rm -rf "$W"
mkdir -p "$W/stock" "$W/bb" "$W/root/bin" "$W/root/dev" "$W/root/proc" "$W/root/sys"
tar -xJf "$CACHE/$KPKG" -C "$W/stock" boot/zImage "boot/dtbs/$DTB.dtb"
tar -xJf "$CACHE/$BBPKG" -C "$W/bb" usr/bin/busybox
cp "$W/bb/usr/bin/busybox" "$W/root/bin/busybox"
chmod 755 "$W/root/bin/busybox"

# DTB with our hog node: decompile the stock DTB, add the node, compile again.
dtc -I dtb -O dts -o "$W/stock.dts" "$W/stock/boot/dtbs/$DTB.dtb" 2>/dev/null
python3 -I - "$W/stock.dts" "$W/hog.dts" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
# Insert after the last property of the node (properties must come before subnodes).
m = re.search(r'(\n([ \t]*)compatible = "x-powers,axp221-gpio";\n(?:[ \t]*[^\n{}]*;\n)*)', s)
assert m and s.count('"x-powers,axp221-gpio"') == 1
ind = m.group(2)
hog = (f'{ind}wifi-power-switch-hog {{\n{ind}\tgpio-hog;\n{ind}\tgpios = <0 0>;\n'
       f'{ind}\toutput-high;\n{ind}\tline-name = "wifi-power-switch";\n{ind}}};\n')
open(sys.argv[2], "w").write(s.replace(m.group(1), m.group(1) + hog))
EOF
dtc -I dts -O dtb -o "$W/hog.dtb" "$W/hog.dts" 2>/dev/null

cat > "$W/root/init" <<'EOF'
#!/bin/busybox sh
B=/bin/busybox
$B mount -t devtmpfs dev /dev
exec > /dev/console 2>&1
$B mount -t proc proc /proc
$B mount -t sysfs sys /sys
$B mount -t debugfs dbg /sys/kernel/debug
echo "HOGTEST kernel $($B uname -r)"
echo "HOGTEST axp driver lines: $($B dmesg | $B grep -c -i -E 'axp20x|AXP209 pinctrl')"
$B dmesg | $B grep -i -E 'axp|hog|gpiochip' | $B sed 's/^/HOGTEST dmesg: /'
$B grep -B1 -A3 -i axp /sys/kernel/debug/gpio | $B sed 's/^/HOGTEST gpio: /'
for bus in 0 1 2 3 4; do
	v=$($B i2cget -f -y $bus 0x34 0x90 2>/dev/null) && echo "HOGTEST i2c-$bus 0x34 reg 0x90 (GPIO0 control) = $v"
done
echo "HOGTEST oops/BUG/WARNING lines: $($B dmesg | $B grep -c -E 'Oops|BUG:|WARNING:')"
echo "HOGTEST done"
$B poweroff -f
EOF
chmod 755 "$W/root/init"
( cd "$W/root" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$W/initramfs.cpio.gz" )

run() {	# $1 = label, $2 = dtb
	echo "===== run $1: $2" >> "$LOG"
	perl -e 'alarm 300; exec @ARGV' qemu-system-arm -M bpim2u -nographic -no-reboot \
		-kernel "$W/stock/boot/zImage" -dtb "$2" -initrd "$W/initramfs.cpio.gz" \
		-append "console=ttyS0,115200 panic=-1 rdinit=/init" < /dev/null >> "$LOG" 2>&1 || true
}
: > "$LOG"
run "A (control, stock DTB)" "$W/stock/boot/dtbs/$DTB.dtb"
run "B (stock DTB + hog node)" "$W/hog.dtb"
echo "---- result (full log: $LOG)"
grep -a -E '^===== run|HOGTEST' "$LOG" | tr -d '\r'
