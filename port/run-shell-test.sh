#!/bin/bash
# Smoke test: load a Quickshell config in a headless Wayland session and record what happens.
# Run INSIDE the test container as the unprivileged user "frame" (see port/Dockerfile).
#
#   run-shell-test.sh <label> <qml path or config dir> [seconds] [omarchy_path]
#
# Session pieces that this script starts (all headless, all software):
#   - a D-Bus session bus (dbus-run-session)
#   - PipeWire + WirePlumber (no audio hardware; the daemons only)
#   - sway with the wlroots headless backend and the pixman renderer, one 1280x800 output
#   - Quickshell on Wayland; Qt Quick renders with Mesa llvmpipe (LIBGL_ALWAYS_SOFTWARE=1)
# Session pieces that are NOT there: Hyprland (so no Hyprland IPC), logind, systemd --user,
# UPower/NetworkManager/BlueZ daemons, a DRM device, real hardware.
#
# Output: $OUT/<arch>-<label>.log (Quickshell log), .mem (memory), .smaps (raw smaps), .png (screenshot)
#
# Optional: HOOK=/path/to/script runs that script (in the same session) 20 s after Quickshell
# starts, for example to send IPC calls. Its output goes to <arch>-<label>.hook.log.

set -u
label=$1
cfg=$2
secs=${3:-60}
omarchy_path=${4:-/omarchy}

arch=$(uname -m)
OUT=${OUT:-/port/logs}
mkdir -p "$OUT"
base="$OUT/$arch-$label"

export XDG_RUNTIME_DIR=/run/user/$(id -u)
export NO_COLOR=1
export LIBGL_ALWAYS_SOFTWARE=1
export OMARCHY_PATH=$omarchy_path
export PATH=$omarchy_path/bin:$PATH

if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  exec dbus-run-session -- "$0" "$@"
fi

cd "$HOME"
pkill -u "$(id -u)" -x sway 2>/dev/null
pkill -u "$(id -u)" -x pipewire 2>/dev/null
pkill -u "$(id -u)" -x wireplumber 2>/dev/null
rm -f "$XDG_RUNTIME_DIR"/wayland-*

pipewire >"$base.pipewire.log" 2>&1 &
sleep 2
wireplumber >"$base.wireplumber.log" 2>&1 &

mkdir -p ~/.config/sway
echo 'output HEADLESS-1 resolution 1280x800' >~/.config/sway/config
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway >"$base.sway.log" 2>&1 &
for _ in $(seq 1 60); do
  [[ -S $XDG_RUNTIME_DIR/wayland-1 ]] && break
  sleep 0.5
done
export WAYLAND_DISPLAY=wayland-1
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=Hyprland   # what the Omarchy session sets; there is no Hyprland here

{
  echo "# label=$label arch=$arch cfg=$cfg secs=$secs OMARCHY_PATH=$OMARCHY_PATH"
  echo "# $(quickshell --version)"
  echo "# qt6-base $(pacman -Q qt6-base | cut -d' ' -f2), qt6-declarative $(pacman -Q qt6-declarative | cut -d' ' -f2), mesa $(pacman -Q mesa | cut -d' ' -f2)"
  echo "# start $(date -u +%FT%TZ)"
} >"$base.log"

start=$(date +%s)
QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  quickshell -n -p "$cfg" >>"$base.log" 2>&1 &
qs=$!

# Sample memory near the end of the run, while the shell is idle.
sample_at=$((secs - 8))
alive=1
for ((t = 0; t < secs; t++)); do
  if ! kill -0 "$qs" 2>/dev/null; then
    alive=0
    break
  fi
  if ((t == 20)) && [[ -n ${HOOK:-} ]]; then
    BASE="$base" bash "$HOOK" >"$base.hook.log" 2>&1
  fi
  if ((t == sample_at)); then
    {
      echo "# memory sample at t=${t}s, $(date -u +%FT%TZ)"
      for name in quickshell sway pipewire wireplumber; do
        for pid in $(pgrep -u "$(id -u)" -x "$name"); do
          echo "## $name pid=$pid exe=$(readlink /proc/$pid/exe)"
          grep -E '^(VmRSS|VmHWM|RssAnon|RssFile|RssShmem|VmSwap|Threads)' /proc/$pid/status
          grep -E '^(Rss|Pss|Pss_Anon|Pss_File|Pss_Shmem|Private_Clean|Private_Dirty|Shared_Clean)' /proc/$pid/smaps_rollup
        done
      done
    } >"$base.mem" 2>&1
    cat /proc/$qs/smaps >"$base.smaps" 2>/dev/null
    grim "$base.png" 2>/dev/null
    swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.type? == "output") | .name' >/dev/null 2>&1
  fi
  sleep 1
done

end=$(date +%s)
if ((alive)); then
  echo "# RESULT: quickshell still running after $((end - start)) s; stopping it with SIGTERM" >>"$base.log"
  kill -TERM "$qs" 2>/dev/null
  wait "$qs" 2>/dev/null
  echo "# exit status after SIGTERM: $?" >>"$base.log"
else
  wait "$qs" 2>/dev/null
  echo "# RESULT: quickshell EXITED EARLY after $((end - start)) s with status $?" >>"$base.log"
fi

pkill -u "$(id -u)" -x sway 2>/dev/null
pkill -u "$(id -u)" -x wireplumber 2>/dev/null
pkill -u "$(id -u)" -x pipewire 2>/dev/null
tail -3 "$base.log"
