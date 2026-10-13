#!/bin/sh
# Watch for the frame on the Mac after power-on. Read-only: it changes nothing.
#   image/tools/watch-frame.sh          # runs for 3 minutes, one line each second on a change
# It looks for: a USB device from the frame, a serial port /dev/cu.usbmodem*,
# a network interface with the gadget's MAC address, an answer from 10.55.0.1.
t0=$(date +%s); last=""
echo "time  usb-device                         serial-port                  network            ping"
while :; do
	t=$(( $(date +%s) - t0 ))
	usb=$(ioreg -p IOUSB -w 0 2>/dev/null | grep -o -E 'PF1007L Linux|USB download gadget|sunxi|Allwinner[^@]*' | head -n 1)
	fel=$(ioreg -p IOUSB -l -w 0 2>/dev/null | grep -c '"idProduct" = 61416')    # 0xefe8 = FEL
	[ "$fel" -gt 0 ] && usb="FEL (boot ROM)"
	ser=$(ls /dev/cu.usbmodem* 2>/dev/null | tr '\n' ' ')
	ifc=$(ifconfig 2>/dev/null | awk '/^[a-z0-9]+:/{i=$1} /ether 02:50:46:10:07:02/{print i}' | tr -d ':')
	ip=""; [ -n "$ifc" ] && ip=$(ifconfig "$ifc" | awk '/inet /{print $2}')
	png=no; [ -n "$ip" ] && ping -c 1 -t 1 10.55.0.1 >/dev/null 2>&1 && png=yes
	now="${usb:-none} | ${ser:-none} | ${ifc:-none} ${ip} | $png"
	if [ "$now" != "$last" ]; then
		printf '%3ds  %s\n' "$t" "$now"; last=$now
	fi
	[ "$t" -ge 180 ] && break
	sleep 1
done
echo "end. Next: screen \$(ls /dev/cu.usbmodem* | head -n 1) 115200   or   ssh -F image/secrets/ssh_config frame"
