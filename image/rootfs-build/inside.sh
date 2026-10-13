#!/bin/bash
# Runs INSIDE the Arch Linux ARM armv7 container (QEMU user emulation on the Mac).
# The container file system IS the future root file system of the frame.
#   /image    image/ of the project (read-only)
#   /in       staged inputs: kernel package, Wi-Fi modules and firmware, touch firmware,
#             optional kernel/out files, SSH public key and host key
#   /manifest output: package list, module list
set -euo pipefail
KVER=7.2.10-1-armv7-ARCH
KPKG=linux-armv7-7.2.10-1-armv7h.pkg.tar.xz
P="pacman --noconfirm --disable-sandbox"
say() { echo "=== $*"; }

say "pacman keyring (for this build only; removed again at the end)"
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinuxarm >/dev/null 2>&1

say "no firmware files from linux-firmware (969 MB; this board needs none of them)"
# The packages stay installed (linux-armv7 depends on linux-firmware); pacman only
# does not unpack their files. regulatory.db (wireless-regdb) is kept.
sed -i 's|^#NoExtract.*|NoExtract   = usr/lib/firmware/* !usr/lib/firmware/regulatory.db* !usr/lib/firmware/aic8800_fw/* !usr/lib/firmware/silead/*|' /etc/pacman.conf
grep -q '^NoExtract' /etc/pacman.conf
# Our own initramfs is used, so the mkinitcpio hook is switched off (a link to /dev/null).
mkdir -p /etc/pacman.d/hooks
ln -sf /dev/null /etc/pacman.d/hooks/90-mkinitcpio-install.hook
# The kernel is pinned: the Wi-Fi modules and the device trees are for this exact build.
sed -i 's|^#IgnorePkg.*|IgnorePkg   = linux-armv7 linux-armv7-headers|' /etc/pacman.conf
grep -q '^IgnorePkg' /etc/pacman.conf

say "full system upgrade"
$P -Syu 2>&1 | tail -n 5
say "kernel $KPKG (pinned file, signature checked by pacman)"
pacman-key --verify "/in/$KPKG.sig" "/in/$KPKG" 2>&1 | grep -E 'Good signature|BAD|No public key' || true
$P -U "/in/$KPKG" 2>&1 | tail -n 3
[ -d "/usr/lib/modules/$KVER" ] || { echo "STOP: no modules for $KVER"; exit 1; }
say "packages"
$P -S --needed sudo iwd iw wireless-regdb zram-generator earlyoom busybox dosfstools usbutils i2c-tools evtest dtc less 2>&1 | tail -n 4
rm -rf /usr/lib/firmware/*
$P -S wireless-regdb 2>&1 | tail -n 1     # puts regulatory.db back
rm -f /boot/initramfs-linux.img /boot/initramfs-linux-fallback.img

say "user, passwords, SSH"
userdel -r alarm 2>/dev/null || true
useradd -m -U -G wheel,video,input,audio,uucp -s /bin/bash frame
# No password hash at all ("!" only). `passwd -l` would keep the tarball's hash of the
# default password "root" behind the lock mark, and `passwd -u` would bring it back.
usermod -p '!' root
usermod -p '!' frame
install -d -m 700 -o frame -g frame /home/frame/.ssh
install -m 600 -o frame -g frame /in/secrets/frame_id_ed25519.pub /home/frame/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*
install -m 600 /in/secrets/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
install -m 644 /in/secrets/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ed25519_key.pub
systemctl mask sshdgenkeys.service >/dev/null 2>&1

say "overlay (image/rootfs)"
(cd /image/rootfs && find . -type d) | while read -r d; do mkdir -p "/$d"; done
(cd /image/rootfs && find . -type f -o -type l) | while read -r f; do
	rm -f "/$f"
	cp -P --no-preserve=ownership,mode "/image/rootfs/$f" "/$f"
	case "$f" in
	./usr/lib/pf1007l/*|./usr/local/bin/*) chmod 755 "/$f" ;;
	./etc/sudoers.d/*) chmod 440 "/$f" ;;
	*) [ -L "/$f" ] || chmod 644 "/$f" ;;
	esac
done
visudo -c -q
sshd -t
udevadm verify /etc/udev/rules.d/60-pf1007l-*.rules 2>&1 | tail -n 3 || true
for u in /usr/lib/systemd/system/pf-*.service /usr/lib/systemd/system/pf-*.timer; do
	systemd-analyze verify "$u" 2>&1 | grep -v -e 'is not a native service' -e '^$' | head -n 5 || true
done

say "system identity and base configuration"
echo pf1007l > /in/hostname.new   # /etc/hostname is a Docker bind mount here; build.sh installs it later
echo 'LANG=C.UTF-8' > /etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
cat > /etc/fstab <<FSTAB
# PF1007L SD card. The disk signature (PARTUUID) is set by image/build.sh.
PARTUUID=@SIG@-02  /      ext4  rw,noatime                                                0 1
PARTUUID=@SIG@-01  /boot  vfat  rw,noatime,flush,umask=0022,nofail,x-systemd.device-timeout=30s  0 2
FSTAB
sed -i "s/@SIG@/$(cat /in/disk-signature)/" /etc/fstab
install -d -m 755 /var/lib/pf1007l /etc/pf1007l
touch /var/lib/pf1007l/firstboot-pending
# No clock battery: systemd moves the clock to the time of this file when the RTC is behind it.
touch /usr/lib/clock-epoch
date -u '+%Y-%m-%dT%H:%M:%SZ' > /etc/pf1007l/image-build-time
# Empty file = "not the first boot" for systemd (as in the ALARM tarball). The text
# "uninitialized" makes systemd run `preset-all`, which disables units (Arch preset: disable *).
: > /etc/machine-id

say "services"
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd sshd earlyoom \
	pf-gadget.service pf-usbwatch.service pf-basic.service pf-late.service pf-collect.timer pf-firstboot.service 2>&1 | grep -v '^Created symlink' || true
systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true

say "Wi-Fi modules (no automatic load), firmware, touch firmware"
install -d "/usr/lib/modules/$KVER/updates"
install -m 644 /in/wifi/*.ko "/usr/lib/modules/$KVER/updates/"
if ls /in/kernel-out/*.ko >/dev/null 2>&1; then
	install -m 644 /in/kernel-out/*.ko "/usr/lib/modules/$KVER/updates/"
	echo "extra modules from kernel/out: $(ls /in/kernel-out/*.ko | xargs -n1 basename | tr '\n' ' ')"
fi
depmod -a "$KVER"
install -d /usr/lib/firmware/aic8800_fw/SDIO/aic8800DC /usr/lib/firmware/silead
install -m 644 /in/aic8800DC/* /usr/lib/firmware/aic8800_fw/SDIO/aic8800DC/
install -m 644 /in/touch/gsl_m86_hd.fw /usr/lib/firmware/silead/gsl_m86_hd.fw
ln -sf gsl_m86_hd.fw /usr/lib/firmware/silead/gsl1680-pf1007l.fw   # the name in the DTS draft
modinfo -k "$KVER" aic8800_fdrv | grep -E '^(filename|vermagic)'

say "initramfs"
I=/tmp/initramfs
rm -rf "$I"; mkdir -p "$I"/{bin,sbin,dev,proc,sys,run,boot,new_root,etc,lib/modules,usr/lib/pf1007l,usr/bin,usr/sbin}
BB=/usr/bin/busybox
file "$BB" | grep -q 'statically linked' || { echo "STOP: busybox is not static"; exit 1; }
install -m 755 "$BB" "$I/bin/busybox"
for a in sh ash mount umount insmod modprobe mkdir cat echo sleep switch_root dd od sed tr cut head tail wc ls ln rm mv sync grep basename dmesg reboot setsid kill ip ifconfig readlink touch date test '[' true false stat df lsmod vi; do
	ln -sf busybox "$I/bin/$a"
done
install -m 755 /image/initramfs/init "$I/init"
install -m 644 /image/rootfs/usr/lib/pf1007l/pf-lib.sh "$I/usr/lib/pf1007l/pf-lib.sh"
install -m 755 /image/rootfs/usr/lib/pf1007l/pf-gadget "$I/usr/lib/pf1007l/pf-gadget"
: > "$I/lib/modules/pf-modules.list"
for m in sunxi_wdt nls_cp437 nls_ascii libcomposite u_serial usb_f_acm u_ether usb_f_ncm usb_f_ecm; do
	modprobe -S "$KVER" --show-depends "$m" | while read -r kind path rest; do
		[ "$kind" = insmod ] || continue        # "builtin" lines need no file
		b=$(basename "$path")
		grep -qx "$b" "$I/lib/modules/pf-modules.list" && continue
		case "$path" in
		*.ko) cp "$path" "$I/lib/modules/$b" ;;
		*.ko.zst) zstd -dq "$path" -o "$I/lib/modules/${b%.zst}"; b=${b%.zst} ;;
		*.ko.xz) xz -dc "$path" > "$I/lib/modules/${b%.xz}"; b=${b%.xz} ;;
		esac
		echo "$b" >> "$I/lib/modules/pf-modules.list"
	done
done
echo "modules in the initramfs: $(tr '\n' ' ' < "$I/lib/modules/pf-modules.list")"
(cd "$I" && find . | LC_ALL=C sort | bsdcpio -o -H newc -R 0:0 --quiet | gzip -9n) > /boot/pf-initramfs.img
ls -la /boot/pf-initramfs.img /boot/zImage
cp "$I/lib/modules/pf-modules.list" /manifest/initramfs-modules.txt

say "clean"
pacman -Q > /manifest/packages.txt
getcap -r /usr 2>/dev/null > /manifest/file-capabilities.txt || true
rm -rf /etc/pacman.d/gnupg /root/.gnupg /root/.bash_history /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /tmp/* /var/tmp/* 2>/dev/null || true
find /var/log -type f -delete 2>/dev/null || true
rm -rf /var/log/journal/* 2>/dev/null || true
du -sx --block-size=1M / 2>/dev/null | cut -f1 > /manifest/rootfs-size-mib.txt
say "root file system: $(cat /manifest/rootfs-size-mib.txt) MiB, $(wc -l < /manifest/packages.txt) packages"
