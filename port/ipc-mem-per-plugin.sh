#!/bin/bash
# HOOK script: open each first-party plugin once and print the Quickshell RSS after it closes.
# Shows which plugin makes memory grow. RSS is from /proc/<pid>/status (under QEMU it includes the emulator).
export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-30s}
pid=$(pgrep -u "$(id -u)" -x quickshell | head -1)
rss() { awk '/^VmRSS/{printf "%.0f", $2/1024}' /proc/$pid/status; }
anon() { awk '/^RssAnon/{printf "%.0f", $2/1024}' /proc/$pid/status; }
echo "start: RSS $(rss) MiB, anon $(anon) MiB"
for plugin in omarchy.menu omarchy.audio omarchy.bluetooth omarchy.monitor omarchy.network omarchy.power \
              omarchy.weather omarchy.clock omarchy.wifiqr omarchy.speedtest omarchy.disk-speedtest \
              omarchy.clipboard omarchy.emojis omarchy.agents omarchy.reminders omarchy.dev-gallery \
              omarchy.image-picker; do
  before=$(anon)
  r=$(omarchy-shell shell summon "$plugin" '{}' 2>&1 | head -c 80)
  sleep "${OPEN_WAIT:-3}"
  open=$(anon)
  omarchy-shell shell hide "$plugin" >/dev/null 2>&1
  sleep "${CLOSE_WAIT:-3}"
  after=$(anon)
  printf '%-24s summon=%-8s anon before %4s  open %4s  closed %4s MiB  (kept %+d)\n' "$plugin" "$r" "$before" "$open" "$after" "$((after - before))"
done
echo "end: RSS $(rss) MiB, anon $(anon) MiB"
