#!/bin/bash
# Runs in the guest as root (vm/build.sh provision). Installs the session packages and the test user.
# It is safe to run again.
set -uo pipefail
exec 2>&1
step() { echo; echo "=== $(date -u +%H:%M:%S) $*"; }

step "pacman keyring"
if [[ ! -d /etc/pacman.d/gnupg/private-keys-v1.d ]]; then
  pacman-key --init && pacman-key --populate archlinuxarm
fi

step "full upgrade (tarball of 2026-08-05 -> today's mirror state)"
time pacman -Syu --noconfirm --noprogressbar

# Session subset of install/omarchy-base.packages, plus the test tools. Names that the armv7h mirror does not
# have are skipped and listed.
want=(
  hyprland hyprland-guiutils hyprpicker hyprsunset hypridle hyprlock uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  quickshell qt6-svg qt6-wayland qt6-imageformats qt6-multimedia
  foot xdg-terminal-exec gum jq socat wl-clipboard wtype libnotify grim slurp imagemagick fd fzf ripgrep less bc
  pipewire pipewire-pulse wireplumber pamixer brightnessctl playerctl power-profiles-daemon udiskie
  ttf-jetbrains-mono-nerd noto-fonts woff2-font-awesome gnome-themes-extra fontconfig
  mesa mesa-utils glslang wayland-utils wlr-randr
  squeekboard firefox
  zram-generator earlyoom smem python strace
)
have=(); missing=()
for p in "${want[@]}"; do
  if pacman -Si "$p" >/dev/null 2>&1; then have+=("$p"); else missing+=("$p"); fi
done
step "install ${#have[@]} packages; not in the armv7h repos: ${missing[*]:-none}"
time pacman -S --needed --noconfirm --noprogressbar "${have[@]}"
echo "pacman exit status: $?"

step "user frame"
id frame >/dev/null 2>&1 || useradd -m -G video,input,render,wheel,audio -s /bin/bash frame
mkdir -p /home/frame/.ssh && cp /root/.ssh/authorized_keys /home/frame/.ssh/ && chown -R frame:frame /home/frame/.ssh && chmod 700 /home/frame/.ssh
loginctl enable-linger frame

step "zram as planned for the frame: 512 MiB, lzo-rle (the only backend of the stock kernel), earlyoom"
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/10-vm.conf <<'EOF'
[zram0]
zram-size = 512
compression-algorithm = lzo-rle
swap-priority = 100
EOF
printf 'vm.swappiness = 100\nvm.page-cluster = 0\n' > /etc/sysctl.d/10-zram.conf
systemctl enable earlyoom.service 2>&1 | tail -1

step "test session helpers (logind session on tty1)"
install -m 644 /root/guest/vt-session.service /etc/systemd/system/vt-session.service
install -m 755 /root/guest/session /usr/local/bin/session
install -m 755 /root/guest/memsnap /usr/local/bin/memsnap
systemctl daemon-reload
systemctl disable --now getty@tty1.service 2>/dev/null

step "clean the package cache and give the freed blocks back to the host"
pacman -Scc --noconfirm >/dev/null
fstrim -v /

step "result"
pacman -Q > /root/packages.txt; wc -l /root/packages.txt
pacman -Q hyprland quickshell mesa qt6-base foot firefox squeekboard aquamarine llvm-libs systemd 2>&1
df -h /
