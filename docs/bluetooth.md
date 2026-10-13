# Native Bluetooth on the PF1007L

Date: 2026-10-12. Test from the Linux SD card. No eMMC writes.

## Result so far

**Native Bluetooth is proved on this frame.** With the normal Wi-Fi/BT
firmware loaded, UART1 replies to HCI `Read Local Version` at 1,500,000 baud.
The reply reports Bluetooth HCI version 0x0b (5.2). BlueZ exposes a powered
LE controller. A 12-second discovery test found 10 devices. A permanent boot
service is installed and **passed a reboot test**. The controller powered
itself and a new 8-second LE scan found 10 devices after reboot. GPIO
reset/wake changes were not needed. The separate SDIO build is ready but no
longer needed for this UART path.

Do not infer that Bluetooth is absent from `bt_used = 0`. That value disables
the vendor board feature. It does not identify the chip or prove missing wires.

## Checked facts

| Evidence | Meaning |
|---|---|
| [VERIFIED on the device] BlueZ and `hci_uart` expose a powered `hci0` | The UART transport, controller initialization and LE discovery work. |
| [VERIFIED in this unit's fex] UART1 is enabled on PG6, PG7, PG8, PG9; type 4 | Stock mapping for TX, RX, RTS and CTS. A valid HCI reply proves the working TX/RX path. |
| [VERIFIED in this unit's fex] BT UART ID = 1, reset = PL8, wake = PL10, host wake = PL9; `bt_used = 0` | Candidate board signals. Do not toggle them without a coordinated test. |
| [VERIFIED in the kernel source] UART1 is `serial@1c28400`; PG6–PG9 have UART1 mux 2 | Mainline supports the stock UART pin mapping. |
| [VERIFIED on the device] PG6–PG9 were initially unclaimed and are now UART1; PL8–PL10 remain unclaimed | No candidate reset/wake GPIO changes were needed. |
| [VERIFIED on the device] Wi-Fi BSP reports BT combo mode, 1,500,000 baud, flow control enabled, low-power mode disabled | BT patch loading is already part of the working Wi-Fi firmware path. |
| [VERIFIED in source] `CONFIG_SDIO_BT=y` changes the BT port from UART to mailbox and selects the shipped `*_hbt_u02` firmware | A native SDIO experiment can avoid UART wiring. It needs a separate driver build and firmware reload. |

The [AICsemi DC datasheet, hosted by Pine64](https://pine64.sfo3.cdn.digitaloceanspaces.com/doc/datasheet/oz64/AIC8800DC%20Datasheet%20v1.0.pdf)
states that AIC8800DC has Bluetooth 5.2 and HCI UART. The product-identification
table distinguishes DC (Wi-Fi plus BT) from DW (Wi-Fi only). **The exact
silicon capability on this board is not proved by the SDIO ID.** In the
vendor driver, `aicwf_sdio_chipmatch()` hardcodes `PRODUCT_ID_AIC8800DC` for
`c8a1:c08d`; the family also covers DW. A controller reply or a chip-marking
photo must close this gap. The valid UART controller reply now closes it:
this board has working Bluetooth-capable silicon.

Source references, pinned Radxa tree at `e9e43ed79c50483080e9bcdfb08caeeb869d7191`:

- `dumps/sys_config.fex`: `[uart1]` and `[bt_para]`.
- `refs/kernel/linux-7.2.10/arch/arm/boot/dts/allwinner/sun8i-a23-a33.dtsi`: UART1 and both PG pin groups.
- `refs/kernel/linux-7.2.10/drivers/pinctrl/sunxi/pinctrl-sun8i-a33.c`: PG6–PG9 UART functions.
- `refs/aic/radxa-pkg_aic8800/src/SDIO/driver_fw/driver/aic8800/aic8800_bsp/aicsdio.c`: `aicwf_sdio_chipmatch()`.
- Same BSP directory, `aic_bsp_driver.c`: `aicbt_info[]`, `aicbt_patch_table_load()`.
- Same BSP directory, `aic_bsp_driver.h`: `AICBT_BTPORT_DEFAULT`, baud/flow defaults and H/ HBT firmware names.
- `aic8800_fdrv/Makefile`, `btsdio.c`, `rwnx_main.c`: optional BlueZ SDIO transport.

## Separate UART test

`wifi/bluetooth-uart1.dtso` changes only UART1 and adds `serial1`, giving
`/dev/ttyS1`. It claims both PG pin groups, including RTS/CTS. It does not
change PL8, PL9 or PL10. It does not add a UART console. Both eMMC and R_UART
remain disabled.

The overlay was built with `dtc -@` and applied with `fdtoverlay` to a copy of
the frame's actual working `/boot/dtbs/sun8i-a33-pf1007l-full.dtb`. Both tools
returned success with no warnings. Outputs are private build artifacts under
`wifi/out/bluetooth/`.

Installed on the frame, with the parent's agreement:

- `/boot/dtbs/sun8i-a33-pf1007l-bluetooth.dtb`
- Separate `bluetooth-test` label in `/boot/extlinux/extlinux.conf`.
- `/usr/local/bin/pf-bt-uart-probe`, from `wifi/bt-uart-probe.py`.
- Boot config backup: `/boot/extlinux/extlinux.conf.before-bluetooth-test`.

The original `full` DTB stays unchanged. During the first test, the parent
restored `DEFAULT full` as soon as SSH returned. The later permanent label is
`full-bluetooth`, documented below. Historical test commands:

```sh
ssh -F image/secrets/ssh_config frame 'sudo pf-bootsel bluetooth-test'
# Coordinate the reboot with the main agent.
# After the test boot returns:
ssh -F image/secrets/ssh_config frame 'sudo pf-bootsel full'
ssh -F image/secrets/ssh_config frame 'sudo pf-bt-uart-probe --flow'
```

The probe sends only H4 `Read Local Version` (opcode 0x1001), with a 3-second
receive bound. It does not query a MAC address or control GPIOs. A real HCI
Command Complete reply proves a controller. A tty node or a controller listed
after `btattach` alone is insufficient: the generic transport can register
before the chip responds.

If the first probe is silent, try without host flow control. A later power
test can use PL8/PL10 only after coordination with the main agent. Record the
original pin states and return them afterwards. Do not reload Wi-Fi firmware
or reboot while the main agent is changing the desktop.

The frame's packaged `btattach` cannot be used directly with this libc.
Use the verified `pf-bt-uart-attach` helper described below.

### First UART test boot

The test label booted. The kernel registered `ttyS1` at `0x1c28400`, IRQ 131,
base baud 1,500,000. Desktop services ran. The parent restored `DEFAULT full`
for future starts. SSH was delayed; the USB serial console provided recovery.

The first probes, at 1,500,000 and 115,200 baud with and without RTS/CTS, gave
no valid HCI reply. The first probe saw six invalid bytes; the others saw
none. **These are not a conclusive hardware test:** the working AIC firmware
was not loaded after reboot. Both SDIO functions existed, but no AIC module
was loaded. The old Wi-Fi blacklist overrode the intended boot module list.
The parent corrected the blacklist and loaded the normal Wi-Fi modules
before the next UART probe. No PL8/PL10 change was made.

### Confirmed controller response after firmware load

The parent loaded the normal Wi-Fi modules. UART probes with and without
RTS/CTS both returned this valid HCI Command Complete packet:

```text
04 0e 0c 05 01 10 00 0b 14 00 0b 3b 0b 14 00
```

It completes opcode 0x1001 with success status 0, HCI version 0x0b, revision
0x0014, LMP version 0x0b, manufacturer 0x0b3b and LMP subversion 0x0014.
This directly proves Bluetooth-capable silicon and a working UART TX/RX
path. The GPIO candidates in the disabled stock BT configuration do not
need to be claimed for this firmware configuration.

The first matcher wrongly required a command-credit count of 1. This chip
returns 5. The probe now ignores that variable count and validates the
event, opcode, status and full packet length. A corrected probe passed with
RTS/CTS. The earlier "no verified response" output after firmware load was
a probe-parser error, not a controller failure.

### BlueZ attachment and discovery passed

The packaged BlueZ 5.87 `btattach -S 1500000` set an invalid UART speed
(input 200 baud, output 0). HCI reset timed out. The hardware was healthy.
The [BlueZ upstream compatibility fix](https://github.com/bluez/bluez/commit/12f5eb7)
explains the glibc 2.42 baud-constant change; this frame uses glibc 2.43.

`wifi/bt-uart-attach.py` uses Python's current termios API to set and verify
the UART baud rate, then attaches H4 with the kernel's HCI line discipline.
It handles shutdown and restores the former line discipline and settings.
Installed as `/usr/local/bin/pf-bt-uart-attach`, it registered a powered
BlueZ `hci0` controller. No firmware reload or GPIO change was needed.

A bounded 12-second `btmgmt find -l` scan started and found **10 unique
devices**. Discovery was stopped. Addresses and names were kept out of tool
output and published logs. Pairing has not been tested: no mouse or keyboard
is available yet.

The controller exposes **LE**, secure connections and privacy. BR/EDR is
absent from its supported settings. Recommend **Bluetooth LE keyboards and
mice** for this verified configuration. The firmware's reason for omitting
classic Bluetooth is not established. Driver `btmode=1` means Wi-Fi/BT
combo, not an explicit LE-only mode. No working firmware was changed to
expand this scope.

### Permanent boot integration installed

The parent approved persistent integration. Installed and enabled:

- `/etc/systemd/system/pf-bluetooth-uart.service`, from `wifi/pf-bluetooth-uart.service`.
- The verified probe and UART helper under `/usr/local/bin/`.
- A separate `full-bluetooth` boot label selecting the verified Bluetooth DTB.
- `DEFAULT full-bluetooth` for the next and later starts.

The original `full` label and DTB remain unchanged. A further boot-config
backup is `/boot/extlinux/extlinux.conf.before-full-bluetooth`.

The unit waits for `dev-ttyS1.device` and `systemd-modules-load.service`.
It loads the normal `aic8800_fdrv` (the BSP downloads BT firmware first),
loads `hci_uart`, verifies a valid HCI local-version reply, and then
supervises the correct-baud helper. `systemd-analyze verify` passed. The
permanent unit is active and exposes a powered controller after replacing
the temporary helper. The parent's final reboot passed: the service started
without manual commands, its UART probe passed, and BlueZ exposed a powered
controller. A new 8-second scan was accepted and found 10 unique devices.
Service boot logs contain no initialization failure. Discovery was stopped.
The parent also confirmed Wi-Fi automatic reconnect and direct HTTPS after
the same reboot. The kernel's `uhid` module is available for future LE HID
keyboards and mice.

Rollback from a shell:

```sh
sudo pf-bootsel full
sudo systemctl disable --now pf-bluetooth-uart.service
sudo reboot
```

## SDIO experiment (built, not deployed)

`wifi/build-bluetooth-sdio.sh` builds in a separate
`refs/aic/build-bluetooth-sdio` tree and writes to
`wifi/out/bluetooth-sdio`. It uses the same pinned vendor source, Radxa kernel
patches, ARM container and kernel-header package as the working Wi-Fi build.
The feature switch is `CONFIG_SDIO_BT=y`. The Ubuntu build selects
BlueZ (`CONFIG_BLUEDROID=0`), and the chip's BT port changes to mailbox.

The first build failed in the previously unused `btsdio.c`: the stock 7.2
kernel removed `hci_dev.dev_type` and `HCI_PRIMARY`. The project patch
`wifi/bluetooth-sdio.patch` removes that obsolete assignment. Before a device
test, source inspection also found unsafe RX and unload paths. The patch
adds an empty-packet guard and an allocation-failure return, removes the
second free after `hci_recv_frame()` takes ownership of an RX buffer, and
keeps driver data alive until HCI unregister and the TX worker finish.
The [upstream HCI receive implementation](https://github.com/torvalds/linux/blob/master/net/bluetooth/hci_core.c)
frees rejected packets itself; the vendor's extra free was invalid.

The patched build passed compilation, link and modpost. The output is
ARMv7 with `7.2.10-1-armv7-ARCH` vermagic. `aic8800_fdrv` now depends on
`cfg80211`, `bluetooth`, and `aic8800_bsp`. Control failure log:
`wifi/logs/bluetooth-sdio/build-control-no-project-patch.log`. Patched log:
`wifi/logs/bluetooth-sdio/build.log`. These are build checks, not proof of a
working controller. The normal Wi-Fi modules are unchanged.

Do not replace the normal Wi-Fi modules yet. Test these via explicit `insmod`
after unloading the normal modules, with the USB management link available.
Keep the original firmware and modules for rollback. The driver must select
the HBT Wi-Fi firmware; firmware names alone do not prove operation.

## Remaining proof

1. Mouse/keyboard pairing and reconnect at boot, when the owner has devices.
