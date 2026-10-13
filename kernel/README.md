# kernel/ — draft mainline sources for the PF1007L (display + board DTS)

Date: 2026-10-12. Status: **DRAFT. Not built into a kernel. Not run on the frame.**

> **Update, 2026-10-12 (later the same day): read section 8 first.** Sections 8 to 14 are new. The
> panel driver is now built as a module for the stock Arch Linux ARM kernel, the two DTBs are
> built, and the DTS has the Wi-Fi, touch and CPU results of the other reports. Sections 1 to 7
> are kept as they were written. Section 8 lists the lines in them that are no longer correct.
> Still true: **nothing ran on the frame.**

## Answer first (first draft; see section 8 for the current state)

- The panel is MIPI-DSI, 800x1280, 4 lanes, RGB888, non-burst video mode. The mainline driver
  `panel-jadard-jd9365da-h3.c` is the correct driver. One patch adds this panel to it.
- The vendor init table is almost the same as two panels that mainline already has
  (`chongzhou,cz101b4001` and `waveshare,10.1-dsi-touch-a`): 188 of 193 register writes are equal.
  So the panel side has low risk. The risk is in the Allwinner DSI host on the A33.
- **No upstream A33 or R16 board uses DSI.** The first picture is a real test of `sun6i_mipi_dsi.c`
  on this SoC.
- The DTS passes `dtc` with zero warnings. This is a syntax check only.
- Three values are still guesses: the regulator for the SoC pin `VCC-DSI`, the panel rotation (90 or
  270), and the CPU supply (DCDC2 or DCDC3).

Tags in this file:

| Tag | Meaning |
|---|---|
| [VERIFIED] | Read in source code or in a dump of this frame. The file and line are given. It is not a hardware test. |
| [DOCUMENTED] | From a second-hand source (another board, a binding example, a project note). |
| [UNCONFIRMED] | Inference or calculation. |
| [UNCONFIRMED — reference design] | Copied from `sun8i-reference-design-tablet.dtsi`. The fex gives no value. |

## Files

| File | Content |
|---|---|
| `patches/0001-drm-panel-jadard-jd9365da-h3-add-pf1007l-panel.patch` | Unified diff against `refs/linux-snippets/panel-jadard-jd9365da-h3.c` (mainline master `24a19b95`). Adds the init function, the mode, the panel description and the match entry. Generated. Do not edit by hand. |
| `tools/gen_jd9365_init.py` | Makes the patch from `dumps/panel/sq9365_init_sequence.txt` and `dumps/sys_config.fex`. Checks the result. |
| `tools/regen_patch.sh` | Runs the generator with the options used for the patch. |
| `dts/sun8i-a33-pf1007l.dts` | Board DTS. SD card in the slot, no serial console. eMMC disabled. |
| `dts/sun8i-a33-pf1007l-uart0-sd.dts` | Debug variant: UART0 on the SD pins PF2/PF4. For FEL boot only. |
| `tools/check_dts.sh` | Runs the C preprocessor and `dtc` on the DTS files. |
| `dts/pf1007l-accelerometer.dtso` | An accelerometer-only overlay for offline review. It is not installed or selected by the image. See `docs/hardware.md`. |

Fetched sources are in `refs/linux-snippets/` (mainline, kernel tree layout) and `refs/bsp-snippets/`
(Allwinner 3.4 BSP for sun8iw5 = A33/R16, from `BPI-SINOVOIP/BPI-M2M-bsp` commit `68ed96f5`).

How to run the checks (no device access, no `sudo`):

```sh
sh kernel/tools/regen_patch.sh     # regenerates the patch, prints CHECK 1..3 and the panel comparison
sh kernel/tools/check_dts.sh       # cpp + dtc on the three DTS variants
```

---

## 1. Display timings

### The fex convention [VERIFIED]

`lcd_hbp` and `lcd_vbp` **include** the sync width. Primary source: the BSP DSI code for this SoC
family, `refs/bsp-snippets/BPI-M2M-bsp__de_dsi.c`:

- line 994: `dsi_hbp = (hbp-hspw)*dsi_pixel_bits[format]/8 - (4+2);`
- `dsi_basic_size0.bits.vsa = vspw;` and `dsi_basic_size0.bits.vbp = vbp-vspw;`
- line 803: `vfp = panel->lcd_vt - panel->lcd_y - panel->lcd_vbp;`

Mainline agrees: `sun4i_tcon.c` says the register "really is the back porch + hsync", and the BSP
writes `lcd_hbp - 1` to that register (`BPI-M2M-bsp__de_lcd.c:280`).

`lcd_vt` is the real line count in this BSP. Control: `disp_lcd.c:489` computes
`dclk / (vt * ht)` and wants 50 to 70 Hz. Here it is 59.7 Hz, so `lcd_vt` is not doubled.

### Arithmetic

Input, `dumps/sys_config.fex` `[lcd0_para]`: `lcd_x = 800`, `lcd_ht = 854`, `lcd_hbp = 36`,
`lcd_hspw = 18`, `lcd_y = 1280`, `lcd_vt = 1314`, `lcd_vbp = 14`, `lcd_vspw = 4`, `lcd_dclk_freq = 67`.

| Value | Formula | Result |
|---|---|---|
| hsync | `lcd_hspw` | 18 |
| h back porch | `lcd_hbp − lcd_hspw` = 36 − 18 | 18 |
| h front porch | `lcd_ht − lcd_x − lcd_hbp` = 854 − 800 − 36 | 18 |
| check | 800 + 18 + 18 + 18 | 854 = `lcd_ht` |
| vsync | `lcd_vspw` | 4 |
| v back porch | `lcd_vbp − lcd_vspw` = 14 − 4 | 10 |
| v front porch | `lcd_vt − lcd_y − lcd_vbp` = 1314 − 1280 − 14 | 20 |
| check | 1280 + 20 + 4 + 10 | 1314 = `lcd_vt` |
| refresh | 67 000 000 / (854 × 1314) | 59.71 Hz |

`drm_display_mode`: `clock = 67000`, h = 800 / 818 / 836 / 854, v = 1280 / 1300 / 1304 / 1314,
`width_mm = 135`, `height_mm = 216` (`lcd_width`, `lcd_height`). The generator computes these values
from the fex and stops if a sum is wrong.

---

## 2. The panel patch

### What the generator checks

| Check | Result |
|---|---|
| 1. The generated C, parsed again with a model of the driver helpers, gives the same writes and delays as the sequence file | PASS: 199 register writes, sleep-out, 120 ms, display-on, 20 ms |
| 2. The helper model agrees with the driver source (`jd9365da_switch_page`, `jadard_enable_standard_cmds`), and `jadard_prepare()` does not send sleep-out or display-on | PASS |
| 3. Timing sums equal `lcd_ht` / `lcd_vt`; refresh is 50 to 70 Hz | PASS |
| Patch applies to the reference file (`patch -p1`, `git apply --check`) | PASS |
| C syntax of the generated block (clang, with stub types) | PASS. This is **not** a kernel build |

Facts about the driver style [VERIFIED: `refs/linux-snippets/panel-jadard-jd9365da-h3.c`]:

- Each init function sends sleep-out (0x11) and display-on (0x29) itself. The common code does not
  (`jadard_prepare()`, lines 96-135; there is no `.enable` hook). So the generated function sends
  them one time. The brief said "many entries leave them to common code". That is not true for this
  driver version.
- `E0 00` + `E1 93, E2 65, E3 F8, 80 03` becomes `jd9365da_switch_page(0x00)` +
  `jadard_enable_standard_cmds()`. The helper sends `80 03` for 4 lanes (lines 60-69).
- The write `80 20` on page 1 stays a normal write.

Two points where the generated code is **not** byte-equal to the vendor:

1. The vendor sends `11 00` and `29 00` (one zero parameter, DSI type 0x15). The driver helpers send
   0x11 and 0x29 with no parameter (type 0x05). All init functions in the driver use the helpers. For an
   A/B test, the generator has `--vendor-exact-11-29`.
2. A 150 ms delay is added after the table. It is in the vendor code, not in the table
   (`power-sequence.md`, Table 1, step 14).

Count note: the brief said "201 one-parameter writes, then 0x11 …". The file has 201 writes in total:
199 register writes + `11 00` + `29 00`. `power-sequence.md` agrees.

### This panel is almost a panel that mainline already has [VERIFIED by the script]

`gen_jd9365_init.py --compare` compares the register writes (page, register, value):

| Existing init function | Compatible | Equal | Different | Only in ours |
|---|---|---|---|---|
| `cz101b4001_init_cmds` | `chongzhou,cz101b4001`, `radxa,display-10hd-ad001` | 188 | 1 | 4 |
| `waveshare_10_1_a_init` (4 lanes) | `waveshare,10.1-dsi-touch-a` (135 x 216 mm, same as ours) | 188 | 1 | 4 |
| all others | | 21 to 41 | 110 to 158 | |

The five differences: page 1 register 0x01 = 0x48 (theirs 0x3b), page 3 `9a ff`, `9b ff`, `af 01`
(ours only), page 4 `37 58` (ours only). The gamma and GIP tables are equal. The meaning of these
registers is not checked (no JD9365DA datasheet here) [UNCONFIRMED].

A new entry is still necessary: the timings, the mode flags and five registers are different.

### Mode flags

Chosen: `MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_SYNC_PULSE | MIPI_DSI_MODE_NO_EOT_PACKET | MIPI_DSI_MODE_LPM`.

| Flag | Why | Evidence |
|---|---|---|
| `VIDEO` | `lcd_dsi_if = 0` = video mode | `BPI-M2M-bsp__drv_display.h:339` `LCD_DSI_IF_VIDEO_MODE = 0`; `power-sequence.md` answer 6 [VERIFIED] |
| no `VIDEO_BURST` | Burst is `lcd_dsi_if = 2`. The vendor does not use it | `drv_display.h:341`; `de_dsi.c:825` [VERIFIED] |
| `VIDEO_SYNC_PULSE` | The BSP fex comment says "0: Non-burst mode with sync pulses". The non-burst code sends HSA and HBP packets | `BPI-M2M-bsp__BPI-M2M-LCD5__sys_config.fex:551`; `de_dsi.c:993-994` [VERIFIED] |
| `NO_EOT_PACKET` | The vendor sets `hs_eotp_en = 0` | `de_dsi.c:817` [VERIFIED] |
| `LPM` | The vendor sends all commands in low-power mode | `power-sequence.md` answer 3 [VERIFIED there] |

**The driver default is not usable.** With `mode_flags = 0` the driver sets `VIDEO | VIDEO_BURST |
NO_EOT_PACKET | LPM` (panel driver lines 3190-3196). See risk R2.

`sun6i_mipi_dsi.c` reads only **one** of these flags: `MIPI_DSI_MODE_VIDEO_BURST` (lines 423, 459,
542). It does not read `SYNC_PULSE`, `NO_EOT_PACKET`, `LPM` or `VIDEO_HSE`. Its fixed behaviour is
equal to the vendor mode: non-burst with HSA / HBP / HFP blanking packets (lines 551-597), no EoT
packet (lines 740-741 set only ECC and CRC), commands always in low-power mode (lines 346-348, 881,
911). So the flags are correct for other hosts, and they do not change the result on the A33.

### Power sequence: vendor against mainline

Vendor data: `dumps/panel/power-sequence.md` (read in the disassembly of this frame's `lcd.ko`).
Mainline: `panel-jadard-jd9365da-h3.c` lines 75-155 and `sun6i_mipi_dsi.c` lines 716-814.

| Step | Vendor | Mainline with this draft | Equal? |
|---|---|---|---|
| Supplies on | DC1SW, 10 ms, ELDO3 | `vccio` then `vdd`, no delay in the driver (lines 101-105). The DTS maps `vccio` = DC1SW, `vdd` = ELDO3 and gives DC1SW a 10 ms enable delay | Yes, by DTS |
| D-PHY on | After the supplies, before the reset | `phy_power_on()` **before** `drm_panel_prepare()` (sun6i lines 762-773). So the PHY is on before the panel supplies | **No.** Order is opposite. See R6 |
| Wait before reset | 50 + 10 + 10 = 70 ms after ELDO3 | `vcioo_to_lp11_delay_ms = 50`, `lp11_to_reset_delay_ms = 25`, + 5 ms in common code = 80 ms | Yes (longer) |
| Reset line during power-up | High | Low. The driver asserts reset at probe (line 3223) and releases it in `prepare()` | No. Low is the usual safe state |
| Reset pulse | **Two** pulses: low 20 ms, high 60 ms, low 30 ms, high 30 ms | **One** pulse, fixed in common code: high 5 ms, low 10 ms, high 130 ms (lines 121-128) | **No.** Not changed in this draft. One pulse is the usual method [UNCONFIRMED that it is sufficient] |
| NOP before reset | None | None (`lp11_before_reset` is not set) | Yes |
| Init commands | DCS short write, 1 parameter (0x15), low-power mode | `mipi_dsi_dcs_write_seq_multi()` gives type 0x15; the host sends in low-power mode | Yes |
| Sleep-out, display-on | `11 00`, 120 ms, `29 00`, 20 ms | `11` (no parameter), 120 ms, `29` (no parameter), 20 ms | Type 0x05, not 0x15 |
| After the table | 150 ms, then HS clock | 150 ms in the init function, then backlight on, then HS clock (sun6i lines 787-790) | Yes for the delay |
| HS clock to HS video | 300 ms | 1 ms, fixed (`udelay(1000)`, line 792) | **No.** Cannot be set from the panel driver. See R7 |
| Backlight on | 100 ms after the video starts. PWM first, then PH06 | Before the HS clock (`drm_panel_enable()`, line 788). PWM first, then the GPIO (`pwm_bl.c:104-106`, `39-55`) | Order of PWM/GPIO: yes. Time: **no**, a short flash is possible |
| Power-off commands | None (no 0x28, no 0x10) | `jadard_disable()` sends 0x28 and 0x10 (lines 83, 88) while HS video runs | No. See R9 |
| Power-off order | Backlight off, video off, reset low, 20 ms, D-PHY off, 30 ms, ELDO3 off, DC1SW off | Backlight off, 0x28, 0x10, reset high 120 ms, reset low 1-2 ms (`reset_before_power_off_vcioo`), ELDO3 off, DC1SW off, then D-PHY off (sun6i lines 803-813) | Supplies order: yes. The PHY goes off after the supplies: no |

---

## 3. The DTS, node by node

Base: `sun8i-a33.dtsi` + `sun8i-reference-design-tablet.dtsi`, as in `research/02` §3.3, with the DSI
branch. "Pattern" is the mainline file that the node shape comes from.

| Node / property | Fex value (this frame) | Pattern | Tag |
|---|---|---|---|
| `model`, `compatible = "efercro,pf1007l"` | `[product] machine = "U708HC"` | `sun8i-a33-ga10h-v1.1.dts` | Vendor prefix is a placeholder [UNCONFIRMED] |
| `&de`, `&tcon0` okay, no pinctrl | `lcd_if = 4` (DSI has its own pins) | `sun50i-a64-pinephone.dtsi` | [VERIFIED] fex; `tcon0_out` endpoint@1 → `dsi` is in `sun8i-a33.dtsi:418` |
| `&dphy` okay | `lcd_if = 4` | `sun50i-a64-pinephone.dtsi:145` | [VERIFIED] |
| `&dsi` okay | `lcd_if = 4`, `lcd_dsi_lane = 4` | `sun50i-a64-pinephone.dtsi:149`, `sun50i-a64-pinetab.dts:160` | [VERIFIED] fex |
| `&dsi` `vcc-dsi-supply = <&reg_dcdc1>` | **No fex value** | Example in `allwinner,sun6i-a31-mipi-dsi.yaml` (A33 address, `reg_dcdc1`) | **[UNCONFIRMED]** placeholder. See R6 |
| `panel@0` compatible `"yhk,zr789-sq9365-101", "jadard,jd9365da-h3"` | `lcd_driver_name = "yhk_zr789_sq9365_101"` | `jadard,jd9365da-h3.yaml` | Name is a placeholder |
| `panel@0` `vccio-supply = DC1SW`, `vdd-supply = ELDO3` | `lcd_power = "axp22_dc1sw"`, `lcd_power1 = "axp22_eldo3"` | binding | Rails [VERIFIED] fex. Which one is VDD and which is VCCIO: [UNCONFIRMED]; the mapping gives the vendor order |
| `panel@0` `reset-gpios = PH7, active low` | `lcd_gpio_0 = port:PH07<1><0><default><1>` | `sun50i-a64-pinephone.dtsi:156` | Pin [VERIFIED] fex. Polarity [VERIFIED] in `power-sequence.md` (code levels) |
| `panel@0` `backlight` | — | binding | — |
| `panel@0` `rotation = <90>` | **No fex value** | `mt8186-corsola-starmie.dtsi:133` | **[UNCONFIRMED]** 90 or 270 |
| `&backlight` `pwms = <&pwm 0 20000 0>` | `lcd_pwm_ch = 0`, `lcd_pwm_freq = 50000` (1e9 / 50000 = 20000 ns), `lcd_pwm_pol = 0`, `[pwm0_para]` PH00 | reference dtsi | [VERIFIED] fex. Polarity 0 = normal = active high: `BPI-M2M-bsp__pwm-sunxi.c:105-126` [VERIFIED]. The reference value (50000 ns, inverted) is not correct for this board |
| `&backlight` `enable-gpios = PH6, active high` | `lcd_bl_en = port:PH06<1><0><default><1>` | reference dtsi | [VERIFIED] fex |
| `&backlight` levels, default level, `power-supply = DC1SW` | (`lcd0_backlight = 197`) | reference dtsi | [UNCONFIRMED — reference design] |
| `&cpu0` no `cpu-supply` | `[power_sply] dcdc2_vol = 1200`, `dcdc3_vol = 1200`; `[dvfs_table]` LV4 = 1008 MHz / 1200 mV | — | **Open question.** See §5 |
| OPP table (not changed, max 1.008 GHz) | `[dvfs_table]` 1008 MHz/1.20 V, 816/1.10, 648/1.04 | `sun8i-a33.dtsi:48-128` | [VERIFIED] the three fex points are equal to the mainline table |
| `&reg_dcdc1` 3.3 V always-on | `dcdc1_vol = 3300` | reference dtsi (3.0 V there) | [VERIFIED] fex |
| `&reg_dcdc2`, `&reg_dcdc3` 1.2 V fixed, always-on | `dcdc2_vol = 1200`, `dcdc3_vol = 1200` | reference dtsi (0.9-1.4 V there) | Voltage [VERIFIED] fex. Names "vdd-sys"/"vdd-cpu" [UNCONFIRMED — reference design] |
| `&reg_dcdc5` 1.5 V | `dcdc5_vol = 1500` | reference dtsi (same) | [VERIFIED] fex |
| `&reg_aldo1` 3.3 V, `&reg_aldo2` 2.5 V, `&reg_aldo3` 3.0 V, always-on | `aldo1_vol = 3300`, `aldo2_vol = 2500`, `aldo3_vol = 3000` | reference dtsi | Voltage [VERIFIED] fex. Names and always-on [UNCONFIRMED — reference design] |
| `&reg_dc1sw` + 10 ms enable delay | `dc1sw_vol = 3300`, `lcd_power` | `sun50i-a64-pinetab.dts:416` | Delay from `power-sequence.md` step 1 |
| `&reg_eldo3` 3.3 V | `eldo3_vol = 3300`, `lcd_power1` | — | [VERIFIED] fex |
| `&reg_dldo1`, `&reg_dldo2` 3.3 V | `[rf_para] module_power1/2 = axp22_dldo1/2`, 3300000 | `sun8i-r16-bananapi-m2m.dts:245-256` | [VERIFIED] fex |
| `&reg_dldo4` 1.8 V, `&reg_eldo1` 2.8 V, not always-on | `dldo4_val = 1800`, `eldo1_vol = 2800` | — | Voltage [VERIFIED] fex. Consumer not known. See R12 |
| `dc5ldo`, `ldo_io1` 3.3 V, `rtc_ldo`, `eldoin-supply` | `ctp_power_ldo = "axp22_ldoio1"`, 3300 for `ldo_io1`; none for the others | reference dtsi | `ldo_io1` [VERIFIED] fex; others [UNCONFIRMED — reference design] |
| `&axp22x` at RSB 0x3a3, `x-powers,axp223` | `[pmu1_para] pmu_used = 1`, `[s_rsb0]` PL00/PL01 | reference dtsi | Bus [VERIFIED] fex. Chip type AXP223 [UNCONFIRMED] |
| `&axp22x` delete `x-powers,drive-vbus-en`; `&reg_drivevbus` disabled | `pmu_vbusen_func = 1` | `axp20x-regulator.c:1730-1733` | Project decision (no VBUS drive) [DOCUMENTED]; fex is weak evidence |
| `&touchscreen` `silead,gsl1680` @0x40, INT PB5, power PH1, i2c0 400 kHz | `ctp_twi_id = 0`, `ctp_twi_addr = 0x40`, `ctp_int_port = PB05`, `ctp_wakeup = PH01` | reference dtsi + `sun8i-a33-ga10h-v1.1.dts` | Bus, address, pins [VERIFIED] fex. Chip model [UNCONFIRMED] (`ctp_name = "gsl_m86_hd"`) |
| `&touchscreen` `avdd-supply`, `vddio-supply` = `ldo_io1` | `ctp_power_ldo = "axp22_ldoio1"`, 3300 | `silead,gsl1680.yaml` | [VERIFIED] fex |
| `&touchscreen` size 1024 x 600, inverted x and y | `ctp_screen_max_x = 1024`, `ctp_screen_max_y = 600`, `ctp_revert_x_flag = 1`, `ctp_revert_y_flag = 1`, `ctp_exchange_x_y_flag = 0` | binding | Values [VERIFIED] fex, but probably old template values [UNCONFIRMED]. Test |
| `&touchscreen` `firmware-name` | — | `sun8i-a33-ga10h-v1.1.dts` | Placeholder |
| `accelerometer@19` on i2c1, `silan,sc7a20`, **disabled** | `gsensor_twi_id = 1`, `gsensor_twi_addr = 0x19`, `gsensor_int1 = PB06`; list: stk831x, sc7a20, mir3da, msa | `st,st-sensors.yaml`, `st_accel_i2c.c:121` | Bus and address [VERIFIED] fex. Chip type [UNCONFIRMED] → node is disabled |
| `&mmc0` (no change) 4-bit, cd PB4, DCDC1 | `[mmc0_para] sdc_buswidth = 4`, `sdc_det = PB04`, `sdc_power_supply = "axp22_dcdc1"` | reference dtsi | [VERIFIED] fex. Card-detect polarity [UNCONFIRMED — reference design] |
| `&mmc1` 4-bit, non-removable, `vmmc = DLDO1`, `vqmmc = DLDO2` | `[wifi_para] wifi_sdc_id = 1`; `[mmc1_para]` PG00-PG05, `sdc_buswidth = 4`, `sdc_detmode = 4` | `sun8i-q8-common.dtsi`, `sun8i-r16-bananapi-m2m.dts:130-138` | Pins and rails [VERIFIED] fex. Which rail is the IO supply [UNCONFIRMED] |
| `wifi_pwrseq` `reset-gpios = PL6, active low` | `wl_reg_on = port:PL06<1><default><default><0>` | `sun8i-r16-bananapi-m2m.dts:91-96` | Pin [VERIFIED] fex. Polarity [DOCUMENTED] (same pin on the M2M) |
| `&mmc2` 8-bit, `cap-mmc-hw-reset`, DCDC1, **disabled** | `[mmc2_para] sdc_buswidth = 8`, PC05/06/08-15, `emmc_rst = PC16`, `sdc_power_supply = "axp22_dcdc1"`; `[card2_boot_para] card_line = 4` | `sun8i-r16-bananapi-m2m.dts:140-148` | [VERIFIED] fex. Disabled because of project safety rule 3. Enable with `-DPF1007L_ENABLE_EMMC` |
| `&usb_otg` `dr_mode = "peripheral"`; `&usbphy` no ID pin, no VBUS supply | `[usbc0] usb_port_type = 2`, `usb_id_gpio = PH08`, `usb_det_vbus_gpio = "axp_ctrl"` | `research/02` skeleton (photo-frame-dashboard U-Boot patch) | The fex says OTG. Peripheral-only is a project decision [DOCUMENTED]. VBUS detection through the AXP [VERIFIED] fex |
| `&r_uart` disabled, `serial0` alias removed | `[s_uart0] s_uart_used = 0`; `[rf_para] chip_en = port:PL02<1>…` (PL2 is an output) | — | [VERIFIED] fex. The reference dtsi puts a UART on PL2/PL3: wrong for this board |
| UART0 on PF2/PF4 (variant file only) | `[uart_para] uart_debug_port = 0`, `uart_debug_tx = PF02`, `uart_debug_rx = PF04` | `uart0_pf_pins` in `sun8i-a23-a33.dtsi:437` | [VERIFIED] fex. Shared with the SD slot |
| Thermal trips (not changed) | `[ths_para]` 75 / 90 / 110 °C | `sun8i-a33.dtsi:326-356` | [VERIFIED] equal |
| LRADC volume keys, `ac_power_supply`, `battery_power_supply` (not changed) | none (`pmu_battery_cap = 0`) | reference dtsi | [UNCONFIRMED — reference design] |

Not in this draft (the fex has values, but they were not in the scope or are not clear):

- Speaker amplifier: `[audio0] audio_pa_ctrl = PH09`. No audio nodes.
- GPIO keys: `[gpio_keys] key1 = PB00`, `key2 = PB01`. The key functions are not known.
- Camera: `[csi0] vip_used = 0`.
- Second USB (host): `[usbc1] usb_used = 1`. It is not known if a port is on the PCB.
- `[rf_para] chip_en = PL02` and `[wifi_para] wl_host_wake = PL07`: not driven.
- `[dram_para]` (`dram_clk = 456`, `dram_zq = 0x7bfb`, `dram_odt_en = 1`) is for U-Boot, not for the
  DTS. `dram_clk` agrees with `research/02` (456 MHz). The fex ZQ value (0x7bfb) is not the number
  that `research/02` gives for U-Boot (15291 = 0x3bbb). It is not checked here if the two use the same
  format [UNCONFIRMED]. The fex has ODT on.

---

## 4. What can stop the first picture

Sources: `refs/linux-snippets/drivers/gpu/drm/sun4i/sun6i_mipi_dsi.c` (= "dsi.c" below),
`sun4i_tcon.c`, `drivers/clk/sunxi-ng/ccu-sun8i-a33.c`, `drivers/phy/allwinner/phy-sun6i-mipi-dphy.c`,
all mainline master `24a19b95`. "Read" means read, not run.

| # | Risk | Evidence | What to do |
|---|---|---|---|
| R1 | **No upstream A33/R16 board enables DSI.** The host driver has no proof on this SoC in the tree | All 14 `sun8i-a33-*` / `sun8i-r16-*` files in `arch/arm/boot/dts/allwinner` (and the A23 / A31 files, 43 files): `&dsi` / `&dphy` are only in `sun8i-a33.dtsi` [VERIFIED, scope: that directory]. The DSI binding example uses the A33 address `dsi@1ca0000` with `bananapi,lhr050h41`, so someone ran it on an A33 one time [DOCUMENTED] | Expect to debug the host, not the panel |
| R2 | **Burst mode breaks the loop delay for this mode.** `delay = (htotal − hdisplay) × 150 / ((clock / 1000) × 8) − 50` = 54 × 150 / 536 − 50 = 15 − 50 = **−35** in a `u16` → wraps; the register macro keeps 12 bits (0xfdd) | dsi.c:457-464, 75. The panel driver default has `VIDEO_BURST` (panel driver 3190-3196) | The patch sets non-burst flags. Do not test this frame with `chongzhou,cz101b4001` (default flags = burst). `waveshare,10.1-dsi-touch-a` has non-burst flags, but it needs a `data-lanes` graph |
| R3 | **VCC-DSI supply is a guess.** A missing or wrong supply gives no error: `devm_regulator_get()` gives a dummy regulator. The supply is enabled at encoder enable, before the PHY. The vendor turns on DC1SW and ELDO3 **before** the D-PHY; mainline starts the PHY before the panel supplies | dsi.c:1137-1140, 728, 762-773; `power-sequence.md` steps 1-3 | If there is no picture: set `vcc-dsi-supply = <&reg_eldo3>` or `<&reg_dc1sw>`. Fastest test: add `regulator-always-on` to `reg_dc1sw` and `reg_eldo3`, then the order cannot matter |
| R4 | **Pixel clock will not be 67 MHz.** The TCON clock must be bit rate / 4, divider fixed at 4, so `lcd-ch0` must be 67 × 24 / 4 = 402 MHz. The DSI module clock is set to 297 MHz with `clk_set_rate_exclusive()`; its parent is `pll-video`, so `pll-video` is locked. `pll-mipi` = `pll-video` × N × K / M has no exact 402 MHz from 297 MHz. Highest value below: 396 MHz (N×K/M = 4/3) → 66.0 MHz pixel clock, 58.8 Hz (−1.5 %). Closest: 405 MHz | sun4i_tcon.c:358-364; dsi.c:1171-1176; ccu-sun8i-a33.c:134-142, 420-426, 463-467; `ccu_nkm.c:75-106` [calculation UNCONFIRMED] | Read `/sys/kernel/debug/clk/clk_summary` (`pll-video`, `pll-mipi`, `lcd-ch0`, `dsi-sclk`, `dsi-dphy`). If the PLL was not at 297 MHz when the DSI driver started, the result is different |
| R5 | **The D-PHY timing uses the nominal clock**, not the real one. The PHY module clock is set to 150 MHz (exclusive) | dsi.c:764-766; phy-sun6i-mipi-dphy.c:206 | Low risk. Note it if the link is not stable |
| R6 | **Panel commands and backlight come before the HS clock.** `drm_panel_prepare()` and `drm_panel_enable()` run, then HS clock, 1 ms, HS video. The driver has a FIXME about this order. The vendor waits 300 ms between HS clock and video, and 100 ms more before the backlight | dsi.c:772-794 (FIXME 775-786) | A flash or noise at start is possible and is not a failure. If the picture is black with backlight on, test a longer delay in place of `udelay(1000)` (dsi.c:792) |
| R7 | **Short writes are not checked.** `sun6i_dsi_dcs_write_short()` starts the transfer and returns. No wait, no error. A dead link gives a clean log and no picture | dsi.c:873-884, 1004-1042 | Use a one-byte DCS read as a link test (the host supports it, dsi.c:927-964), for example register 0x0a (power mode) |
| R8 | **Host packet types.** The host accepts DCS short write (0x05, 0x15), generic short write with 2 parameters, DCS long write and a 1-byte DCS read. All other types give `-EINVAL` | dsi.c:1019-1039 | All writes of this panel are 0x15 or 0x05. OK |
| R9 | **Blank / unblank can fail.** `jadard_disable()` sends 0x28 and 0x10 while HS video runs. The FIXME says commands do not work in HS mode. The vendor sends no command at power-off | dsi.c:797-814, 775-786; panel driver 75-95 | Not a first-picture problem. Test `xset dpms` / suspend later |
| R10 | **One reset pulse, not two**, and reset low during power-up | panel driver 121-128, 3223; `power-sequence.md` steps 6-11 | If the panel does not start: copy the vendor pulses in `jadard_prepare()` for a test |
| R11 | **`vblk` is 0 in mainline.** The BSP computes 4 for this mode with 4 lanes | dsi.c:590-596; `BPI-M2M-bsp__de_dsi.c:999-1003` (tmp = 2562 × 1314 − 2504 = 3 363 964; 4 − tmp % 4 = 4) | The mainline comment says 0 works. Keep as a test point |
| R12 | **Rails with no known consumer.** `[power_sply]` also has `dldo4 = 1800` and `eldo1 = 2800`. If the vendor bootloader turns them on and a part needs them (panel IO, touch, sensor), that part is dead under mainline. Linux turns off regulators that have no user | fex `[power_sply]`; meaning of `dldo1_val = 1003300` not decoded [UNCONFIRMED] | If touch, panel or sensor is dead: add `regulator-always-on` to `reg_dldo4` / `reg_eldo1` |
| R13 | **Panel driver not in the kernel config.** The driver is `CONFIG_DRM_PANEL_JADARD_JD9365DA_H3` | `drivers/gpu/drm/panel/Kconfig:404`. Not checked in the ALARM config [UNCONFIRMED] | Set it to `m` or `y` with `DRM_SUN6I_DSI` and `PHY_SUN6I_MIPI_DPHY` |
| R14 | **No early picture, no easy console.** U-Boot cannot drive DSI, so there is no boot picture. The debug UART shares the SD pins. The panel attaches only after the DRM device is registered (probe deferral), and the connector arrives as a hotplug event | dsi.c:966-986; `research/02` §2 | Use USB gadget networking, or the `-uart0-sd` variant with FEL boot |
| R15 | **Rotation is not known**, and the display engine cannot rotate | `research/02` §6.3 | First picture in portrait is a pass. Then set 90 or 270 |

Values that agree between mainline and the BSP for this mode (computed from the two sources, so
these are **not** risks) [VERIFIED by reading; not measured]:

| Item | Mainline | BSP | Value |
|---|---|---|---|
| HSA / HBP / HFP / HBLK packet sizes | dsi.c:558-588 | `de_dsi.c:993-997` | 44 / 48 / 38 / 2498 bytes |
| DSI video start delay | dsi.c:365-374 | `de_dsi.c:802-813` | 1295 lines |
| TCON DRQ | off, because front porch 18 ≤ 20 (dsi.c:439-450) | off (`de_dsi.c:851`) | 0 |
| TCON block space | sun4i_tcon.c:395-396 | `de_lcd.c:366` | 441 |
| TCON start delay | sun4i_tcon.c:405-407 | `de_lcd.c:315` | 5460 |
| Lane mask | dsi.c:332 | `de_dsi.c:865` | 4 lanes |

Limits that the driver does **not** have [VERIFIED: no `mode_valid` in dsi.c]: no check of the pixel
clock, the lane count or the mode. A mode that the hardware cannot do is accepted with no message.

---

## 5. Open question: CPU supply (DCDC2 or DCDC3)

| Source | Says |
|---|---|
| `sun8i-reference-design-tablet.dtsi` | `cpu-supply = <&reg_dcdc2>`, but DCDC3 is named "vdd-cpu" and DCDC2 "vdd-sys" |
| `sun8i-a33-sinlinx-sina33.dts:81`, `sun8i-r16-bananapi-m2m.dts:104` | DCDC3 |
| BSP fex of the BPI-M2M (R16) | `dcdc2_vol = 1100`, `dcdc3_vol = 1200` (1.2 V = the 1008 MHz boot point → DCDC3 looks like the CPU rail there) [DOCUMENTED, other board] |
| This frame's fex | `dcdc2_vol = 1200`, `dcdc3_vol = 1200`. **No answer** |

Draft decision: no `cpu-supply`. The two rails are fixed at 1.2 V (the fex boot value). cpufreq changes
only the frequency, up to 1.008 GHz. This is safe for the two possible answers. It uses more power at
low frequency. To close the question: read the vendor kernel log or `/sys/class/regulator` on Android,
or measure the two inductors while the CPU frequency changes.

---

## 6. Placeholders and TODO list

| # | Item | Now | How to close it |
|---|---|---|---|
| 1 | Panel compatible `yhk,zr789-sq9365-101` | Placeholder from `lcd_driver_name`. "yhk" is not in `vendor-prefixes.yaml` | Read the label on the back of the panel. The binding YAML also needs the new name |
| 2 | Board compatible `efercro,pf1007l` | Placeholder | Decide before any upstream work |
| 3 | `vcc-dsi-supply` | DCDC1 (guess) | Schematic, or the tests in R3 |
| 4 | Electrical role of DC1SW and ELDO3 (VDD / VCCIO) | Mapped for the vendor order only | Meter on the panel connector |
| 5 | `rotation` | 90 (guess) | Look at the first picture; `getprop ro.sf.hwrotation` on Android |
| 6 | CPU supply | No `cpu-supply`, rails fixed at 1.2 V | §5 |
| 7 | Touch firmware, chip model, size, axes | Placeholder name; fex size 1024 x 600 | Extract the firmware from the vendor module; `evtest` |
| 8 | Accelerometer chip | `silan,sc7a20`, disabled | `i2cdetect` / WHO_AM_I read, then enable |
| 9 | Wi-Fi power: `post-power-on-delay-ms`, PL2 `chip_en`, IO rail, 32 kHz clock | Not set | Check that the SDIO ID appears; then tune |
| 10 | eMMC | Disabled | Enable in PLAN.md Phase 9 (or sooner, read-only, for a backup) |
| 11 | AXP chip type | AXP223 (reference) | Chip marking or `dmesg` |
| 12 | `dldo4` 1.8 V, `eldo1` 2.8 V consumers | Not always-on | R12 |
| 13 | Reset pulses, 300 ms HS-clock-to-video gap, 0x11/0x29 parameter byte | Common driver code, not changed | Only if the first picture fails (R6, R10) |
| 14 | Kernel build | Not done | Apply the patch to a 7.2/7.3 tree, enable R13 options, `make dtbs` + modules |
| 15 | dt-schema check (`make dtbs_check`) | Not done (needs a kernel tree and dt-schema) | Run it in the kernel build container |
| 16 | Battery / AC / LRADC keys / audio / GPIO keys | Reference values or not present | After the first picture |

The panel power sequence is **not** a placeholder any more: the delays in the patch come from
`dumps/panel/power-sequence.md`. That file is read from the disassembly. It is not a measurement.

---

## 7. Syntax check result

Tool: `clang -E` (as the kernel C preprocessor step) + `dtc` 1.8.1 from Homebrew. Includes:
`refs/linux-snippets/arch/arm/boot/dts/allwinner` and `refs/linux-snippets/include` (dt-bindings
headers fetched from mainline master).

| File | Result |
|---|---|
| `sun8i-a33-pf1007l.dts` | `dtc`: OK, DTB 24.6 kB, **0 warnings** (default `dtc` warning set) |
| `sun8i-a33-pf1007l.dts -DPF1007L_ENABLE_EMMC` | OK, 0 warnings |
| `sun8i-a33-pf1007l-uart0-sd.dts` | OK, 0 warnings |
| Control: upstream `sun8i-a33-ga10h-v1.1.dts`, same method | OK, 1 warning (`avoid_unnecessary_addr_size` on `dsi@1ca0000`, from `sun8i-a33.dtsi`). Our DTS does not have it because the DSI node has a child |

Limits of this check:

- `check_dts.sh` passes `-W no-unit_address_vs_reg`, as the kernel build does. A second run with no
  warning option gave the same result (0 warnings).
- It is a syntax and structure check. It does not check the properties against the binding schemas.
- The DTB was decompiled and the main nodes were read (panel, DSI, backlight, CPU, PMIC, MMC, USB).
- Nothing was compiled into a kernel. The panel patch was checked with `patch`, `git apply --check`
  and a stub syntax compile only.

---

# Part 2 — artifacts for the boot card (added 2026-10-12)

Tags are the same as in part 1. Two more words are used here, because they are different things:
**built** / **ran** = done in this work (in a container or an emulator on the Mac), and
**read** = read in source code. Nothing ran on the frame.

## 8. Answer first

- **The stock kernel `linux-armv7 7.2.10-1` is enough.** No kernel build is necessary. Only the panel
  driver is absent from it (`CONFIG_DRM_PANEL_JADARD_JD9365DA_H3` is not set). The full audit is in
  `kernel/config-audit.md`.
- **The panel driver is built** as an out-of-tree module against the stock headers:
  `kernel/out/panel-jadard-jd9365da-h3.ko`. It loads and unloads on the real stock kernel image in
  an emulator. It has never driven a panel.
- **The two DTBs are built** with the `dtc` of the stock kernel and the include files of Linux
  v7.2.10: `kernel/out/sun8i-a33-pf1007l.dtb` and `kernel/out/sun8i-a33-pf1007l-uart0-sd.dtb`.
- **`kernel/build.sh` makes all three files again** from a clean state. Two runs gave the same
  SHA-256 values.
- The settings for a first boot with no screen and no serial line are in section 12. Draft files
  are in `kernel/bootcard/`.

```
2342541c5c52b3481a56e2db0f0d9c096abcb00441e461fa6a23669843543dbf  panel-jadard-jd9365da-h3.ko
db88666274df153cf513bb4f5b97b0e0be1e85ffc053043e5da1233ca6b4ff40  sun8i-a33-pf1007l.dtb
b0f59dac0c0ae48e0867feb45a13727901325c638fbddf74b665d226a5ec71c2  sun8i-a33-pf1007l-uart0-sd.dtb
```

### What was built or run, and what was only read

| Item | Level |
|---|---|
| Stock config and module list | Read from the two packages (hashes in `config-audit.md`) |
| Panel module build, `modinfo`, symbol and CRC checks | **Built and ran** in the armv7 container |
| Control: the master version of the driver against the 7.2.10 headers | **Ran**: fails, as expected (section 9) |
| Module load on the stock `zImage` (QEMU `orangepi-pc`) + control with a wrong CRC | **Ran** in an emulator |
| `depmod` prefers `updates/`; alias lookup finds our compatible | **Ran** in the armv7 container |
| DTB build with the stock kernel's `dtc`; control against a stock DTB | **Built and ran** |
| DTB rule checks (`check_dtb.py`); control on an upstream DTB | **Ran** |
| dt-schema (`dtbs_check`); two controls | **Ran** in a Python container |
| AXP GPIO hog on the stock kernel (QEMU `bpim2u`, emulated AXP221) | **Ran** in an emulator |
| MMC power-up order, `mmc-pwrseq-simple`, `regulator-fixed`, hog code, `sunxi-mmc`, `u_serial` console | Read in the v7.2.10 source |
| USB gadget link, boot-card files, Wi-Fi power sequence, touch, display | **Not run.** No hardware |

### Lines in sections 1 to 7 that are no longer correct

| Where | Old statement | Now |
|---|---|---|
| Status line, "Answer first" | "Not built into a kernel"; "The DTS passes `dtc` … syntax check only" | Module and DTBs are built for the stock kernel. Section 10 has the `dtc` and dt-schema results |
| "Answer first", §5, §6 item 6 | "CPU supply (DCDC2 or DCDC3)" is a guess | The vendor software uses **DCDC3** [VERIFIED in binaries, not measured] (`dumps/vendor-facts/README.md` §1). The default DTB still changes the frequency only. `-DPF1007L_CPU_DVFS_DCDC3` adds the supply (section 10) |
| "Files" table, §7 | The patch is a diff against master; includes are `refs/linux-snippets` (master) | The built patch is `patches/v7.2.10/0001-*.patch`, against Linux v7.2.10. The master patch is kept for upstream work. Includes: `refs/kernel/linux-7.2.10` |
| §3 `&touchscreen` rows | size 1024 x 600, inverted X and Y, placeholder firmware name | 960 x 640, no inversion, `gsl_m86_hd.fw`, `silead,max-fingers = <5>` (`dumps/touch/README.md`) |
| §3 `wifi_pwrseq`, `&mmc1` rows; "Not in this draft: `chip_en = PL02` … not driven" | PL6 only, DLDO1 = `vmmc` | PL2 is driven, with a wait before PL6. AXP GPIO0 hog. `keep-power-in-suspend`. DLDO1 and DLDO2 always on (section 10) |
| §3 `&reg_dcdc2` / `&reg_dcdc3` rows | Names are [UNCONFIRMED — reference design] | DCDC3 = CPU, DCDC2 = system: [VERIFIED in vendor binaries, not measured] |
| R13 | "Panel driver not in the kernel config … not checked" | Checked: not set. Solved with the module |
| §6 items 7, 9, 14, 15 | Touch firmware, Wi-Fi power, kernel build, dt-schema: open | Done in this part, as far as it is possible with no hardware |
| §2 "`mode_flags = 0` … driver default … lines 3190-3196" | Line numbers of master | In v7.2.10 the default is at lines 2948-2953 and has no `MIPI_DSI_MODE_LPM`. Our entry sets its own flags, so the result is the same |

All other parts of sections 1 to 7 are still valid. The risk list R1 to R15 (except R13) is not
reduced by this work: no hardware was used.

## 9. The panel driver as an out-of-tree module

### Base: v7.2.10, not master

Source: `drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c` at tag `v7.2.10`, SHA-256
`153da8a8…62dcf32`. Three sources give the same bytes: the kernel.org tarball `linux-7.2.10.tar.xz`
(SHA-256 `2feaa704…cff2ebf3`, equal to `sha256sums.asc` on kernel.org), `git.kernel.org` (stable
tree, by tag) and the `gregkh/linux` GitHub mirror. [VERIFIED]

Differences between the v7.2.10 file and the master file (`24a19b95`) that part 1 used
[VERIFIED: `diff`, 3 hunks]:

| # | Difference | Does it matter? |
|---|---|---|
| 1 | Master calls `drm_of_get_panel_orientation()`. v7.2.10 calls `of_drm_get_panel_orientation()` | **Yes.** The stock kernel exports only the old name (`Module.symvers`: 1 hit and 0 hits). A master-based file does not compile against the stock headers |
| 2 | Master has one more panel, `dcltek,dt300250` (242 lines) | For the patch: yes. All line numbers after line 2931 move by 242, so the master patch does not apply with `git apply` |
| 3 | Master adds `MIPI_DSI_MODE_LPM` to the default flags (`desc->mode_flags == 0`) | No. Our entry sets its flags |
| — | Helpers, `struct jadard_panel_desc` fields, `jadard_prepare()`, the match table end | No difference. The generator needs no change in its logic |

Control [ran]: the master file + our entry, built against the stock headers, stops with
`error: implicit declaration of function 'drm_of_get_panel_orientation'`
(`kernel/logs/00-control-master-driver-on-7.2.10.log`).

About the old patch [ran]: `git apply --check` of the master patch on the v7.2.10 file fails.
`patch -p1` applies it with an offset and gives the same file as the generator. Do not rely on that:
use the v7.2.10 patch.

### Tool changes

| File | Change |
|---|---|
| `tools/gen_jd9365_init.py` | New option `--patch-state` (first lines of the patch header: base and build state). No change in the generated C. The C block is byte-equal for the two bases |
| `tools/regen_patch.sh` | `BASE=v7.2.10` (default) writes `patches/v7.2.10/0001-*.patch`. `BASE=master` writes the old `patches/0001-*.patch` (its diff body is not changed) |
| `tools/check_dts.sh` | Uses the v7.2.10 include tree. It is a fast syntax check on the Mac only |

Generator result on the v7.2.10 base: CHECK 1, 2, 3 PASS. The comparison with the panels in the
driver is the same as in part 1 (188 of 193 writes equal to `cz101b4001` and `waveshare_10_1_a`).

### Build recipe [built]

```sh
kernel/build.sh          # about 50 seconds on this Mac
```

| Item | Value |
|---|---|
| Method | Native build in an armv7 container under QEMU user emulation. The same as `wifi/build.sh`, with its three traps (pacman `--disable-sandbox`, `-j` on the outer `make`, `git apply` in a private git directory) |
| Container image | `menci/archlinuxarm@sha256:3ede3a01…22b5f04e` (`base-devel-20261012.38214418911`) |
| Compiler | `gcc (GCC) 16.1.1 20260430`, the version that built the kernel |
| Headers | `linux-armv7-headers 7.2.10-1`, SHA-256 `c8a042ff…9f6b04` |
| Command | `make -j10 -C /usr/lib/modules/7.2.10-1-armv7-ARCH/build M=$PWD modules`, with `Kbuild` = `obj-m := panel-jadard-jd9365da-h3.o` |
| Result | 0 errors, 0 warnings from the C compiler. One Kbuild note: the compiler *name* is different (`gcc` and `armv7l-unknown-linux-gnueabihf-gcc` are the same 16.1.1). Log: `kernel/logs/panel-build.log`. Two clean runs: same SHA-256 |

### Checks on the module [ran] (`kernel/logs/panel-modinfo.txt`)

| Check | Result |
|---|---|
| File type | ELF 32-bit LSB relocatable, ARM, EABI5 |
| Module name | `panel_jadard_jd9365da_h3` |
| vermagic | `7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8`. Equal to `panel-lvds.ko` and `sun6i_mipi_dsi.ko` of the stock package |
| Our compatible in the alias list | `of:N*T*Cyhk,zr789-sq9365-101` and `…C*`: 2 lines. The 14 upstream compatibles are also there |
| Undefined symbols | 31. Not exported by the stock kernel: **0** |
| Symbol CRCs | 32 entries. Mismatch or missing against `Module.symvers`: **0** |
| Module dependencies | None (`depends:` is empty). All 31 symbols are in `vmlinux` |

### Load test in an emulator [ran] (`kernel/tools/qemu_loadtest.sh`)

The real `boot/zImage` of `linux-armv7 7.2.10-1`, in `qemu-system-arm -M orangepi-pc`
(log: `kernel/logs/qemu-loadtest-orangepi-pc.log`).

| Step | Result |
|---|---|
| `insmod panel-jadard-jd9365da-h3.ko` | rc=0. `/sys/bus/mipi-dsi/drivers/jadard-jd9365da` appears |
| Taint | 4096 (out-of-tree module) only |
| `rmmod`, then `insmod` again | rc=0, rc=0 |
| **Control:** the same file with one bit changed in the CRC of `drm_panel_add` | **Refused**: `disagrees about version of symbol drm_panel_add`, rc=1. So the kernel does check the CRCs, and our file passes that check |
| Oops, BUG, WARNING | 0 |

This proves the module format, the relocations and the symbol versions. It does not prove the
probe: the emulated board has no DSI host and no panel.

### Does the stock package ship this module? How to install ours

**No.** The option is not set and the file is not in the package (`build.sh` checks this in each
run). So our module is an addition. It does not replace a file.

Install it in `updates/`, with the upstream file name:

```sh
install -Dm644 kernel/out/panel-jadard-jd9365da-h3.ko \
    <rootfs>/usr/lib/modules/7.2.10-1-armv7-ARCH/updates/panel-jadard-jd9365da-h3.ko
depmod -b <rootfs> 7.2.10-1-armv7-ARCH        # in an armv7 or native Linux environment
```

Why `updates/` [ran, in the armv7 container with kmod of the image]: Arch Linux ARM has
`search updates extramodules built-in` in `/usr/lib/depmod.d/search.conf`. In a test tree with our
file in `updates/` **and** a second copy in `kernel/drivers/gpu/drm/panel/`, `modules.dep` listed
only `updates/panel-jadard-jd9365da-h3.ko`, and `modprobe --show-depends` gave that path for the
name and for the device-tree alias. So if a later stock package ships this driver, ours still wins.

Two rules:

- The module is only for kernel release `7.2.10-1-armv7-ARCH`. Hold the kernel package
  (`IgnorePkg = linux-armv7 linux-armv7-headers` in `pacman.conf`) or build again after each kernel
  update (`KPKGVER` and the two hashes in `build.sh`). [UNCONFIRMED: an update was not tested]
- The DTB must have `"yhk,zr789-sq9365-101"` as the first compatible. With only the fallback
  `"jadard,jd9365da-h3"`, no driver binds: the driver has no entry for the fallback name. [VERIFIED: match table]

## 10. The DTBs

### Method [built]

`build.sh` uses the command of the kernel build (`cmd_dtc` in `scripts/Makefile.dtbs`, v7.2.10):
`gcc -E -nostdinc -I include-prefixes -undef -D__DTS__ -x assembler-with-cpp`, then the `dtc` binary
from `linux-armv7-headers` (`DTC 1.7.2-g53373d13`).

| Point | Value | Tag |
|---|---|---|
| `.dtsi` files and `dt-bindings` headers | Tag `v7.2.10`, 19 files, each with a pinned SHA-256 (`kernel/sources-v7.2.10.sha256`) | [VERIFIED] |
| The 9 `dt-bindings` headers | Byte-equal to the copies in `linux-armv7-headers` | [VERIFIED: `cmp` in each run] |
| The 8 Allwinner `.dts`/`.dtsi` files | Equal in v7.2.10 and in master (`refs/linux-snippets`) | [VERIFIED: `cmp`] |
| `dtc` flags | `-@` only. Arch Linux ARM builds its DTBs with `make DTC_FLAGS="-@" dtbs`. The command-line value replaces the `-Wno-…` list of the Makefile | [VERIFIED: PKGBUILD line 80 + the control below] |
| **Control** | The upstream `sun8i-a33-ga10h-v1.1.dts`, built with this method, is **byte-equal** to `boot/dtbs/sun8i-a33-ga10h-v1.1.dtb` of the stock package | [VERIFIED: ran] |
| Overlays | The DTBs have `__symbols__`. The kernel has `CONFIG_OF_OVERLAY=y` | [VERIFIED] |

### `dtc` warnings [ran] (`kernel/logs/dtb-build.log`, `dtb-w2.log`)

| Build | Warnings |
|---|---|
| The two artifacts, stock flags (all default `dtc` checks on) | **0** |
| The two artifacts, kernel `W=1` checks | **0**, and the bytes are the same |
| The four other switches (one at a time, and all four), `W=1` | **0** |
| The two UART switches together | Stops with `#error`, as designed |
| Control (`ga10h`) | 1 warning, `avoid_unnecessary_addr_size` on `dsi@1ca0000`, from `sun8i-a33.dtsi` (its DSI node has no child). Ours has the panel child |
| The two artifacts, kernel `W=2` strict names (report only) | 5 for each file. 1 is from our file: the standard property `dr_mode` has a `_`. 4 are from upstream `.dtsi` files (`usb0_vbus_power-supply`, `ldo_io0`, `ldo_io1`, `rtc_ldo`). No action |

### dt-schema [ran] (`kernel/tools/dtbs_check.sh`, `kernel/logs/dtbs-check.log`)

Tool: `dtschema 2026.9` (pip) in a `python:3.12-slim` container, with the 5668 binding schemas of
Linux v7.2.10 (`dt-mk-schema`: 0 messages) and `dt-validate -m`.

| DTB | Messages |
|---|---|
| Control: upstream `sun8i-a33-ga10h-v1.1` (= the stock DTB) | **0** |
| `sun8i-a33-pf1007l.dtb` | **6**, from 3 causes |
| `sun8i-a33-pf1007l-uart0-sd.dtb` | The same 6 |

| # | Finding | Meaning | Action |
|---|---|---|---|
| 1 | `/`: compatible `efercro,pf1007l` is in no schema (2 messages) | Placeholder board name. `sunxi.yaml` lists each board | Before upstream work only |
| 2 | `panel@0`: compatible `yhk,zr789-sq9365-101` is not in `jadard,jd9365da-h3.yaml` (2 messages) | Placeholder panel name. The binding needs the new name | Before upstream work only |
| 3 | `gpio` of the PMIC: `wifi-power-switch-hog` matches no pattern of `x-powers,axp209-gpio.yaml` (2 messages) | That binding permits only `…-pins` child nodes. It has no hog pattern | **Not a run-time problem**, see below. For upstream: add the hog pattern to the binding, or model the pin in a different way |

No other node that we add or change has a finding: touch, panel properties, DSI, backlight,
`regulator-fixed`, `mmc-pwrseq-simple`, MMC1, the regulators.

Control that the check can fail on these nodes [ran]: a copy of the DTB with three deliberate
errors (an unknown property in the touch node, an unknown property in the PL2 regulator, a string
in `post-power-on-delay-ms`) gave a message for each (`kernel/logs/dtbs-check-negative-control.log`).

Finding 3, checked two ways:

- [VERIFIED: read, v7.2.10] `gpiochip_hog_lines()` (`drivers/gpio/gpiolib.c:1060-1080`) takes each
  child node with `gpio-hog`. `gpiochip_generic_request()` returns 0 while the chip has no pin range
  (`gpiolib.c:2405`), and `pinctrl-axp209.c` adds its range after the chip (lines 502-508). The
  output call writes function 1 = "output high" (`pinctrl-axp209.c:198-219`).
- [VERIFIED: ran in an emulator] `kernel/tools/qemu_axp_hog_test.sh`: stock `zImage`, QEMU `bpim2u`
  (emulated AXP221, the same `x-powers,axp221-gpio` driver data). Control, stock DTB: no hog, GPIO0
  control register 0x90 = `0x07`. With our hog node: the driver loads
  (`AXP209 pinctrl and GPIO driver loaded`), the line `wifi-power-switch` is in
  `/sys/kernel/debug/gpio`, and register 0x90 = **`0x01`** (output high). 0 warnings.
  (`debugfs` shows "out lo": the emulator does not copy the output to the status register.)
  Limit: emulated AXP221 on I2C, not the AXP223 on RSB of the frame.

### What is merged into `dts/sun8i-a33-pf1007l.dts`

| Part | Change | Source | Tag |
|---|---|---|---|
| Wi-Fi `chip_en` (PL2) | New node `regulator-wifi-chip-en`: `regulator-fixed`, GPIO PL2 active high, `startup-delay-us = <150000>`, `vin-supply = DLDO1`. It is the `vmmc-supply` of MMC1 | `wifi/README.md` §8 | Pin and order [VERIFIED vendor binary]. This node shape: [UNCONFIRMED], not tested |
| Wi-Fi `wl_reg_on` (PL6) | Stays the `mmc-pwrseq-simple` reset GPIO. `post-power-on-delay-ms = <200>` | `wifi/README.md` §8 | Pin [VERIFIED]. 200 ms: guess (value of the mainline Q8 tablets) |
| AXP GPIO0 | `gpio-hog`, output high, in `&axp_gpio` | `wifi/README.md` §8 | [VERIFIED vendor binary] that the vendor sets it. What it switches: not known. Hog code path: see above |
| MMC1 | `keep-power-in-suspend` | `wifi/README.md` §7 | [VERIFIED driver source there] |
| DLDO1, DLDO2 | `regulator-always-on` | Vendor turns on the two rails at kernel boot, before PL2 | [VERIFIED vendor binary]; pattern `sun8i-r16-bananapi-m2m.dts` |
| Touch | `firmware-name = "gsl_m86_hd.fw"`, size 960 x 640, no inversion, no swap, `silead,max-fingers = <5>` | `dumps/touch/README.md` §7 | Firmware name and finger count [VERIFIED]. Size and axes [UNCONFIRMED — test with evtest] |
| CPU | Comment and switch `PF1007L_CPU_DVFS_DCDC3` | `dumps/vendor-facts/README.md` §1 | See below |
| Console | Comment in `chosen`; switch `PF1007L_UART0_ON_PB_PINS` | Section 11 | — |
| eMMC | **No change: disabled.** `check_dtb.py` rule R3 stops the build if it is enabled in an artifact | Project safety rule 3 | — |

`avdd-supply` stays in the touch node (the touch report has only `vddio-supply`). The two point to
the same LDO, and the driver turns on the two together, so the result is the same.

### The PL2 → PL6 wait: 5 ms, and why the DTS has 150 ms

Two reports read the same vendor loop (`wifi_pm_power`: 5 × `const_udelay(0x066665b0)`) and
disagree: 5 ms (`wifi/README.md`) and about 125 ms (`dumps/vendor-facts/README.md`).

The arithmetic gives **5 ms**:

| Step | Value | Tag |
|---|---|---|
| 32-bit ARM, Linux 3.4: `udelay(n)` = `__const_udelay(n * UDELAY_MULT)`, `UDELAY_MULT = (2199023 * HZ) >> 11` | — | [DOCUMENTED: `arch/arm/include/asm/delay.h` of the BPI-M2M 3.4 BSP, `refs/bsp-snippets/BPI-M2M-bsp__arch_arm_include_asm_delay.h` lines 13 and 54-58. Same kernel family, not the frame's own source] |
| `HZ` of the frame's vendor kernel | 100 | [VERIFIED: `CONFIG_HZ=100` in the config that is inside this frame's kernel image (`IKCFG_ST` in `dumps/raw/boot-kernel.bin`)] |
| `1000 * ((2199023 * 100) >> 11)` | 107 374 000 = `0x066665b0` | [VERIFIED: arithmetic, exact] |

So the constant is `udelay(1000)` = 1 ms, and the loop is `mdelay(5)`. The 125 ms value comes from
the x86 factor (2^32 / 10^6 = 4295). I did not change the two reports (outside `kernel/`).

The DTS uses **150 ms**. It is longer than the two values. It is safe for the 125 ms reading. It is
safe for the 5 ms reading if the chip needs only a *minimum* time between the pins [UNCONFIRMED:
there is no AIC8800 datasheet here]. The cost is 0.15 s at each Wi-Fi power-up.

Why not two GPIOs in the pwrseq node (the fragment of `wifi/README.md` §8.2):
`mmc_pwrseq_simple_post_power_on()` sets all reset GPIOs in one call
(`drivers/mmc/core/pwrseq_simple.c:79-90`), so there is **no** interval, and no order. The DTS
order instead [VERIFIED: read, v7.2.10 — `mmc_power_up()` `core.c:1338-1370`,
`sunxi_mmc_card_power()` `sunxi-mmc.c:901-927`, `fixed.c:194, 275`]:

```
boot:        DLDO1 on, DLDO2 on (always-on), AXP GPIO0 = 1 (hog)      = vendor rf_pm_probe
MMC1 on:     PL6 low (pwrseq pre-power-on)
             vmmc on  -> PL2 high, wait 150 ms (regulator start-up delay)
             vqmmc on -> DLDO2 (already on), wait 10 ms (MMC core)
             PL6 high (pwrseq post-power-on), wait 200 ms
             SDIO card detection
```

For an A/B test on the frame, `-DPF1007L_WIFI_PWRSEQ_TWO_PINS` gives the fragment of
`wifi/README.md` (the two pins together). It has a compile check only.

### CPU supply switch

| Build | `cpu-supply` | DCDC3 range | Behaviour |
|---|---|---|---|
| Default (the artifacts) | none | 1.2 V fixed | cpufreq changes the frequency only. Safe for each wiring |
| `-DPF1007L_CPU_DVFS_DCDC3` | `<&reg_dcdc3>` | 1.04 V to 1.20 V | cpufreq also sets the voltage |

The OPP voltages need no new nodes. The table of `sun8i-a33.dtsi` (v7.2.10, lines 49-123) has
1.04 V to 648 MHz, 1.10 V for 720 and 816 MHz, 1.20 V for 912 and 1008 MHz. These are equal to
the three vendor points in this range (`[dvfs_table]`: 648 MHz / 1040 mV, 816 / 1100, 1008 / 1200)
[VERIFIED: fex and `.dtsi`]. The three values are steps of the AXP22x DCDC3 (600 mV + n × 20 mV).
The switch changes two things in the DTB: `cpu-supply` on `cpu@0` and the minimum of DCDC3
[VERIFIED: decompiled the two DTBs]. The vendor points above 1.008 GHz (1.2 GHz / 1.32 V,
1.344 GHz / 1.46 V) are not added.

Before you set the switch: on rooted vendor Android, AXP register 0x23 must change with the CPU
frequency and register 0x22 must not (`dumps/vendor-facts/README.md` §1, "Certainty").
Not checked here: the time that DCDC3 needs to rise before the frequency goes up. The DTS gives
no ramp delay, as the upstream A33 boards with `cpu-supply = <&reg_dcdc3>` [UNCONFIRMED].

### Rule checks on the DTBs [ran] (`kernel/tools/check_dtb.py`, `kernel/logs/dtb-rules.log`)

A small FDT reader checks the two binary files in each `build.sh` run: 22 rules on the default DTB,
21 on the UART DTB, all PASS. The rules cover PL2/PL3, console, eMMC off, PB0/PB1 free, no
`cpu-supply`, DCDC2/DCDC3 at 1.2 V, panel compatible, Wi-Fi nodes, `__symbols__`.
Control: the same script on the upstream `ga10h` DTB gives 9 FAIL lines (R_UART on PL2/PL3,
`stdout-path` on it, `cpu-supply`, DCDC2/DCDC3 range) and then stops because there is no panel
node, as it must.

## 11. Console, PL2/PL3 and U-Boot

**Result: in the two built DTBs nothing but the Wi-Fi power node uses PL2, and nothing uses PL3.**
[VERIFIED: `check_dtb.py` rule R1 on the binary files]

| Check | Default DTB | UART DTB |
|---|---|---|
| GPIO users of PL2 | 1: `/regulator-wifi-chip-en` | the same |
| GPIO users of PL3 | 0 | 0 |
| Enabled nodes that use the pin group `r-uart-pins` (PL2/PL3) | 0 | 0 |
| `r_uart` | disabled, no `pinctrl-0` | the same |
| `/aliases/serial0` | absent | `/soc/serial@1c28000` (UART0) |
| `/chosen/stdout-path` | absent | `serial0:115200n8` |
| Enabled UARTs | 0 | UART0 on PF2/PF4; MMC0 (the SD slot, same pins) disabled |

Is this coherent for a board with no accessible UART? Yes:

- Default DTB: no serial alias and no `stdout-path`. The kernel console is then `tty0` (the panel,
  after DRM starts) and each `console=` of the command line that has a driver. `console=ttyS0` has
  no device in this build: do not use it. Use `console=ttyGS0` (USB serial gadget) with `console=tty0`
  (section 12).
- The vendor console was `ttyS0,115200` = UART0 on PF2/PF4 [VERIFIED: `dumps/vendor-facts/uboot-env.txt`,
  fex `[uart_para]`]. These are SD-card pins (CLK and D3). So that console is possible only with no
  SD card, thus only with FEL boot: this is the UART DTB.

**What PB0/PB1 are** [VERIFIED: `dumps/sys_config.fex`]:

| fex section | Value | Meaning |
|---|---|---|
| `[gpio_keys]` `keys_used = 1`, `key1 = port:PB00<4>`, `key2 = port:PB01<4>` | mux 4 = external interrupt | **The vendor uses the two pins as key inputs** |
| `[uart2]` `uart_used = 0`, `uart_tx = PB00<2>`, `uart_rx = PB01<2>` | mux 2 = UART2, not used | A template entry |
| `[uart_para]`, `[uart0]` | PF02 / PF04 | The vendor debug UART0 is on the SD pins, not on PB0/PB1 |

The SoC can put UART0 on PB0/PB1 (mux 3) [VERIFIED: `pinctrl-sun8i-a33.c:24-35` at v7.2.10].
`sun8i-a23-a33.dtsi` has no pin group for it. The DTS has the switch `-DPF1007L_UART0_ON_PB_PINS`
with its own pin group (compile check only). It is useful only if the two pads can be found on
the PCB. The frame has one button, so the pads are possibly test points or not there
[UNCONFIRMED]. If they are there, this is the only serial console that works with an SD card.

**To carry forward to the U-Boot work** (I did not build or read U-Boot):

- `CONFIG_CONS_INDEX=5` makes U-Boot use R_UART on PL2 (TX) and PL3 (RX). On this board PL2 is the
  Wi-Fi `chip_en` pin. A UART TX line is high when idle and changes with each character. So U-Boot
  holds `chip_en` high and pulses it, before Linux starts and possibly before the Wi-Fi rails are on.
  [VERIFIED: pin functions in the fex and `pinctrl-sun8i-a23-r.c:38-47`; the effect on the chip is UNCONFIRMED]
- Linux corrects the state: when `regulator-wifi-chip-en` probes, PL2 becomes a GPIO output at low,
  and the MMC power-up then does the full sequence. So Wi-Fi should still start. [UNCONFIRMED]
- The reference repository uses `CONS_INDEX=5` on its units (`pf1007l-uboot.patch`) and reports
  no Wi-Fi problem from it [DOCUMENTED]. A console on a pin that drives nothing is cleaner:
  UART0 (`CONS_INDEX=1`) or a silent console. Which pins U-Boot uses for UART0 on an A33 (PF2/PF4 or
  PB0/PB1) must be read in the U-Boot source [UNCONFIRMED: not read here].

## 12. Settings for a blind first boot (no screen, no serial line)

All of this section is a plan. **Nothing here ran on the frame.** The files in `kernel/bootcard/`
are drafts for the boot-card work.

### What is automatic and what to force

- All board modules of the stock package have a device-tree alias, so `udev` loads them with no
  list [VERIFIED: `.modinfo`, `config-audit.md`]. Our panel module also, after `depmod` [ran].
- Built in, no module necessary: USB device controller (musb, its PHY, the UDC core), PMIC,
  regulators, MMC, `pwm-backlight`, UART.
- The list below is thus a way to fix the **order** and to remove the alias lookup as an unknown.

`/etc/modules-load.d/pf1007l.conf` (`kernel/bootcard/etc/modules-load.d/pf1007l.conf`):

| Order | Module | Why here |
|---|---|---|
| 1 | `g_cdc` | USB link first: CDC ECM network (`usb0`) + CDC ACM serial (`ttyGS0`). One module, no configfs script. Dependencies `libcomposite`, `u_ether`, `usb_f_ecm`, `usb_f_acm`, `u_serial` load with it |
| 2 | `sun4i-gpadc-iio` | The A33 temperature sensor. Without it the `cpu-thermal` zone has no sensor |
| 3 | `pwm-sun4i` | The backlight (`pwm-backlight`, built in) waits for this PWM |
| 4 | `panel-jadard-jd9365da-h3` | Ours, from `updates/`. Before the DSI host, so that the panel binds at once |
| 5 | `sun6i_mipi_dsi` | DSI host. It makes the panel device |
| 6 | `sun4i-frontend`, `sun4i-backend`, `sun6i_drc`, `sun4i-tcon` | Parts of the display pipeline |
| 7 | `sun4i-drm` | The master. The first mode set happens when it binds |
| 8 | `lima` | GPU. It does not drive the screen |
| 9 | `zram` | `lzo-rle` only |
| not in the list | `aic8800_bsp`, `aic8800_fdrv` | `udev` loads them when the SDIO card appears. A forced load with no card fails after 2 s |
| not in the list | `silead`, audio, `st_accel_i2c` | By alias |

`/etc/modprobe.d/pf1007l.conf`: fixed (project-made, locally administered) addresses for `g_cdc`,
so that the Mac sees the same network interface on each boot, and two `softdep` lines (panel before
the DSI host, PWM before the master). The `g_cdc` parameters `dev_addr`, `host_addr`,
`iManufacturer`, `iProduct` exist [VERIFIED: `.modinfo` of the stock `g_cdc.ko`].

### Kernel command line

Stage 2 = normal (`kernel/bootcard/cmdline-stage2.txt`):

```
root=/dev/mmcblk0p2 rw rootwait console=ttyGS0,115200 console=tty0 psi=1 cpufreq.default_governor=schedutil ignore_loglevel log_buf_len=1M
```

| Parameter | Why | Tag |
|---|---|---|
| `root=/dev/mmcblk0p2 rootwait` | Example. The DTS alias `mmc0` = the SD slot, so the card is `mmcblk0`. MMC, ext4, btrfs and f2fs are built in: no initramfs is necessary. The partition number is the choice of the boot-card work | [VERIFIED config]; number is an example |
| `console=ttyGS0,115200` | Kernel messages on the USB serial gadget. The stock kernel has `U_SERIAL_CONSOLE=y`. The console starts when `g_cdc` loads | [VERIFIED config + `u_serial.c:1077-1106`]; not run |
| `console=tty0` (last) | Messages on the panel when DRM is up. The last `console=` is `/dev/console`: it stays on the VT, so a not-connected USB serial line cannot block user space | [UNCONFIRMED: design choice, not tested] |
| no `console=ttyS0` | No UART in the default DTB | Section 11 |
| `psi=1` | `PSI_DEFAULT_DISABLED=y` in the stock config | [VERIFIED] |
| `cpufreq.default_governor=schedutil` | The stock default is `performance`: always 1.008 GHz at 1.2 V | [VERIFIED config and `kernel-parameters.txt:1017`] |
| `ignore_loglevel log_buf_len=1M` | All messages, larger buffer (default 256 kB) | [VERIFIED] |

Stage 1 = the very first boot (`cmdline-stage1.txt`): the same line plus

```
modprobe.blacklist=sun4i_drm,sun4i_tcon,sun4i_backend,sun4i_frontend,sun6i_drc,sun6i_mipi_dsi,sun8i_tcon_top,panel_jadard_jd9365da_h3,lima,aic8800_bsp,aic8800_fdrv,aic8800_btlpm
```

Reason: the DSI host has never run on an A33 in the upstream tree (R1). If the display stack
stops the kernel, a blind boot gives no information. With the blacklist the frame comes up with
USB only, and you load the display by hand while the log is visible. `modprobe.blacklist=` stops
automatic loads; a `modprobe <name>` by hand still works. It should also stop the matching lines of
`modules-load.d` [UNCONFIRMED: kmod and systemd behaviour from memory, not tested].

UART DTB (`cmdline-uart0-sd.txt`, FEL boot, no SD card): add `earlycon` and `console=ttyS0,115200`
as the last console. The root device is then not the SD card.

Useful only when a problem shows [VERIFIED that the names exist in `kernel-parameters.txt` of v7.2.10]:
`regulator_ignore_unused` and `clk_ignore_unused` (keep what U-Boot turned on; a test for R12),
`initcall_debug`, `drm.debug=0x1e` (also at run time: `/sys/module/drm/parameters/debug`).

### How to get `dmesg` out

| Way | Frame side | Mac side | Works when |
|---|---|---|---|
| A. USB serial | `g_cdc` + `console=ttyGS0` + `systemctl enable serial-getty@ttyGS0.service` | `ls /dev/cu.usbmodem*`, then `screen /dev/cu.usbmodem… 115200`, log in, `dmesg` | musb gadget + `g_cdc` work. No network setup |
| B. USB network | `kernel/bootcard/etc/systemd/network/20-usb0.network`: `usb0` = 10.55.0.1/24, DHCP server; `systemd-networkd` and `sshd` on | The Mac gets an address on the new interface. `ssh alarm@10.55.0.1 dmesg > dmesg.txt` | The same + networkd |
| C. netconsole | `modprobe netconsole netconsole=@10.55.0.1/usb0,6666@<IP address of the Mac>/` | `nc -ul 6666` | Only for a crash that A and B cannot show |
| D. On the card | `kernel/bootcard/usr/local/sbin/pf1007l-bootlog` + its service: writes `dmesg`, the module list, the SDIO IDs and the DRM connector state to `/boot/pf1007l-log/` at 0, 20, 60 and 180 s | Put the card in the Mac and read the FAT partition | **Even with no USB link.** Needs a FAT `/boot` (NLS modules load from the root file system) |

Limits, all [UNCONFIRMED]: macOS should bind its own CDC ECM and CDC ACM drivers to `g_cdc`
(USB ID 0525:a4aa); not tested on this Mac. The serial console replays the old log when `g_cdc`
loads, but the Mac has not opened the port at that time, so early lines can be lost: run `dmesg`
after login. For Internet from the Mac (Internet Sharing), `usb0` must be a DHCP client, not a
server: that is a later step. The log can have MAC addresses: remove them before a commit.

### Order of work on the first boot (stage 1)

1. Boot with `cmdline-stage1.txt`. Wait 60 s. Look for the new serial port and network interface on
   the Mac. If there is nothing after 3 minutes: power off, read `pf1007l-log/` on the card (way D).
2. `dmesg | grep -i -E 'axp|regulator|mmc1|sdio'`, then `cat /sys/bus/sdio/devices/*/uevent`.
   Gate (from `wifi/README.md` §9): `SDIO_ID=C8A1:C08D`.
   If there is no card: the host does not scan a non-removable slot again, and it turns the
   power off. To run the power sequence again, unbind and bind the host
   (`echo 1c10000.mmc > /sys/bus/platform/drivers/sunxi-mmc/unbind`, then `…/bind`)
   [UNCONFIRMED: sysfs names from memory].
3. `modprobe pwm-sun4i`, then `echo 0 > /sys/class/backlight/backlight/bl_power`. Gate: the backlight
   glows. This tests the PWM, PH6 and DC1SW with no DSI.
4. `echo 0x1e > /sys/module/drm/parameters/debug`, then, one at a time with `dmesg` after each:
   `modprobe panel-jadard-jd9365da-h3`, `modprobe sun6i_mipi_dsi`,
   `modprobe -a sun4i-frontend sun4i-backend sun6i_drc sun4i-tcon`, `modprobe sun4i-drm`.
5. Gate: `cat /sys/class/drm/card*-DSI-1/status` = `connected`, and a picture (the text console).
   Read `grep -E 'pll-video|pll-mipi|lcd-ch0|dsi' /sys/kernel/debug/clk/clk_summary` (R4).
6. `modprobe lima`, then `dmesg | grep -i lima`.
7. Touch: `dmesg | grep -i silead` (`dumps/touch/README.md` §8).
8. When all gates pass: change to `cmdline-stage2.txt`.

Files that the boot card needs from other work: `/usr/lib/firmware/silead/gsl_m86_hd.fw`
(`dumps/touch/`, do not publish), the Wi-Fi modules and firmware (`wifi/README.md` §6 and §9), and
the `zImage` of `linux-armv7 7.2.10-1` (SHA-256 of the package: `b49a4d4d…de6ebca`). A different
kernel release does not load our module.

## 13. Open points (part 2)

| # | Open point | How to close it |
|---|---|---|
| 1 | The module has never probed a panel. The DTBs have never booted | First boot, section 12 |
| 2 | PL2 as a fixed regulator with 150 ms: not tested. The assumption "a longer wait is safe" has no datasheet behind it | SDIO ID gate. If the card is absent: build with `-DPF1007L_WIFI_PWRSEQ_TWO_PINS`, or change the delay |
| 3 | DLDO1 / DLDO2 always on: the vendor order, but which rail is the IO supply is not known | Meter, or the SDIO ID gate |
| 4 | AXP GPIO0 hog: works in an emulator with an AXP221. Not tested on the AXP223 / RSB. What the pin switches is not known | `cat /sys/kernel/debug/gpio` on the frame; meter |
| 5 | dt-schema finding 3 (hog not in the AXP GPIO binding) | Only for upstream work |
| 6 | CPU supply switch: DCDC3 is from the vendor software, not measured. No ramp delay | Register 0x22 / 0x23 test on Android, then build with `-DPF1007L_CPU_DVFS_DCDC3` |
| 7 | Touch size, axes, chip ID | `evtest` (`dumps/touch/README.md` §8) |
| 8 | The two reports disagree on the PL2 → PL6 wait. This file says 5 ms and gives the arithmetic. The reports are not changed | The owner of `dumps/vendor-facts/README.md` can correct the 125 ms line |
| 9 | U-Boot `CONS_INDEX=5` drives PL2 | U-Boot work: section 11 |
| 10 | PB0/PB1 pads on the PCB | Look at the board. If found: `-DPF1007L_UART0_ON_PB_PINS` |
| 11 | USB gadget on this musb in peripheral-only mode; macOS drivers for `g_cdc`; `console=ttyGS0`; `modprobe.blacklist=` with `modules-load.d` | First boot. Way D is the fallback |
| 12 | A kernel package update breaks the module (vermagic, CRCs) | `IgnorePkg`, or run `build.sh` with the new version and hashes |
| 13 | `kernel/out/` is not in `.gitignore` (`wifi/out/` is). The files have no serial and no MAC address | Owner's decision |
| 14 | `build.sh` does not fetch the full bindings tree. `dtbs_check.sh` needs it in `refs/kernel/linux-7.2.10/Documentation/devicetree/bindings` (it prints the two commands) | Only for the schema check |
| 15 | All risks R1 to R12 and R14, R15 of section 4 | Hardware |

## 14. Files (part 2)

| Path | Content |
|---|---|
| `kernel/build.sh` | Builds the module and the two DTBs from a clean state, with all controls. Pinned: tag `v7.2.10` + 19 file hashes, image digest, the two package hashes |
| `kernel/sources-v7.2.10.sha256` | SHA-256 of each v7.2.10 file that the build uses |
| `kernel/out/` | `panel-jadard-jd9365da-h3.ko`, `sun8i-a33-pf1007l.dtb`, `sun8i-a33-pf1007l-uart0-sd.dtb`, `SHA256SUMS` |
| `kernel/config-audit.md` | The stock config audit and the verdict |
| `kernel/patches/v7.2.10/0001-*.patch` | The panel patch against Linux v7.2.10 (this is what is built) |
| `kernel/patches/0001-*.patch` | The panel patch against master (for upstream work; not built) |
| `kernel/tools/check_dtb.py` | Project rules on the binary DTBs |
| `kernel/tools/dtbs_check.sh` | dt-schema check with the upstream control |
| `kernel/tools/qemu_loadtest.sh`, `qemu_loadtest.sha256` | Module load test on the stock kernel in QEMU, with the wrong-CRC control |
| `kernel/tools/qemu_axp_hog_test.sh` | AXP GPIO hog test on the stock kernel in QEMU |
| `kernel/bootcard/` | Draft command lines, `modules-load.d`, `modprobe.d`, `usb0` network file, boot-log script and service |
| `kernel/logs/` | `panel-build.log`, `panel-modinfo.txt`, `dtb-build.log`, `dtb-w2.log`, `dtb-rules.log`, `dtbs-check.log`, `dtbs-check-negative-control.log`, `qemu-loadtest-orangepi-pc.log`, `qemu-axp-hog-bpim2u.log`, `00-control-master-driver-on-7.2.10.log`, `regen-patch.log`, `sources-check.log` |
| `refs/kernel/` (git-ignored) | `linux-7.2.10/` (pinned files, the bindings tree, the sources that this part cites), `pkgcache/` (the two kernel packages, busybox), `stock/` (config, `Module.symvers`), build and test trees. 170 MB |
