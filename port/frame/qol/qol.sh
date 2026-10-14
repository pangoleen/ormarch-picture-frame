#!/bin/bash
# PF1007L quality-of-life set (docs/experiments.md E071). Run on the frame as user frame, after
# apply.sh. Every step is safe to run again. It changes user settings, one Omarchy script (with a
# backup) and installs small packages. It does not touch the boot files.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
[[ $(id -un) == "frame" && $(uname -m) == "armv7l" ]] || { echo "STOP: run on the frame as user frame"; exit 1; }

# Small tools that Omarchy calls and that exist for armv7h.
sudo env ALL_PROXY="${ALL_PROXY:-}" pacman -S --noconfirm --needed \
  hyprpicker zbar qrencode mpv-mpris ffmpegthumbnailer gnome-themes-extra woff2-font-awesome \
  galculator rtkit tesseract tesseract-data-eng

# Screenshot: Omarchy calls omasnap, which has no ARM package.
install -D -m 755 "$here/omasnap" "$HOME/.local/bin/omasnap"

# Web apps open in Firefox (no Chromium on armv7h).
python3 "$here/patch-webapp.py" "$OMARCHY_PATH"

# Editor for the "edit config" menu rows: neovim does not install on armv7h.
mkdir -p "$HOME/.local/state/omarchy/defaults"
[[ -s $HOME/.local/state/omarchy/defaults/editor ]] || echo nano >"$HOME/.local/state/omarchy/defaults/editor"

# Menu: hide the rows that cannot work here or that undo the frame setup.
ext=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
mkdir -p "$(dirname "$ext")"
if [[ -f $ext ]] && ! grep -q "PF1007L" "$ext" && [[ ! -f $ext.before-frame-qol ]]; then
  cp "$ext" "$ext.before-frame-qol"
fi
install -m 644 "$here/omarchy-menu.jsonc" "$ext"

# Bar icon for the dictation state.
install -D -m 644 "$here/dictation/manifest.json" "$HOME/.config/omarchy/plugins/frame.dictation/manifest.json"
install -m 644 "$here/dictation/Widget.qml" "$HOME/.config/omarchy/plugins/frame.dictation/Widget.qml"

# Touch button that closes the focused window.
install -D -m 644 "$here/controls/manifest.json" "$HOME/.config/omarchy/plugins/frame.controls/manifest.json"
install -m 644 "$here/controls/Widget.qml" "$HOME/.config/omarchy/plugins/frame.controls/Widget.qml"

# Bar: add the close button; remove widgets with no function here (a battery that does not exist,
# agents, keyboard layout, the upstream update notice).
python3 - "$HOME/.config/omarchy/shell.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
layout = data["bar"]["layout"]
before = json.dumps(layout, sort_keys=True)
drop = {"omarchy.power", "omarchy.agents", "omarchy.keyboard-layout", "omarchy.system-update"}
for section in layout:
    layout[section] = [w for w in layout[section] if w.get("id") not in drop]
if not any(w.get("id") == "frame.controls" for s in layout.values() for w in s):
    layout["right"].insert(0, {"id": "frame.controls"})
if not any(w.get("id") == "frame.dictation" for s in layout.values() for w in s):
    layout["right"].insert(0, {"id": "frame.dictation"})
if json.dumps(layout, sort_keys=True) != before:
    backup = path.with_suffix(".json.before-frame-qol")
    if not backup.exists():
        backup.write_text(path.read_text())
    path.write_text(json.dumps(data, indent=2) + "\n")
PY

# File types: pictures open in the picture viewer and media in mpv, not in Firefox.
[[ -f $HOME/.config/mimeapps.list ]] || install -m 644 "$here/mimeapps.list" "$HOME/.config/mimeapps.list"
gsettings set org.gnome.desktop.interface icon-theme Adwaita 2>/dev/null || true

# The Bluetooth pairing agent was tied to a target that never starts on this frame.
systemctl --user add-wants default.target bt-agent.service 2>/dev/null || true

# No suspend: the frame has no proven wake-up path (apply.sh also does this).
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1

echo "Done. Restart the shell to see the bar and menu changes: omarchy-restart-shell"

# ---- Round 2: performance, Firefox, slideshow, no lock (E071) ----
sudo install -D -m 644 "$here/system/20-pf1007l-vm.conf" /etc/sysctl.d/20-pf1007l-vm.conf
sudo sysctl -q --system
sudo install -m 644 "$here/system/earlyoom" /etc/default/earlyoom
sudo systemctl enable -q earlyoom && sudo systemctl restart earlyoom
sudo install -D -m 644 "$here/system/60-pf1007l-perf.rules" /etc/udev/rules.d/60-pf1007l-perf.rules
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=devfreq --action=add
sudo udevadm trigger --subsystem-match=block --action=change
# (E075: no raised CPU minimum; lowest power draw first. system/pf1007l-cpufreq.conf is kept for tests.)
sudo rm -f /etc/tmpfiles.d/pf1007l-cpufreq.conf
sudo install -D -m 644 "$here/system/journald-pf1007l.conf" /etc/systemd/journald.conf.d/pf1007l.conf
sudo install -D -m 644 "$here/system/logind-pf1007l.conf" /etc/systemd/logind.conf.d/10-pf1007l.conf
sudo systemctl reload systemd-logind 2>/dev/null || true
sudo install -D -m 644 "$here/firefox-frame.js" /usr/lib/firefox/browser/defaults/preferences/frame.js
sudo install -D -m 644 "$here/firefox-policies.json" /usr/lib/firefox/distribution/policies.json
install -D -m 755 "$here/pf-slideshow" "$HOME/.local/bin/pf-slideshow"
mkdir -p "$HOME/Pictures/frame"
install -m 644 "$here/omarchy-menu.jsonc" "$ext"
python3 "$here/tune-hypr-qol.py"

# The lock screen cannot show the touch keyboard: never lock, never start the terminal screensaver.
python3 - "$HOME/.config/omarchy/shell.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
if data.get("idle") != {"screensaver": 0, "lock": 0}:
    data["idle"] = {"screensaver": 0, "lock": 0}
    path.write_text(json.dumps(data, indent=2) + "\n")
PY

# Wi-Fi power saving off: the AIC8800 SDIO driver hung with it on (E073).
sudo install -D -m 644 "$here/../system/nm-wifi-powersave.conf" /etc/NetworkManager/conf.d/20-pf1007l-wifi-powersave.conf
sudo install -D -m 644 "$here/../system/aic8800-options.conf" /etc/modprobe.d/pf1007l-aic8800-options.conf
sudo iw dev wlan0 set power_save off 2>/dev/null || true

# Compressed swap as large as the RAM (E077); takes effect at the next boot.
sudo install -D -m 644 "$here/../system/zram-generator.conf" /etc/systemd/zram-generator.conf

# YouTube app: search, pick, play (E078).
install -D -m 755 "$here/pf-youtube-search" "$HOME/.local/bin/pf-youtube-search"
install -D -m 755 "$here/../pf-youtube" "$HOME/.local/bin/pf-youtube"
install -D -m 644 "$here/pf-youtube.desktop" "$HOME/.local/share/applications/pf-youtube.desktop"

# "Play in mpv" button for Firefox (ff2mpv add-on, installed by policy) with the frame's own helper.
install -D -m 755 "$here/pf-ff2mpv-host" "$HOME/.local/bin/pf-ff2mpv-host"
install -D -m 644 "$here/ff2mpv-native.json" "$HOME/.mozilla/native-messaging-hosts/ff2mpv.json"
sudo install -D -m 644 "$here/firefox-policies.json" /usr/lib/firefox/distribution/policies.json

# Web view mode (E080): one page full screen, optional at login. Local dashboard server on 127.0.0.1.
install -D -m 755 "$here/pf-webview" "$HOME/.local/bin/pf-webview"
install -D -m 644 "$here/pf-dashboard.service" "$HOME/.config/systemd/user/pf-dashboard.service"
mkdir -p "$HOME/.local/share/pf-dashboard"
systemctl --user daemon-reload
python3 - "$HOME/.config/hypr/autostart.lua" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1]); text = path.read_text()
marker = "-- PF1007L web view at login"
if marker not in text:
    path.write_text(text + f'\n{marker} (only when ~/.config/pf-webview.boot exists)\no.launch_on_start("pf-webview boot-start")\n')
PY
echo "Round 2 done. Reboot to apply the Hyprland block (Xwayland off, render scheduling)."
