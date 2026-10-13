# Test container for the Omarchy 4 shell stack on Arch Linux ARM.
# The same file builds the 32-bit test image and the 64-bit control image:
#
#   docker build --platform linux/arm/v7 -t omf-smoke:armv7 port/
#   docker build --platform linux/arm64  -t omf-smoke:arm64 port/
#
# Run (the Omarchy clone and port/ are mounted, not copied):
#
#   docker run -d --name omf-armv7 --platform linux/arm/v7 \
#     -v "$PWD/refs/omarchy:/omarchy:ro" -v "$PWD/port:/port" omf-smoke:armv7
#   docker exec -u frame omf-armv7 /port/run-shell-test.sh trivial-panel /port/qml-trivial/panel.qml 30
#
# Base image: menci/archlinuxarm:base, index sha256:f66f11c5442a9a1d27ebea0190eb79f9a0d654eb2699441ec69ad2fc3c81d54c
# (built 2026-10-12 06:57 UTC by pacstrap from the official Arch Linux ARM mirrors).
# Each platform is pinned by its own manifest digest. Do NOT pin the index digest: a Docker engine
# that already has one platform of that index gives you that platform for every --platform value
# (this happened in the first try: the "arm64" image was armv7l). Always check `uname -m`.
# The packages come from the live mirror at build time, so a later build gets later versions.
ARG TARGETARCH
FROM menci/archlinuxarm@sha256:9c43138e53ee540e75530308e979cd1e87d87250f569a88521866d5345ebf25b AS base-arm
FROM menci/archlinuxarm@sha256:04fa7026ab3979652115a8fea047f50c69fd1a71bc21bd7cb3b3a9aa86a8bb0d AS base-arm64
FROM base-${TARGETARCH}

# --disable-sandbox: pacman 7 tries to put its downloader in a Landlock sandbox. Under QEMU user
# emulation that fails ("Landlock is not supported by the kernel"). This is an emulation artefact.
RUN pacman -Syu --noconfirm --disable-sandbox \
 && pacman -S --needed --noconfirm --disable-sandbox \
      quickshell hyprland foot mesa \
      sway grim wlr-randr mesa-utils \
      dbus pipewire wireplumber upower libnotify \
      inotify-tools gum jq socat procps-ng python imagemagick git \
      ttf-dejavu ttf-jetbrains-mono-nerd \
 && pacman -Q > /root/packages-installed.txt \
 && rm -f /var/cache/pacman/pkg/*

# sway has the file capability cap_sys_nice. Docker's default capability set does not include it,
# so an unprivileged user gets "Operation not permitted" on exec. Remove the file capability.
RUN setcap -r /usr/bin/sway \
 && useradd -m -u 1000 frame \
 && mkdir -p /run/user/1000 /run/dbus \
 && chown frame:frame /run/user/1000 && chmod 700 /run/user/1000 \
 && printf '%s\n' '#!/bin/bash' \
      '# Start a system D-Bus (no services on it), then keep the container alive.' \
      'mkdir -p /run/dbus; rm -f /run/dbus/pid' \
      'dbus-daemon --system --fork' \
      'exec "$@"' > /usr/local/bin/entrypoint.sh \
 && chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
