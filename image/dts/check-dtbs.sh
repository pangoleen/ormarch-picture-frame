#!/bin/sh
# Runs INSIDE the pf1007l-uboot-build container. Safety checks on each DTB in /out:
#   - the eMMC controller (mmc@1c11000) must not be enabled  (project safety rule 3)
#   - R_UART (serial@1f02800, pins PL2/PL3) must not be enabled (PL2 = Wi-Fi chip_en)
#   - the USB port must be in peripheral mode
set -eu
rc=0
st() { fdtget -t s "$1" "$2" status 2>/dev/null || echo "(none)"; }
for f in /out/*.dtb; do
	n=$(basename "$f")
	emmc=$(st "$f" /soc/mmc@1c11000); ruart=$(st "$f" /soc/serial@1f02800)
	mode=$(fdtget -t s "$f" /soc/usb@1c19000 dr_mode 2>/dev/null || echo "(none)")
	echo "$n: eMMC=$emmc r_uart=$ruart usb=$mode model='$(fdtget -t s "$f" / model)'"
	[ "$emmc" = okay ] && { echo "STOP: $n enables the eMMC"; rc=1; }
	[ "$ruart" = okay ] && { echo "STOP: $n enables R_UART on PL2/PL3"; rc=1; }
	[ "$mode" = peripheral ] || { echo "STOP: $n: USB is not in peripheral mode"; rc=1; }
done
exit $rc
