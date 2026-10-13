#!/bin/bash
# Runs INSIDE the pf1007l-image-tools container (native arm64).
# stdin  = tar of the root file system (docker export of the build container)
# /image = image/ (read-only), /stage = staged files (U-Boot, DTBs, boot.scr), /out = output
# env: SIG (MBR disk signature, 8 hex digits), IMG_MIB, P1_START_MIB, P1_MIB, EXT4_UUID, HOSTNAME_NEW
set -euo pipefail
: "${SIG:?}" "${IMG_MIB:?}" "${P1_START_MIB:?}" "${P1_MIB:?}" "${EXT4_UUID:?}"
P2_START_MIB=$((P1_START_MIB + P1_MIB))
P2_MIB=$((IMG_MIB - P2_START_MIB))

echo "== unpack the root file system"
mkdir -p /rootfs /bootfs
tar -x -p --numeric-owner --xattrs --xattrs-include='*' -f - -C /rootfs
# Docker leftovers: bind-mount points and the files that Docker manages.
rm -f /rootfs/.dockerenv
rmdir /rootfs/image /rootfs/in /rootfs/manifest 2>/dev/null || true
echo "${HOSTNAME_NEW:-pf1007l}" > /rootfs/etc/hostname
cat > /rootfs/etc/hosts <<HOSTS
# Static table lookup for hostnames. See hosts(5) for details.
127.0.0.1  localhost
::1        localhost
127.0.1.1  ${HOSTNAME_NEW:-pf1007l}
HOSTS
rm -f /rootfs/etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /rootfs/etc/resolv.conf
chmod 644 /rootfs/etc/hostname /rootfs/etc/hosts
[ "$(stat -c %u:%g /rootfs/home/frame)" != "0:0" ] || { echo "STOP: owners were lost in the tar"; exit 1; }
getfattr -d -m security.capability /rootfs/usr/bin/newuidmap 2>/dev/null | grep -q capability \
	&& echo "file capabilities: kept" || echo "WARNING: file capabilities were lost"

echo "== FAT partition content"
mv /rootfs/boot/* /bootfs/
cp /stage/dtbs/*.dtb /bootfs/dtbs/
mkdir -p /bootfs/extlinux /bootfs/pf/stage /bootfs/pf/last /bootfs/.fseventsd
sed "s/@SIG@/$SIG/g" /image/boot/extlinux/extlinux.conf > /bootfs/extlinux/extlinux.conf
cp /image/boot/uEnv.txt /bootfs/uEnv.txt
cp /image/boot/pf/README.TXT /image/boot/pf/gadget.conf /image/boot/pf/uboot.env /bootfs/pf/
: > /bootfs/pf/stages.log
cp /stage/boot.scr /stage/boot.cmd /bootfs/
# Tell macOS not to index the volume and not to keep an event log on it.
: > /bootfs/.metadata_never_index
: > /bootfs/.fseventsd/no_log
du -sh /bootfs | sed 's/^/boot files: /'

truncate -s "${P1_MIB}M" /tmp/p1.img
mkfs.fat -F 32 -s 4 -h "$((P1_START_MIB * 2048))" -n PFBOOT -i "$SIG" /tmp/p1.img > /tmp/mkfs.fat.log
[ "$(dd if=/tmp/p1.img bs=1 skip=82 count=5 2>/dev/null)" = FAT32 ] || { cat /tmp/mkfs.fat.log; echo "STOP: not FAT32"; exit 1; }
(cd /bootfs && mcopy -i /tmp/p1.img -s -Q -m ./* ./.metadata_never_index ./.fseventsd ::/)
fsck.fat -n /tmp/p1.img | tail -n 1

echo "== ext4 root file system"
truncate -s "${P2_MIB}M" /tmp/p2.img
mkfs.ext4 -q -F -L pfroot -U "$EXT4_UUID" \
	-E "root_owner=0:0,lazy_itable_init=1,lazy_journal_init=1,hash_seed=$EXT4_UUID" \
	-d /rootfs /tmp/p2.img
e2fsck -fn /tmp/p2.img 2>&1 | tail -n 1
dumpe2fs -h /tmp/p2.img 2>/dev/null | grep -E '^(Block count|Free blocks|Filesystem features):'

echo "== card image"
IMG=/out/pf1007l-sd.img
rm -f "$IMG"; truncate -s "${IMG_MIB}M" "$IMG"
sfdisk -q "$IMG" <<PT
label: dos
label-id: 0x$SIG
unit: sectors
start=$((P1_START_MIB * 2048)), size=$((P1_MIB * 2048)), type=c, bootable
start=$((P2_START_MIB * 2048)), size=$((P2_MIB * 2048)), type=83
PT
dd if=/stage/u-boot.bin of="$IMG" bs=1024 seek=8 conv=notrunc status=none
[ "$(stat -c %s /stage/u-boot.bin)" -lt $(( (P1_START_MIB * 1024 - 8) * 1024 )) ] || { echo "STOP: U-Boot overlaps partition 1"; exit 1; }
dd if=/tmp/p1.img of="$IMG" bs=1M seek="$P1_START_MIB" conv=notrunc,sparse status=none
dd if=/tmp/p2.img of="$IMG" bs=1M seek="$P2_START_MIB" conv=notrunc,sparse status=none
sync
sfdisk -l "$IMG"
# Files for the QEMU test variant and for the manifest.
cp /bootfs/dtbs/sun8i-h3-orangepi-pc.dtb /out/qemu-sun8i-h3-orangepi-pc.dtb 2>/dev/null || true
(cd /bootfs && find . -type f | LC_ALL=C sort | xargs sha256sum) > /out/boot-partition-files.sha256
(cd /rootfs && du -sx --block-size=1M . | cut -f1) > /out/rootfs-size-mib.txt
