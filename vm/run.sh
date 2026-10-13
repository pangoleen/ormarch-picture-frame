#!/bin/bash
# Run the 32-bit ARM test VM (QEMU TCG, machine "virt", stock ALARM kernel, virtio-gpu KMS display).
#
#   vm/run.sh start            start QEMU in the background (serial console -> vm/logs/serial.log)
#   vm/run.sh wait             wait until SSH answers
#   vm/run.sh ssh USER 'cmd'   run a command in the guest (USER: root, alarm or frame)
#   vm/run.sh scp SRC... DST   copy files; write the guest as root@vm:/path
#   vm/run.sh shot NAME        screenshot of the guest screen -> vm/logs/NAME.png (QMP screendump)
#   vm/run.sh key CHORD...     press keys, for example: meta_l-ret
#   vm/run.sh stop             clean power-off (falls back to QMP quit)
#   vm/run.sh status
#
# Environment: MEM (MiB, default 1024 = the frame), SMP (default 4), CPU (default cortex-a7),
#   GPU (default "virtio-gpu-pci,xres=1280,yres=800"), SSH_PORT (default 22722), EXTRA_APPEND (kernel arguments).
set -euo pipefail
VM=$(cd "$(dirname "$0")" && pwd)
MEM=${MEM:-1024}; SMP=${SMP:-4}; CPU=${CPU:-cortex-a7}
GPU=${GPU:-virtio-gpu-pci,xres=1280,yres=800}
SSH_PORT=${SSH_PORT:-22722}
QMP=$VM/run/qmp.sock; PID=$VM/run/qemu.pid
SSH_OPTS=(-i "$VM/keys/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
          -o ConnectTimeout=10 -o ServerAliveInterval=30)

running() { [[ -f $PID ]] && kill -0 "$(cat "$PID")" 2>/dev/null; }

case ${1:-} in
start)
  running && { echo "already running (pid $(cat "$PID"))"; exit 0; }
  mkdir -p "$VM/run" "$VM/logs"; rm -f "$QMP"
  [[ -f $VM/logs/serial.log ]] && mv "$VM/logs/serial.log" "$VM/logs/serial.prev.log"
  # highmem=off: the stock kernel has no LPAE, so all devices (PCI ECAM too) must be below 4 GiB.
  # No -dtb: QEMU makes the device tree of "virt". No initramfs: virtio-pci, virtio-blk and ext4 are built in.
  qemu-system-arm \
    -M virt,highmem=off,gic-version=2 -cpu "$CPU" -smp "$SMP" -m "$MEM" \
    -accel tcg,thread=multi,tb-size=512 \
    -kernel "$VM/out/zImage" \
    -append "console=ttyAMA0 root=/dev/vda rw rootwait psi=1 loglevel=6 systemd.show_status=1 ${EXTRA_APPEND:-}" \
    -drive if=none,id=hd0,file="$VM/out/root.qcow2",format=qcow2,discard=unmap,detect-zeroes=unmap,cache=unsafe \
    -device virtio-blk-pci,drive=hd0 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$SSH_PORT"-:22 -device virtio-net-pci,netdev=n0 \
    -device "$GPU" -device virtio-keyboard-pci -device virtio-tablet-pci -device virtio-rng-pci \
    -display none -monitor none -serial file:"$VM/logs/serial.log" \
    -qmp unix:"$QMP",server=on,wait=off -pidfile "$PID" -daemonize
  date -u +%s > "$VM/run/start.epoch"
  echo "started: pid $(cat "$PID"), MEM=$MEM SMP=$SMP CPU=$CPU GPU=$GPU"
  ;;
wait)
  for i in $(seq 1 180); do
    if ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" root@127.0.0.1 true 2>/dev/null; then
      echo "ssh up after $(( $(date -u +%s) - $(cat "$VM/run/start.epoch") )) s"; exit 0
    fi
    running || { echo "QEMU stopped"; tail -5 "$VM/logs/serial.log"; exit 1; }
    sleep 5
  done
  echo "no SSH after 15 minutes"; exit 1
  ;;
ssh)
  user=$2; shift 2
  exec ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" "$user"@127.0.0.1 "$@"
  ;;
scp)
  shift; args=()
  for a in "$@"; do args+=("${a/#*@vm:/${a%%@vm:*}@127.0.0.1:}"); done
  exec scp -q -r "${SSH_OPTS[@]}" -P "$SSH_PORT" "${args[@]}"
  ;;
shot)
  python3 "$VM/qmp.py" "$QMP" screendump "$VM/logs/$2.png" && echo "$VM/logs/$2.png"
  ;;
key)
  shift; python3 "$VM/qmp.py" "$QMP" key "$@"
  ;;
qmp)
  shift; python3 "$VM/qmp.py" "$QMP" "$@"
  ;;
stop)
  running || { echo "not running"; exit 0; }
  ssh "${SSH_OPTS[@]}" -p "$SSH_PORT" root@127.0.0.1 'sync; systemctl poweroff' 2>/dev/null || true
  for i in $(seq 1 60); do running || break; sleep 2; done
  running && python3 "$VM/qmp.py" "$QMP" quit
  rm -f "$PID"; echo stopped
  ;;
status)
  running && echo "running (pid $(cat "$PID"))" || echo "not running"
  ;;
*)
  sed -n '2,14p' "$0"; exit 1 ;;
esac
