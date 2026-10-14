#!/bin/bash
# PF1007L speaker, automatic rotation and automatic brightness (light sensor). Run on the frame as user frame, from a clone of this
# repository, after wifi/install-uart-bluetooth.sh --activate has made the full-bluetooth label.
#
#   port/frame/install-audio-rotate.sh --activate          make the full-audio label, services, mixer
#   port/frame/install-audio-rotate.sh --rollback          back to full-bluetooth, services off
#   port/frame/install-audio-rotate.sh --build-only FILE   only build the device tree to FILE
#
# The full-bluetooth label and its device tree stay untouched. Measured basis: docs/experiments.md E062.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
conf=/boot/extlinux/extlinux.conf
base=/boot/dtbs/sun8i-a33-pf1007l-bluetooth.dtb
out=/boot/dtbs/sun8i-a33-pf1007l-audio.dtb

build() {
  command -v dtc >/dev/null && command -v fdtoverlay >/dev/null || { echo "STOP: missing dtc or fdtoverlay"; exit 1; }
  [[ -f $base ]] || { echo "STOP: $base is missing. Run wifi/install-uart-bluetooth.sh --activate first."; exit 1; }
  local tmp
  tmp=$(mktemp -d)
  dtc -@ -I dts -O dtb -o "$tmp/accel.dtbo" "$root/kernel/dts/pf1007l-accelerometer.dtso"
  dtc -@ -I dts -O dtb -o "$tmp/speaker.dtbo" "$root/kernel/dts/pf1007l-audio-speaker.dtso"
  dtc -@ -I dts -O dtb -o "$tmp/light.dtbo" "$root/kernel/dts/pf1007l-light-sensor.dtso"
  fdtoverlay -i "$base" -o "$tmp/audio.dtb" "$tmp/accel.dtbo" "$tmp/speaker.dtbo" "$tmp/light.dtbo"
  # The overlay must not claim the amplifier pin: pf-speaker-amp drives it from user space.
  if dtc -I dtb -O dts "$tmp/audio.dtb" 2>/dev/null | grep -q 'speaker-amp-hog'; then
    echo "STOP: the device tree claims the amplifier pin"; exit 1
  fi
  install -m 644 "$tmp/audio.dtb" "$1" 2>/dev/null || sudo install -m 755 "$tmp/audio.dtb" "$1"
  rm -rf "$tmp"
}

activate() {
  [[ $(id -un) == "frame" && $(uname -m) == "armv7l" ]] || { echo "STOP: run on the frame as user frame"; exit 1; }
  [[ $(uname -r) == 7.2.10-1-* ]] || { echo "STOP: tested only on kernel 7.2.10-1"; exit 1; }
  sudo env ALL_PROXY="${ALL_PROXY:-}" pacman -S --noconfirm --needed \
    alsa-utils pipewire-audio pipewire-alsa pipewire-pulse
  build "$out"

  sudo cp "$conf" "$conf.before-full-audio.$(date -u +%Y%m%dT%H%M%SZ)"
  if ! grep -q "^LABEL full-audio$" "$conf"; then
    append=$(awk '/^LABEL full-bluetooth$/ {f=1} f && /^[ \t]*APPEND/ {print; exit}' "$conf" |
      sed 's/pf\.label=full-bluetooth/pf.label=full-audio/')
    [[ $append == *pf.label=full-audio* ]] || { echo "STOP: no full-bluetooth APPEND line in $conf"; exit 1; }
    printf '\n# Bluetooth + accelerometer + speaker; the key converter is left to the light sensor service.\nLABEL full-audio\n\tKERNEL /zImage\n\tINITRD /pf-initramfs.img\n\tFDT /dtbs/%s\n%s\n' \
      "$(basename "$out")" "$append" | sudo tee -a "$conf" >/dev/null
  fi

  sudo install -m 755 "$here/pf-speaker-amp" /usr/local/bin/pf-speaker-amp
  sudo install -m 644 "$here/pf-speaker-amp.service" /etc/systemd/system/pf-speaker-amp.service
  sudo install -m 644 "$here/pf1007l-lradc.conf" /etc/modprobe.d/pf1007l-lradc.conf
  sudo install -m 755 "$here/pf-auto-brightness" /usr/local/bin/pf-auto-brightness
  sudo install -m 644 "$here/pf-auto-brightness.service" /etc/systemd/system/pf-auto-brightness.service
  sudo systemctl daemon-reload
  sudo systemctl enable pf-speaker-amp.service pf-auto-brightness.service
  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
  install -m 755 "$here/pf-autorotate" "$HOME/.local/bin/pf-autorotate"
  install -m 644 "$here/pf-autorotate.service" "$HOME/.config/systemd/user/pf-autorotate.service"
  systemctl --user daemon-reload
  systemctl --user enable pf-autorotate.service pipewire-pulse.socket

  # The codec gives the audio interface no clock until this switch is on; playback then fails
  # with an I/O error. alsa-restore applies the file at each boot when the card appears.
  sudo install -m 644 "$here/asound.state" /var/lib/alsa/asound.state

  sudo sed -i 's/^DEFAULT[ \t].*/DEFAULT full-audio/' "$conf"
  sync
  echo "Done. Reboot. Then test: speaker-test -c 2 -t sine -l 1"
  echo "Rollback: $0 --rollback"
}

rollback() {
  sudo cp "$conf" "$conf.before-audio-rollback.$(date -u +%Y%m%dT%H%M%SZ)"
  sudo sed -i 's/^DEFAULT[ \t].*/DEFAULT full-bluetooth/' "$conf"
  sudo systemctl disable --now pf-speaker-amp.service pf-auto-brightness.service || true
  systemctl --user disable --now pf-autorotate.service || true
  sync
  echo "Default label: full-bluetooth. Reboot."
}

case "${1:-}" in
  --activate) activate ;;
  --rollback) rollback ;;
  --build-only) build "${2:?give an output file}" ;;
  *) echo "Use: $0 --activate | --rollback | --build-only FILE"; exit 1 ;;
esac
