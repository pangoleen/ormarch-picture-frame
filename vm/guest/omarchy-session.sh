#!/bin/bash
# Guest (root): start the whole Omarchy session on tty1, the way Omarchy's SDDM session entry does:
#   uwsm start -e -D Hyprland hyprland.desktop     (default/wayland-sessions/omarchy.desktop, without "-g -1")
#   omarchy-session.sh start [NAME=VALUE ...]      extra environment for the compositor and the shell
#   omarchy-session.sh stop
set -u
case ${1:-} in
start)
  shift
  # uwsm reads ~/.config/uwsm/env; the extra test variables go there so that they reach the systemd user units.
  install -d -o frame -g frame /home/frame/.config/uwsm
  { echo 'export OMARCHY_PATH=/usr/share/omarchy'; echo 'export PATH=/usr/share/omarchy/bin:$PATH'
    for kv in "$@"; do echo "export $kv"; done; } > /home/frame/.config/uwsm/env
  chown frame:frame /home/frame/.config/uwsm/env
  session start NO_COLOR=1 OMARCHY_PATH=/usr/share/omarchy "$@" -- 'exec uwsm start -e -D Hyprland hyprland.desktop'
  ;;
stop)
  runuser -u frame -- env XDG_RUNTIME_DIR=/run/user/$(id -u frame) uwsm stop 2>&1 | tail -2
  sleep 3; session stop ;;
esac
