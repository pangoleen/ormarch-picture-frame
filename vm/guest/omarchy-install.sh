#!/bin/bash
# Guest (root): put the Omarchy tree where the omarchy and omarchy-settings packages put it, by hand.
# Tree: basecamp/omarchy branch quattro, commit defbf90e (newer than v4.0.4), NOT changed.
# Only the files that a session needs are installed outside /usr/share/omarchy (see the omarchy-settings PKGBUILD).
# Not done: /etc/sudoers.d, nsswitch, SDDM, Plymouth, Limine, snapper, pacman.conf, the lock-screen PAM file.
set -euo pipefail
T=/usr/share/omarchy
rm -rf $T && mkdir -p $T && tar -xzf /root/omarchy-quattro-defbf90e.tar.gz -C $T
install -Dm644 $T/default/uwsm/env.d/10-omarchy /usr/share/uwsm/env.d/10-omarchy
install -Dm644 $T/etc/profile.d/omarchy.sh /etc/profile.d/omarchy.sh
install -Dm644 $T/etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf \
  /etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf
install -Dm644 $T/default/fontconfig/conf.avail/50-omarchy.conf /usr/share/fontconfig/conf.avail/50-omarchy.conf
ln -sfn /usr/share/fontconfig/conf.avail/50-omarchy.conf /etc/fonts/conf.d/50-omarchy.conf
install -Dm644 $T/default/xdg-terminal-exec/hyprland-xdg-terminals.list /usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list
install -Dm644 $T/default/applications/mimeapps.list /usr/share/applications/mimeapps.list
for u in $T/default/systemd/user/*.service; do install -Dm644 "$u" /usr/lib/systemd/user/"$(basename "$u")"; done
# The package installs bin/* in /usr/bin. Here a PATH entry does the same and keeps the tree in one place.
echo 'export PATH=/usr/share/omarchy/bin:$PATH' > /etc/profile.d/00-omarchy-path.sh
cat $T/version; du -sh $T

# User side: what /etc/skel and omarchy-theme-set give a new user.
runuser -u frame -- bash -lc '
  set -e
  export OMARCHY_PATH=/usr/share/omarchy PATH=/usr/share/omarchy/bin:$PATH
  mkdir -p ~/.config ~/.local/share/applications ~/.local/state/omarchy
  cp -a $OMARCHY_PATH/config/. ~/.config/
  cp $OMARCHY_PATH/applications/*.desktop ~/.local/share/applications/ 2>/dev/null || true
  omarchy-theme-set "Tokyo Night" 2>&1 | tail -5
  ls -la ~/.local/state/omarchy/current/ 2>&1 | head
'
