#!/bin/bash
# Guest (root): one start of Hyprland alone on the KMS device, with a given config and environment.
#   hypr-test.sh LABEL CONFIG [NAME=VALUE ...]
# Output in /root/out/LABEL.*: .log (full Hyprland log), .info (hyprctl answers), .png (grim), .mem (memsnap)
set -u
label=$1; cfg=$2; shift 2
out=/root/out; mkdir -p $out; rm -f $out/$label.*
uid=$(id -u frame); rt=/run/user/$uid
asframe() { runuser -u frame -- env XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=wayland-1 "$@"; }
install -d -o frame -g frame /home/frame/hyprtest; install -o frame -g frame -m 644 /root/guest/hyprtest/*.lua /home/frame/hyprtest/

t0=$(date +%s)
session start HYPRLAND_TRACE=1 AQ_TRACE=1 NO_COLOR=1 "$@" -- "exec Hyprland --config /home/frame/hyprtest/$cfg.lua"
ok=0
for i in $(seq 1 90); do
  if asframe hyprctl -i 0 version >/dev/null 2>&1; then ok=1; break; fi
  systemctl is-active -q vt-session.service || [[ $i -lt 5 ]] || break
  sleep 2
done
t1=$(date +%s)
{
  echo "# label=$label config=$cfg env: $*"
  echo "# hyprctl answered: $ok, after $((t1 - t0)) s; unit state: $(systemctl is-active vt-session.service)"
} > $out/$label.info
if (( ok )); then
  # With a Lua config, "hyprctl dispatch" takes Lua. hl.exec_cmd is what Omarchy's own config uses.
  asframe hyprctl -i 0 eval 'hl.exec_cmd([[foot -T one sh -c "uname -a; echo; head -8 /proc/cpuinfo; echo $LABEL; exec sh"]])' >>$out/$label.info 2>&1
  sleep 15
  asframe hyprctl -i 0 eval 'hl.exec_cmd([[foot -T two sh -c "while :; do date; sleep 1; done"]])' >>$out/$label.info 2>&1
  sleep 20
  {
    echo "## hyprctl version";     asframe hyprctl -i 0 version
    echo "## hyprctl monitors";    asframe hyprctl -i 0 monitors
    echo "## hyprctl clients";     asframe hyprctl -i 0 clients | grep -E '^Window|at:|size:|class:|title:|xwayland'
    echo "## hyprctl configerrors"; asframe hyprctl -i 0 configerrors
    echo "## hyprctl systeminfo (GL part)"; asframe hyprctl -i 0 systeminfo | grep -iE 'GL |GLES|renderer|vendor|Hyprland|aquamarine|Explicit|plugins|uname|system name' | head -30
  } >> $out/$label.info 2>&1
  asframe grim /tmp/$label.png 2>>$out/$label.info && mv /tmp/$label.png $out/$label.png
  memsnap "$label" > $out/$label.mem 2>&1
fi
cp /var/log/vt-session.log $out/$label.log
sig=$(ls -t $rt/hypr 2>/dev/null | head -1)
[[ -n $sig && -f $rt/hypr/$sig/hyprland.log ]] && cp $rt/hypr/$sig/hyprland.log $out/$label.hyprland.log
[[ ${KEEP:-0} == 1 ]] || session stop >/dev/null 2>&1
echo "--- $label: hyprctl ok=$ok after $((t1 - t0)) s"
sed -E 's/\x1b\[[0-9;]*m//g' $out/$label.log | grep -E 'Using: |Vendor: |Renderer: |GLES|EGL context|retry|RASSERT|Assertion|CRIT|ERR |terminate|[Ss]hader|GL error|what\(\)' | grep -v TRACE | cut -c1-220 | sort | uniq -c | sort -rn | head -30
grep -E '^Window|class:|title:' $out/$label.info | head -8
