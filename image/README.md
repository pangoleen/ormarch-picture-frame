# image/ — PF1007L SD-card image builder

This document records the first image build on 2026-10-12 for the PF1007L
(Allwinner A33). Its original `image/out` artifact was validated in QEMU only:
it was not booted end-to-end on the physical frame. The working frame setup in
the repository root uses the same SD-only design, but a fresh rebuild from this
revision remains a hardware test on each compatible frame.

## 1. Answer first

- **The image is built**: `image/out/pf1007l-sd.img`, 3,221,225,472 bytes (3 GiB), about 0.9 GB on disk
  (sparse). SHA-256: see `image/out/pf1007l-sd.img.sha256` and section 9.
- **One command builds all open-source inputs from a clean clone**: `image/build.sh`
  (6 to 12 minutes after the proprietary touch firmware has been supplied as
  `PF1007L_TOUCH_FIRMWARE`; see `vendor/README.md`).
- **It boots in an emulator** (`qemu-system-arm -M orangepi-pc`): U-Boot → boot script → kernel →
  initramfs → systemd → SSH login with our key. The first-boot work, the USB gadget, the markers and
  the fallback logic passed their tests there. Results: section 7.
- **The first boot on the frame is still a real test.** The emulator is not the A33. It has no AXP223,
  no DSI panel and no working USB device controller. The list of unproven points is in section 10.
- **Next step for the owner**: section 8 (write a second card, power on, watch the Mac).

Tags: **[VERIFIED]** = read in source code or measured here (the place is given).
**[DOCUMENTED]** = a second-hand source says so. **[UNCONFIRMED]** = inference or design, not tested.
"Ran in QEMU" always means the emulator, never the frame.

### What was built or run, and what is only designed

| Item | Level |
|---|---|
| U-Boot build L for the frame (`u-boot-pf1007l-L.bin`) | **Built.** Config and device tree checked in the binary. **Never run** (not on the frame, not in QEMU: QEMU has no A33 board) |
| U-Boot test build (same source, same boot command, same `boot.scr`, Orange Pi PC board) | **Built and ran** in QEMU |
| Boot script `boot.scr`: counter, state file, decision Linux / USB disk mode | **Ran** in QEMU, 3 starts |
| Kernel `linux-armv7 7.2.10-1` (stock), our initramfs, root file system, all services | **Ran** in QEMU (with the Orange Pi PC device tree) |
| Device trees `min`, `pmic`, `full` for the frame | **Built** (`dtc`, 0 errors) and checked by rule. **Never booted** |
| USB gadget script (configfs, ACM + NCM) | **Ran** in QEMU against the kernel's loopback controller: a Linux host side enumerated it, logged in over ACM and got a DHCP address over NCM |
| The gadget on the A33 MUSB controller, and macOS as the host | **Not run** |
| First boot: root file system growth, pacman keyring, clock rule | **Ran** in QEMU |
| Card writer `tools/write-card.py` | The guards ran with fake disk data: 1 good card accepted, 9 wrong disks refused; the image hash check ran on the real image. **The write and the readback were not run** (they need a card and `sudo`) |
| Owner's procedure, timings on the frame, decision table | **Design** |

---

## 2. The card layout

| Offset | Content | Why |
|---|---|---|
| Sector 0 | MBR partition table, disk signature `0x50463037` | The A33 boot ROM does not read a partition table. MBR, not GPT: a GPT keeps its entries in sectors 2–33 and the SPL starts at sector 16, so the two overlap. A GPT also wants a second header at the end of the disk, and the image is smaller than the card [VERIFIED: sizes; the boot ROM offset is from Wes Bos's docs, DOCUMENTED] |
| 8 KiB (sector 16) | `u-boot-pf1007l-L.bin` (SPL + U-Boot, 536,544 bytes, ends at 532 KiB) | The boot ROM loads the SPL from 8 KiB of the SD card, before the eMMC [VERIFIED on this unit for the FEL stub, E016/E017] |
| 4 MiB (sector 8192) | Partition 1: FAT32, 256 MiB, label `PFBOOT` | A Mac reads and writes FAT32 with no tools. It holds the kernel, the device trees, the initramfs, `extlinux.conf`, the boot script, the markers and the logs. Start at 4 MiB: clear of U-Boot, and the value the project's card scripts require (≥ sector 8192) |
| 260 MiB (sector 532480) | Partition 2: ext4, label `pfroot`, to the end of the image | Root file system. 850 MiB used |

- Image size 3 GiB. The card class of the project has 15,939,928,064 bytes: the image fits.
- **The root partition grows at the first boot** to the end of the card (`pf-firstboot`: `sfdisk`,
  `partx`, `resize2fs`) [ran in QEMU: 2.7 GiB → 3.7 GiB on a 4 GiB card].
- The root file system is found by `PARTUUID=50463037-02`, not by a device name. The kernel has
  MMC and ext4 built in, so this works with and without the initramfs [VERIFIED: stock config].
- The files `.metadata_never_index` and `.fseventsd/no_log` on the FAT partition tell macOS not to
  index the volume [UNCONFIRMED effect; harmless].

---

## 3. U-Boot build L

Source: U-Boot v2025.10 (`e50b1e87…`, the commit of builds A–E)
+ `uboot/0001-wes-pf1007l-uboot.patch` (a byte-equal copy of Wes Bos's patch, SHA-256 `3aa2cbba…`)
+ `uboot/0002-pf1007l-linux-boot.patch` (ours).
Config: `pf1007l_linux_defconfig` = the settings of build E, plus the changes below.

**The full difference between the `.config` of build E and build L** [VERIFIED: `diff` of the two files]:

| Setting | Build E | Build L | Why |
|---|---|---|---|
| `CONFIG_CONS_INDEX` | 5 (R_UART, PL2/PL3) | 1 (UART0) | PL2 is the Wi-Fi `chip_en` pin on this unit |
| `CONFIG_SUNXI_CONSOLE_NO_PINMUX` (new) | — | y | The SPL connects no pin to the console UART |
| `CONFIG_SYS_CONSOLE_IS_IN_ENV`, `CONFIG_SYS_DEVICE_NULLDEV` | off | y | Console input = null device |
| `CONFIG_CMD_UMS_NO_ABORT` (new) | — | y | `ums` does not stop on console CTRL+C or on host eject |
| `CONFIG_MMC_SUNXI_SLOT_EXTRA` | 2 | −1 | No eMMC in this build |
| `CONFIG_DEFAULT_DEVICE_TREE` | `…-backup` | `…-linux` | eMMC, Wi-Fi bus, R_UART, display nodes disabled |
| `CONFIG_ENV_IS_NOWHERE` | off (`ENV_IS_IN_FAT`) | y | The behaviour never depends on a `uboot.env` file on the card |
| `CONFIG_BOOTCOMMAND` | `run distro_bootcmd` | see below | |
| `CONFIG_FASTBOOT_FLASH_MMC_DEV` | 1 | 0 | Follows from "no eMMC slot". fastboot is not used |

Not changed: `DRAM_CLK=456`, `DRAM_ZQ=31739`, `AXP_DCDC1_VOLT=3300`, `AXP_DCDC2_VOLT=1200`,
`AXP_DCDC3_VOLT=1200`, `AXP_DCDC5_VOLT=1500`, `AXP_ALDO1_VOLT=3300`, `AXP_ALDO2_VOLT=2500`,
`AXP_ALDO3_VOLT=3000`, `BOOTDELAY=-2`, `USB_MUSB_GADGET`, `CMD_USB_MASS_STORAGE`, `FAT_WRITE`
(`build.sh` checks these lines on each build).

**SPL size**: the SPL code ends at **`0x450a`**. The limit of `build-uboot.sh` is `0x5e00`.
(Build E: `0x456a`.) The eGON header checksum is correct [VERIFIED: computed].

### 3.1 Console: UART0 with no pins, and no console input

The SPL sets the console pins in `arch/arm/mach-sunxi/board.c`, `gpio_init()`. For an A33 the code
has these choices, and this board uses each of the pins for something else:

| `CONS_INDEX` | Pins that U-Boot switches (`board.c` line) | On this board (`dumps/sys_config.fex`) |
|---|---|---|
| 5 (builds A–E) | PL2, PL3 = R_UART (184–187) | PL2 = `[rf_para] chip_en` (Wi-Fi enable). PL3 floats |
| 1 | PB0, PB1 = UART0 (120–123) | `[gpio_keys] key1 = PB00`, `key2 = PB01`: key inputs |
| 1 + `UART0_PORT_F` | PF2, PF4 (84–99) | SD card CLK and D3: no SD boot is possible |
| 2 | PG6, PG7 = UART1 (188–192) | `[uart1] uart_used = 1`, type 4: the Bluetooth UART of the Wi-Fi module |
| 3 | PB0, PB1 = UART2 (176–179) | The same key inputs |
| other | `#error` | — |

All [VERIFIED: source lines and fex]. So each existing choice drives a pin that has another function.

**Decision: `CONS_INDEX=1` + the new option `CONFIG_SUNXI_CONSOLE_NO_PINMUX`.**
- The SPL and U-Boot use UART0 as before, with its normal clock (`clock_sun6i.c:87–118`, the path of
  the upstream A33 board Sinlinx SinA33). **No pin is switched to a UART function.** The text goes
  nowhere.
- The U-Boot device tree has `&uart0` with no `pinctrl` property, `stdout-path = "serial0"`, and
  `&r_uart` disabled [VERIFIED: the device tree inside the built binary, decompiled].
- Why not "no serial driver at all" (`REQUIRE_SERIAL_CONSOLE=n`, `SPL_SERIAL=n`): that changes more
  code paths than necessary. A UART that runs with no pins keeps U-Boot on the paths that builds
  A–E used. [UNCONFIRMED: build L never ran on the frame]
- Why not `CONFIG_SILENT_CONSOLE`: it stops the text but the pins are still switched.

**Console input.** A floating RX pin can look like key presses. The project measured this today: `ums`
stopped after about 7 minutes in two runs, and a build that ignores console CTRL+C and host eject
ran 30+ minutes (probable cause: noise on PL3 with `CONS_INDEX=5`) [VERIFIED on the frame by the
main session; cause UNCONFIRMED]. Build L has three independent protections:

| # | Protection | Where | Test |
|---|---|---|---|
| 1 | No pin is connected to the UART RX input | `SUNXI_CONSOLE_NO_PINMUX` | Source only. What the UART reads with no pin is not known [UNCONFIRMED] |
| 2 | `stdin=nulldev` in the built-in environment (and `setenv stdin nulldev` again in the boot command). `BOOTDELAY=-2`: autoboot never looks for a key (`common/autoboot.c:500`) | `include/configs/sunxi-common.h`, `CONFIG_BOOTCOMMAND` | **Ran in QEMU**: U-Boot prints `In: nulldev`; CTRL+C and text typed on the console for 20 s did not stop the script or `ums` |
| 3 | `ums` ignores console CTRL+C and host eject (`CONFIG_CMD_UMS_NO_ABORT`): the same protection as the diagnostic patch `scripts/uboot/wesbos-issue24-ums-diag.diff`, as a build option | `drivers/usb/gadget/f_mass_storage.c`, `cmd/usb_mass_storage.c` | Built. The patch it copies ran 30+ minutes on the frame |

`ums` still ends when the USB cable check fails. The boot command then starts it again after 3 s.
Not copied from the diagnostic patch: the watchdog, the read retries and the SRAM console log. Reason:
the SD card showed no read errors, and a watchdog reset in "USB disk mode" would start Linux again
with nobody watching. This is a choice, not a test result.

### 3.2 eMMC protection: build L has no eMMC device

Project safety rule 3: no write to the eMMC before the last phase. Build L does not "refuse" eMMC
writes: **it has no path to the eMMC at all.**

| Layer | What | Evidence |
|---|---|---|
| SPL | `CONFIG_MMC_SUNXI_SLOT_EXTRA=-1`: the SPL does not set the eMMC pins and does not start the controller (`board/sunxi/board.c:515`) | [VERIFIED: config + source] |
| U-Boot | `&mmc2 { status = "disabled"; }`: no driver instance. `mmc 1` does not exist | [VERIFIED: device tree in the binary]. In QEMU the test build shows one MMC device only (a different board: weak evidence) |
| U-Boot `ums` | Still read-only, as in builds A–E (write refused + write-protect flag), now for the SD card | [VERIFIED: the string `ums: refused write` is in the binary; `build.sh` stops without it] |
| Boot script | The only write command is `fatwrite mmc 0:1` (one small file on the SD card's FAT partition) | [VERIFIED: `uboot/boot.cmd`] |
| Linux | All three device trees have the eMMC controller disabled. `build.sh` stops if a DTB enables it (`dts/check-dtbs.sh`) | [VERIFIED: ran on the 3 DTBs] |
| Linux, second layer | A udev rule makes a block device of type `MMC` read-only (`force_ro`) if one shows up | [UNCONFIRMED: no eMMC in the emulator. Tested only that it does not touch the SD card] |

Why "remove the device" and not "keep the two-layer refusal": build L needs writes to the SD card
(the state file), so a blanket "no MMC writes" patch is not possible; and a device that does not
exist cannot be written by a mistake in a script. The Wi-Fi bus (`&mmc1`) is also disabled in U-Boot:
with the Q8 device tree, U-Boot would probe it and switch PL6/PL7/PL11.

### 3.3 Boot method and boot script

Built-in boot command (it cannot be lost with the card's files):

```
setenv stdin nulldev; if load mmc 0:1 ${scriptaddr} /boot.scr; then source ${scriptaddr}; fi; while true; do ums 0 mmc 0; sleep 3; done
```

`/boot.scr` (source: `uboot/boot.cmd`, on the card as `/boot.cmd`):

1. Reads `/pf/uboot.env` (its own state from the last start) and `/pf/linux-ok.env` (written by Linux).
2. Reads `/uEnv.txt` if it exists: plain text settings for the owner (`pf_mode=auto|linux|ums`).
3. Adds 1 to the start counter `pf_boots` (a hex number).
4. Decides. Normal: Linux. **If the last start was a Linux start and Linux did not confirm it: "USB disk
   mode".**
5. Writes `/pf/uboot.env` again (one small file, `fatwrite`) **before** it starts Linux.
6. Linux: `sysboot mmc 0:1 any ${pxefile_addr_r} /extlinux/extlinux.conf` = the standard
   `extlinux.conf` method. If a label cannot load its files, U-Boot tries the next labels; if none
   loads, the script writes `pf_last=loadfail` and goes to USB disk mode.
7. USB disk mode: `ums 0 mmc 0`. The Mac sees the **SD card as a read-only USB disk** ("USB download
   gadget", the device that builds A–E showed [VERIFIED on this unit for the eMMC, E018]). The owner
   reads the markers and logs **without pulling the card**.

So U-Boot is observable over USB without a UART in two ways: the state file on the FAT partition after
each start, and the USB disk on the start after a failed Linux start.

"Linux confirmed the start" means: the Mac **configured** the USB gadget (UDC state `configured`).
A Linux that runs but is not visible on USB counts as a failed start: the next power-on then shows
its logs to the Mac as a USB disk. With a wall charger (no USB host) each second power-on is USB disk
mode; set `pf_mode=linux` in `/uEnv.txt` to stop that.

[Ran in QEMU, with the same `boot.scr` and U-Boot source: start 1 → Linux; confirmed → start 2 → Linux;
not confirmed → start 3 → USB disk mode. The state file had the expected values after each start.]

`BOOTDELAY=-2`: no delay and no key check, as in builds A–E.

Observation, not a change: U-Boot has `CONFIG_USB_ETHER=y` (as build E). It prints
"using musb-hdrc … RNDIS ready" at start. Build E does the same and its `ums` works on the frame.

---

## 4. Linux: what the image does at boot

### 4.1 Device trees: a ladder of three steps

The boot menu (`/extlinux/extlinux.conf` on the FAT partition) has these labels. U-Boot starts
`DEFAULT` at once. Change it with a text editor on the Mac, or on the frame with `pf-bootsel <label>`.

| Label | Device tree | What the kernel can touch | Use |
|---|---|---|---|
| **`min`** (default) | `dts/sun8i-a33-pf1007l-min.dts` (ours, does not include the board draft) | SD slot + USB device port + CPU. **No PMIC node**, no display, touch, Wi-Fi, I2C, UART | The first, blind boot |
| `pmic` | The board draft `kernel/dts/sun8i-a33-pf1007l.dts` with display, backlight, PWM, GPU, touch and Wi-Fi bus disabled | + AXP223 on RSB, all regulators, I2C, keys | Step 2 |
| `full-stage1` | `kernel/out/sun8i-a33-pf1007l.dtb` (the kernel work's DTB) + the module blacklist of `kernel/bootcard/cmdline-stage1.txt` | Everything in the device tree, but display, GPU and Wi-Fi modules load only by hand | Step 3: `kernel/README.md` section 12, steps 2–7 |
| `full` | `kernel/out/sun8i-a33-pf1007l.dtb` | Everything | Step 4 |
| `min-noinitrd` | as `min`, no initramfs | | If the initramfs is the suspect |
| `min-shell` | as `min`, `pf.shell` | Stops in the initramfs: root shell on USB serial for 10 minutes | Debug |

Why `min` has no PMIC node [VERIFIED in source, UNCONFIRMED on the frame]:
- U-Boot build L already set the supply voltages to the vendor values. With no PMIC driver, nothing
  changes them and nothing turns a rail off.
- cpufreq then changes only the clock. The highest OPP of `sun8i-a33.dtsi` is 1.008 GHz at 1.2 V =
  the DCDC3 value. The `min` and `pmic` labels also keep the stock governor (`performance`), so the
  CPU clock does not change at all in the first boots.
- The USB PHY: with no `usb0_vbus_det` GPIO and no `usb0_vbus_power-supply`, the driver reports "VBUS
  present" (`phy-sun4i-usb.c:433`, "Fallback: report vbus as high"). The frame takes its power from
  VBUS, so that is true each time the frame runs. The link to the Mac thus does not depend on the PMIC
  driver or on the AXP's VBUS detection. The `pmic` label keeps this; `full` uses the AXP detection.
- The SD slot uses `broken-cd` (polling): no dependence on the polarity of the card-detect pin.

`dts/check-dtbs.sh` runs on each build: each DTB must have the eMMC disabled, R_UART disabled and
the USB port in peripheral mode. Result today: 3 of 3 pass.

### 4.2 Kernel command line

```
root=PARTUUID=50463037-02 rootfstype=ext4 rootwait ro console=tty0 ignore_loglevel log_buf_len=1M panic=20 psi=1 zswap.enabled=0 fsck.repair=yes pf.label=<label>
```

- `ro` + `fsck.repair=yes`: systemd checks the file system, then mounts it read-write (`/etc/fstab`).
  An unclean power-off is normal for this frame (the cable is the power switch).
- `panic=20`: a kernel panic restarts the SoC after 20 s. The next start is then USB disk mode. The
  restart needs the watchdog driver (`sunxi_wdt`, a module): the initramfs loads it first.
- `psi=1`: the stock kernel has PSI disabled by default [VERIFIED: config].
- `console=tty0` only. **`console=ttyGS0` is not on by default** (see 4.5).

### 4.3 Initramfs (`/pf-initramfs.img`, 0.9 MB)

Our own small initramfs: static busybox + 9 kernel modules + 3 scripts. Source: `initramfs/init`.
It is not the mkinitcpio image (the mkinitcpio hook is switched off; the kernel package is held).

1. Loads `sunxi_wdt`, `nls_cp437`, `nls_ascii`, `libcomposite`, `u_serial`, `usb_f_acm`, `u_ether`,
   `usb_f_ncm`, `usb_f_ecm` (the stock kernel has all of these as modules; MUSB, the PHY, configfs
   and VFAT are built in [VERIFIED: `refs/alarm-pkgbuilds/core/linux-armv7/config`]).
2. Finds the card by the MBR disk signature. Mounts the FAT partition. Marker `20-initramfs-start`.
3. **Starts the USB gadget.** Marker `30-gadget-up`.
4. Mounts the root file system read-only. Marker `35-root-mounted`. `switch_root`.
5. If the root file system cannot be mounted: marker `39-initramfs-RESCUE` with the reason, a root
   shell on the USB serial port for 10 minutes, then a restart.

Why an initramfs, when the kernel can mount the root by itself: the gadget is up some seconds sooner,
and **a root file system problem is no longer dark**: the Mac still gets a USB device and a shell.
[Ran in QEMU: steps 1–4. Step 5 was not run.]

### 4.4 USB gadget: ACM serial + NCM network (`/usr/lib/pf1007l/pf-gadget`)

One composite device through configfs, `1d6b:0104`, product "PF1007L Linux", serial text
`PF1007L0001` (a fixed text, not the SoC serial).

| Function | On the Mac | Driver on the Mac |
|---|---|---|
| CDC ACM (`acm.GS0` → `/dev/ttyGS0`) | `/dev/cu.usbmodem*`: a login console with no network setup | Built into macOS |
| CDC NCM (`ncm.usb0` → `usb0`) | A new network interface. The Mac gets `10.55.0.10`–`29` by DHCP; the frame is `10.55.0.1` | Built into macOS |

Sources and limits for the macOS side — **none of this was tested on this Mac**:
- NCM in a composite device works on macOS, and **ECM inside a composite device stopped working in
  macOS Catalina** (it works when ECM is the only function): NVIDIA Jetson forum, 2019, one thread
  [DOCUMENTED]. This is why the default is NCM and not ECM, and why the image does not use `g_cdc`
  (ECM + ACM = the combination that the thread reports as broken).
- Raspberry Pi's gadget package uses CDC-ECM for macOS hosts (as a single function) [DOCUMENTED].
- RNDIS has no built-in macOS driver (HoRNDIS project page) [DOCUMENTED]; not used.
- The device name `/dev/cu.usbmodem…` for CDC ACM on macOS is from general knowledge [UNCONFIRMED].
- macOS can ask "Allow accessory to connect?" for a new USB device [UNCONFIRMED for this Mac and hub].

Settings: `/pf/gadget.conf` on the FAT partition (edit on the Mac): `SERIAL=0|1`, `NET=ncm|ecm|none`,
`MAXPOWER`. If macOS does not bind the composite device, try `NET=none` (serial only), then
`SERIAL=0` + `NET=ecm` (ECM as the only function).
`MAXPOWER=2` mA in the descriptor: the value of the U-Boot gadget that this Mac setup accepted (E018).

The stock kernel provides: `USB_MUSB_SUNXI=y`, `USB_GADGET=y`, `USB_CONFIGFS=m` with ACM, NCM, ECM,
RNDIS, mass storage; legacy `g_cdc`, `g_ether`, `g_ncm`, `g_serial` also exist [VERIFIED: config and
file list of the package].

Network: `systemd-networkd`, match by interface **type** `gadget` (not by name). Static address,
DHCP server with **no router and no DNS** in the lease, so the Mac keeps its own internet. mDNS is on
(`pf1007l.local`). [Ran in QEMU with the loopback controller: the host side got `10.55.0.x`, no default
route.]

### 4.5 The login console on `ttyGS0`, and a trap found in the test

- udev starts `serial-getty@ttyGS0` when the port exists. The drop-in logs in the user `frame`
  automatically (there are no passwords; the USB cable gives no more access than the SD card).
- **Trap** [VERIFIED in QEMU, read in `u_serial.c:825–834`]: a gadget serial port with no USB host
  accepts no data (write room 0). The stock `serial-getty@.service` has `TTYReset=yes`: systemd writes
  a reset sequence to the port **before** it starts agetty and **holds its lock on `/dev/console`**
  during that write. With no host the write never returns, and other units that need the lock wait for
  ever (seen: `systemd-vconsole-setup`, more than 20 minutes). The drop-in sets `TTYReset=no`,
  `TTYVHangup=no`. Then only agetty waits for the host. [Ran in QEMU: no stuck job with no host; login
  works when a host connects.]
- **Kernel messages on the USB serial port are off by default.** `u_serial` registers a console for
  `ttyGS0` by itself (`gserial_alloc_line()`, `u_serial.c:1330–1338`); the kernel uses it when
  `console=ttyGS0` is on the command line. In the first test image it was on: the result was the trap
  above (systemd also starts a getty on each kernel console). The drop-in now makes that safe, but the
  kernel-console path of the gadget is one more unknown on a blind boot, and the Mac must have the port
  open to see anything. `dmesg` after the login gives the same text. To turn it on: add
  `console=ttyGS0,115200` before `console=tty0` in `extlinux.conf` [UNCONFIRMED on the frame].
- `pf-gadget down` stops the getty first. Without that, removing the serial function waits for ever
  while a program has the port open [VERIFIED in QEMU].

### 4.6 Boot-stage markers and logs on the FAT partition

All in `/pf/` on the card (`/boot/pf/` on the frame). The file `/pf/README.TXT` on the card explains them.

| File | Writer | Content |
|---|---|---|
| `uboot.env` | U-Boot, each start | `pf_boots` (hex counter), `pf_last` = `linux` / `ums` / `loadfail`, `pf_prev_ok` |
| `linux-ok.env` | Linux (`pf-usbwatch`) | `pf_ok=<counter>` when the Mac configured the gadget |
| `stages.log` | initramfs + services | One line for each stage of each start, with seconds since kernel start |
| `stage/NN-name` | the same | One empty file for each stage of the last start |
| `last/dmesg.txt`, `journal.txt`, `status.txt` | `pf-collect` | Kernel log, journal of this start, status report. Written when the file systems are mounted, at multi-user, at 20 s, 60 s, 180 s, each 15 minutes, and at shutdown |
| `prev/` | | The same for the start before |

Stages: `20-initramfs-start`, `30-gadget-up` / `30-gadget-FAILED`, `35-root-mounted`,
`39-initramfs-RESCUE`, `40-systemd-gadget-unit`, `50-local-fs-mounted`, `60-multi-user`,
`70-usb-<state>`, `71-usb-confirmed`, `80…89-firstboot-*`, `90-logs-saved`.

So a start with a dead USB link still leaves the kernel log on the card. [Ran in QEMU: all markers
and the three log files; `prev/` after the second start; the shutdown copy.]
The logs can hold MAC addresses and the card's serial number. Do not publish them as they are.

### 4.7 First boot (`pf-firstboot`, one time, in the background)

It does not block the gadget, the console or sshd.

1. **Clock first.** The frame has no clock battery. systemd moves the clock to the image build time
   (`/usr/lib/clock-epoch`) when the RTC is behind it; the script checks that. To set the real time
   from the Mac: `image/tools/frame-set-clock.sh`.
2. Grows the root partition and file system. It refuses a disk that is not of type `SD`.
3. **pacman keyring**: `pacman-key --init` and `--populate archlinuxarm` run on the frame, offline.
   The image holds no pacman private key (the build-time keyring is deleted). A failed try starts
   again from nothing, up to 3 times. Found in the test: gpg stops with "key was created N seconds in
   the future" when the clock moves back during the work (a time server corrected the emulator's
   clock). The retry solves that.
[Ran in QEMU: all three steps; the ALARM build key is trusted after it.]

### 4.8 Users, keys, passwords

- User `frame` (groups `wheel`, `video`, `input`, `audio`, `uucp`), `sudo` with no password.
- **No password exists.** `root` and `frame` have no password hash (`!` in `/etc/shadow`): the
  tarball's default hashes are removed, not only locked. The default user `alarm` is removed.
  sshd: keys only, no root login, `AllowUsers frame`.
- `build.sh` makes two key pairs in `image/secrets/` (git-ignored): the user key
  (`frame_id_ed25519`) and the frame's SSH host key. The host key is in the image, so the first
  start needs no key generation, and the Mac can check the frame's identity:
  `ssh -F image/secrets/ssh_config frame`.
- The image file itself is private: it holds the host key and vendor firmware.

### 4.9 Kernel, modules, firmware

| Item | In the image | Note |
|---|---|---|
| Kernel | `linux-armv7 7.2.10-1`, the stock package (SHA-256 `b49a4d4d…6ebca`, signature checked by pacman) | `IgnorePkg = linux-armv7 linux-armv7-headers`: an update cannot break the out-of-tree modules |
| Panel module | `kernel/out/panel-jadard-jd9365da-h3.ko` → `updates/`, `depmod` | Loads by alias with the `full` label only |
| Wi-Fi modules | `wifi/out/aic8800_{bsp,fdrv,btlpm}.ko` → `updates/` | **Not loaded automatically** (`/etc/modprobe.d/pf1007l-wifi.conf`) |
| Wi-Fi firmware | `/usr/lib/firmware/aic8800_fw/SDIO/aic8800DC/` (Radxa set, revision U02 only) | Layout of `wifi/README.md` §6 |
| Touch firmware | `/usr/lib/firmware/silead/gsl_m86_hd.fw` (+ a link with the old draft name) | From `dumps/touch/` |
| `linux-firmware` | The packages are installed, **their files are not** (`NoExtract`) | 969 MB that this board does not use. For a USB Wi-Fi dongle later: remove the `NoExtract` line and install the package again |
| Memory | `zram-generator`: `ram / 2`, `lzo-rle` (the only zram backend of this kernel); `earlyoom`; `vm.swappiness=100` | [Ran in QEMU: 491 MiB zram swap] |
| Network tools | `iwd` (installed, not enabled), `iw`, `wireless-regdb` | |

**Wi-Fi manual step** (the chip type and revision of this unit are not read yet):
`/usr/share/doc/pf1007l/WIFI.md` on the frame. Short: boot the `full-stage1` or `full` label, run
`pf-wifi-check` (read-only; gate: `SDIO_ID=C8A1:C08D`), then `pf-wifi-check --load`.

---

## 5. Where this design differs from the kernel work's drafts (`kernel/bootcard/`, `kernel/README.md` §12)

Reused as they are: the DTB and the panel module of `kernel/out/`; the stage-1 module blacklist
(label `full-stage1`); `ignore_loglevel log_buf_len=1M`; `psi=1`; the two `softdep` lines
(`/etc/modprobe.d/pf1007l-display.conf`); the address plan `10.55.0.1/24` and the two MAC addresses;
"log to the FAT partition at 0/20/60/180 s"; holding the kernel package.

| Topic | Draft | This image | Reason |
|---|---|---|---|
| Gadget | `g_cdc` (ECM + ACM) from `modules-load.d` | configfs, **NCM** + ACM, from the initramfs | The one report found says macOS's ECM driver fails inside a composite device, NCM works [DOCUMENTED]. The initramfs brings the link up sooner and keeps it when the root file system fails. ECM is one line in `gadget.conf` |
| `console=ttyGS0` | On | Off by default | Section 4.5: it made systemd start a getty that blocked on the port, in the test. Now safe, but not necessary for the first boot |
| First boot | Full DTB + module blacklist | Two steps before that: `min` and `pmic` | A blacklist stops modules. Built-in drivers still run with the full DTB: PMIC, all regulators, the Wi-Fi power sequence, `pwm-backlight`. `min` keeps them out of the first boot |
| Governor | `schedutil` in both stages | `schedutil` only for the `full` labels | `min`/`pmic`: no CPU clock change in the first boots (one unknown less) |
| Root | `root=/dev/mmcblk0p2 rw` | `PARTUUID=…`, `ro`, fsck by systemd | No dependence on device numbering; power cuts are normal here |
| Log copies | Numbered files for each start | `last/` + `prev/`, plus stage markers and the U-Boot state file | The card stays small and the decision table needs only the last two starts |
| `modules-load.d` list (display order) | Installed | Not installed | With `full`, udev loads by alias; the draft says the blacklist's effect on this list is not tested. The list is in `kernel/bootcard/` for a later step |
| Network match | `Name=usb0` | `Type=gadget` + a `.link` file | Works for any interface name |
| Login | `ssh alarm@…` (stock passwords) | User `frame`, keys only | Task rule: no default passwords |

---

## 6. Build

```sh
image/build.sh            # all steps, 6 to 12 minutes; needs Docker (OrbStack) with linux/arm/v7 emulation
image/build.sh test       # QEMU test, about 25 minutes (needs qemu-system-arm from Homebrew)
image/build.sh clean      # removes the build container and the imported base image (about 2.4 GB in Docker)
```

Steps: `uboot` (cross-build in the project's `pf1007l-uboot-build` image) → `dtbs` → `secrets` →
`rootfs` (the ALARM tarball becomes a Docker image; one armv7 container under QEMU does the upgrade,
packages, users, overlay and initramfs) → `assemble` (FAT, ext4 with `mkfs.ext4 -d`, MBR; native
arm64 tools image) → `sums`.

Pinned inputs (`build.sh` stops on a mismatch):

| Input | Pin |
|---|---|
| U-Boot | commit `e50b1e8715011def8aff1588081a2649a2c6cd47` (v2025.10) |
| Wes Bos's patch | SHA-256 `3aa2cbba09a096f9fd20b3f1a0d90c6d178ef7f311bf9f666e00d409a6d41351` (photo-frame-dashboard `9dd323e7`) |
| `ArchLinuxARM-armv7-latest.tar.gz` | SHA-256 `ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0` (file of 2026-08-05; MD5 equal to the mirror's `.md5`) |
| Kernel package | `linux-armv7-7.2.10-1`, SHA-256 `b49a4d4dd1a99c1f71eced0fa9fc28d8348d8749a5db6696c56dcd77ade6ebca` |
| Wi-Fi modules | `wifi/out/SHA256SUMS` is checked |
| Test-only `dummy_hcd.c` | Linux v7.2.10, SHA-256 `7dd400f2…239e57` |

**Not reproducible bit for bit**: the root file system gets a full `pacman -Syu` from the live
mirrors, because a partial upgrade of the August tarball is not supported by Arch. `out/packages.txt`
records the 184 package versions of each build. U-Boot has a fixed build time and is reproducible (two builds, same SHA-256). The FAT and ext4 file
times change with each build.

Inputs from other parts of the project (read only): `kernel/dts/`, `kernel/out/` (if present),
`refs/kernel/linux-7.2.10` or `refs/linux-snippets` (include files), `wifi/out/`,
`refs/aic/radxa-pkg_aic8800` (firmware), `dumps/touch/gsl_m86_hd.fw`,
`refs/photo-frame-dashboard/diagnostics/u-boot` (read with `git archive`; if it is absent, `build.sh`
fetches the commit into `image/cache/`).

One line in the build log looks like an error and is not one: `error: command failed to execute
correctly` after "Loading new kernel modules" (a pacman hook that needs a running systemd).

### Files

| Path | Content |
|---|---|
| `build.sh` | The one command |
| `uboot/0001-…patch`, `0002-…patch` | U-Boot patches (0002 is generated: `uboot/src/apply-edits.py`) |
| `uboot/src/` | Build L device tree, the two defconfigs, the edit script |
| `uboot/boot.cmd` | Boot script source |
| `dts/` | `min`, `pmic`, `full` device trees, build and check scripts |
| `boot/` | Templates for the FAT partition: `extlinux.conf`, `uEnv.txt`, `pf/` |
| `initramfs/init` | The initramfs script |
| `rootfs/` | Overlay: scripts in `usr/lib/pf1007l/`, units, network, udev, sshd, docs |
| `rootfs-build/inside.sh` | What runs in the armv7 container |
| `tools/assemble-in-container.sh` | Makes the card image |
| `tools/write-card.py`, `watch-frame.sh`, `read-card.sh`, `frame-set-clock.sh` | For the owner, on the Mac |
| `tools/qemu-test.sh`, `tools/dummy-hcd/build.sh` | The test |
| `test/` | Test logs and results |
| `secrets/`, `cache/`, `work/`, `out/` | git-ignored (`.gitignore`) |

---

## 7. The test without the frame

`image/tools/qemu-test.sh`. It boots a **copy** of the image in `qemu-system-arm -M orangepi-pc`
(Allwinner H3, 4× Cortex-A7, 1 GiB). Two things differ in the copy: the U-Boot at 8 KiB is the test
build for the Orange Pi PC (same source, same boot command), and the boot menu has one more label
with the Orange Pi PC device tree and a serial console. The kernel, the initramfs, the root file
system, `boot.scr` and all scripts are the files of the real image.

### What it covers

| Area | How |
|---|---|
| Card layout | The emulated boot ROM loads the SPL from 8 KiB; U-Boot reads the FAT partition; the kernel finds the root by PARTUUID |
| Boot script | 3 starts: Linux → (confirmed) Linux → (not confirmed) USB disk mode; the state file after each |
| U-Boot console input | CTRL+C and text on the console for 20 s: no effect |
| Stock kernel + our initramfs | Module load order, FAT mount, markers, gadget, `switch_root` |
| Root file system | systemd reaches `running` with 0 failed units; SSH with the key and the pinned host key; `sudo`; locked passwords |
| First boot | Root growth 2.7 → 3.7 GiB, pacman keyring, clock rule; it does not run a second time |
| Memory | zram swap with `lzo-rle`, earlyoom |
| Gadget with no host | Bound to QEMU's inert MUSB model: no stuck job, `usb0` has its address, the start is not confirmed |
| Gadget with a host | `dummy_hcd` (the kernel's loopback USB controller, built here as a test-only module, not in the image): the same kernel, as USB host, enumerates `1d6b:0104` "PF1007L Linux", binds `cdc_acm` and `cdc_ncm`; a command typed into `ttyACM0` runs in the frame's shell on `ttyGS0`; the host side gets `10.55.0.x` by DHCP with no default route; the confirmation file is written |
| Markers and logs | Read from the FAT partition of the copy after the run, as a Mac reads the card |

### What it cannot cover

- **The A33**: the SPL of build L (DRAM setup, AXP223 voltages), U-Boot build L itself, the three
  frame device trees, the A33 clock and pin drivers.
- **The MUSB controller and the USB PHY** of the frame: QEMU's Orange Pi PC only shows a controller
  that never connects.
- **macOS**: which drivers it binds, the device names, the DHCP client, a possible accessory prompt.
- **U-Boot `ums`** on real USB (it has no host in QEMU), and `fatwrite` on a real card.
- The DSI panel, the PMIC, touch, Wi-Fi, the eMMC guard (no eMMC in the emulator).
- Timing. The emulator is 10 to 30 times slower than the frame; the Mac was also under load.
- The initramfs rescue shell (`39-initramfs-RESCUE`) and `panic=20`: not run.

### Result

Final run, 2026-10-12, on the image of section 9 (SHA-256 `a9bea449…cefe82`). The Mac was under
heavy load from other work (load average 20 to 30), so the emulated system needed about 9 minutes
for each start.

**52 checks: 52 passed, 0 failed** (`test/results.txt`).

| Part | Checks | Result |
|---|---|---|
| Start 1: U-Boot, boot script, console input = null device, state file, initramfs, markers | 7 | pass |
| Start 1: system (user, no password hash, sshd keys only, kernel release, not a systemd "first boot") | 5 | pass |
| Start 1: first boot (root growth to 3.7 GiB, pacman keyring, flag removed) | 3 | pass |
| Start 1: zram, earlyoom, file capabilities, Wi-Fi modules not loaded, firmware files, panel module, `/boot`, SD card not read-only, one MMC device, markers 20–60, logs on FAT, no stuck job | 12 | pass |
| Gadget with no host | 5 | pass |
| Gadget with the loopback host (enumeration, ACM login and command, NCM + DHCP, no default route, confirmation file, markers) | 9 | pass |
| Start 2: Linux again after a confirmed start; first-boot work not repeated; `prev/` logs; shutdown log copy | 5 | pass |
| Start 3: USB disk mode after a start that was not confirmed; no kernel start; CTRL+C on the console has no effect; still running after 30 s | 4 | pass |
| The FAT partition read from outside | 2 | pass |

Evidence in `image/test/`: `results.txt` (each check), `boot1.serial.log`, `boot2.serial.log`,
`boot3.serial.log` (console of each start), `gadget-loopback.dmesg.txt`, `gadget-loopback.acm.txt`,
`boot1.pf-status.txt`, `boot1.systemd.txt` (`state: running`, no failed unit), `fat-uboot.env.txt`,
`fat-stages.log.txt`, `fat-pf-listing.txt`.

One observation from the ACM capture, for the Mac side: when the host opens the serial port in
"cooked" mode with echo, it sends the frame's own text back to the frame, and the shell sees garbage
for a moment. `screen` opens the port raw, so this should not happen with the procedure in section 8.

Earlier runs, kept as evidence of what the test found:
- `test/run1-first-image/boot1.serial.log`: the first image. Found: systemd "first boot" presets
  (`/etc/machine-id` with the text `uninitialized`), the getty / console-lock trap, the pacman
  keyring clock problem, the `/boot` mount timeout under a slow start, `pf-gadget down` waiting for
  ever. All five are corrected and tested again.
- `test/run2-image-13039513/`: the second image. 51 of 52 passed. The one failure was a fault of the
  check (its text filter did not remove terminal control sequences); the filter is corrected. In
  that run the pacman keyring needed its second try (the emulator's clock moved back during the
  first), so the retry logic has run one time. After that run the image changed in one point: the
  default password hashes of the tarball are removed, not only locked.
- One more run was lost: I changed the test script while it ran, and the shell stopped with a
  syntax error. Lesson: do not edit a running shell script.
- Found by the builds, not by the test: a file or folder that the Mac replaces right after a
  container wrote it can look empty or damaged to the next container. `build.sh` now uses new folder
  names for each build, makes such copies inside the container, and compares the files in the image
  with the built files from the Mac side ("image self-check").

---

## 8. Procedure for the owner (macOS)

Do this **after the eMMC backup is complete and verified** (safety rule 2). No step writes the eMMC.

### Before you start

- Use a **second MicroSD card**. **Not the FEL stub card**: you need the stub card to get back to FEL.
- Card: 4 GB or more (the project's cards have 15,939,928,064 bytes). All data on it is lost.
- Cable and port: the same USB-A → USB-C data cable and the same hub port that work for the backup.

### Write the card

1. Put the second card in the Mac's reader.
2. `diskutil list external physical` — find the card. Read its exact size:
   `diskutil info diskN | grep "Disk Size"` (the number in bytes).
3. Check, with no write: `python3 -I image/tools/write-card.py check diskN <exact-bytes>`
4. Write: `sudo python3 -I image/tools/write-card.py write diskN <exact-bytes>` (about 5 minutes).
   The script stops if: the size is not exactly what you gave; the disk is internal or not removable;
   the size is the eMMC's (15,634,268,160 bytes); the disk is a U-Boot USB disk; **the card is the
   FEL stub card** (it knows the stub's hash); the image does not match its SHA-256. After the write
   it reads the card back and compares the SHA-256, then ejects the card.

### First boot

5. Unplug the frame (no power). Take out the stub card. Put in the new card.
6. In a terminal on the Mac: `image/tools/watch-frame.sh` (it only reads; it runs 3 minutes).
7. Plug the frame into the Mac. Note the time.

**What to expect** — all times are estimates [UNCONFIRMED], the screen stays **dark** the whole time:

| Time after power | On the Mac |
|---|---|
| 0–8 s | Nothing. (Boot ROM, SPL, U-Boot, kernel load. U-Boot shows nothing on USB when it starts Linux) |
| 8–15 s | A new USB device "PF1007L Linux". `watch-frame.sh` prints a serial port `/dev/cu.usbmodem…` and a network interface. If macOS asks to allow the accessory: allow |
| 15–40 s | The network interface gets `10.55.0.x`. `ping 10.55.0.1` answers. The serial port gives a shell |
| 30–60 s | `ssh -F image/secrets/ssh_config frame` works |
| 1–4 min | First boot only: the frame grows its file system and makes the pacman keyring (in the background) |

8. Log in:
   - Serial: `screen $(ls /dev/cu.usbmodem* | head -n 1) 115200` (press Enter; leave with `Ctrl-A` `K`).
   - Network: `ssh -F image/secrets/ssh_config frame`
9. On the frame: `pf-status`. Then `image/tools/frame-set-clock.sh` on the Mac.
10. To turn the frame off: `sudo poweroff`, wait 10 s, unplug.

### Decision table

Wait **120 s** before you call it "nothing".

| What the Mac shows | Meaning | Do this |
|---|---|---|
| Serial port **and** network, login works | Linux is up, the USB link works | Step 9. Then the ladder: `pf-bootsel pmic`, `sudo reboot`; later `full-stage1`, `full` |
| Serial port works, no network address | NCM is not bound or DHCP failed | Use the serial console: `pf-status`, `networkctl`. Try `NET=ecm` in `/boot/pf/gadget.conf`, `sudo reboot` |
| Network works, no serial port | ACM is not bound | Use `ssh`. Record `system_profiler SPUSBDataType` |
| USB device "PF1007L Linux" is in System Information, but no port and no interface | The kernel and the gadget work; macOS binds no driver | Set `NET=none` (serial only) in `gadget.conf` on the card; next try `SERIAL=0` + `NET=ecm` |
| A read-only disk **PFBOOT** appears ("USB download gadget") | U-Boot runs and is in **USB disk mode**: the last Linux start was not confirmed, or the kernel files did not load | `image/tools/read-card.sh` (reads the markers over USB). Unplug and plug again = one more Linux try |
| **Nothing** after 120 s | Linux did not come up on USB | Unplug. Plug in again and wait 20 s: you should get the PFBOOT disk (row above). That proves U-Boot runs |
| Nothing after the second plug-in also | U-Boot did not run its script | Pull the card, read it in the Mac's reader: `image/tools/read-card.sh`. Then the table below |
| The screen shows Android | The boot ROM did not take the card | Card not seated, or the write failed. Write it again |
| The Mac shows the FEL device (`1f3a:efe8`) | The stub card is in the slot | Wrong card |

**Reading the markers** (`/Volumes/PFBOOT/pf/`, card in the reader or USB disk mode):

| State on the card | Meaning |
|---|---|
| `uboot.env` still says `pf_boots=0` | U-Boot never ran its script. With a dark screen and no Android: the SPL or U-Boot hangs (DRAM or PMIC setup when started from the card). **Plan B:** enter FEL with the stub card, change to the new card while the frame stays powered, then `sunxi-fel uboot image/out/u-boot-pf1007l-L.bin`. FEL starts the SPL that way on this unit already (build E). [UNCONFIRMED: the card change in FEL mode] |
| `pf_last=loadfail` | U-Boot could not load the kernel, device tree or initramfs from the FAT partition. Check the files; write the card again |
| `pf_last=linux`, and `stages.log` has no `20-initramfs-start` line for that start number | The kernel did not reach our initramfs: wrong device tree, a hang before user space, or the SD card does not work in Linux. Try the label `min-noinitrd` (edit `DEFAULT` in `extlinux/extlinux.conf`) |
| `20-…` then `30-gadget-FAILED` | The kernel has no USB device controller: MUSB or its PHY did not probe. `last/dmesg.txt` has the reason |
| `30-gadget-up`, no `70-usb-configured` | The gadget is configured on the frame, the Mac never talked to it: cable, hub, PHY/VBUS, or macOS. Read `70-usb-…` lines and `last/dmesg.txt` |
| `39-initramfs-RESCUE …` | The root file system did not mount; the line gives the reason |
| `35-root-mounted`, no `40-…` | systemd did not start |
| `40-…`, no `60-multi-user` | A service hangs: `last/journal.txt` |
| `71-usb-confirmed` | Linux and USB worked in that start |

Send the folder `pf/` to the next work session when something fails. It holds MAC addresses: keep it private.

---

## 9. Numbers

| Item | Value |
|---|---|
| Image | `image/out/pf1007l-sd.img`, 3,221,225,472 bytes, 919 MB on disk (sparse) |
| Image SHA-256 | `a9bea449d53c10159fb6fbdf18e9f60bd6afb2d0f838decc45756c5000cefe82` |
| U-Boot build L | `image/out/u-boot-pf1007l-L.bin`, 536,544 bytes, SHA-256 `d12cb37382c41ce6fd7af7ac53a69a26ecc3ff9ed8265b09b876562bf984971d` (two builds gave the same hash) |
| SPL code end | `0x450a` (limit `0x5e00`) |
| `boot.scr` | SHA-256 `3c46db7a6b45a1db9d7717649dcbfe6ae5542343fa68dbdb18dfb11887b2417e` |
| Patch 0002 | SHA-256 `8ed3bff59b848cc872ba15d775e4ea8fe4fac7ac1ac43b18cbc88aae8bc052d3` |
| Device trees | `min` `5e237a1e…`, `pmic` `359f3598…`, `full` `db886662…` (= `kernel/out/sun8i-a33-pf1007l.dtb`) |
| Root file system | 850 MiB, 184 packages: `linux-armv7 7.2.10-1`, `systemd 262-1`, `openssh 10.6p1-1`, `iwd 3.12-2`, `zram-generator 1.2.1-1`, `earlyoom 1.9.0-1` (full list: `out/packages.txt`) |
| Initramfs | 0.9 MB, 9 modules (`out/initramfs-modules.txt`) |
| FAT partition | 64 MB used of 256 MiB |
| Full manifest | `image/out/MANIFEST.txt` |
| Disk use after `build.sh clean` | `image/cache` 771 MB (the tarball and the kernel package), `image/out` 920 MB, Docker: one small layer (`pf1007l-image-tools`) on the project's U-Boot build image |
| Disk use during a build | about 2.4 GB more in Docker (the imported tarball image and the build container) |

The image hash changes with each build (package versions, file times). The value above is the image
that the final test of section 7 used. `image/out/pf1007l-sd.img.sha256` holds it; `write-card.py`
checks it before a write.

---

## 10. Not proven until it runs on the frame

| # | Open point | First sign if it is wrong |
|---|---|---|
| 1 | **The SPL of build L started by the boot ROM from the SD card.** All starts on this unit were over FEL. Wes Bos reports SD boot on his unit [DOCUMENTED] | Dark, `pf_boots=0`. Plan B in section 8 |
| 2 | UART0 with no pins: U-Boot runs normally | The same |
| 3 | `fatwrite` to a real card from U-Boot on this board | `uboot.env` does not change; Linux can still start |
| 4 | The `min` device tree: no PMIC node, regulators as U-Boot left them, SD slot with `broken-cd` | No `20-initramfs-start` |
| 5 | The A33 MUSB controller in peripheral mode with the VBUS fallback, under Linux 7.2.10 | `30-gadget-FAILED`, or `30-gadget-up` with no `70-usb-configured` |
| 6 | **macOS binds ACM + NCM of this composite device.** Sources are second-hand; one of them is from 2019 | Section 8, decision table |
| 7 | The USB descriptor says 2 mA. A host that limits current by the descriptor could be a problem | The device shows and then drops |
| 8 | Timings in section 8 | — |
| 9 | Power: the frame under Linux load on the hub port (E019–E022: power is a known suspect) | Random restarts; `pf_boots` grows by itself |
| 10 | The udev rule that makes an eMMC read-only | Only relevant with a device tree that enables the eMMC |
| 11 | The `pmic`, `full-stage1` and `full` steps: everything in `kernel/README.md` §4 and §13 | The ladder shows which step breaks the USB link |
| 12 | Wi-Fi: chip type, revision, driver with the chip | `pf-wifi-check` |
| 13 | The initramfs rescue shell and `panic=20` restart (need `sunxi_wdt` on the A33) | — |
| 14 | U-Boot `ums` for the SD card, and its new "no abort" option (the option's source is the patch that ran 30+ minutes on the frame, but this build did not run) | USB disk mode does not appear or drops |
| 15 | `write-card.py`: the write, the readback, the FEL stub test and the `diskutil` calls on real hardware | It stops with a message; it cannot write a disk that fails its checks |
| 16 | Internet through the Mac (Internet Sharing) | Documented on the frame, not tested |

Known limits by design:
- The console on USB logs in with no password. Remove the drop-in
  `/etc/systemd/system/serial-getty@ttyGS0.service.d/10-pf1007l-autologin.conf` before the frame
  leaves the desk.
- A power cut while U-Boot or Linux writes the FAT partition can damage it. `fsck.fat` runs at each
  start. The window in U-Boot is one small file.
- With no USB host, each second power-on is USB disk mode (`pf_mode=linux` in `/uEnv.txt` stops that).

---

## 11. Sources

Project files: `CLAUDE.md`, `PLAN.md`, `research/02`, `research/03`, `docs/experiments.md` (E014,
E018, E023, E024, E030–E033), `dumps/sys_config.fex`, `kernel/README.md` (§8–14),
`kernel/bootcard/`, `kernel/out/`, `wifi/README.md`, `scripts/uboot/wesbos-issue24-ums-diag.diff`.

Source code read:
- U-Boot v2025.10 (`refs/photo-frame-dashboard/diagnostics/u-boot`): `arch/arm/mach-sunxi/board.c`
  (81–195), `arch/arm/mach-sunxi/clock_sun6i.c` (87–118), `board/sunxi/board.c` (510–517),
  `drivers/serial/serial-uclass.c` (99–155), `common/autoboot.c` (425, 500),
  `drivers/usb/gadget/f_mass_storage.c` (650–690, 1313–1330), `cmd/usb_mass_storage.c` (175–250),
  `include/configs/sunxi-common.h`, `arch/arm/dts/sun8i-q8-common.dtsi`.
- Linux v7.2.10 (`refs/kernel/linux-7.2.10`): `drivers/phy/allwinner/phy-sun4i-usb.c` (400–440,
  742–768), `drivers/usb/gadget/function/u_serial.c` (825–834, 1077–1110, 1330–1338),
  `arch/arm/boot/dts/allwinner/sun8i-a23-a33.dtsi`, `sun8i-a33.dtsi`.
- Stock kernel config: `refs/alarm-pkgbuilds/core/linux-armv7/config`.

Web (second-hand, read on 2026-10-12):
- [NVIDIA forum: SSH into Jetson Nano through macOS Catalina](https://forums.developer.nvidia.com/t/ssh-into-jetson-nano-through-mac-os-catalina/83405) — ECM in a composite device fails on Catalina, NCM in a composite device works.
- [Raspberry Pi: USB gadget mode in Raspberry Pi OS](https://www.raspberrypi.com/news/usb-gadget-mode-in-raspberry-pi-os-ssh-over-usb/) — CDC-ECM for macOS and Linux hosts; Internet Sharing steps.
- [HoRNDIS](https://joshuawise.com/horndis) — macOS has no RNDIS driver of its own.
- [Apple developer forum: USB CDC ECM or NCM device requirements](https://developer.apple.com/forums/thread/769793) — an ECM device needs the NetworkConnection notification (search summary only; the page was not read in full).
- [Linux: USB gadget configured through configfs](https://docs.kernel.org/usb/gadget_configfs.html)
