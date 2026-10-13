#!/bin/bash
# HOOK script: open the Omarchy menu and one panel with long waits (QEMU is slow), take screenshots.
export OMARCHY_SHELL_IPC_TIMEOUT=30s
call() { echo "\$ omarchy-shell $*"; omarchy-shell "$@" 2>&1 | head -c 600; echo " [exit ${PIPESTATUS[0]}]"; }
call shell summon omarchy.menu '{"menu":"root"}'
sleep 10
grim "$BASE.menu.png"
call shell hide omarchy.menu
sleep 3
call shell summon omarchy.power '{}'
sleep 10
grim "$BASE.power.png"
call shell hide omarchy.power
