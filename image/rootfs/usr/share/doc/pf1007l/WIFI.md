# Wi-Fi (AIC8800 on SDIO): manual first test

Status: the driver was built for this kernel and loads in an emulator. It never ran with the chip.
The chip type and revision of this unit are not read yet. So the image does NOT load the driver
by itself (`/etc/modprobe.d/pf1007l-wifi.conf`).

Files in this image:
- Modules: `/usr/lib/modules/7.2.10-1-armv7-ARCH/updates/aic8800_bsp.ko`, `aic8800_fdrv.ko`, `aic8800_btlpm.ko`
- Firmware: `/usr/lib/firmware/aic8800_fw/SDIO/aic8800DC/` (Radxa set, chip revision U02 only)

Steps (from `wifi/README.md` section 9):
1. Start with the `full` device tree: `pf-bootsel full`, then `sudo reboot`. The `min` and `pmic`
   trees keep the Wi-Fi bus off.
2. `pf-wifi-check`. Expected: `SDIO_ID=C8A1:C08D`. **This is the first gate.** No SDIO device means
   a power or reset problem in the device tree, not a driver problem. Do not load the driver then.
3. `pf-wifi-check --load`. Record the `chip_id`, `chip_sub_id` and revision lines of `dmesg`.
4. `iw dev`, then `sudo systemctl start iwd`, `iwctl station wlan0 scan`, `iwctl station wlan0 get-networks`.
5. If it works and you want it at each start: remove `/etc/modprobe.d/pf1007l-wifi.conf` and
   `sudo systemctl enable iwd`.

Use a good power supply for this test: one unit of another owner froze at the driver load on hub power.
The driver makes a new MAC address at each load (2 random bytes).
