# PF1007L bring-up image: notes on the device

The full design is in the project: `image/README.md`. This file is the short copy on the frame.

## USB link to the Mac
- The frame is a USB device with two functions: a serial port (ACM) and a network port (NCM).
- Serial: on the Mac, `ls /dev/cu.usbmodem*`, then `screen /dev/cu.usbmodemXXXX 115200`.
  The console logs in the user `frame` with no password. `sudo` needs no password.
- Network: the frame is `10.55.0.1`. It gives the Mac an address `10.55.0.10` to `10.55.0.29`.
  `ssh frame@10.55.0.1` with the key from `image/secrets/`.
- Settings: `/boot/pf/gadget.conf`. Script: `/usr/lib/pf1007l/pf-gadget up|down|status`.

## Boot-stage markers
- `/boot` is the FAT partition of the card. A Mac reads it with no tools.
- `/boot/pf/stages.log`: one line for each stage of each start.
- `/boot/pf/stage/`: one empty file for each stage of the last start.
- `/boot/pf/last/`: `dmesg.txt`, `journal.txt`, `status.txt` of the last start. `/boot/pf/prev/`: the start before.
- `/boot/pf/uboot.env`: written by U-Boot. `/boot/pf/linux-ok.env`: written by Linux when the Mac configured the USB link.

## Device trees
`pf-bootsel` shows the labels. Start with `min`. Then `pmic`. Then `full`.

## Clock
The frame has no clock battery. At each start the clock is at least the image build time.
Set it from the Mac: `image/tools/frame-set-clock.sh`.

## Internet through the Mac (later)
1. On the frame: `sudo cp /usr/share/doc/pf1007l/20-usb-gadget-client.network /etc/systemd/network/10-usb-gadget.network`
   and `sudo systemctl restart systemd-networkd`. The frame then asks the Mac for an address.
2. On the Mac: System Settings, General, Sharing, Internet Sharing: share your connection to the
   "PF1007L Linux" interface. The frame then gets an address `192.168.2.x`.
3. Find the frame: `ping pf1007l.local`, or use the serial console and `ip -br addr`.
This is not tested.

## Safety
- The eMMC (Android) is not visible: the device trees keep its controller disabled.
  A udev rule makes an eMMC read-only if one shows up.
- The Wi-Fi driver does not load by itself. See `WIFI.md`.
