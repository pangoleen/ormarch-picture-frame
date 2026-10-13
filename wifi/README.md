# AIC8800 SDIO Wi-Fi driver for 32-bit ARM (`linux-armv7` 7.2.10)

Date: 2026-10-12. Board: PF1007L (Allwinner A33). Nothing in this report ran on the frame.

## 1. Result

**The driver builds for 32-bit ARM. No project patch was necessary.**

| Question | Answer | Tag |
|---|---|---|
| Does it build for `ARCH=arm` against `linux-armv7` 7.2.10-1? | Yes. 0 errors. 3 modules. | [VERIFIED: built here] |
| Which source? | `radxa-pkg/aic8800`, commit `e9e43ed7`, with the Radxa Debian patch series | [VERIFIED] |
| How many project patches? | 0. `wifi/patches/` is empty on purpose. | [VERIFIED] |
| Were there 32-bit problems? | No. No 64-bit division, no pointer-cast warning, no format warning. | [VERIFIED: build log] |
| Do the modules load? | Yes, on the real `linux-armv7` 7.2.10-1 kernel in QEMU (emulated Cortex-A7, sun8i board). | [VERIFIED: emulator, not the frame] |
| Does Wi-Fi work on the frame? | Not known. The driver has never run with the chip. | [UNCONFIRMED] |

One more result, not in the task but important for the device tree:
the vendor kernel of this unit drives **two** enable pins for the AIC chip (PL2, then PL6 after 5 ms)
and one PMIC pin (AXP GPIO0). See section 8.

Tags: **[VERIFIED]** = built, run or read in the source here. **[DOCUMENTED]** = from a second-hand source.
**[UNCONFIRMED]** = inference or guess.

## 2. Survey of the driver sources

All these trees come from the same AICSemi vendor code. Clones are in `refs/aic/` (git-ignored).

| Source | Last commit | Newest kernel in the code | Bus | SDIO for DC/DW | Licence | DC firmware in the tree | Verdict |
|---|---|---|---|---|---|---|---|
| **`radxa-pkg/aic8800`** `e9e43ed7` | 2026-10-12 | Vendor SDK V5.0 (2026-01-23) has guards to 6.12. The Debian series adds 6.13 to 7.3. | SDIO, USB, PCIe | Yes (`aic8800_bsp/aic8800dc_compat.c`) | `src/` GPL-2, packaging GPL-3+ (`debian/copyright`) | `src/SDIO/driver_fw/fw/aic8800DC/`, 23 files, U02 only | **Chosen** |
| Armbian (`armbian/build`) | 2026-10-12 | Skips kernels >= 7.3 | SDIO, USB, PCIe | Same as Radxa | GPL-2.0 | Installs the Radxa `.deb` packages | Not a different source. `extensions/radxa-aic8800.sh` downloads the Radxa DKMS package. |
| `nickyg666/orangepi-zero3w-aic8800` `6d78b24` | 2026-10-12 | 7.3-rc2 | SDIO | Yes (`aic_bsp_8800dc.c`) | No licence file | None | One-board port (arm64, A733). Different file layout. Backup files in the tree. Use only as a reference. |
| `shenmintao/aic8800d80` `43db800` | 2026-10-08 | 7.3 | **USB** (`CONFIG_SDIO_SUPPORT = n`) | No | GPL-2.0 | `fw/aic8800DC/` (USB set) | Not for SDIO |
| `goecho/aic8800_linux_drvier` `9dca972` | 2026-09-07 | 6.12 | **USB** (`CONFIG_SDIO_SUPPORT = n`) | No | MIT | D80 only | Not for SDIO |
| LibreELEC (`LibreELEC.tv`) | n/a | n/a | n/a | n/a | n/a | n/a | No `aic8800` hit. Scope: one GitHub code search. |
| `LYU4662`, `walnutpi`, `0x754C`, `shawnchain` | 2024 to 2026-04 | 6.3 to 6.7 | SDIO | Yes | none found | varies | Old vendor drops. Not cloned again. See `research/02`. [DOCUMENTED] |

Why Radxa: it is the only SDIO tree with DC support, a licence, firmware, and a patch for each kernel to 7.3.

Note about the Radxa series: 2 USB-only patches do not apply at this commit
(`fix-usb-firmware-path.patch`, `fix-Lower-the-debugging-log-level.patch`; the USB files have CRLF line ends).
They do not touch the SDIO driver. `build.sh` applies only the SDIO hunks: 17 of the 29 patches.

## 3. Build recipe (this is what worked)

Method: **native build in an armv7 container under QEMU user emulation** (not a cross-compile).

```sh
wifi/build.sh        # about 90 seconds on this Mac, 10 jobs
```

| Item | Value |
|---|---|
| Base source | `https://github.com/radxa-pkg/aic8800` commit `e9e43ed79c50483080e9bcdfb08caeeb869d7191` |
| Patches | Radxa `debian/patches/series`, SDIO hunks only (17 patches). Project patches: none. |
| Container image | `menci/archlinuxarm:base-devel-20261012.38214418911`, index digest `sha256:3ede3a01ca0e0dc89fb6a539be60d836ff0b2aed724832dc5cefd00d22b5f04e`, `linux/arm/v7` manifest `sha256:849a94e97bb17403fe34cdcc4422a01bd6d443dbf2a4eadb0832a737a71ddee4` |
| Compiler | `gcc (GCC) 16.1.1 20260430` (the kernel was built with the same version) |
| Kernel headers | `linux-armv7-headers 7.2.10-1`, SHA-256 `c8a042ff54f94acf44db1bfa1a61083e2403008b81a349b71705728c2f9f6b04` |
| Kernel release | `7.2.10-1-armv7-ARCH` |
| Build command | `make -j10 -C /usr/lib/modules/7.2.10-1-armv7-ARCH/build M=$PWD modules` in `src/SDIO/driver_fw/driver/aic8800` |
| Driver config | Vendor defaults: `CONFIG_PLATFORM_UBUNTU=y`, `CONFIG_OOB=n`, `CONFIG_GPIO_WAKEUP=n`, `CONFIG_USE_FW_REQUEST=n` |

Three things to know:

1. `pacman` needs `--disable-sandbox` in this container. Its Landlock sandbox does not work under QEMU.
2. Give `-j` to the outer `make`. The `-j` line in the vendor Makefile has no effect, and one job is very slow.
3. `git apply` must run in its own git directory. Inside the project repository it skips the files and reports no error.

The build is reproducible: two clean runs gave the same SHA-256 for the three modules.

**If the project uses its own kernel:** these modules are only for `7.2.10-1-armv7-ARCH`.
The kernel has `CONFIG_MODVERSIONS=y`. Build the modules again against the tree of the new kernel. [UNCONFIRMED: not tested here]

## 4. Compile errors and causes

### 4.1 Build with the Radxa series: no errors

110 warnings, 0 errors (`logs/build.log`):

| Warning | Count | Cause | 32-bit problem? |
|---|---|---|---|
| `-Wmissing-prototypes` | 103 | Vendor style: global functions without a declaration | No |
| `-Wexpansion-to-defined` | 4 | `defined` in a macro (`aic8800d80*_compat.c`) | No |
| `-Wimplicit-fallthrough` | 1 | `rwnx_main.c:4627`, TDLS code | No |
| `-Wattribute-warning` (fortify) | 1 | `rwnx_rx.c:1440`: `memcpy` over a struct field in the monitor-mode radiotap code. The kernel has `CONFIG_FORTIFY_SOURCE=y`, so monitor mode can print a warning at run time. | No |
| "compiler differs" | 1 | Name only: `armv7l-unknown-linux-gnueabihf-gcc` and `gcc` are the same 16.1.1 | No |

I also searched the driver source for word-size conditions (`CONFIG_64BIT`, `BITS_PER_LONG`, `__aarch64__`)
and for direct comparisons of `jiffies`. There are none. Scope: `aic8800_bsp` and `aic8800_fdrv`, text search.

### 4.2 Control: the vendor tree without patches fails

This control shows that the headers are really 7.2 and that the test can fail.
Log: `logs/00-control-unpatched-vendor-tree.log`. Result: 51 errors, no module.
**Each error is kernel API drift. None is a 32-bit error.**

| Error | Cause | Radxa patch that corrects it |
|---|---|---|
| `linux/of_gpio.h: No such file` (`aic8800_btlpm/rfkill.c`) | Header removed from the kernel | `fix-linux-7.1-build` |
| `implicit declaration of function 'vfree'` | `linux/vmalloc.h` not included | `fix-vmalloc-not-include` |
| `'VFS_internal_I_am_really_a_filesystem...' undeclared` | `MODULE_IMPORT_NS()` needs a string since 6.13 | `fix-linux-6.13-build` |
| `implicit declaration of 'in_irq'` | Renamed to `in_hardirq()` | `fix-linux-6.19-build` |
| `implicit declaration of 'strncpy'` | `strncpy` removed from the kernel; use `strscpy` | `fix-linux-7.2-build` |
| `implicit declaration of 'del_timer_sync'`, `'del_timer'` | Renamed to `timer_delete_sync()`, `timer_delete()` | `fix-linux-6.15-build` |
| `implicit declaration of 'from_timer'`; `'reord_timer' undeclared` | Renamed to `timer_container_of()` | `fix-linux-6.16-build` |
| `wakeup_source_create/add/remove/destroy` not declared | No longer exported; use `wakeup_source_register()` | `fix-linux-6.16-build` |
| `too few arguments to 'cfg80211_rx_spurious_frame'`, `'cfg80211_rx_unexpected_4addr_frame'` | New `link_id` argument | `fix-linux-6.17-build` |
| `cfg80211_new_sta` / `cfg80211_del_sta`: incompatible pointer | Now take `struct wireless_dev *` | `fix-linux-7.1-build` |
| `cfg80211_ops` initialisers: incompatible pointer types (`add_key`, `get_key`, `del_key`, `set_default_mgmt_key`, `add_station`, `del_station`, `change_station`, `get_station`, `dump_station`) | The callbacks now take `struct wireless_dev *`, not `struct net_device *` | `fix-linux-7.1-build`, `fix-linux-7.3-build` |
| `.set_monitor_channel`: incompatible pointer | New `struct net_device *` argument | `fix-linux-6.13-build` |
| `.set_wiphy_params`, `.set_tx_power`, `.get_tx_power`: incompatible pointer | New `radio_idx` / `link_id` arguments | `fix-linux-6.14-build`, `fix-linux-6.17-build` |
| `.remain_on_channel`: incompatible pointer | New `rx_addr` argument in 7.2 | `fix-linux-7.2-build` |
| `rwnx_tdls.c`: `struct has no member named 'u'` | TDLS frame struct layout changed | `fix-linux-7.1-build` |
| `expression in static assertion is not an integer` | Follow-on error of `MODULE_IMPORT_NS` | `fix-linux-6.13-build` |

Nothing was stubbed. Nothing was disabled.

## 5. Checks on the modules

Files: `out/aic8800_bsp.ko`, `out/aic8800_fdrv.ko`, `out/aic8800_btlpm.ko` (Bluetooth sleep; not necessary, the fex has `bt_used = 0`).

```
438899739d39245dda40af97e9ca939b282db0963adf8bc47e7e2a4d0a9805fc  aic8800_bsp.ko
ec5d1b745020bf1ee463e5a54efce23a4d6f1eb28322a7ef7f3d770e0d207e26  aic8800_btlpm.ko
1d504c3bd8c22d2d48b2b27fe2f4e7cdabbf7e1b5de7197b1bdddfb42118588b  aic8800_fdrv.ko
```

### 5.1 `modinfo` (full text: `logs/modinfo.txt`)

```
=== aic8800_bsp.ko   ELF 32-bit LSB relocatable, ARM, EABI5
license:        GPL
version:        1.0
description:    AIC BSP
import_ns:      VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver
alias:          sdio:c07v*d*
depends:
vermagic:       7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8

=== aic8800_fdrv.ko  ELF 32-bit LSB relocatable, ARM, EABI5
license:        GPL
version:        6.4.3.0
description:    RivieraWaves 11nac driver for Linux cfg80211
alias:          sdio:c*vC8A1d2082*
alias:          sdio:c*vC8A1d9086*
alias:          sdio:c*vC8A1d9085*
alias:          sdio:c*vC8A1d9084*
alias:          sdio:c*vC8A1d9083*
alias:          sdio:c*vC8A1d9082*
alias:          sdio:c*vC8A1d9081*
alias:          sdio:c*vC8A1d0082*
alias:          sdio:c*vC8A1dC08D*
alias:          sdio:c*v5449d0145*
depends:        cfg80211,aic8800_bsp
vermagic:       7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8

=== aic8800_btlpm.ko ELF 32-bit LSB relocatable, ARM, EABI5
depends:        rfkill,aic8800_bsp
vermagic:       7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8
```

The `vermagic` is the same as that of `cfg80211.ko` in the real `linux-armv7-7.2.10-1` package
(package SHA-256 `b49a4d4d…6ebca`). [VERIFIED]

The `firmware:` lines in `modinfo` (`fmacfw.bin`, `rwnx_settings.ini`, …) are old text. The driver does not load those names.

### 5.2 SDIO IDs that the driver claims

| Module | Alias | Vendor:Device | Chip (name in the source) |
|---|---|---|---|
| `aic8800_fdrv` | `sdio:c*vC8A1dC08D*` | **`c8a1:c08d`** | **AIC8800DC** (the source uses the same ID for DW) |
| `aic8800_fdrv` | `sdio:c*v5449d0145*` | `5449:0145` | AIC8801 |
| `aic8800_fdrv` | `sdio:c*vC8A1d0082*` | `c8a1:0082` | AIC8800D80 |
| `aic8800_fdrv` | `sdio:c*vC8A1d9081*` … `9086*` | `c8a1:9081` to `c8a1:9086` | AIC8800D80N, D80LN, D80WN, D40N, D40LN, D40WN |
| `aic8800_fdrv` | `sdio:c*vC8A1d2082*` | `c8a1:2082` | AIC8800D80X2 |
| `aic8800_bsp` | `sdio:c07v*d*` | Class 0x07, each vendor and device | Each SDIO WLAN function. The code then examines the IDs. |

The ID of the chip in this frame has not been read. `c8a1:c08d` is the expected value. [UNCONFIRMED for this unit]

### 5.3 Symbols

| Module | Undefined symbols | Not exported by the kernel or `aic8800_bsp` | Symbol CRC entries | CRC mismatch |
|---|---|---|---|---|
| `aic8800_bsp` | 85 | 0 | 86 | 0 |
| `aic8800_fdrv` | 255 | 0 | 256 | 0 |
| `aic8800_btlpm` | 14 | 0 | 15 | 0 |

Method: `nm -u` and `modprobe --dump-modversions` compared with the kernel `Module.symvers`. `modpost` also gave no error.
The only compiler helpers are `__aeabi_idiv`, `__aeabi_uidiv`, `__aeabi_uidivmod`. The kernel exports them. There is no 64-bit division.

### 5.4 Load test in an emulator (more than the task asked)

I started the real `zImage` of `linux-armv7 7.2.10-1` in `qemu-system-arm -M orangepi-pc`
(Allwinner H3, Cortex-A7, the nearest emulated sun8i board) with a small initramfs. Log: `logs/qemu-loadtest-orangepi-pc.log`.

| Step | Result |
|---|---|
| `insmod rfkill`, `libarc4`, `cfg80211` | rc=0 |
| `insmod aic8800_bsp` | rc=0. Prints `aicbsp_init`, `RELEASE_DATE:2026_0123_5f7be68d` |
| `insmod aic8800_btlpm` | rc=0 |
| `insmod aic8800_fdrv` | **rc=1, `No such device`, after 2 s. This is correct**: there is no chip in the emulator. The module code ran (`aicbsp_platform_power_on`, then `set power on fail`). |
| `rmmod` | rc=0 |
| Oops, BUG or WARNING | None. Taint = 4096 (out-of-tree module) only. |

This proves: the relocations are good, the symbol versions agree, and the init and exit code runs on an ARMv7 7.2.10 kernel.
This does not prove: SDIO transfers, the firmware download, or radio operation.

To do it again: unpack `linux-armv7-7.2.10-1` (for `boot/zImage`, the H3 DTB, `rfkill.ko`, `libarc4.ko`, `cfg80211.ko`)
and the static `busybox` package of Arch Linux ARM. Make a `newc` cpio with an `/init` script that runs `insmod` in the order of the table. Then:

```sh
qemu-system-arm -M orangepi-pc -nographic -no-reboot -kernel zImage \
  -dtb sun8i-h3-orangepi-pc.dtb -initrd initramfs.cpio.gz \
  -append "console=ttyS0,115200 panic=-1 rdinit=/init"
```

## 6. Firmware files

The driver reads firmware with `filp_open()` from a fixed directory. It does not use `request_firmware()`.

- Directory: **`/lib/firmware/aic8800_fw/SDIO/aic8800DC/`** (Radxa path patches). Module parameter `aic_fw_path=` of `aic8800_bsp` sets a different directory.
- Source in the clone: `refs/aic/radxa-pkg_aic8800/src/SDIO/driver_fw/fw/aic8800DC/` (vendor blobs: keep them local).

The driver reads the chip revision from the chip and then selects the files [VERIFIED: read in `aic_bsp_main.c`, `aic_bsp_driver.c`; not run]:

| Chip | Wi-Fi patch | Patch table | Calibration | Bluetooth patches (the BSP loads them also) |
|---|---|---|---|---|
| **DC, U02** (`chip_sub_id` 1) | `fmacfw_patch_8800dc_u02.bin` | `fmacfw_patch_tbl_8800dc_u02.bin` | `fmacfw_calib_8800dc_u02.bin` | `fw_adid_8800dc_u02.bin`, `fw_patch_8800dc_u02.bin`, `fw_patch_table_8800dc_u02.bin`, `fw_patch_8800dc_u02_ext0.bin` |
| DC "H", U02 (`chip_sub_id` 2) | `fmacfw_patch_8800dc_h_u02.bin` | `fmacfw_patch_tbl_8800dc_h_u02.bin` | `fmacfw_calib_8800dc_h_u02.bin` | `fw_adid_8800dc_u02h.bin`, `fw_patch_8800dc_u02h.bin`, `fw_patch_table_8800dc_u02h.bin` |
| DC, U01 (`chip_sub_id` 0) | `fmacfw_patch_8800dc.bin` | `fmacfw_patch_tbl_8800dc.bin` | none | `fw_adid_8800dc.bin`, `fw_patch_8800dc.bin`, `fw_patch_table_8800dc.bin` — **Radxa does not ship these** |

All variants: `aic_userconfig_8800dc.txt` (TX power and crystal settings). RF test mode only: `lmacfw_rf_8800dc.bin`.
Simplest procedure: copy the full `aic8800DC/` directory (23 files, less than 0.5 MB).

SHA-256 (first 16 digits) of the U02 set in the clone:
`fmacfw_patch_8800dc_u02.bin 7df85a59e397fa6c`, `fmacfw_patch_tbl_8800dc_u02.bin 42465d1e755728a3`,
`fmacfw_calib_8800dc_u02.bin 1e485503e232c83d`, `aic_userconfig_8800dc.txt 536ca60c3494464e`.

When Android is rooted: copy `/system/vendor/etc/firmware/` and `/system/vendor/modules/aic*` from the frame, then compare the names and hashes.
The frame's `aic_userconfig_8800dc.txt` has the settings for this PCB. Use it in place of Radxa's file.

## 7. How the driver behaves (read in the source, important for the first test)

| Fact | Where | Effect |
|---|---|---|
| `aic8800_bsp` and `aic8800_fdrv` read **no** device-tree property | no `of_*` call in the two modules | Power, reset and the SDIO host come from the kernel and the DT only |
| No power control in this build mode | `aicsdio.c`, `CONFIG_PLATFORM_UBUNTU` | The SDIO card must be on the bus **before** `aic8800_fdrv` loads. If not, `insmod` fails with `No such device` after 2 s. |
| The driver sets the clock to 50 MHz itself | `aicsdio.c:1828`: `host->ios.clock = feature.sdio_clock` (50 MHz for DC), then `host->ops->set_ios()` | A lower `max-frequency` in the DT has no effect after the probe. `sunxi-mmc` permits 52 MHz (`sunxi-mmc.c:1424`). |
| In-band SDIO interrupt (DAT1) | `CONFIG_OOB=n`, `CONFIG_GPIO_WAKEUP=n` | The host-wake pin PL7 is not used |
| Suspend needs `MMC_PM_KEEP_POWER` | `aicbsp_sdio_suspend()` returns `-EINVAL` without it | Put `keep-power-in-suspend` in the DT, or system suspend fails |
| The chip has 2 SDIO functions; the driver probes function 2 and uses function 1 for data | `aicbsp_sdio_probe()` | Normal for DC/DW |
| MAC address: fixed prefix `88:00:33:77` + 2 random bytes at each load, if the chip has no MAC in efuse | `rwnx_main.c:6020-6038` | Set a fixed MAC in user space (`systemd-networkd` `.link`) |
| `udev` loads the modules automatically | aliases in 5.2 | `aic8800_fdrv` loads when `c8a1:c08d` appears |

## 8. Device tree

### 8.1 What the vendor kernel does on this unit (new evidence)

Source: disassembly of `rf_pm` and `wifi_pm` in this unit's 3.4.39 kernel, with this unit's fex.
File: `logs/vendor-wifi-power-disassembly.txt`. [VERIFIED in the binary. Not measured on the board.]

| When | Action | fex key |
|---|---|---|
| Kernel boot (`rf_pm_probe`, `module_num = 10`) | DLDO1 on at 3.3 V, DLDO2 on at 3.3 V | `module_power1`, `module_power2` |
| Kernel boot | **AXP223 GPIO0 = 1** | `power_switch = port:power0<1><0>` |
| Kernel boot | No 32 kHz clock for the module | `lpo_use_apclk = ""` |
| Wi-Fi on (`wifi_pm_power(1)`, AIC branch) | **PL2 = 1**, wait 5 ms, **PL6 = 1** | `chip_en = PL02`, `wl_reg_on = PL06` |
| Wi-Fi off | PL2 = 0, wait 5 ms, PL6 = 0 | |

Also on this unit [VERIFIED: ramdisk dump]: `init.sun8i.rc` loads `aic8800_bsp.ko`, and `libhardware_legacy.so` loads
`/system/vendor/modules/aic8800_fdrv.ko`. The two-module layout is the same as in the Radxa tree.

### 8.2 Fragment

`kernel/dts/sun8i-a33-pf1007l.dts` has the Wi-Fi nodes already. This fragment shows the three changes that the evidence supports
(marked `NEW`). I did not edit that file.

```dts
/ {
	wifi_pwrseq: pwrseq {
		compatible = "mmc-pwrseq-simple";
		/*
		 * Vendor kernel: chip_en (PL2) high, 5 ms, wl_reg_on (PL6) high.
		 * The two pins are active high. "reset" is the opposite: ACTIVE_LOW.
		 */
		reset-gpios = <&r_pio 0 2 GPIO_ACTIVE_LOW>,	/* NEW: PL2 chip_en   [VERIFIED vendor binary] */
			      <&r_pio 0 6 GPIO_ACTIVE_LOW>;	/*      PL6 wl_reg_on [VERIFIED vendor binary] */
		post-power-on-delay-ms = <200>;			/* NEW: GUESS, value of the Q8 tablets */
	};
};

&axp_gpio {
	/* NEW: [rf_para] power_switch = AXP223 GPIO0, high from boot in the vendor kernel. */
	wifi-power-switch-hog {
		gpio-hog;
		gpios = <0 GPIO_ACTIVE_HIGH>;
		output-high;
		line-name = "wifi-power-switch";
	};
};

&mmc1 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc1_pg_pins>;		/* PG0-PG5 [VERIFIED fex mmc1_para] */
	vmmc-supply = <&reg_dldo1>;		/* 3.3 V [VERIFIED fex module_power1] */
	vqmmc-supply = <&reg_dldo2>;		/* 3.3 V [VERIFIED fex module_power2]; which rail is the IO supply: GUESS */
	mmc-pwrseq = <&wifi_pwrseq>;
	bus-width = <4>;
	non-removable;
	keep-power-in-suspend;			/* NEW: the driver refuses suspend without it [VERIFIED driver source] */
	status = "okay";

	wifi: wifi@1 {
		reg = <1>;
		/* No compatible: the driver binds by SDIO ID and reads no DT property. */
	};
};
```

### 8.3 What is a fact and what is a guess

| Item | Status |
|---|---|
| PL2 and PL6 are the two enable pins, active high, PL2 first | [VERIFIED: vendor binary + fex] |
| `mmc-pwrseq-simple` sets the two pins together. The 5 ms interval is lost. | [VERIFIED: `pwrseq_simple.c`]. If the chip needs the interval: [UNCONFIRMED] |
| `post-power-on-delay-ms = <200>` | GUESS. The vendor kernel code has no delay after PL6. The Allwinner mode of the Radxa source waits 50 ms, then asks for a card scan (`aicsdio.c:584-586`). The vendor module of this unit is not dumped. |
| AXP GPIO0 must be high | [VERIFIED: the vendor kernel sets it]. What this pin switches on the PCB: not known. The hog was not tested. |
| `axp_gpio` label, `x-powers,axp221-gpio`, pin 0 = GPIO0 | [VERIFIED: `axp22x.dtsi` and `pinctrl-axp209.c` at v7.2; `CONFIG_PINCTRL_AXP209=y`] |
| DLDO1 and DLDO2 at 3.3 V | [VERIFIED: fex]. Which is `vmmc` and which is `vqmmc`: GUESS. The MMC core switches on the two rails before the enable pins go high, which is the vendor order. |
| No 32 kHz clock in the pwrseq node | [VERIFIED: `lpo_use_apclk` is empty on this unit] |
| Host-wake interrupt on PL7 | Not in the fragment. This driver build does not use it. `wl_host_wake = PL07` is in the fex. A later build with `CONFIG_OOB=y` needs driver work, because the generic mode has no code to get the interrupt number. |
| Syntax | The fragment compiles with `dtc` on top of `kernel/dts/sun8i-a33-pf1007l.dts`: 0 errors, 0 warnings. This is a syntax check only. | 
| **Do not enable `&r_uart`** | PL2 is the Wi-Fi `chip_en` pin on this unit. `research/02` suggests `CONFIG_CONS_INDEX=5` (R_UART on PL2/PL3) for U-Boot: that drives PL2 as a UART output. |

## 9. First test on the frame (later, not done)

1. Boot with the DT nodes of section 8. Do not load the driver.
2. `cat /sys/bus/sdio/devices/*/uevent`. Expected: `SDIO_ID=C8A1:C08D`. **This is the first gate.** If there is no card, the cause is power or reset, not the driver.
3. Copy the firmware to `/lib/firmware/aic8800_fw/SDIO/aic8800DC/`.
4. Copy the modules to `/usr/lib/modules/7.2.10-1-armv7-ARCH/updates/`, then `depmod -a`.
5. `modprobe aic8800_fdrv`, then `dmesg | grep -i -E "aic|rwnx"`. Record `chip_id`, `chip_sub_id` and the chip revision lines.
6. `iw dev`, `iw dev wlan0 scan`.

## 10. Not proven

| # | Open point | How to close it |
|---|---|---|
| 1 | The driver has never run with the chip. The SDIO transfers, the firmware download and the radio are not tested. | Section 9 on the frame |
| 2 | The chip type of this unit is not read. "AIC8800DC" is [DOCUMENTED] from other units. | Step 2 of section 9 |
| 3 | The chip revision is not known. Radxa ships the U02 files only. A U01 chip needs the frame's own files. | `dmesg` at step 5; copy the vendor firmware from Android |
| 4 | The three DT changes (PL2, AXP GPIO0 hog, 200 ms delay) are not tested. The lost 5 ms interval can be a problem. | Step 2 of section 9; if the card is absent, replace the pwrseq with two `regulator-fixed` nodes that have `startup-delay-us` |
| 5 | Which board net AXP GPIO0 controls | Measure, or read the PCB |
| 6 | Transfer buffers and `CONFIG_VMAP_STACK=y`: I read the main paths (`cmd_buf` from `kzalloc`, data in `sk_buff`). I did not read each call. `sunxi-mmc` uses DMA. | A scan and a ping on the frame, then `dmesg` |
| 7 | Suspend and resume | Test after Wi-Fi works |
| 8 | Power: Wes PR #15 reports a freeze at `insmod aic8800_fdrv.ko` on one hub-powered unit [DOCUMENTED] | Use a good supply for the first test |
| 9 | A project kernel with a different release string needs a new module build (section 3) | Run the same `make` against that kernel tree |
| 10 | The LibreELEC result is from one code search. The older SDIO forks were not cloned again. | Not necessary unless Radxa stops |

## 11. Files

| Path | Content |
|---|---|
| `wifi/build.sh` | Builds from a clean state. Pinned commit, image digest and header package hash. |
| `wifi/patches/` | Empty. No project patch is necessary. `build.sh` applies `*.patch` from here if you add one. |
| `wifi/out/*.ko`, `SHA256SUMS` | The three modules for `7.2.10-1-armv7-ARCH` (git-ignored; `build.sh` makes them again) |
| `wifi/logs/build.log` | Full log of the good build |
| `wifi/logs/00-control-unpatched-vendor-tree.log` | Control build without patches: 51 errors |
| `wifi/logs/modinfo.txt` | `modinfo`, symbol and CRC checks |
| `wifi/logs/qemu-loadtest-orangepi-pc.log` | Kernel boot and module load in QEMU |
| `wifi/logs/vendor-wifi-power-disassembly.txt` | Vendor power sequence, annotated disassembly |
| `refs/aic/` (git-ignored) | Clones, `pkgcache/` (header package), `build/` (patched tree), `linux-v7.2-snippets/`, `armbian-snippets/` |
