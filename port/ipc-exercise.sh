#!/bin/bash
# HOOK script for run-shell-test.sh: open every first-party plugin of the Omarchy shell through IPC,
# so that the lazily loaded QML also loads. Takes one screenshot of the menu.
# Needs OMARCHY_PATH and PATH from run-shell-test.sh. $BASE is the output file prefix.
call() { echo "\$ omarchy-shell $*"; omarchy-shell "$@" 2>&1 | head -c 1500; echo " [exit ${PIPESTATUS[0]}]"; }

call shell ping
call shell listPlugins
for plugin in omarchy.menu omarchy.audio omarchy.bluetooth omarchy.monitor omarchy.network omarchy.power \
              omarchy.weather omarchy.clock omarchy.wifiqr omarchy.tailscale omarchy.speedtest omarchy.disk-speedtest \
              omarchy.dropbox omarchy.clipboard omarchy.emojis omarchy.image-picker omarchy.agents \
              omarchy.reminders omarchy.dev-gallery; do
  call shell summon "$plugin" '{}'
  sleep 2
  if [[ $plugin == omarchy.menu ]]; then grim "$BASE.menu.png"; fi
  if [[ $plugin == omarchy.power ]]; then grim "$BASE.power.png"; fi
  call shell hide "$plugin"
  sleep 1
done
call osd show '{"text":"armv7h smoke test"}'

echo '$ notify-send'; notify-send "armv7h smoke test" "A notification through the Quickshell notification server"; echo " [exit $?]"
sleep 3
grim "$BASE.notification.png"

# Last: the lock screen (ext-session-lock). Nothing unlocks it; the test ends with the session.
call lock lock
sleep 5
grim "$BASE.lock.png"
