#!/bin/bash
# Runs in a native arm64 Arch Linux ARM container. Cross-compiles Hypoland for armv7h with clang and an
# ALARM armv7h sysroot that pacman fills with no emulation (--noscriptlet: the scripts are armv7 programs).
#   in-container.sh setup      host tools + sysroot
#   in-container.sh configure  cmake configure only
#   in-container.sh build      full build (ninja), then file(1) on the result
set -uo pipefail
SRC=/work/src; B=/build; LOG=/logs
mkdir -p $LOG

setup() {
  pacman -Syu --disable-sandbox --noconfirm --needed --noprogressbar clang lld cmake ninja pkgconf git python file \
    hyprwayland-scanner hyprwire wayland wayland-protocols hwdata 2>&1 | tail -5
  cat > /tmp/pacman-armv7.conf <<'CONF'
[options]
Architecture = armv7h
SigLevel = Required DatabaseOptional
[core]
Server = http://mirror.archlinuxarm.org/armv7h/$repo
[extra]
Server = http://mirror.archlinuxarm.org/armv7h/$repo
[alarm]
Server = http://mirror.archlinuxarm.org/armv7h/$repo
CONF
  mkdir -p /sysroot/var/lib/pacman /tmp/pkg
  # "hyprland" pulls every run-time library with its headers (Arch packages are not split into -dev).
  # The rest are the build-time parts of the Hypoland PKGBUILD and of its CMakeLists.txt.
  pacman --config /tmp/pacman-armv7.conf --root /sysroot --dbpath /sysroot/var/lib/pacman --cachedir /tmp/pkg \
    --gpgdir /etc/pacman.d/gnupg --disable-sandbox --noscriptlet --noconfirm --noprogressbar -Sy \
    glibc gcc linux-api-headers hyprland hyprwayland-scanner hyprland-protocols wayland-protocols hwdata xorgproto \
    libei libcanberra sdbus-cpp lua re2 muparser lcms2 libdisplay-info seatd 2>&1 | tee $LOG/sysroot-pacman.log | tail -15
  rm -rf /tmp/pkg
  du -sh /sysroot | tee -a $LOG/sysroot-pacman.log
  pacman --root /sysroot --dbpath /sysroot/var/lib/pacman -Q > $LOG/sysroot-packages.txt
}

configure() {
  # Copy the source into the container's own file system. The /src bind mount comes from macOS and ignores
  # case: there "#include <version>" (a C++ standard header) opens Hypoland's ./VERSION file and the build fails.
  rm -rf /work && mkdir -p /work && cp -a /src /work/src
  git config --global --add safe.directory '*'
  clang --version | head -1
  rm -rf $B
  ( time cmake -S $SRC -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_SKIP_RPATH=ON \
      -DCMAKE_TOOLCHAIN_FILE=/vmh/toolchain-armv7.cmake ) 2>&1 | tee $LOG/configure.log
}

build() {
  ( time ninja -C $B -k 0 -j ${JOBS:-8} ) > $LOG/build.log 2>&1
  echo "ninja exit status: $?" | tee -a $LOG/build.log
  grep -c 'error:' $LOG/build.log
  ls -l $B/hypoland $B/hyprctl/hyprctl 2>&1; file $B/hypoland 2>&1
}

"$@"
