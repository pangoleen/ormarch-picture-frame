# Stock kernel config audit — `linux-armv7 7.2.10-1` for the PF1007L

Date: 2026-10-12. Nothing in this file ran on the frame.

## Verdict

**The stock Arch Linux ARM kernel is enough. A custom kernel is not necessary for the first boot and
the first picture.**

- One driver is absent: the panel driver (`CONFIG_DRM_PANEL_JADARD_JD9365DA_H3` is not set). We need
  a patched copy of it in each case, and it builds as an out-of-tree module against the stock
  headers. `kernel/build.sh` makes it. It loads on the stock kernel in an emulator.
- All other parts that the board needs are `=y`, or `=m` with the `.ko` file in the package.
- The parts of the display chain with the highest risk (`sun6i_mipi_dsi`, `sun4i-tcon`, `sun4i-drm`)
  are modules. We can patch them and build them out of tree, as we do for the panel driver.

A custom kernel becomes necessary only if one of these is true later:

| Reason | Why the stock kernel cannot do it |
|---|---|
| A fix in built-in code is necessary: the clock driver (`ccu-sun8i-a33`, pixel-clock risk R4), the D-PHY (`PHY_SUN6I_MIPI_DPHY=y`), `musb`, `sunxi-mmc`, the AXP drivers | Built-in code cannot be replaced by a module |
| `zstd` or `lz4` for zram | Only `ZRAM_BACKEND_LZO=y`. `lzo-rle` is the default and is usable |
| `dev_dbg()` messages of the DSI host at run time | `CONFIG_DYNAMIC_DEBUG` is not set. Out-of-tree builds of the sun4i modules with `-DDEBUG` are an alternative |
| A log that stays after a crash (`ramoops`) | `CONFIG_PSTORE` is not set |
| Multi-generation LRU (memory tuning for 1 GB) | `CONFIG_LRU_GEN` is not set |

## Source of the config

| Item | Value | Tag |
|---|---|---|
| Config file | `usr/lib/modules/7.2.10-1-armv7-ARCH/build/.config` in the package `linux-armv7-headers-7.2.10-1-armv7h.pkg.tar.xz` | [VERIFIED: read] |
| Package hash | SHA-256 `c8a042ff…9f6b04` (the same file that `wifi/build.sh` pins) | [VERIFIED] |
| Second source | `core/linux-armv7/config` in `archlinuxarm/PKGBUILDs` commit `6faf352b`. Equal to the packaged config, except for 5 lines that the compiler makes (`CC_VERSION_TEXT`, `GCC_VERSION`, …) | [VERIFIED: `diff`] |
| `.ko` list | File list of `linux-armv7-7.2.10-1-armv7h.pkg.tar.xz`, SHA-256 `b49a4d4d…de6ebca` (3539 modules, not compressed) and its `modules.builtin` | [VERIFIED: read] |
| On the device | `/proc/config.gz` exists (`CONFIG_IKCONFIG_PROC=y`) | [VERIFIED config, not read on a device] |

"In package" means: the `.ko` path is in the package file list. "Built in" means: the name is in
`modules.builtin`. All rows are [VERIFIED] against these two files unless a row says something else.

## Display

| Option | Value | Module file / note |
|---|---|---|
| `DRM` | y | built in (`drm.ko`, `drm_kms_helper.ko` in `modules.builtin`) |
| `DRM_MIPI_DSI`, `DRM_PANEL`, `DRM_PANEL_BRIDGE` | y | built in |
| `DRM_SUN4I` | m | `sun4i-drm.ko`, `sun4i-tcon.ko`, `sun6i_drc.ko`, `sun4i_tv.ko`: in package |
| `DRM_SUN4I_BACKEND` | m | `sun4i-backend.ko`, `sun4i-frontend.ko`: in package |
| `DRM_SUN6I_DSI` | m | `sun6i_mipi_dsi.ko`: in package. Alias `allwinner,sun6i-a31-mipi-dsi` = the A33 node |
| `PHY_SUN6I_MIPI_DPHY` | y | built in |
| **`DRM_PANEL_JADARD_JD9365DA_H3`** | **not set** | **Not in package.** Our out-of-tree module fills the gap: `kernel/out/panel-jadard-jd9365da-h3.ko` |
| `DRM_PANEL_SIMPLE` | y | built in (not used by this board) |
| `DRM_LIMA` | m | `lima.ko`: in package. Alias `arm,mali-400` |
| `BACKLIGHT_PWM` | y | built in (`pwm_bl.ko`) |
| `PWM_SUN4I` | m | `pwm-sun4i.ko`: in package. Alias `allwinner,sun7i-a20-pwm` = the A33 node |
| `DRM_SIMPLEDRM` | y | built in. Not useful here: U-Boot cannot start the DSI panel, so there is no boot framebuffer |
| `FB_SIMPLE` | not in the config | Hidden by `DRM_SIMPLEDRM=y` (`depends on !DRM_SIMPLEDRM`) |
| `DRM_FBDEV_EMULATION`, `FRAMEBUFFER_CONSOLE`, `FRAMEBUFFER_CONSOLE_ROTATION` | y | The kernel log shows on the panel when DRM starts |
| `CMA_SIZE_MBYTES` | 64 | One 800x1280 32-bit buffer is 4 MB |

## Power, bus, storage

| Option | Value | Module file / note |
|---|---|---|
| `SUNXI_RSB` | y | built in |
| `MFD_AXP20X_RSB` (and `MFD_AXP20X`, `MFD_AXP20X_I2C`) | y | built in |
| `REGULATOR_AXP20X` | y | built in |
| `PINCTRL_AXP209` | y | built in. This is the driver of the AXP GPIO0 hog (Wi-Fi power switch) |
| `REGULATOR_FIXED_VOLTAGE` | y | built in. Used for the PL2 `chip_en` regulator |
| `AXP20X_POWER` (USB power supply) | y | built in |
| `CHARGER_AXP20X`, `BATTERY_AXP20X`, `AXP20X_ADC`, `INPUT_AXP20X_PEK` | m | `axp20x_ac_power.ko`, `axp20x_battery.ko`, `axp20x_adc.ko`, `axp20x-pek.ko`: in package |
| `MMC_SUNXI`, `MMC_BLOCK` | y | built in |
| `PWRSEQ_SIMPLE`, `PWRSEQ_EMMC` | y | built in |
| `PINCTRL_SUN8I_A33`, `PINCTRL_SUN8I_A23_R`, `SUN8I_A33_CCU`, `SUN8I_R_CCU` | y | built in |
| `EXT4_FS`, `BTRFS_FS`, `F2FS_FS`, `VFAT_FS` | y | built in. `NLS_CODEPAGE_437`, `NLS_ISO8859_1`, `NLS_ASCII` are modules: a FAT mount needs them from the root file system |

## USB (device mode on the USB-C port)

| Option | Value | Module file / note |
|---|---|---|
| `USB_MUSB_HDRC`, `USB_MUSB_SUNXI` | y | built in (`musb_hdrc.ko`, `sunxi.ko` in `modules.builtin`). Match `allwinner,sun8i-a33-musb` [VERIFIED: `drivers/usb/musb/sunxi.c:848` at v7.2.10] |
| `USB_MUSB_DUAL_ROLE` | y | Host and gadget mode are in the build. `dr_mode = "peripheral"` in the DTS selects gadget mode |
| `USB_MUSB_GADGET`, `USB_MUSB_HOST` | not set | Correct: the three are one choice, and dual role is selected |
| `PHY_SUN4I_USB` | y | built in |
| `USB_GADGET` | y | built in |
| `USB_LIBCOMPOSITE` | m | `libcomposite.ko`: in package |
| `USB_CONFIGFS` | m | In `libcomposite.ko` |
| `USB_CONFIGFS_NCM` / `_ECM` / `_ECM_SUBSET` / `_RNDIS` / `_EEM` / `_ACM` / `_SERIAL` / `_MASS_STORAGE` / `_F_FS` / `_F_HID` | y | Functions: `usb_f_ncm.ko`, `usb_f_ecm.ko`, `usb_f_ecm_subset.ko`, `usb_f_rndis.ko`, `usb_f_eem.ko`, `usb_f_acm.ko`, `usb_f_serial.ko`, `usb_f_mass_storage.ko`, `usb_f_fs.ko`: in package |
| `USB_U_ETHER`, `USB_U_SERIAL` | m | `u_ether.ko`, `u_serial.ko`: in package |
| `U_SERIAL_CONSOLE` | y | `console=ttyGS0` is possible. The console has `CON_PRINTBUFFER` [VERIFIED: `u_serial.c:1092`] |
| `USB_ETH` (the task name `USB_G_ETHER` is not a Kconfig name) | m | `g_ether.ko`: in package. `USB_ETH_RNDIS=y`, `USB_ETH_EEM=y` |
| `USB_G_NCM` | m | `g_ncm.ko`: in package |
| `USB_CDC_COMPOSITE` | m | `g_cdc.ko`: in package. ECM network + ACM serial in one module. **Used for the blind boot** |
| `USB_G_SERIAL`, `USB_G_MULTI`, `USB_G_ACM_MS` | m | in package |
| `USB_DUMMY_HCD` | not set | The gadget link cannot be tested in an emulator with this kernel |
| `NETCONSOLE` | m | `netconsole.ko`: in package. `NETCONSOLE_DYNAMIC=y` |

## Console and debug

| Option | Value | Note |
|---|---|---|
| `SERIAL_8250`, `SERIAL_8250_CONSOLE`, `SERIAL_8250_DW`, `SERIAL_OF_PLATFORM`, `SERIAL_EARLYCON` | y | built in. 6 UARTs maximum |
| `VT`, `VT_CONSOLE`, `DUMMY_CONSOLE` | y | `console=tty0` is possible |
| `DEBUG_LL` | not set | No low-level debug UART. `earlycon` works with the UART DTB variant |
| `PRINTK_TIME` | y | |
| `LOG_BUF_SHIFT` | 18 | 256 kB. Use `log_buf_len=1M` |
| `DYNAMIC_DEBUG` | not set | See the verdict table |
| `PSTORE` | not set | See the verdict table |
| `DEBUG_FS`, `GPIO_SYSFS`, `GPIO_CDEV`, `I2C_CHARDEV`, `MAGIC_SYSRQ` | y | Clock summary, GPIO state and I2C tools are possible |
| `OF_OVERLAY` | y | The stock DTBs have `__symbols__` (built with `DTC_FLAGS="-@"`). Ours also |

## Memory and CPU

| Option | Value | Note |
|---|---|---|
| `ZRAM` | m | `zram.ko`: in package |
| `ZRAM_BACKEND_LZO` | y | The only backend. `ZRAM_BACKEND_LZ4`, `_LZ4HC`, `_ZSTD`, `_DEFLATE`, `_842`: not set |
| `ZRAM_DEF_COMP` | `lzo-rle` | `ZRAM_WRITEBACK=y`, `ZRAM_MULTI_COMP` not set |
| `ZSWAP` | y | Not on by default. It can use `zstd` (`CRYPTO_ZSTD=y`) |
| `PSI` | y | |
| `PSI_DEFAULT_DISABLED` | y | **`psi=1` is necessary on the command line** |
| `MEMCG`, `CGROUPS` | y | |
| `LRU_GEN` | not set | |
| `CPUFREQ_DT`, `CPUFREQ_DT_PLATDEV` | y | built in |
| `CPU_FREQ_DEFAULT_GOV_PERFORMANCE` | y | The CPU stays at 1.008 GHz. `CPU_FREQ_GOV_SCHEDUTIL=y`, `_ONDEMAND=y`: use `cpufreq.default_governor=schedutil` |
| `CPU_THERMAL`, `THERMAL_OF` | y | |
| `SUN8I_THERMAL` | y | built in, but it has **no A33 entry** [VERIFIED: no `a33` string in `sun8i_thermal.c` at v7.2.10] |
| `SUN4I_GPADC` (the A33 sensor driver) | m | `sun4i-gpadc-iio.ko`: in package. It matches `allwinner,sun8i-a33-ths` [VERIFIED: `sun4i-gpadc-iio.c:482`]. **If this module does not load, the `cpu-thermal` zone has no sensor.** Put it in `modules-load.d` |
| `HIGHMEM` | y | `ARM_LPAE` not set (1 GB RAM: no problem) |

## Input, sensors, audio, Wi-Fi

| Option | Value | Module file / note |
|---|---|---|
| `TOUCHSCREEN_SILEAD` | m | `silead.ko`: in package. Alias `silead,gsl1680`. Needs `/usr/lib/firmware/silead/gsl_m86_hd.fw` |
| `FW_LOADER`, `FW_LOADER_COMPRESS_XZ` | y | `FW_LOADER_COMPRESS_ZSTD` not set: do not compress the touch firmware with zstd |
| `INPUT_EVDEV` | m | `evdev.ko`: in package |
| `KEYBOARD_SUN4I_LRADC` | m | `sun4i-lradc-keys.ko`: in package |
| `KEYBOARD_GPIO` | y | built in (for PB0/PB1 keys, if we add them) |
| `IIO` | y | built in |
| `IIO_ST_ACCEL_3AXIS`, `IIO_ST_ACCEL_I2C_3AXIS` | m | `st_accel.ko`, `st_accel_i2c.ko`, `st_sensors.ko`, `st_sensors_i2c.ko`: in package. **`sc7a20` is in this driver**: aliases `of:…silan,sc7a20` and `i2c:sc7a20` are in `st_accel_i2c.ko` [VERIFIED: `.modinfo` of the stock module] |
| `STK8312`, `STK8BA50` | m | in package (fex candidate `stk831x`) |
| `DA280`, `DA311` | m | in package (fex candidate `mir3da`) |
| `MSA311` | **not set** | Not in package. Only a problem if the chip is a MEMSIC MSA (fex candidate `msa`). Then: one more out-of-tree module, not a custom kernel |
| `MXC4005`, `KXCJK1013`, `BMA220`, `BMC150_ACCEL`, `MMA8452`, `DMARD10` | m | in package |
| `SND_SUN8I_CODEC`, `SND_SUN8I_CODEC_ANALOG`, `SND_SUN4I_I2S`, `SND_SIMPLE_CARD` | m | `sun8i-codec.ko` (alias `allwinner,sun8i-a33-codec`), `sun8i-codec-analog.ko`, `sun8i-adda-pr-regmap.ko`, `sun4i-i2s.ko`, `snd-soc-simple-card.ko`: in package. The board DTS has no audio nodes yet |
| `CFG80211` | m | `cfg80211.ko`: in package (the AIC driver needs it). `RFKILL=m` |
| `MAC80211` | m | in package (the AIC driver does not use it) |

## Modules

| Option | Value | Note |
|---|---|---|
| `MODVERSIONS` (`BASIC_MODVERSIONS`, `GENKSYMS`) | y | Each out-of-tree module must have the symbol CRCs of this kernel. `build.sh` checks them against `Module.symvers` |
| `MODULE_SIG` | not set | Unsigned modules load. Taint flag `O` only |
| `MODULE_COMPRESS` | not set | The package modules are plain `.ko`. Ours also |
| `MODULE_UNLOAD`, `MODULE_FORCE_LOAD` | y | |
| `DEBUG_INFO_NONE` | y | No debug sections. Our module is not stripped |
| vermagic | `7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8` | Ours is equal to that of `panel-lvds.ko` and `sun6i_mipi_dsi.ko` from the package |

## Module load: what is automatic

All board modules of the stock package have a device-tree alias [VERIFIED: `.modinfo` of each file].
With `udev` and a correct `modules.dep`, they load with no list. The blind-boot list in
`kernel/README.md` section 12 forces an order for the display parts only to remove one unknown.

| Module | Dependencies (from `.modinfo`) |
|---|---|
| `sun4i-drm` | `sun4i-tcon`, `sun4i-frontend`, `sun8i_tcon_top` |
| `sun4i-tcon` | `sun8i_tcon_top` |
| `sun4i-backend` | `sun4i-frontend` |
| `sun6i_mipi_dsi`, `sun6i_drc`, `lima`, `pwm-sun4i`, `silead`, `sun4i-gpadc-iio`, `zram` | none |
| `g_cdc` | `libcomposite`, `u_ether` (and `usb_f_ecm`, `usb_f_acm`, `u_serial` at run time) |
| `st_accel_i2c` | `st_sensors`, `st_accel`, `st_sensors_i2c` |
| `panel-jadard-jd9365da-h3` (ours) | none: all 31 imported symbols are in `vmlinux` |
