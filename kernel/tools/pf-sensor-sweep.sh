#!/bin/bash
# PF1007L sensor hunt: log every cheap-to-read input one time each second, so that a change made by
# hand (cover the front hole, shine a torch into it, clap) shows as a column that moves.
#
# Run on the frame as root:   sudo pf-sensor-sweep.sh <seconds> <output.csv>
# It reads only. It asks for GPIO lines as inputs, and only lines that the pin controller reports as
# "(MUX UNCLAIMED) (GPIO UNCLAIMED)"; port C (the eMMC pins) is always left out.
set -u
secs=${1:?seconds}
out=${2:?output file}
pinctrl=/sys/kernel/debug/pinctrl/1c20800.pinctrl/pinmux-pins
axp=$(ls -d /sys/kernel/debug/regmap/*rsb* 2>/dev/null | head -1)
accel=""
for d in /sys/bus/iio/devices/iio:device*; do
	[ -r "$d/name" ] && [ "$(cat "$d/name")" = sc7a20 ] && accel=$d
done

# Free pins of the main controller, without port A (not on the A33) and port C (eMMC).
lines=$(awk '/MUX UNCLAIMED\) \(GPIO UNCLAIMED/ {n=$2+0; if (n >= 32 && !(n >= 64 && n < 96)) printf "%d ", n}' "$pinctrl")

axp_regs() {   # AXP223 ADC result registers and the ADC enable register
	[ -n "$axp" ] || return
	awk -F': ' '$1 ~ /^(56|57|58|59|5a|5b|78|79|7a|7b|7c|7d|82|84)$/ {printf "%s=%s ", $1, $2}' "$axp/registers"
}

lradc() {      # A33 LRADC (key ADC) control and data registers, read through /dev/mem if the kernel allows it
	python3 - <<'PY' 2>/dev/null || echo "lradc=unreadable"
import mmap, os, struct
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x01C22000)
ctrl, intc, ints, d0, d1 = struct.unpack_from("<5I", m, 0x800)
print(f"lradc_ctrl={ctrl:08x} lradc_data0={d0 & 0x3f} lradc_data1={d1 & 0x3f}")
PY
}

{
	echo "# lines: $lines"
	echo "# columns: t | accel x y z | soc temp | axp regs | lradc | gpio levels in the order of 'lines'"
} >"$out"

end=$((SECONDS + secs))
while ((SECONDS < end)); do
	a=""
	[ -n "$accel" ] && a="$(cat "$accel/in_accel_x_raw") $(cat "$accel/in_accel_y_raw") $(cat "$accel/in_accel_z_raw")"
	# shellcheck disable=SC2086
	g=$(gpioget -c gpiochip1 --numeric $lines 2>&1 | tr -d ' \n')
	echo "$(date +%H:%M:%S) | $a | $(cat /sys/class/thermal/thermal_zone0/temp) | $(axp_regs)| $(lradc) | $g" >>"$out"
	sleep 1
done
