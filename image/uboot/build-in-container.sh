#!/bin/bash
# Runs INSIDE the pf1007l-uboot-build container. Input: a tar of the pristine
# U-Boot tree on stdin, /u = image/uboot (read-only), /out = output directory.
set -euo pipefail
export CROSS_COMPILE=arm-linux-gnueabihf-
mkdir -p /tmp/src && cd /tmp/src && tar -xf -
patch -s -p1 < /u/0001-wes-pf1007l-uboot.patch
patch -s -p1 < /u/0002-pf1007l-linux-boot.patch
# A fixed build time makes the binary reproducible (U-Boot honours SOURCE_DATE_EPOCH).
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1791763200}"
build() {	# $1 = defconfig, $2 = output name
	rm -rf /build && mkdir /build
	make -s O=/build "$1" > /dev/null
	make -s O=/build -j"$(nproc)" > "/out/$2.build.log" 2>&1 || { tail -40 "/out/$2.build.log"; exit 1; }
	cp /build/u-boot-sunxi-with-spl.bin "/out/$2.bin"
	cp /build/.config "/out/$2.config"
	cp /build/spl/u-boot-spl.map "/out/$2.spl.map" 2>/dev/null || true
	echo "built $2: $(stat -c %s "/out/$2.bin") bytes, warnings: $(grep -c -i 'warning' "/out/$2.build.log" || true)"
}
build pf1007l_linux_defconfig       u-boot-pf1007l-L
# A separate recovery binary.  It restores U-Boot's normal UMS write path but
# keeps build L's MMC configuration: U-Boot has only mmc 0 (the removable SD),
# and no eMMC controller or pins.  The normal image continues to use build L.
if [ "${PF1007L_WRITABLE_RECOVERY:-0}" = 1 ]; then
	patch -s -p1 < /u/0003-pf1007l-writable-recovery.patch
	build pf1007l_linux_defconfig       u-boot-pf1007l-L-rw-recovery
	patch -s -R -p1 < /u/0003-pf1007l-writable-recovery.patch
fi
build pf1007l_qemu_opipc_defconfig  u-boot-qemu-opipc
mkimage -C none -A arm -T script -n "pf1007l build L boot script" -d /u/boot.cmd /out/boot.scr > /dev/null
cp /u/boot.cmd /out/boot.cmd
