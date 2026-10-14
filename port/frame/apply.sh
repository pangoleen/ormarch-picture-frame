#!/bin/bash
# Run on the frame as user frame, after copying this directory there.
# Uses the frame's direct Wi-Fi connection when available. A caller may supply
# ALL_PROXY for USB-recovery bring-up; it is never stored by this script.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
export LANG=C.UTF-8
export OMARCHY_SHELL_IPC_TIMEOUT=5s
[[ $(id -un) == "frame" && $(uname -m) == "armv7l" ]]
[[ -f $OMARCHY_PATH/shell/shell.qml ]]
python3 "$here/patch-platform.py" "$OMARCHY_PATH"
python3 "$here/patch-first-run.py" "$OMARCHY_PATH"

sudo env ALL_PROXY="${ALL_PROXY:-}" pacman -S --noconfirm --needed \
  qt6-imageformats networkmanager bluez bluez-utils bluez-tools pipewire wireplumber \
  squeekboard xdg-terminal-exec xdg-user-dirs adwaita-icon-theme woff2-font-awesome \
  firefox nautilus mpv imv fastfetch btop ripgrep noto-fonts noto-fonts-emoji \
  bat eza fd fzf tldr tmux slurp foot hyprland quickshell uwsm wireless-regdb iwd iw git
sudo install -m 755 "$here/pf-pacman-guard" /usr/lib/pf1007l/pf-pacman-guard
sudo install -m 644 "$here/pf1007l-lradc.conf" /etc/modprobe.d/pf1007l-lradc.conf
sudo install -D -m 644 "$here/system/session-stop.conf" /etc/systemd/system/session-.scope.d/10-pf-stop.conf
sudo install -D -m 644 "$here/system/manager-stop.conf" /etc/systemd/system.conf.d/10-pf-stop.conf
sudo python3 "$here/guard-updater.py" "$OMARCHY_PATH"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" \
  "$HOME/.config/omarchy/plugins/frame.keyboard" "$HOME/.local/share/fonts" \
  "$HOME/.local/share/applications" "$HOME/.config/foot"
install -m 755 "$here/pf-keyboard-toggle" "$HOME/.local/bin/pf-keyboard-toggle"
install -m 755 "$here/pf-health-check" "$HOME/.local/bin/pf-health-check"
install -m 755 "$here/pf-install-yt-dlp" "$HOME/.local/bin/pf-install-yt-dlp"
install -m 755 "$here/pf-youtube" "$HOME/.local/bin/pf-youtube"
"$HOME/.local/bin/pf-install-yt-dlp"
install -m 644 "$here/pf-keyboard.service" "$HOME/.config/systemd/user/pf-keyboard.service"
install -m 644 "$OMARCHY_PATH/default/systemd/user/bt-agent.service" "$HOME/.config/systemd/user/bt-agent.service"
cp "$here/keyboard/manifest.json" "$here/keyboard/Widget.qml" "$HOME/.config/omarchy/plugins/frame.keyboard/"
cp "$OMARCHY_PATH/default/fonts/omarchy/omarchy.ttf" "$HOME/.local/share/fonts/"
fc-cache -f "$HOME/.local/share/fonts"
if [[ ! -f $HOME/.config/foot/foot.ini ]]; then
  cp "$OMARCHY_PATH/config/foot/foot.ini" "$HOME/.config/foot/"
fi
if [[ ! -f $HOME/.config/xdg-terminals.list ]]; then
  printf 'foot.desktop\n' >"$HOME/.config/xdg-terminals.list"
fi
cat >"$HOME/.local/share/applications/pf-keyboard.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Touch Keyboard
Exec=$HOME/.local/bin/pf-keyboard-toggle
Icon=input-keyboard
Categories=Utility;Accessibility;
Terminal=false
EOF

python3 - "$HOME/.config/hypr/autostart.lua" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text() if path.exists() else ""
marker = "-- PF1007L touch keyboard"
if marker not in text:
    if path.exists():
        backup = path.with_suffix(".lua.before-frame-keyboard")
        if not backup.exists():
            backup.write_text(text)
    text += '''
-- PF1007L touch keyboard
o.launch_on_start("systemctl --user import-environment WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP && systemctl --user start pf-keyboard.service")
'''
    path.write_text(text)
PY
python3 "$here/tune-hypr.py"

# Keep USB recovery access with systemd-networkd; NM manages only Wi-Fi.
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' | \
  sudo tee /etc/NetworkManager/conf.d/10-pf1007l-usb.conf >/dev/null
printf '# AIC8800DC H U02 tested on this frame (E051).\naic8800_bsp\naic8800_fdrv\n' | \
  sudo tee /etc/modules-load.d/pf1007l-wifi.conf >/dev/null
sudo python3 "$here/unblacklist-wifi.py" /etc/modprobe.d
sudo modprobe aic8800_bsp
sudo modprobe aic8800_fdrv
sudo systemctl disable --now iwd
sudo systemctl enable --now NetworkManager bluetooth
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo timedatectl set-ntp true
sudo install -m 644 "$here/pf-hyprland.service" /etc/systemd/system/pf-hyprland.service
sudo mkdir -p /etc/systemd/system/pf-hyprland.service.d
if [[ -f /etc/systemd/system/pf-hyprland.service.d/omarchy.conf && ! -f /etc/systemd/system/pf-hyprland.service.d/omarchy.conf.before-frame-desktop ]]; then
  sudo cp /etc/systemd/system/pf-hyprland.service.d/omarchy.conf /etc/systemd/system/pf-hyprland.service.d/omarchy.conf.before-frame-desktop
fi
sudo install -m 644 "$here/omarchy.conf" /etc/systemd/system/pf-hyprland.service.d/omarchy.conf
sudo systemctl daemon-reload
sudo systemctl enable pf-hyprland.service
systemctl --user daemon-reload
systemctl --user enable --now pipewire.socket wireplumber.service bt-agent.service
xdg-user-dirs-update
omarchy-toggle-idle stay-awake
omarchy-display-text-size 18
omarchy-shell shell rescanPlugins
omarchy-plugin-enable frame.keyboard --section right --index 0
echo "Frame desktop configured. Restart the Hyprland session to check autostart."
