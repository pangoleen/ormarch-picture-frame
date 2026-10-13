PF1007L SD card - what the files in this folder mean
====================================================

You can read all of this on a Mac: put the card in the reader, open the volume PFBOOT.

uboot.env       Written by U-Boot at EACH start, before it starts Linux.
                  pf_boots   = number of starts, in HEX (a = 10, 10 = 16)
                  pf_last    = what U-Boot did: linux | ums | loadfail
                  pf_prev_ok = yes: Linux confirmed the start before this one
linux-ok.env    Written by Linux when the Mac CONFIGURED the USB gadget.
                  pf_ok = the pf_boots value of that start
stages.log      One line for each stage of each start. "up=" is seconds since the kernel started.
stage/          One empty file for each stage of the LAST start. The file .boot holds its number.
last/           Logs of the last start: dmesg.txt, journal.txt, status.txt
prev/           Logs of the start before that
gadget.conf     USB gadget settings (edit here)

Stages in order
  20-initramfs-start        the kernel runs, our initramfs runs, this partition is writable
  30-gadget-up              the USB gadget is configured in the kernel (the Mac can see it now)
  30-gadget-FAILED          no USB device controller, or configfs error
  35-root-mounted           the root file system (partition 2) is mounted
  39-initramfs-RESCUE       the initramfs could not mount the root file system
  40-systemd-gadget-unit    systemd runs
  45-boot-partition-mounted lines that were made before this partition was mounted are now written
  50-local-fs-mounted       all file systems are mounted
  60-multi-user             the system is up (sshd, network)
  70-usb-<state>            USB state: "configured" = the Mac talks to the frame
  70-usb-no-udc             the kernel has no USB device controller
  71-usb-confirmed          Linux wrote linux-ok.env
  80..89-firstboot-*        first-boot work (grow the file system, pacman keyring)
  90-logs-saved             the logs in last/ are complete for that moment

How to read a failed start
  uboot.env not changed (pf_boots as before)       U-Boot did not run, or could not write
  pf_last=loadfail                                 U-Boot could not load the kernel files
  pf_last=linux, no "20-" line for that start      the kernel did not reach our initramfs
  "20-" but "30-gadget-FAILED"                     the kernel has no USB device controller
  "30-gadget-up", no "70-usb-configured"           the gadget is up, the Mac did not configure it
  "39-initramfs-RESCUE"                            root file system problem (text in the line)
  "35-" but no "40-"                               systemd did not start
  "40-" but no "60-"                               a service hangs; read last/journal.txt
