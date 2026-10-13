#!/bin/bash
# Bootstrap the SD-card desktop. Run on the frame as user frame.
# It fetches pinned Omarchy quattro, seeds user config, then runs apply.sh.
# It never runs the upstream ISO installer. It never writes eMMC.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export OMARCHY_COMMIT="defbf90e893e741067e48f4a27d2ec694c71358e"
export OMARCHY_REPO="https://github.com/basecamp/omarchy.git"
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export LANG=C.UTF-8

[[ $(id -un) == "frame" ]] || { echo "STOP: run as user frame"; exit 1; }
[[ $(uname -m) == "armv7l" ]] || { echo "STOP: needs armv7l"; exit 1; }
[[ -f /boot/extlinux/extlinux.conf ]] || { echo "STOP: no /boot config"; exit 1; }
uname -r | grep -q "^7.2.10-1-armv7-ARCH" || { echo "STOP: kernel must stay 7.2.10-1"; exit 1; }

# The base recovery image deliberately stays small and does not require Git.
# Bootstrap needs it only to fetch the pinned Omarchy source.
sudo pacman -S --noconfirm --needed git

if [[ -d $HOME/.config/hypr && -n $(ls -A $HOME/.config/hypr 2>/dev/null) && ! -d $OMARCHY_PATH ]]; then
  echo "STOP: ~/.config/hypr exists but Omarchy tree is missing."
  echo "Move it aside first, then run again. It is not overwritten."
  exit 1
fi

if [[ ! -f $OMARCHY_PATH/shell/shell.qml ]]; then
  echo "Fetch Omarchy quattro $OMARCHY_COMMIT"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  if [[ -d $here/../../refs/omarchy ]]; then
    git -C "$here/../../refs/omarchy" archive "$OMARCHY_COMMIT" shell bin config default themes version | tar -x -C "$tmp"
  else
    rm -rf "$tmp/omarchy"
    git clone --quiet --filter=blob:none --no-checkout "$OMARCHY_REPO" "$tmp/omarchy"
    git -C "$tmp/omarchy" fetch --quiet --depth 1 origin "$OMARCHY_COMMIT"
    git -C "$tmp/omarchy" archive FETCH_HEAD shell bin config default themes version | tar -x -C "$tmp"
  fi
  mkdir -p "$HOME/.local/share"
  rm -rf "$OMARCHY_PATH"
  mkdir -p "$OMARCHY_PATH"
  cp -a "$tmp/shell" "$tmp/bin" "$tmp/config" "$tmp/default" "$tmp/themes" "$tmp/version" "$OMARCHY_PATH/"
  echo "$OMARCHY_COMMIT" > "$OMARCHY_PATH/.pf-pinned-commit"
  rm -rf "$tmp"
  trap - EXIT
else
  echo "Omarchy tree exists. Keep it. No fetch."
fi

if [[ ! -f $HOME/.config/hypr/hyprland.lua ]]; then
  echo "Seed user config from Omarchy defaults"
  mkdir -p "$HOME/.config"
  cp -a "$OMARCHY_PATH/config/." "$HOME/.config/"
else
  echo "User config exists. Keep it. No overwrite."
fi

echo "Run apply.sh"
bash "$here/apply.sh"
echo "Done. Reboot to check autostart."
