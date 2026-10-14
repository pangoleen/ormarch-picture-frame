#!/usr/bin/env bash
# Build the PF1007L SD-card image (U-Boot build L + Arch Linux ARM armv7h).
#
#   image/build.sh            all steps: uboot dtbs secrets rootfs assemble sums
#   image/build.sh uboot      one step (also: dtbs, secrets, rootfs, assemble, sums, clean)
#   image/build.sh test       QEMU test of the built image (see image/tools/qemu-test.sh)
#
# Runs on the Mac. Needs: git, curl, shasum, ssh-keygen, python3, docker (OrbStack) with
# linux/arm/v7 emulation. For "test": qemu-system-arm (Homebrew).
# It writes only to image/ and to Docker (images pf1007l-*, one temporary container).
# No sudo. No USB device, card reader or external disk is touched. It makes an image FILE.
set -euo pipefail

# ---- pinned inputs -----------------------------------------------------------
UBOOT_REPO="https://github.com/u-boot/u-boot.git"
UBOOT_COMMIT="e50b1e8715011def8aff1588081a2649a2c6cd47"      # v2025.10 (the commit of builds A-E)
WES_PATCH_SHA256="3aa2cbba09a096f9fd20b3f1a0d90c6d178ef7f311bf9f666e00d409a6d41351"  # photo-frame-dashboard 9dd323e7, scripts/a33-uboot/pf1007l-uboot.patch
UBOOT_EPOCH=1791763200                                       # 2026-10-12 00:00 UTC: fixed build time in the binary

ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz"
ALARM_SHA256="${ALARM_SHA256:-ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0}"  # the file of 2026-08-05
ALARM_TAG="tarball-20260805"

KPKG="linux-armv7-7.2.10-1-armv7h.pkg.tar.xz"
KPKG_URL="http://mirror.archlinuxarm.org/armv7h/core/$KPKG"
KPKG_SHA256="b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca"
KVER="7.2.10-1-armv7-ARCH"

# Layout of the card image (MBR).
SIG="50463037"                 # MBR disk signature -> PARTUUID=50463037-01 / -02
IMG_MIB=3072                   # image size; the root file system grows at the first boot
P1_START_MIB=4                 # sector 8192
P1_MIB=256                     # FAT32 "PFBOOT"
EXT4_UUID="50463130-3037-4c00-8000-726f6f746673"
CARD_BYTES=15939928064         # the 16 GB card class of the project (for the size check only)

# ---- paths --------------------------------------------------------------------
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
CACHE="$HERE/cache"; WORK="$HERE/work"; OUT="$HERE/out"; SECRETS="$HERE/secrets"
WES="$ROOT/refs/photo-frame-dashboard"
BUILD_CT="pf1007l-rootfs-build"
TOUCH_FW="${PF1007L_TOUCH_FIRMWARE:-$HERE/vendor/gsl_m86_hd.fw}"
TOUCH_FW_SHA256="e11ffa8a33a56b78f8d2f57925fef1b67ea9a58c264bb5f3a8553ea52b14a9e6"
mkdir -p "$CACHE" "$WORK" "$OUT" "$SECRETS"
chmod 700 "$SECRETS"

say() { printf '\n==== %s\n' "$*"; }
stop() { echo "STOP: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
need() { command -v "$1" >/dev/null || stop "missing tool: $1"; }

# These generated artifacts are deliberately absent from Git.  The scripts that
# make them use pinned source and package hashes, so a clean clone can rebuild
# them before assembling the card image.
ensure_kernel_artifacts() {
	if [ ! -f "$ROOT/kernel/out/sun8i-a33-pf1007l.dtb" ]; then
		echo "kernel artifacts missing; building pinned kernel overlay"
		bash "$ROOT/kernel/build.sh"
	fi
}

ensure_wifi_artifacts() {
	if ! (cd "$ROOT/wifi/out" 2>/dev/null && shasum -a 256 -c SHA256SUMS >/dev/null); then
		echo "Wi-Fi modules missing; building pinned AIC8800 driver"
		bash "$ROOT/wifi/build.sh"
	fi
}

require_touch_firmware() {
	[ -f "$TOUCH_FW" ] || stop "missing proprietary touch firmware: set PF1007L_TOUCH_FIRMWARE (see image/vendor/README.md)"
	[ "$(sha "$TOUCH_FW")" = "$TOUCH_FW_SHA256" ] || stop "touch firmware hash does not match the tested PF1007L board"
}

prepare_image_inputs() {
	ensure_kernel_artifacts
	ensure_wifi_artifacts
	require_touch_firmware
}

# Empty a directory but keep the directory itself: a directory that is removed and made
# again can show stale (empty) content in a container that mounts it right after.
fresh_dir() { mkdir -p "$1"; find "$1" -mindepth 1 -delete; }

free_gib() { df -g "$HERE" | awk 'NR==2 {print $4}'; }

# ---- step: uboot ----------------------------------------------------------------
uboot_src_tar() {
	# A pristine tree of the pinned commit, as a tar on stdout. The reference clone of
	# the project is read-only for us: `git archive` reads it and changes nothing.
	local src="$WES/diagnostics/u-boot"
	if [ -d "$src/.git" ] && git -C "$src" cat-file -e "$UBOOT_COMMIT^{commit}" 2>/dev/null; then
		git -C "$src" archive --format=tar "$UBOOT_COMMIT"
	else
		src="$CACHE/u-boot"
		if [ ! -d "$src/.git" ]; then
			git init -q "$src"
			git -C "$src" remote add origin "$UBOOT_REPO"
		fi
		git -C "$src" cat-file -e "$UBOOT_COMMIT^{commit}" 2>/dev/null \
			|| git -C "$src" fetch -q --depth 1 origin "$UBOOT_COMMIT"
		git -C "$src" archive --format=tar "$UBOOT_COMMIT"
	fi
}

step_uboot() {
	say "U-Boot build L (v2025.10 $UBOOT_COMMIT + 0001 Wes Bos + 0002 build L)"
	[ "$(sha "$HERE/uboot/0001-wes-pf1007l-uboot.patch")" = "$WES_PATCH_SHA256" ] || stop "0001 patch hash differs"
	docker image inspect pf1007l-uboot-build >/dev/null 2>&1 \
		|| docker build -q -t pf1007l-uboot-build -f "$HERE/uboot/Dockerfile.uboot-build" "$HERE/uboot" >/dev/null
	fresh_dir "$WORK/uboot"
	uboot_src_tar | docker run --rm -i -e SOURCE_DATE_EPOCH="$UBOOT_EPOCH" \
		-e PF1007L_WRITABLE_RECOVERY="${PF1007L_WRITABLE_RECOVERY:-0}" \
		-v "$HERE/uboot":/u:ro -v "$WORK/uboot":/out pf1007l-uboot-build /u/build-in-container.sh
	# The SPL must stay clear of the early stack (limit from Wes Bos's build-uboot.sh).
	python3 -I - "$WORK/uboot/u-boot-pf1007l-L.bin" <<'EOF'
import sys
d = open(sys.argv[1], 'rb').read()
spl = d[:0x6000]
end = max(i for i, b in enumerate(spl) if b) + 1
print(f"SPL code ends at {end:#x} (limit 0x5e00)")
if d[4:12] != b"eGON.BT0": sys.exit("STOP: no eGON header")
if end > 0x5e00: sys.exit("STOP: SPL is too close to the stack/global-data area")
if b"ums: refused write" not in d: sys.exit("STOP: the read-only USB disk patch is not in the binary")
EOF
	grep -q '^CONFIG_MMC_SUNXI_SLOT_EXTRA=-1$' "$WORK/uboot/u-boot-pf1007l-L.config" || stop "build L must not have an eMMC slot"
	grep -q '^CONFIG_SUNXI_CONSOLE_NO_PINMUX=y$' "$WORK/uboot/u-boot-pf1007l-L.config" || stop "console pin mux must be off"
	for v in 'DRAM_ZQ=31739' 'DRAM_CLK=456' 'AXP_DCDC1_VOLT=3300' 'AXP_DCDC2_VOLT=1200' 'AXP_DCDC3_VOLT=1200' 'AXP_ALDO1_VOLT=3300' 'CONS_INDEX=1' 'BOOTDELAY=-2'; do
		grep -q "^CONFIG_$v\$" "$WORK/uboot/u-boot-pf1007l-L.config" || stop "config check failed: $v"
	done
	echo "config checks: OK (DRAM, voltages, console, no eMMC slot, read-only USB disk)"
}

# ---- step: dtbs -----------------------------------------------------------------
step_dtbs() {
	say "kernel device trees (min, pmic, full)"
	local inc="$ROOT/refs/kernel/linux-7.2.10"
	[ -f "$inc/arch/arm/boot/dts/allwinner/sun8i-a33.dtsi" ] || inc="$ROOT/refs/linux-snippets"
	[ -f "$inc/arch/arm/boot/dts/allwinner/sun8i-a33.dtsi" ] || stop "no kernel .dtsi files: need refs/kernel/linux-7.2.10 or refs/linux-snippets (see kernel/README.md)"
	[ -f "$ROOT/kernel/dts/sun8i-a33-pf1007l.dts" ] || stop "no board draft: kernel/dts/sun8i-a33-pf1007l.dts"
	echo "include tree: ${inc#"$ROOT"/}"
	fresh_dir "$WORK/dtbs"
	# kernel/out/sun8i-a33-pf1007l.dtb (the kernel work's DTB) replaces our compile of the draft
	# for the label "full". The copy is made INSIDE the container: a file that the container
	# wrote and the Mac then replaced can look damaged to the next container (stale cache).
	local kout="$ROOT/kernel/out"
	[ -d "$kout" ] || { kout="$WORK/no-kernel-out"; mkdir -p "$kout"; }
	docker run --rm -v "$HERE/dts":/dts:ro -v "$ROOT/kernel/dts":/kdts:ro -v "$inc":/inc:ro \
		-v "$kout":/kout:ro -v "$WORK/dtbs":/out pf1007l-uboot-build sh -euc '
			/dts/build-dtbs.sh
			if [ -f /kout/sun8i-a33-pf1007l.dtb ]; then
				cp /kout/sun8i-a33-pf1007l.dtb /out/sun8i-a33-pf1007l-full.dtb
				echo "label full: kernel/out/sun8i-a33-pf1007l.dtb ($(sha256sum /out/sun8i-a33-pf1007l-full.dtb | cut -c1-16))"
			else
				echo "label full: our compile of the draft kernel/dts/sun8i-a33-pf1007l.dts (kernel/out has no DTB)"
			fi
			/dts/check-dtbs.sh'
}

# ---- step: secrets ----------------------------------------------------------------
step_secrets() {
	say "SSH keys (image/secrets, git-ignored)"
	[ -f "$SECRETS/frame_id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C 'pf1007l frame user (Mac side)' -f "$SECRETS/frame_id_ed25519"
	[ -f "$SECRETS/ssh_host_ed25519_key" ] || ssh-keygen -q -t ed25519 -N '' -C 'pf1007l host key' -f "$SECRETS/ssh_host_ed25519_key"
	chmod 600 "$SECRETS/frame_id_ed25519" "$SECRETS/ssh_host_ed25519_key"
	local hostpub; hostpub="$(cut -d' ' -f1,2 "$SECRETS/ssh_host_ed25519_key.pub")"
	{
		echo "10.55.0.1 $hostpub"
		echo "pf1007l.local $hostpub"
		echo "[127.0.0.1]:2222 $hostpub"
	} > "$SECRETS/known_hosts"
	cat > "$SECRETS/ssh_config" <<EOF
# ssh -F image/secrets/ssh_config frame
Host frame
	HostName 10.55.0.1
Host frame-mdns
	HostName pf1007l.local
Host frame-qemu
	HostName 127.0.0.1
	Port 2222
Host *
	User frame
	IdentityFile $SECRETS/frame_id_ed25519
	IdentitiesOnly yes
	UserKnownHostsFile $SECRETS/known_hosts
	StrictHostKeyChecking yes
	ConnectTimeout 5
EOF
	echo "key fingerprints: $(ssh-keygen -lf "$SECRETS/frame_id_ed25519.pub" | cut -d' ' -f2) (user), $(ssh-keygen -lf "$SECRETS/ssh_host_ed25519_key.pub" | cut -d' ' -f2) (host)"
}

# ---- step: rootfs -------------------------------------------------------------------
fetch() {	# url, file, sha256 ("" = no check)
	if [ ! -f "$2" ]; then curl -L --fail --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; fi
	if [ -n "$3" ] && [ "$(sha "$2")" != "$3" ]; then stop "$(basename "$2"): SHA-256 is $(sha "$2"), expected $3"; fi
}

step_rootfs() {
	say "root file system (Arch Linux ARM armv7h, in Docker under QEMU)"
	[ "$(free_gib)" -ge 6 ] || stop "less than 6 GiB free on the internal disk"
	fetch "$ALARM_URL" "$CACHE/ArchLinuxARM-armv7-latest.tar.gz" "$ALARM_SHA256"
	fetch "$ALARM_URL.sig" "$CACHE/ArchLinuxARM-armv7-latest.tar.gz.sig" ""
	if [ -f "$ROOT/refs/kernel/pkgcache/$KPKG" ] && [ ! -f "$CACHE/$KPKG" ] && [ "$(sha "$ROOT/refs/kernel/pkgcache/$KPKG")" = "$KPKG_SHA256" ]; then
		cp "$ROOT/refs/kernel/pkgcache/$KPKG" "$CACHE/$KPKG"
	fi
	fetch "$KPKG_URL" "$CACHE/$KPKG" "$KPKG_SHA256"
	fetch "$KPKG_URL.sig" "$CACHE/$KPKG.sig" ""

	docker image inspect "pf1007l-alarm:$ALARM_TAG" >/dev/null 2>&1 \
		|| docker import --platform linux/arm/v7 "$CACHE/ArchLinuxARM-armv7-latest.tar.gz" "pf1007l-alarm:$ALARM_TAG" >/dev/null
	[ "$(docker run --rm --platform linux/arm/v7 "pf1007l-alarm:$ALARM_TAG" uname -m)" = armv7l ] || stop "no linux/arm/v7 emulation in Docker"

	# Inputs for the container: copies, so that the container sees only what it needs.
	# A new directory name for each build: the container cannot see stale content of an old one.
	rm -rf "$WORK"/in.*
	local in; in="$(mktemp -d "$WORK/in.XXXXXX")"
	mkdir -p "$in/wifi" "$in/aic8800DC" "$in/touch" "$in/secrets" "$in/kernel-out" "$WORK/manifest"
	cp "$CACHE/$KPKG" "$CACHE/$KPKG.sig" "$in/"
	echo "$SIG" > "$in/disk-signature"
	(cd "$ROOT/wifi/out" && shasum -a 256 -c SHA256SUMS >/dev/null) || stop "wifi/out: SHA256SUMS check failed"
	cp "$ROOT"/wifi/out/*.ko "$in/wifi/"
	local fw="$ROOT/refs/aic/radxa-pkg_aic8800/src/SDIO/driver_fw/fw/aic8800DC"
	[ -d "$fw" ] || stop "no AIC8800DC firmware: run wifi/build.sh first (it clones radxa-pkg/aic8800)"
	cp "$fw"/* "$in/aic8800DC/"
	cp "$TOUCH_FW" "$in/touch/gsl_m86_hd.fw"
	cp "$SECRETS/frame_id_ed25519.pub" "$SECRETS/ssh_host_ed25519_key" "$SECRETS/ssh_host_ed25519_key.pub" "$in/secrets/"
	if ls "$ROOT"/kernel/out/*.ko >/dev/null 2>&1; then cp "$ROOT"/kernel/out/*.ko "$in/kernel-out/"; fi

	docker rm -f "$BUILD_CT" >/dev/null 2>&1 || true
	docker run --platform linux/arm/v7 --name "$BUILD_CT" \
		-v "$HERE":/image:ro -v "$in":/in -v "$WORK/manifest":/manifest \
		"pf1007l-alarm:$ALARM_TAG" /bin/bash /image/rootfs-build/inside.sh 2>&1 | tee "$WORK/rootfs-build.log"
	[ "$(docker inspect -f '{{.State.ExitCode}}' "$BUILD_CT")" = 0 ] || stop "the root file system build failed (see image/work/rootfs-build.log)"
	rm -rf "$in/secrets"
}

# ---- step: assemble --------------------------------------------------------------------
step_assemble() {
	say "card image (MBR, U-Boot at 8 KiB, FAT32 at sector $((P1_START_MIB * 2048)), ext4)"
	docker inspect "$BUILD_CT" >/dev/null 2>&1 || stop "no build container: run the rootfs step first"
	docker image inspect pf1007l-image-tools >/dev/null 2>&1 \
		|| docker build -q -t pf1007l-image-tools -f "$HERE/tools/Dockerfile.image-tools" "$HERE/tools" >/dev/null
	rm -rf "$WORK"/stage.*
	local stage; stage="$(mktemp -d "$WORK/stage.XXXXXX")"
	mkdir -p "$stage/dtbs"
	cp "$WORK/uboot/u-boot-pf1007l-L.bin" "$stage/u-boot.bin"
	cp "$WORK/uboot/boot.scr" "$WORK/uboot/boot.cmd" "$stage/"
	cp "$WORK"/dtbs/*.dtb "$stage/dtbs/"
	rm -f "$OUT/pf1007l-sd.img"
	docker export "$BUILD_CT" | docker run --rm -i \
		-e SIG="$SIG" -e IMG_MIB="$IMG_MIB" -e P1_START_MIB="$P1_START_MIB" -e P1_MIB="$P1_MIB" \
		-e EXT4_UUID="$EXT4_UUID" -e HOSTNAME_NEW=pf1007l \
		-v "$HERE":/image:ro -v "$stage":/stage:ro -v "$OUT":/out \
		pf1007l-image-tools /image/tools/assemble-in-container.sh
	[ "$(stat -f %z "$OUT/pf1007l-sd.img")" -le "$CARD_BYTES" ] || stop "the image is larger than the card"
	# Cross-check from the Mac side: the files that went into the image are the files we built.
	local f h
	for f in dtbs/sun8i-a33-pf1007l-min.dtb dtbs/sun8i-a33-pf1007l-pmic.dtb dtbs/sun8i-a33-pf1007l-full.dtb; do
		h="$(sha "$WORK/$f")"
		grep -q "^$h  ./$f\$" "$OUT/boot-partition-files.sha256" || stop "$f in the image is not the file in work/dtbs"
	done
	h="$(sha "$WORK/uboot/boot.scr")"
	grep -q "^$h  ./boot.scr\$" "$OUT/boot-partition-files.sha256" || stop "boot.scr in the image is not the built file"
	if [ -f "$ROOT/kernel/out/sun8i-a33-pf1007l.dtb" ]; then
		[ "$(sha "$ROOT/kernel/out/sun8i-a33-pf1007l.dtb")" = "$(sha "$WORK/dtbs/sun8i-a33-pf1007l-full.dtb")" ] || stop "label full is not kernel/out/sun8i-a33-pf1007l.dtb"
	fi
	python3 -I - "$OUT/pf1007l-sd.img" "$WORK/uboot/u-boot-pf1007l-L.bin" "$SIG" <<'EOF2'
import struct, sys
img = open(sys.argv[1], 'rb'); ub = open(sys.argv[2], 'rb').read()
mbr = img.read(512)
if mbr[510:512] != b"\x55\xaa" or struct.unpack('<I', mbr[440:444])[0] != int(sys.argv[3], 16):
    sys.exit("STOP: MBR or disk signature is wrong")
p1 = struct.unpack('<I', mbr[454:458])[0]
img.seek(8192)
if img.read(len(ub)) != ub: sys.exit("STOP: U-Boot at 8 KiB is not the build L binary")
if 8192 + len(ub) > p1 * 512: sys.exit("STOP: U-Boot overlaps partition 1")
print(f"image self-check: MBR ok, U-Boot build L at 8 KiB ({len(ub)} bytes), partition 1 at sector {p1}, DTBs and boot.scr equal to the built files")
EOF2
	echo "image: $(stat -f %z "$OUT/pf1007l-sd.img") bytes, on disk: $(du -h "$OUT/pf1007l-sd.img" | cut -f1) (sparse)"
}

# ---- step: sums ------------------------------------------------------------------------
step_sums() {
	say "hashes and manifest"
	cp "$WORK/uboot/u-boot-pf1007l-L.bin" "$WORK/uboot/u-boot-pf1007l-L.config" "$WORK/uboot/boot.scr" "$OUT/"
	cp "$WORK/manifest/packages.txt" "$OUT/packages.txt"
	cp "$WORK/manifest/initramfs-modules.txt" "$OUT/initramfs-modules.txt"
	(cd "$OUT" && shasum -a 256 pf1007l-sd.img > pf1007l-sd.img.sha256 && cat pf1007l-sd.img.sha256)
	{
		echo "PF1007L SD-card image manifest"
		echo "built (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
		echo "image: pf1007l-sd.img, $(stat -f %z "$OUT/pf1007l-sd.img") bytes, SHA-256 $(cut -d' ' -f1 "$OUT/pf1007l-sd.img.sha256")"
		echo "MBR disk signature: $SIG; partition 1 FAT32 PFBOOT at sector $((P1_START_MIB * 2048)), $P1_MIB MiB; partition 2 ext4 at sector $(((P1_START_MIB + P1_MIB) * 2048))"
		echo "U-Boot: v2025.10 $UBOOT_COMMIT + 0001 ($WES_PATCH_SHA256) + 0002 ($(sha "$HERE/uboot/0002-pf1007l-linux-boot.patch"))"
		echo "U-Boot build L binary SHA-256: $(sha "$OUT/u-boot-pf1007l-L.bin")"
		echo "boot.scr SHA-256: $(sha "$OUT/boot.scr")"
		echo "Arch Linux ARM tarball SHA-256: $ALARM_SHA256"
		echo "kernel package: $KPKG SHA-256 $KPKG_SHA256 (modules: $KVER)"
		echo "Wi-Fi modules:"; sed 's/^/  /' "$ROOT/wifi/out/SHA256SUMS"
		echo "touch firmware SHA-256: $(sha "$TOUCH_FW")"
		echo "device trees:"; (cd "$WORK/dtbs" && shasum -a 256 ./*.dtb | sed 's/^/  /')
		echo "root file system: $(cat "$OUT/rootfs-size-mib.txt") MiB in $(wc -l < "$OUT/packages.txt" | tr -d ' ') packages (list: packages.txt)"
		echo "Docker images: uboot-build $(docker image inspect -f '{{.Id}}' pf1007l-uboot-build), image-tools $(docker image inspect -f '{{.Id}}' pf1007l-image-tools)"
	} > "$OUT/MANIFEST.txt"
	echo "manifest: image/out/MANIFEST.txt"
}

step_clean() {
	say "remove the build container and the imported base image (the image file stays)"
	docker rm -f "$BUILD_CT" >/dev/null 2>&1 || true
	docker image rm "pf1007l-alarm:$ALARM_TAG" >/dev/null 2>&1 || true
	rm -rf "$WORK"/in.* "$WORK"/stage.* "$WORK/in" "$WORK/stage"
}

need git; need curl; need shasum; need docker; need python3; need ssh-keygen
case "${1:-all}" in
all) prepare_image_inputs; step_uboot; step_dtbs; step_secrets; step_rootfs; step_assemble; step_sums ;;
uboot) step_uboot ;;
dtbs) ensure_kernel_artifacts; step_dtbs ;;
secrets) step_secrets ;;
rootfs) prepare_image_inputs; step_secrets; step_rootfs ;;
assemble) step_assemble ;;
sums) step_sums ;;
clean) step_clean ;;
test) shift; exec "$HERE/tools/qemu-test.sh" "$@" ;;
*) stop "unknown step: $1" ;;
esac
