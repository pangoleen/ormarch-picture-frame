#!/bin/bash
# Host-side driver for the smoke test. Run from the project root:
#
#   port/run-all.sh armv7     # the 32-bit test (QEMU user emulation on Apple silicon)
#   port/run-all.sh arm64     # the 64-bit control (native on Apple silicon)
#
# Needs: Docker (OrbStack), refs/omarchy at tag v4.0.4, and optionally refs/omarchy-quattro
# (shell/ bin/ config/ default/ of a newer upstream commit) for the comparison run.
# It builds the image from port/Dockerfile, starts one container, runs every test and writes
# port/logs/<uname -m>-*.{log,mem,png}. It removes the container at the end. It removes nothing else.
set -eu
which=${1:?armv7 or arm64}
case $which in
  armv7) platform=linux/arm/v7 ;;
  arm64) platform=linux/arm64 ;;
  *) echo "armv7 or arm64"; exit 1 ;;
esac
root=$(cd "$(dirname "$0")/.." && pwd)
name=omf-$which
image=omf-smoke:$which
secs=${SECS:-75}

ctx=$(mktemp -d)
cp "$root/port/Dockerfile" "$ctx/"
docker build -q --platform "$platform" -t "$image" "$ctx" >/dev/null 2>&1
rm -rf "$ctx"

docker rm -f "$name" >/dev/null 2>&1 || true
mounts=(-v "$root/refs/omarchy:/omarchy:ro" -v "$root/port:/port")
[[ -d $root/refs/omarchy-quattro ]] && mounts+=(-v "$root/refs/omarchy-quattro:/omarchy-quattro:ro")
docker run -d --name "$name" --platform "$platform" "${mounts[@]}" "$image" >/dev/null

ctr() { docker exec -u frame -e HOME=/home/frame -w /home/frame "$name" bash -c "$1"; }
env_base='export XDG_RUNTIME_DIR=/run/user/1000 NO_COLOR=1'
arch=$(ctr 'uname -m')
log=$root/port/logs
mkdir -p "$log"
echo "== container $name: uname -m = $arch"

{
  echo "# uname -a"; ctr 'uname -a'
  echo "# quickshell --version"; ctr "$env_base; quickshell --version"
  echo "# Hyprland --version"; ctr "$env_base; Hyprland --version"
  echo "# foot --version"; ctr 'foot --version'
  echo "# file"; ctr 'file -b /usr/bin/quickshell /usr/bin/Hyprland'
  echo "# pacman -Q"; ctr 'pacman -Q quickshell hyprland aquamarine foot mesa llvm-libs qt6-base qt6-declarative qt6-wayland qt6-svg sway pipewire wireplumber'
  echo "# root filesystem (MiB)"; docker exec "$name" bash -c 'du -sm --exclude=/proc --exclude=/sys --exclude=/omarchy --exclude=/omarchy-quattro --exclude=/port / 2>/dev/null | cut -f1'
} >"$log/$arch-versions.txt" 2>&1

# Test b1: trivial config, Qt offscreen platform (no compositor at all).
ctr "$env_base QT_QPA_PLATFORM=offscreen; timeout 20 quickshell -p /port/qml-trivial/shell.qml; echo \"# exit status: \$? (124 = still running when the 20 s timeout stopped it)\"" \
  >"$log/$arch-trivial-offscreen.log" 2>&1 || true

# Test: does Qt 6.12 hide a config singleton that is named Color?
ctr "$env_base QT_QPA_PLATFORM=offscreen; timeout 20 quickshell -p /port/qml-trivial/colortest/shell.qml; timeout 20 quickshell -p /port/qml-trivial/colortest/shell611.qml" \
  >"$log/$arch-colortest.log" 2>&1 || true

# Test b2: trivial layer-shell bar on headless sway + llvmpipe.
ctr "QSG_INFO=1 /port/run-shell-test.sh trivial-panel /port/qml-trivial/panel.qml 30" || true

# Session data that a real install has: user config from the repo, one theme applied by Omarchy's own script.
ctr "$env_base OMARCHY_PATH=/omarchy PATH=/omarchy/bin:\$PATH; cp -r /omarchy/config/. ~/.config/; omarchy-theme-set 'Tokyo Night'" \
  >"$log/$arch-theme-set.log" 2>&1 || true

# Test c1: Omarchy v4.0.4 shell, not changed.
ctr "/port/run-shell-test.sh omarchy-v4.0.4-stock /omarchy/shell $secs /omarchy" || true

# Test c2: Omarchy v4.0.4 shell, 'import QtQuick' pinned to 6.11.
ctr "/port/make-pinned-tree.sh /omarchy ~/omarchy-pin && /port/run-shell-test.sh omarchy-v4.0.4-qtquick611 ~/omarchy-pin/shell $secs ~/omarchy-pin" || true

# Test c3: newer upstream shell (if present), not changed, on the stock Quickshell.
if [[ -d $root/refs/omarchy-quattro ]]; then
  ctr "mkdir -p ~/omarchy-quattro && ln -sfn /omarchy-quattro/* ~/omarchy-quattro/ && ln -sfn /omarchy/themes ~/omarchy-quattro/themes \
      && /port/run-shell-test.sh omarchy-quattro-stock ~/omarchy-quattro/shell $secs ~/omarchy-quattro" || true
fi

# Test c4: the same as c2, with the wallpaper scaled to the panel size (1280x800) first.
ctr "$env_base; bg=\$(readlink -f ~/.local/state/omarchy/current/background); \
     magick \"\$bg\" -resize '1280x800^' -gravity center -extent 1280x800 -quality 92 ~/bg-1280x800.jpg \
     && ln -sfn ~/bg-1280x800.jpg ~/.local/state/omarchy/current/background" || true
ctr "/port/run-shell-test.sh omarchy-v4.0.4-qtquick611-bg1280 ~/omarchy-pin/shell $secs ~/omarchy-pin" || true

# Test c5: the same as c4, Qt Quick software backend (no OpenGL at all in the shell).
ctr "QT_QUICK_BACKEND=software /port/run-shell-test.sh omarchy-v4.0.4-qtquick611-bg1280-swbackend ~/omarchy-pin/shell $secs ~/omarchy-pin" || true

# Test c6: the same as c4, Mesa told to report OpenGL 2.1 / GLSL 1.20 (a first look at an old-GPU
# feature level; llvmpipe still does the work, so this is NOT a Mali-400 test).
ctr "MESA_GL_VERSION_OVERRIDE=2.1 MESA_GLSL_VERSION_OVERRIDE=120 QSG_INFO=1 \
     /port/run-shell-test.sh omarchy-v4.0.4-qtquick611-bg1280-gl21 ~/omarchy-pin/shell 60 ~/omarchy-pin" || true

# Test c7: open the menu and one panel through IPC, with long waits, and take screenshots.
ctr "HOOK=/port/ipc-menu.sh /port/run-shell-test.sh omarchy-v4.0.4-qtquick611-menu ~/omarchy-pin/shell 45 ~/omarchy-pin" || true

# Test c8: open every first-party plugin through IPC, then a notification, then the lock screen.
ctr "HOOK=/port/ipc-exercise.sh /port/run-shell-test.sh omarchy-v4.0.4-qtquick611-ipc ~/omarchy-pin/shell 60 ~/omarchy-pin" || true

# Test c9: memory of the shell after each plugin opens and closes.
ctr "HOOK=/port/ipc-mem-per-plugin.sh /port/run-shell-test.sh omarchy-v4.0.4-qtquick611-plugin-mem ~/omarchy-pin/shell 40 ~/omarchy-pin" || true

# Test c10: memory after each plugin on the newer upstream shell (if present).
if [[ -d $root/refs/omarchy-quattro ]]; then
  ctr "HOOK=/port/ipc-mem-per-plugin.sh /port/run-shell-test.sh omarchy-quattro-stock-plugin-mem ~/omarchy-quattro/shell 40 ~/omarchy-quattro" || true
fi

# Test a2: the foot terminal in the headless compositor.
ctr "$env_base; rm -f \$XDG_RUNTIME_DIR/wayland-*; \
     (WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway >/dev/null 2>&1 &); \
     for i in \$(seq 1 40); do [[ -S \$XDG_RUNTIME_DIR/wayland-1 ]] && break; sleep 0.5; done; \
     export WAYLAND_DISPLAY=wayland-1; \
     (foot -e bash -c 'echo foot on \$(uname -m): TERM=\$TERM cols=\$(tput cols); sleep 8' &); \
     sleep 6; grim /port/logs/$arch-foot.png; sleep 3; pkill -x sway" >"$log/$arch-foot.log" 2>&1 || true

# Test e: Hyprland with no display hardware, and the llvmpipe OpenGL ES version lines.
ctr "/port/hyprland-try.sh" >"$log/$arch-hyprland-headless.log" 2>&1 || true

# Memory: split program and emulator parts, then drop the large raw dumps.
for f in "$log/$arch"-*.smaps; do
  [[ -e $f ]] || continue
  python3 -I "$root/port/mem-from-smaps.py" "$f" >"${f%.smaps}.memsplit.txt"
  rm -f "$f"
done

docker rm -f "$name" >/dev/null
echo "== done: $log/$arch-*"
