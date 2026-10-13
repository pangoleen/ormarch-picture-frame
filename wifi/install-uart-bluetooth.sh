#!/bin/bash
# Install or remove native Bluetooth LE over UART1. Run on the frame.
#   sudo wifi/install-uart-bluetooth.sh --activate   make full-bluetooth label + service
#   sudo wifi/install-uart-bluetooth.sh --rollback   back to full label, service off
# Keeps the original full label and DTB. Never writes eMMC.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
conf=/boot/extlinux/extlinux.conf
dtb_dir=/boot/dtbs
full_dtb=$dtb_dir/sun8i-a33-pf1007l-full.dtb
bt_dtb=$dtb_dir/sun8i-a33-pf1007l-bluetooth.dtb
usage() { echo "Use: $0 --activate | --rollback"; exit 1; }
[[ $# -eq 1 ]] || usage
[[ $(id -u) -eq 0 ]] || exec sudo "$0" "$@"
[[ -f $conf && -f $full_dtb ]] || { echo "STOP: need $conf and full DTB"; exit 1; }
command -v dtc >/dev/null || { echo "STOP: missing dtc"; exit 1; }
command -v fdtoverlay >/dev/null || { echo "STOP: missing fdtoverlay"; exit 1; }

rollback() {
  echo "Rollback to full label"
  cp "$conf" "$conf.before-bt-rollback.$(date -u +%Y%m%dT%H%M%SZ)"
  sed -i "s/^DEFAULT[ \t].*/DEFAULT full/" "$conf"
  systemctl disable --now pf-bluetooth-uart.service 2>/dev/null || true
  sync
  echo "Next start: full. Reboot to apply."
}

activate() {
  echo "Build Bluetooth DTB from full DTB plus overlay"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  dtc -@ -I dts -O dtb -o "$tmp/bt-uart1.dtbo" "$root/wifi/bluetooth-uart1.dtso"
  cp "$full_dtb" "$tmp/base.dtb"
  fdtoverlay -i "$tmp/base.dtb" -o "$tmp/bluetooth.dtb" "$tmp/bt-uart1.dtbo"
  install -m 644 "$tmp/bluetooth.dtb" "$bt_dtb"
  rm -rf "$tmp"
  trap - EXIT

  echo "Install helpers and service"
  install -m 755 "$root/wifi/bt-uart-probe.py" /usr/local/bin/pf-bt-uart-probe
  install -m 755 "$root/wifi/bt-uart-attach.py" /usr/local/bin/pf-bt-uart-attach
  install -m 644 "$root/wifi/pf-bluetooth-uart.service" /etc/systemd/system/pf-bluetooth-uart.service
  systemctl daemon-reload
  systemd-analyze verify pf-bluetooth-uart.service

  echo "Add full-bluetooth label (keep full untouched)"
  cp "$conf" "$conf.before-full-bluetooth"
  if ! grep -q "^LABEL full-bluetooth$" "$conf"; then
    awk '
      /^LABEL full$/ { full=1 }
      full && /^$/ { print ""; print "LABEL full-bluetooth"; print "\tKERNEL /zImage"; print "\tINITRD /pf-initramfs.img"; print "\tFDT /dtbs/sun8i-a33-pf1007l-bluetooth.dtb"; print "\tAPPEND root=PARTUUID=50463037-02 rootfstype=ext4 rootwait ro console=tty0 ignore_loglevel log_buf_len=1M panic=20 psi=1 zswap.enabled=0 fsck.repair=yes cpufreq.default_governor=schedutil pf.label=full-bluetooth"; full=0; next }
      { print }
    ' "$conf" > "$conf.new" && mv "$conf.new" "$conf"
  fi
  grep -q "^LABEL full-bluetooth$" "$conf" || { echo "STOP: label not added"; exit 1; }
  sed -i "s/^DEFAULT[ \t].*/DEFAULT full-bluetooth/" "$conf"
  systemctl enable pf-bluetooth-uart.service
  sync
  echo "Next start: full-bluetooth. Reboot to apply."
  echo "Rollback: sudo $0 --rollback"
}

case "$1" in
  --activate) activate ;;
  --rollback) rollback ;;
  *) usage ;;
esac
