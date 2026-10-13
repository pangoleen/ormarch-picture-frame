#!/bin/bash
# Build the 32-bit ARM test VM from a clean state. No root on the host. No QEMU build.
#
#   vm/build.sh            make vm/out/zImage, vm/out/root.qcow2 and the SSH key
#   vm/build.sh provision  boot the VM and install the test packages in the guest (vm/guest/provision.sh)
#
# Inputs (pinned by SHA-256; the script stops if a hash is different):
#   ArchLinuxARM-armv7-latest.tar.gz        root file system ("latest" is a moving name: the hash pins it)
#   linux-armv7-7.2.10-1-armv7h.pkg.tar.xz  stock Arch Linux ARM kernel: zImage and modules
# The script reads them from image/cache/ (another agent's cache) if they are there, else it downloads to vm/cache/.
set -euo pipefail
VM=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$VM")

TARBALL=ArchLinuxARM-armv7-latest.tar.gz
TARBALL_URL=http://os.archlinuxarm.org/os/$TARBALL
TARBALL_SHA=ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0
KPKG=linux-armv7-7.2.10-1-armv7h.pkg.tar.xz
KPKG_URL=http://mirror.archlinuxarm.org/armv7h/core/$KPKG
KPKG_SHA=b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca
KVER=7.2.10-1-armv7-ARCH
BUILDER_IMAGE=alpine:3          # native arm64 helper: only unpacks files and runs mke2fs
DISK_SIZE=${DISK_SIZE:-10G}     # virtual size; the qcow2 file grows on use

mkdir -p "$VM"/{out,keys,cache,logs,run}

fetch() { # name url sha
  local f
  for f in "$ROOT/image/cache/$1" "$VM/cache/$1"; do
    if [[ -f $f ]] && [[ $(shasum -a 256 "$f" | cut -d' ' -f1) == "$3" ]]; then echo "$f"; return; fi
  done
  echo "download $2" >&2
  curl -fL --retry 3 -o "$VM/cache/$1" "$2" >&2
  [[ $(shasum -a 256 "$VM/cache/$1" | cut -d' ' -f1) == "$3" ]] || { echo "HASH MISMATCH for $1 (the upstream file changed; update the pin)" >&2; exit 1; }
  echo "$VM/cache/$1"
}

if [[ ${1:-} == provision ]]; then
  "$VM/run.sh" start
  "$VM/run.sh" wait
  "$VM/run.sh" scp "$VM/guest" root@vm:/root/
  "$VM/run.sh" ssh root 'bash /root/guest/provision.sh' 2>&1 | tee "$VM/logs/provision.log"
  exit 0
fi

tarball=$(fetch "$TARBALL" "$TARBALL_URL" "$TARBALL_SHA")
kpkg=$(fetch "$KPKG" "$KPKG_URL" "$KPKG_SHA")

# 1. Kernel: the zImage of the stock package, not changed.
bsdtar -xOf "$kpkg" boot/zImage > "$VM/out/zImage"
shasum -a 256 "$VM/out/zImage" | tee "$VM/logs/zImage.sha256"

# 2. SSH key for the test VM only (never used for another host).
[[ -f $VM/keys/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -C omarchy-vm-test -f "$VM/keys/id_ed25519"

# 3. Root file system: unpack the tarball in a container, add the 7.2.10-1 modules, write an ext4 image with
#    mke2fs -d (no mount, no root on the host), then convert to qcow2 on the host.
#    Left out to save disk space: /usr/lib/firmware (a VM needs none) and the old 7.1.6 kernel.
#    Their entries are removed from the pacman database too, so "pacman -Syu" does not bring them back.
indir=$(mktemp -d "$VM/cache/in.XXXXXX"); trap 'rm -rf "$indir"' EXIT
cp "$tarball" "$kpkg" "$VM/keys/id_ed25519.pub" "$indir/"
docker run --rm --platform linux/arm64 -v "$indir":/in:ro -v "$VM/out":/out "$BUILDER_IMAGE" sh -euc '
  apk add --no-cache libarchive-tools e2fsprogs kmod >/dev/null
  mkdir /r
  # --no-xattrs: the tarball has SMACK64 labels on all files (the container cannot set them) and a file
  # capability on newuidmap and newgidmap only (the guest "pacman -Syu" installs shadow again).
  bsdtar -xpf /in/'"$TARBALL"' -C /r --no-xattrs --exclude "./usr/lib/firmware/*" --exclude "./boot/*" --exclude "./usr/lib/modules/*"
  rm -rf /r/var/lib/pacman/local/linux-firmware* /r/var/lib/pacman/local/linux-armv7-*
  rm -f /r/etc/mkinitcpio.d/linux-armv7.preset   # no kernel package in the guest: the pacman hook has nothing to build
  bsdtar -xpf /in/'"$KPKG"' -C /r usr/lib/modules
  depmod -b /r '"$KVER"'
  for h in root home/alarm; do
    mkdir -p /r/$h/.ssh; cp /in/id_ed25519.pub /r/$h/.ssh/authorized_keys; chmod 700 /r/$h/.ssh; chmod 600 /r/$h/.ssh/authorized_keys
  done
  chown -R 1000:1000 /r/home/alarm/.ssh
  echo omarchy-vm > /r/etc/hostname
  # sshd: key login only
  printf "PasswordAuthentication no\nPermitRootLogin prohibit-password\nUseDNS no\n" > /r/etc/ssh/sshd_config.d/10-vm.conf
  # modules that a VM needs early and that udev may load late
  printf "virtio_net\nvirtio-gpu\nvirtio_input\nevdev\nvirtio_rng\n" > /r/etc/modules-load.d/vm.conf
  du -sh /r | sed "s/^/rootfs tree: /"
  mke2fs -q -t ext4 -L vmroot -E lazy_itable_init=1,lazy_journal_init=1 -d /r /out/root.raw '"$DISK_SIZE"'
'
# Alpine 3.24 arm64 has no qemu-img package, so the host qemu-img makes the qcow2 file.
qemu-img convert -f raw -O qcow2 "$VM/out/root.raw" "$VM/out/root.qcow2"
rm -f "$VM/out/root.raw"
qemu-img info "$VM/out/root.qcow2" | tee "$VM/logs/root-image-info.txt"
echo "OK. Next: vm/build.sh provision"
