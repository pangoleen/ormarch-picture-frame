#!/usr/bin/env bash
# Test the built card image without the frame, in qemu-system-arm -M orangepi-pc
# (Allwinner H3: the nearest emulated sun8i board).
#
#   image/build.sh test            # or: image/tools/qemu-test.sh
#
# What it does:
#   1. Makes a COPY of image/out/pf1007l-sd.img (4 GiB, QEMU wants a power of 2) and
#      changes two things in the copy: the U-Boot at 8 KiB (same source and boot
#      command, built for the Orange Pi PC) and one more boot label "qemu" (the Orange
#      Pi PC device tree + a serial console). Kernel, initramfs, root file system,
#      boot.scr and all scripts are the files of the real image.
#   2. Start 1: first boot. Checks over SSH (user key + pinned host key): services,
#      root file system growth, pacman keyring, zram, markers on the FAT partition.
#      Then the USB gadget against the kernel's loopback controller (dummy_hcd,
#      a test-only module): ACM serial login, NCM network, DHCP, confirmation file.
#   3. Start 2: U-Boot must choose Linux again (the start before was confirmed).
#      Nothing confirms this start.
#   4. Start 3: U-Boot must choose "USB disk mode". The test sends CTRL+C to the
#      console: the ums command must not stop.
#   5. Reads the FAT partition of the copy: markers and logs, as a Mac reads the card.
#
# It does not touch USB devices. It needs no sudo. It listens on 127.0.0.1:2222 only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="$HERE/work/qemu"; T="$HERE/test"; IMG="$W/test.img"
SSH=(ssh -F "$HERE/secrets/ssh_config" -o ConnectTimeout=10 frame-qemu)
SCP=(scp -q -F "$HERE/secrets/ssh_config")
PASS=0; FAIL=0
mkdir -p "$W" "$T"
: > "$T/results.txt"
say() { printf '\n==== %s\n' "$*"; }
ok() { PASS=$((PASS + 1)); echo "PASS  $*" | tee -a "$T/results.txt"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $*" | tee -a "$T/results.txt"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
clean_log() { sed $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\r//g' "$1" | grep -v 'A start job is running for' > "$2" || true; }

command -v qemu-system-arm >/dev/null || { echo "STOP: qemu-system-arm is not installed"; exit 1; }
[ -f "$HERE/out/pf1007l-sd.img" ] || { echo "STOP: no image, run image/build.sh"; exit 1; }
[ -f "$HERE/work/uboot/u-boot-qemu-opipc.bin" ] || { echo "STOP: no test U-Boot, run image/build.sh uboot"; exit 1; }
[ -f "$W/../dummy/dummy_hcd.ko" ] || "$HERE/tools/dummy-hcd/build.sh"

QPID=""
qemu_start() {	# $1 = name of the serial log
	rm -f "$W/serial.sock"
	qemu-system-arm -M orangepi-pc -m 1G -smp 4 -display none -monitor none -no-reboot \
		-chardev "socket,id=ser,path=$W/serial.sock,server=on,wait=off,logfile=$W/$1.raw,logappend=off" \
		-serial chardev:ser \
		-drive "file=$IMG,format=raw,if=sd" \
		-nic "user,hostfwd=tcp:127.0.0.1:2222-:22" > "$W/$1.qemu.out" 2>&1 &
	QPID=$!
}
qemu_stop() {
	if [ -n "$QPID" ] && kill -0 "$QPID" 2>/dev/null; then kill "$QPID" 2>/dev/null || true; wait "$QPID" 2>/dev/null || true; fi
	QPID=""
}
trap qemu_stop EXIT
wait_log() {	# file, pattern, seconds
	local n=0
	until grep -q -a -e "$2" "$W/$1.raw" 2>/dev/null; do
		n=$((n + 2)); [ "$n" -ge "$3" ] && return 1
		kill -0 "$QPID" 2>/dev/null || return 1
		sleep 2
	done
}
wait_ssh() {	# seconds
	local n=0
	until "${SSH[@]}" true 2>/dev/null; do
		n=$((n + 5)); [ "$n" -ge "$1" ] && return 1
		kill -0 "$QPID" 2>/dev/null || return 1
		sleep 5
	done
}
r() { "${SSH[@]}" "$@"; }		# run a command on the guest
guest_off() {	# $1 = log name. Clean power-off; the emulated board then halts (QEMU keeps running).
	r 'sudo systemctl poweroff' >/dev/null 2>&1 || true
	local n=0
	while kill -0 "$QPID" 2>/dev/null && [ "$n" -lt 400 ]; do
		grep -q -a -e 'reboot: Power down' -e 'reboot: System halted' "$W/$1.raw" 2>/dev/null && break
		sleep 2; n=$((n + 2))
	done
	sleep 2
	qemu_stop
}

# ---- 1. the test copy ---------------------------------------------------------------
say "test copy of the image"
rm -f "$IMG"
cp -c "$HERE/out/pf1007l-sd.img" "$IMG" 2>/dev/null || cp "$HERE/out/pf1007l-sd.img" "$IMG"
truncate -s 4G "$IMG"
docker run --rm -v "$HERE/work":/work pf1007l-image-tools bash -euo pipefail -c '
IMG=/work/qemu/test.img
dd if=/work/uboot/u-boot-qemu-opipc.bin of=$IMG bs=1024 seek=8 conv=notrunc status=none
mcopy -i $IMG@@4M ::/extlinux/extlinux.conf /tmp/e.conf
{ sed "s/^DEFAULT .*/DEFAULT qemu/" /tmp/e.conf
  printf "\n# TEST ONLY (QEMU orangepi-pc): the kernel, initramfs and root file system of the image,\n# the Orange Pi PC device tree, a serial console.\nLABEL qemu\n\tKERNEL /zImage\n\tINITRD /pf-initramfs.img\n\tFDT /dtbs/sun8i-h3-orangepi-pc.dtb\n"
  grep -m1 "APPEND" /tmp/e.conf | sed "s/pf.label=min/pf.label=qemu console=ttyS0,115200/"
} > /tmp/q.conf
mcopy -o -i $IMG@@4M /tmp/q.conf ::/extlinux/extlinux.conf
'
echo "copy: $IMG (the real image is not changed)"

# ---- 2. start 1: first boot ------------------------------------------------------------
say "start 1: first boot (U-Boot -> boot.scr -> extlinux -> kernel -> initramfs -> systemd)"
qemu_start boot1
if wait_ssh 900; then ok "start 1: SSH login with the generated key and the pinned host key"; else bad "start 1: no SSH after 900 s"; clean_log "$W/boot1.raw" "$T/boot1.serial.log"; exit 1; fi
check "U-Boot ran boot.scr and chose Linux" grep -q -a 'pf1007l: start 1 (hex), last start confirmed: no, now: linux' "$W/boot1.raw"
check "U-Boot console input is the null device" grep -q -a '^In: *nulldev' "$W/boot1.raw"
check "U-Boot wrote its state file (fatwrite)" grep -q -a 'bytes written' "$W/boot1.raw"
check "initramfs: stage marker 20 (FAT partition writable)" grep -q -a 'stage=20-initramfs-start disk=mmcblk0' "$W/boot1.raw"
check "initramfs: USB gadget configured through configfs" grep -q -a 'stage=30-gadget-up' "$W/boot1.raw"
check "initramfs: root file system found by PARTUUID" grep -q -a 'stage=35-root-mounted /dev/mmcblk0p2' "$W/boot1.raw"
check "user frame, sudo without a password" r 'test "$(id -un)" = frame && sudo -n true'
check "no password exists: root and frame have no hash in /etc/shadow, user alarm is removed" r 'test "$(sudo grep -c -E "^(root|frame):!:" /etc/shadow)" = 2 && ! grep -q "^alarm:" /etc/passwd'
check "sshd: password authentication is off" r 'sudo /usr/bin/sshd -T | grep -i -qx "passwordauthentication no" && sudo /usr/bin/sshd -T | grep -i -qx "permitrootlogin no"'
check "kernel 7.2.10-1-armv7-ARCH" r 'test "$(uname -r)" = 7.2.10-1-armv7-ARCH'
check "not a systemd 'first boot' (no preset-all)" r '! sudo journalctl -b --no-pager | grep -q "Detected first boot"'
echo "waiting for the first-boot work (root file system growth, pacman keyring) ..."
n=0; until r 'test ! -e /var/lib/pf1007l/firstboot-pending' 2>/dev/null; do n=$((n + 10)); [ "$n" -ge 900 ] && break; sleep 10; done
check "first boot: complete (flag removed)" r 'test ! -e /var/lib/pf1007l/firstboot-pending'
check "first boot: root file system grew to the card size (> 3.4 GiB of 4 GiB)" r 'test "$(df --output=size -BM / | tail -n 1 | tr -dc 0-9)" -gt 3400'
check "first boot: pacman keyring made on the device, ALARM key trusted" r 'sudo pacman-key --list-keys builder@archlinuxarm.org | grep -q "\[  full  \]"'
check "zram swap with lzo-rle" r 'zramctl --noheadings | grep -q lzo-rle && swapon --noheadings | grep -q zram0'
check "earlyoom runs" r 'systemctl is-active -q earlyoom'
check "file capabilities kept (newuidmap)" r 'getcap /usr/bin/newuidmap | grep -q cap_setuid'
check "Wi-Fi modules installed, not loaded, blacklisted for automatic load" r 'modinfo aic8800_fdrv >/dev/null && ! lsmod | grep -q aic8800 && grep -q "blacklist aic8800_fdrv" /etc/modprobe.d/pf1007l-wifi.conf'
check "Wi-Fi and touch firmware files in place" r 'test -s /usr/lib/firmware/aic8800_fw/SDIO/aic8800DC/fmacfw_patch_8800dc_u02.bin && test -s /usr/lib/firmware/silead/gsl_m86_hd.fw'
check "panel module from kernel/out installed in updates/" r 'modinfo -F filename panel-jadard-jd9365da-h3 | grep -q /updates/'
check "/boot is the FAT partition, read-write" r 'grep -q " /boot vfat rw" /proc/mounts'
check "eMMC guard: the SD card is not read-only (rule does not match type SD)" r 'test "$(cat /sys/block/mmcblk0/ro)" = 0 && test "$(cat /sys/block/mmcblk0/device/type)" = SD'
check "only the SD card exists as an MMC block device" r 'test "$(ls /sys/block | grep -c "^mmcblk[0-9]*$")" = 1'
check "stage markers on the FAT partition (20, 30, 35, 40, 50, 60)" r 'cd /boot/pf/stage && ls 20-* 30-gadget-up 35-* 40-* 50-* 60-*'
check "logs on the FAT partition (dmesg, journal, status)" r 'test -s /boot/pf/last/dmesg.txt && test -s /boot/pf/last/journal.txt && test -s /boot/pf/last/status.txt'
check "no start job is stuck (console lock)" r 'test "$(systemctl list-jobs --no-legend | wc -l)" = 0'
r 'systemctl --failed --no-legend --no-pager; echo "state: $(systemctl is-system-running)"; systemd-analyze 2>/dev/null | head -n 1' > "$T/boot1.systemd.txt" 2>&1 || true

say "start 1: USB gadget with NO host (QEMU's inert musb controller)"
check "gadget is bound; the port has no host" r 'test -n "$(cat /sys/kernel/config/usb_gadget/pf1007l/UDC)" && ! grep -q configured /sys/class/udc/*/state'
check "usb0 has 10.55.0.1/24 without carrier" r 'ip -br addr show usb0 | grep -q 10.55.0.1/24'
check "getty on ttyGS0 started and holds no console lock (agetty runs, no '(agetty)')" r 'pgrep -f "agetty --autologin frame" >/dev/null && ! ps -eo comm | grep -Fqx "(agetty)"'
check "systemd-vconsole-setup can run while the getty waits for a host" r 'sudo timeout 60 systemctl restart systemd-vconsole-setup.service'
check "this start is NOT confirmed yet (no host configured the gadget)" r 'test ! -e /boot/pf/linux-ok.env'

say "start 1: USB gadget against the loopback controller (dummy_hcd = the 'Mac' side in the same kernel)"
"${SCP[@]}" "$W/../dummy/dummy_hcd.ko" frame-qemu:/tmp/dummy_hcd.ko
r 'sudo timeout 120 /usr/lib/pf1007l/pf-gadget down; sudo modprobe -a cdc_acm cdc_ncm; sudo insmod /tmp/dummy_hcd.ko; sudo /usr/lib/pf1007l/pf-gadget up 5; sleep 20; sudo dmesg | grep -E "usb 1[0-9]-1|cdc_acm|cdc_ncm|pf-gadget|configfs-gadget" | tail -n 14' > "$T/gadget-loopback.dmesg.txt" 2>&1 || true
check "host side sees the composite device 1d6b:0104 'PF1007L Linux'" r 'lsusb -d 1d6b:0104 && grep -rqs "PF1007L Linux" /sys/bus/usb/devices/*/product'
check "host side binds CDC ACM (ttyACM0) and CDC NCM" r 'test -c /dev/ttyACM0 && lsusb -t | grep -q "Driver=cdc_ncm"'
check "UDC state is 'configured'" r 'grep -q configured /sys/class/udc/dummy_udc.0/state'
check "ACM: automatic login of 'frame' on ttyGS0 (login + shell run)" r 'sleep 15; pgrep -t ttyGS0 -x bash >/dev/null || pgrep -t ttyGS0 login >/dev/null'
# The host side opens ttyACM0 raw (as `screen` does on a Mac), clears the frame's input line
# (CTRL+C), then types two commands. The answer must come back over the ACM link.
r 'sudo sh -c "stty -F /dev/ttyACM0 115200 raw -echo; (timeout 20 cat /dev/ttyACM0 > /tmp/acm.out &) ; sleep 2; printf \"\\003\\r\" > /dev/ttyACM0; sleep 3; printf \"id -un; tty\\r\" > /dev/ttyACM0; sleep 12"; cat /tmp/acm.out' > "$T/gadget-loopback.acm.txt" 2>&1 || true
# The shell's answer has terminal control sequences around it (OSC "ESC ] ... ESC \\" from the
# systemd shell integration, CSI "ESC [ ... x"): remove them, then look for the two answer lines.
acm_answers() {
	python3 -I - "$T/gadget-loopback.acm.txt" <<'PY'
import re, sys
t = open(sys.argv[1], 'rb').read().decode('latin-1')
t = re.sub(r'\x1b\][^\x07\x1b]*(\x07|\x1b\\)', '', t)      # OSC ... BEL or ST
t = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', t).replace('\r', '')
lines = [l.strip() for l in t.split('\n')]
sys.exit(0 if 'frame' in lines and '/dev/ttyGS0' in lines else 1)
PY
}
check "ACM: commands typed on the host side run in the frame's shell (answers: frame, /dev/ttyGS0)" acm_answers
check "NCM: the host side gets an address 10.55.0.x from the frame's DHCP server" r 'sleep 10; ip -br addr | grep -v "^usb0" | grep -q "10\.55\.0\."'
check "NCM: the lease has no router and no DNS (the Mac keeps its own internet)" r 'IF=$(ip -br addr | grep -v "^usb0" | awk "/10\\.55\\.0\\./{print \$1}"); ! ip route show default dev "$IF" | grep -q .'
check "usbwatch wrote the confirmation for U-Boot (linux-ok.env = start counter)" r 'sleep 5; test "$(cat /boot/pf/linux-ok.env)" = "pf_ok=$(sed -n s/^pf_boots=//p /boot/pf/uboot.env)"'
check "stage markers 70-usb-configured and 71-usb-confirmed" r 'ls /boot/pf/stage/70-usb-configured /boot/pf/stage/71-usb-confirmed'
r 'pf-status; echo; cat /boot/pf/stages.log' > "$T/boot1.pf-status.txt" 2>&1 || true
guest_off boot1
clean_log "$W/boot1.raw" "$T/boot1.serial.log"

# ---- 3. start 2: confirmed -> Linux again; this one stays unconfirmed ---------------------
say "start 2: U-Boot must choose Linux (start 1 was confirmed)"
qemu_start boot2
if wait_ssh 900; then ok "start 2: SSH works"; else bad "start 2: no SSH after 900 s"; fi
check "U-Boot: 'last start confirmed: yes, now: linux'" grep -q -a 'pf1007l: start 2 (hex), last start confirmed: yes, now: linux' "$W/boot2.raw"
check "first-boot work does not run again" r 'test ! -e /var/lib/pf1007l/firstboot-pending && ! systemctl is-active -q pf-firstboot'
check "logs of start 1 moved to pf/prev" r 'test -s /boot/pf/prev/dmesg.txt && test "$(cat /boot/pf/stage/.boot)" = 2'
check "shutdown log copy ran at the end of start 1 (stages.log)" r 'grep -q "start=1 .*90-logs-saved shutdown" /boot/pf/stages.log'
guest_off boot2
clean_log "$W/boot2.raw" "$T/boot2.serial.log"

# ---- 4. start 3: unconfirmed -> USB disk mode; CTRL+C must not stop ums ----------------------
say "start 3: U-Boot must choose USB disk mode (start 2 was not confirmed)"
qemu_start boot3
if wait_log boot3 'pf1007l: USB disk mode' 120; then ok "U-Boot: 'last start confirmed: no, now: ums' -> USB disk mode"; else bad "U-Boot did not reach USB disk mode"; fi
check "U-Boot did not start the kernel in start 3" bash -c "! grep -q -a 'Starting kernel' '$W/boot3.raw'"
sleep 5
# CTRL+C, some text and Enter on the console, 20 times in 20 s.
python3 -I - "$W/serial.sock" <<'EOF' || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
for _ in range(20):
    s.send(b"\x03\x03 reset\r\n\x03"); time.sleep(1)
s.close()
EOF
sleep 5
check "console input (CTRL+C, 'reset') does not stop USB disk mode or restart U-Boot" bash -c "test \"\$(grep -a -c 'U-Boot SPL' '$W/boot3.raw')\" = 1 && ! grep -q -a -e 'CTRL+C' -e 'Operation aborted' -e 'INTERRUPT' -e '^=> ' '$W/boot3.raw'"
kill -0 "$QPID" 2>/dev/null && ok "U-Boot still runs in USB disk mode after 30 s" || bad "QEMU ended in USB disk mode"
qemu_stop
clean_log "$W/boot3.raw" "$T/boot3.serial.log"

# ---- 5. read the card as a Mac does ------------------------------------------------------------
say "the FAT partition of the test copy (what a Mac shows for the card)"
rm -rf "$W/fat"; mkdir -p "$W/fat"
docker run --rm -v "$HERE/work":/work pf1007l-image-tools bash -c '
mcopy -s -n -i /work/qemu/test.img@@4M ::/pf /work/qemu/fat/ && mdir -/ -i /work/qemu/test.img@@4M ::/pf' > "$T/fat-pf-listing.txt" 2>&1 || true
cp "$W/fat/pf/uboot.env" "$T/fat-uboot.env.txt" 2>/dev/null || true
cp "$W/fat/pf/stages.log" "$T/fat-stages.log.txt" 2>/dev/null || true
check "after start 3 the card says: pf_boots=3, pf_last=ums, pf_prev_ok=no" bash -c "grep -qx 'pf_boots=3' '$W/fat/pf/uboot.env' && grep -qx 'pf_last=ums' '$W/fat/pf/uboot.env' && grep -qx 'pf_prev_ok=no' '$W/fat/pf/uboot.env'"
check "stages.log on the card has the lines of starts 1 and 2" bash -c "grep -q 'start=1 .*60-multi-user' '$W/fat/pf/stages.log' && grep -q 'start=2 .*60-multi-user' '$W/fat/pf/stages.log'"
# The logs can hold addresses: keep only a short extract in the test folder.
head -n 40 "$W/fat/pf/prev/status.txt" > "$T/fat-prev-status.head.txt" 2>/dev/null || true

say "result: $PASS passed, $FAIL failed  (image/test/results.txt)"
echo "TOTAL: $PASS passed, $FAIL failed; image SHA-256 $(cut -d' ' -f1 "$HERE/out/pf1007l-sd.img.sha256" 2>/dev/null)" >> "$T/results.txt"
rm -f "$IMG"
[ "$FAIL" = 0 ]
