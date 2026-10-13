#!/usr/bin/env bash
# Load test of kernel/out/panel-jadard-jd9365da-h3.ko on the REAL stock kernel
# (boot/zImage of linux-armv7 7.2.10-1) in an emulator. Not the frame.
#
#   kernel/tools/qemu_loadtest.sh        (run kernel/build.sh first)
#
# Machine: qemu-system-arm -M orangepi-pc (Allwinner H3, Cortex-A7: the nearest
# emulated sun8i board; same method as wifi/README.md section 5.4).
# What it proves: the module format, the relocations and the symbol versions are
# accepted by the stock kernel, and the module init and exit code runs.
# Control: a copy of the module with one changed symbol CRC must be REFUSED.
# What it does not prove: anything about the DSI host, the panel or the board.
#
# Needs: qemu-system-arm, curl, shasum, tar, cpio, python3. No sudo, no USB.
# Writes only to refs/kernel/qemu/ and kernel/logs/.
set -euo pipefail

KREL="7.2.10-1-armv7-ARCH"
KPKG="linux-armv7-7.2.10-1-armv7h.pkg.tar.xz"
KPKG_SHA256="b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca"
BBPKG="busybox-1.36.1-4-armv7h.pkg.tar.xz"       # static busybox of Arch Linux ARM
MIRROR="http://mirror.archlinuxarm.org/armv7h"
MOD="panel-jadard-jd9365da-h3"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="$ROOT/refs/kernel/pkgcache"
W="$ROOT/refs/kernel/qemu"
LOG="$ROOT/kernel/logs/qemu-loadtest-orangepi-pc.log"
PINFILE="$ROOT/kernel/tools/qemu_loadtest.sha256"

[ -f "$ROOT/kernel/out/$MOD.ko" ] || { echo "run kernel/build.sh first" >&2; exit 1; }
mkdir -p "$CACHE"
[ -f "$CACHE/$KPKG" ] || curl -fL --max-time 600 -o "$CACHE/$KPKG" "$MIRROR/core/$KPKG"
echo "$KPKG_SHA256  $CACHE/$KPKG" | shasum -a 256 -c -
[ -f "$CACHE/$BBPKG" ] || curl -fL --max-time 300 -o "$CACHE/$BBPKG" "$MIRROR/extra/$BBPKG"
( cd "$CACHE" && shasum -a 256 -c "$PINFILE" )

rm -rf "$W"
mkdir -p "$W/stock" "$W/bb" "$W/root/bin" "$W/root/m" "$W/root/dev" "$W/root/proc" "$W/root/sys"
tar -xJf "$CACHE/$KPKG" -C "$W/stock" boot/zImage boot/dtbs/sun8i-h3-orangepi-pc.dtb
tar -xJf "$CACHE/$BBPKG" -C "$W/bb" usr/bin/busybox
cp "$W/bb/usr/bin/busybox" "$W/root/bin/busybox"
chmod 755 "$W/root/bin/busybox"
cp "$ROOT/kernel/out/$MOD.ko" "$W/root/m/"

# Control module: same file, the CRC of one imported symbol changed by one bit.
python3 -I - "$ROOT/kernel/out/$MOD.ko" "$W/root/m/bad-crc.ko" <<'EOF'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
name = b"drm_panel_add\0"
hits = [i for i in range(len(d)) if d[i:i + len(name)] == name and d[i - 1] != 0x5F and i % 4 == 0]
# struct modversion_info { unsigned long crc; char name[60]; }: the CRC is the 4 bytes before the name.
cands = [i for i in hits if d[i + len(name):i + 60] == bytes(60 - len(name))]
assert len(cands) == 1, cands
d[cands[0] - 4] ^= 0x01
open(sys.argv[2], "wb").write(d)
print(f"control module: CRC of drm_panel_add changed at file offset {cands[0] - 4:#x}")
EOF

cat > "$W/root/init" <<'EOF'
#!/bin/busybox sh
B=/bin/busybox
$B mount -t devtmpfs dev /dev
exec > /dev/console 2>&1
$B mount -t proc proc /proc
$B mount -t sysfs sys /sys
M=panel_jadard_jd9365da_h3
echo "LOADTEST kernel $($B uname -r)"
$B insmod /m/panel-jadard-jd9365da-h3.ko; echo "LOADTEST insmod panel rc=$?"
echo "LOADTEST lsmod: $($B grep $M /proc/modules)"
echo "LOADTEST dsi driver registered: $($B ls /sys/bus/mipi-dsi/drivers/ | $B tr '\n' ' ')"
echo "LOADTEST tainted=$($B cat /proc/sys/kernel/tainted)"
$B rmmod $M; echo "LOADTEST rmmod panel rc=$?"
$B insmod /m/bad-crc.ko; echo "LOADTEST insmod bad-crc (control, must fail) rc=$?"
$B insmod /m/panel-jadard-jd9365da-h3.ko; echo "LOADTEST insmod panel again rc=$?"
echo "LOADTEST oops/BUG/WARNING lines: $($B dmesg | $B grep -c -E 'Oops|BUG:|WARNING:')"
echo "LOADTEST done"
$B poweroff -f
EOF
chmod 755 "$W/root/init"
( cd "$W/root" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$W/initramfs.cpio.gz" )

# timeout: perl is on every Mac; `timeout` is not.
perl -e 'alarm 240; exec @ARGV' qemu-system-arm -M orangepi-pc -nographic -no-reboot \
	-kernel "$W/stock/boot/zImage" -dtb "$W/stock/boot/dtbs/sun8i-h3-orangepi-pc.dtb" \
	-initrd "$W/initramfs.cpio.gz" \
	-append "console=ttyS0,115200 panic=-1 rdinit=/init" < /dev/null > "$LOG" 2>&1 || true

echo "---- result (full log: $LOG)"
grep -a -E 'LOADTEST|disagrees|version magic|jadard|Linux version' "$LOG" | tr -d '\r'
ok=1
grep -aq 'LOADTEST insmod panel rc=0' "$LOG" || ok=0
grep -aq 'LOADTEST rmmod panel rc=0' "$LOG" || ok=0
grep -aq 'LOADTEST insmod panel again rc=0' "$LOG" || ok=0
grep -aq 'LOADTEST insmod bad-crc (control, must fail) rc=[1-9]' "$LOG" || ok=0
grep -aq 'disagrees about version of symbol drm_panel_add' "$LOG" || ok=0
grep -aq 'LOADTEST oops/BUG/WARNING lines: 0' "$LOG" || ok=0
grep -aq "Linux version $KREL" "$LOG" || ok=0
if [ "$ok" = 1 ]; then echo "LOADTEST PASS"; else echo "LOADTEST FAIL"; exit 1; fi
