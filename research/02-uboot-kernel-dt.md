# 02 — Mainline U-Boot + Linux kernel + device tree for the PF1007L (Allwinner A33)

Research date: 2026-10-12. Scope: boot chain, kernel, DTS. Not covered here: rootfs, Omarchy
packaging, Hyprland/GPU stack, RAM tuning (other agents).

Tags: **[VERIFIED]** = read in source code or primary doc (path/URL given). **[DOCUMENTED]** =
secondary source. **[UNCONFIRMED]** = inference. Source trees read:

- Linux `torvalds/linux` master at `24a19b95` (= **v7.3-rc7**, 2026-10-11), sparse clone at
  `scratchpad/repos/linux`.
- U-Boot `u-boot/u-boot` master at `5e3b01c8` (2026-10-10), clone at `scratchpad/repos/u-boot`.
- Wes Bos repo at `scratchpad/repos/photo-frame-dashboard`.
- ALARM PKGBUILDs (`core/linux-armv7`, Linux **7.2.10**) at `scratchpad/repos/alarm-pkgbuilds`.
- pmaports mirror (`external-mirrors/pmaports`, 2026-10-12) at `scratchpad/repos/pmaports`.
- linux-sunxi wiki archive (`HashSource/linux-sunxi-archive`) at `scratchpad/repos/linux-sunxi-archive`.

---

## 1. Summary (5 bullets)

1. **Mainline U-Boot already runs on this exact board.** Wes's repo boots U-Boot v2025.10 on a
   PF1007L from FEL (USB) and from the SD card. It uses DRAM 456 MHz, ZQ 15291, eMMC on MMC2,
   based on `q8_a33_tablet` / `Sinlinx_SinA33`. **Units differ:** one unit (PR #6) needed a DRAM
   byte-lane-0 retrain patch, a warm-up DRAM init, and 4-bit/26 MHz eMMC; another did not. Display in U-Boot was kept OFF (pins not
   known). The Boot ROM reads the TF slot first, so all bring-up can happen from SD with the
   eMMC (Android) untouched. [VERIFIED: `docs/allwinner-a33-mainline-uboot.md`,
   `docs/allwinner-a33-sdcard-adb-wifi.md`, `scripts/a33-uboot/pf1007l-uboot.patch`]
2. **Every SoC block has a mainline driver — the Wi-Fi chip does not.** CPU/cpufreq, AXP223
   (RSB), MMC/eMMC, display engine (sun4i-drm DE1: backend+TCON0) with **RGB, LVDS (since v5.7)
   and MIPI-DSI**, lima (Mali-400 MP2), audio codec, thermal (via GPADC), PWM backlight, USB OTG
   (musb), LRADC keys: all mainline. **Wi-Fi is AIC8800DC on SDIO, NOT RTL8723CS** (the `8723cs`
   in the product name is a vendor leftover): Android loads `aic8800_fdrv.ko` and reads
   `aic_userconfig_8800dc.txt` [DOCUMENTED: Wes PR #6 `pf1007l/README.md`, PR #15]. **There is no
   AIC8800 driver in mainline v7.3-rc7** [VERIFIED: full tree listing, MAINTAINERS,
   `sdio_ids.h`]. Best out-of-tree option: **Radxa `aic8800-sdio-dkms`**, patched up to Linux
   7.3, ships AIC8800DC firmware; a 32-bit armhf build on 6.x/7.x is plausible but **not
   confirmed by anyone** (see §2b).
3. **The one unknown that blocks the display is the panel interface.** The panel is **natively
   800x1280, used rotated** to 1280x800 [DOCUMENTED: PR #6]. LVDS (`lcd_if=3`) is likely but
   unconfirmed. LVDS = easy (generic `panel-lvds` + timings). DSI = hard (needs a panel driver
   with the vendor init sequence, and U-Boot cannot light it). The DE1 backend has **no
   rotation** [VERIFIED], so the compositor must rotate every frame. Read `lcd_if` from the
   stock `script.bin` before any DTS work. Also unknown: touch (likely Silead GSL1680), Wi-Fi
   power GPIO, speaker amp GPIO, CPU rail.
4. **Closest upstream model: `sun8i-a33-ga10h-v1.1.dts`** (A33 10" tablet, LVDS panel in U-Boot,
   SDIO Wi-Fi on MMC1, Silead touch, AXP223) on top of `sun8i-a33.dtsi` +
   `sun8i-reference-design-tablet.dtsi`. Wes's U-Boot DTS (Q8 base + MMC2 8-bit + OTG
   peripheral + no VBUS drive) gives the eMMC/USB parts. A skeleton DTS is in §3.
5. **Kernel: do not start from `sunxi_defconfig`** (177 lines, no namespaces/zram/Wi-Fi). Start
   from **Arch Linux ARM `linux-armv7` 7.2.10 config**: it already has sun4i-drm, lima,
   panel-lvds, DSI, AXP RSB, silead/goodix/edt-ft5x06, cgroups/namespaces/BPF/seccomp/uinput,
   and the USB Wi-Fi fallback drivers (`MT7601U`, `MT76x0U`, `RTL8XXXU`, `MT7921U` = m). Add the
   board DTB and the out-of-tree AIC8800 SDIO module. Cross-build in a Linux
   container on the Mac (Docker/Colima/OrbStack), on a container volume (case-sensitive FS).
   ⚠ Cross-cutting: Hyprland hard-requires GLES ≥ 3.0 and lima is GLES 2.0 — see Risks.

---

## 2. Subsystem support table (mainline, v7.3-rc7)

Legend: **works** = driver + DT binding exist and upstream A33 boards use them. **needs work** =
driver exists, board DT/data must be written or found. **unknown** = depends on hardware not yet
identified.

| Subsystem | Status | Detail | Tag / evidence |
|---|---|---|---|
| CPU (4x A7) SMP | works | `sun8i-a23-a33.dtsi`, `ARCH_SUNXI_MC_SMP` | [VERIFIED] dtsi |
| cpufreq | works, needs data | `sun8i-a33.dtsi` OPP table 120 MHz–1.008 GHz (1.04–1.2 V). `cpufreq-dt-platdev` creates the device because cpu0 has `operating-points-v2`. Needs correct `cpu-supply` (DCDC2 vs DCDC3 — upstream disagrees, see Risks). | [VERIFIED] `sun8i-a33.dtsi`, `drivers/cpufreq/cpufreq-dt-platdev.c:230-249` |
| DRAM | works in SPL — **but varies by unit** | `CONFIG_DRAM_CLK=456`, `CONFIG_DRAM_ZQ=15291` on all tested units. Unit C (merged docs) needed nothing else. **Cal Evans' unit (PR #6): 1 GB DDR3 on a 16-bit bus, byte lane 0 comes out of reset disabled (every even byte reads 0) → patch `dram_sun8i_a33.c` to copy DX1GCR0 into DX0GCR0 and retrain; and the first DRAM init after power-on fails, a second ("warm-up") SPL run succeeds.** Size auto-detected. | [VERIFIED] Wes `pf1007l-uboot.patch`; PR #6 `frame-a33.patch` [DOCUMENTED: unmerged PR, one unit] |
| eMMC (MMC2) | works — **bus width varies by unit** | Unit C: 8-bit worked in U-Boot. PR #6 unit: "8-bit high-speed hung U-Boot mid-transfer" → `bus-width = <4>`, `max-frequency = <26000000>`. **Start Linux at 4-bit/26 MHz, raise later.** Driver compat `sun7i-a20-mmc` → no HS200. | [VERIFIED] Wes doc + dtsi; PR #6 [DOCUMENTED] |
| SD card (MMC0) | works | Reference dtsi: `cd-gpios` PB4, `vmmc=dcdc1`. Boot ROM boots from it first. | [VERIFIED] dtsi; boot order [VERIFIED] Wes route S |
| PMIC AXP223 | works | `axp20x-rsb.c` / `axp20x.c` / `axp20x_usb_power.c` support `x-powers,axp223`. Reference dtsi has the full regulator map. That the frame really has AXP223 is not yet confirmed. | driver [VERIFIED]; chip on this PCB [UNCONFIRMED] |
| Display engine (DE1 backend, FE, DRC, TCON0) | works | `sun4i-drm`: `allwinner,sun8i-a33-display-engine/-backend/-tcon`. Atomic KMS. No HDMI on A33. | [VERIFIED] `drivers/gpu/drm/sun4i/sun4i_drv.c:434`, `sun4i_tcon.c:1559` |
| Panel: parallel RGB | works | Q8 tablets / SinA33 use it (`lcd_rgb666_pins`). Unlikely for 10.1" 1280x800. | [VERIFIED] |
| Panel: LVDS | works since **v5.7**, needs DT | `sun8i_a33_quirks.supports_lvds = true`. **The TCON only takes the LVDS path if the panel node is `compatible = "...", "panel-lvds"`** — a `panel-simple` compatible goes down the RGB path. No LVDS pin group in the A33 dtsi: add PD18–PD27 `function = "lvds0"`. 18- and 24-bit both handled. No upstream A33 board uses LVDS in Linux (GA10H uses it only in U-Boot). | [VERIFIED] `sun4i_tcon.c:1251-1263, 425-480`, `pinctrl-sun8i-a33.c:213+`, v5.6/v5.7 diff |
| Panel: MIPI-DSI | driver works, **needs work** | `sun6i_mipi_dsi` (A31 compat) + `sun6i-a31-mipi-dphy`; `dsi`/`dphy` nodes exist in `sun8i-a33.dtsi` (disabled). **No upstream A33/R16 board enables DSI.** Needs a panel driver carrying the vendor init sequence. U-Boot cannot drive DSI → no boot splash, no simplefb. linux-sunxi A33_Q7 page: "Mainline Kernel OK … but not support DSI LCD" (old). | [VERIFIED] dtsi/grep; [DOCUMENTED] wiki |
| Early display (simplefb) | works if LVDS/RGB | U-Boot `VIDEO_SUNXI` + `VIDEO_LCD_PANEL_LVDS` lights the panel and passes `simple-framebuffer` → `simpledrm` in Linux. Good first milestone. | [VERIFIED] `drivers/video/sunxi/lcdc.c:48-115`, `ga10h_v1_1_defconfig` |
| Backlight | works, needs data | `pwm-backlight` on PWM0 (PH0) + enable PH6 in reference dtsi. Channel, frequency, polarity from fex. | [VERIFIED] reference dtsi |
| GPU Mali-400 MP2 | kernel works | `lima` binds `arm,mali-400`; A33 OPP 144/240/384 MHz; thermal cooling maps. Userspace = Mesa lima, **OpenGL ES 2.0 only** (GPU agent). | [VERIFIED] `lima_drv.c:477`; GLES level [DOCUMENTED] |
| Video decode | works | `cedrus` (`allwinner,sun8i-a33-video-engine`). | [VERIFIED] dtsi |
| **Wi-Fi AIC8800DC (SDIO on MMC1)** | **no mainline driver** | Not in v7.3-rc7. Out-of-tree vendor driver (`aic8800_bsp` + `aic8800_fdrv`) only. SDIO ID in the vendor header: vendor `0xc8a1`, device `0xc08d`. No MAC in efuse → random MAC each load. Details §2b. | absence [VERIFIED]; chip [DOCUMENTED: Wes PR #6/#15]; IDs [VERIFIED: `walnutpi/aic8800_sdio/src/aic8800_fdrv/aicwf_sdio.h:85-89`] |
| ~~RTL8723CS~~ | not fitted | `rtw88_8723cs` (mainline since v6.10) would have worked — kept here only to stop the next reader from following the product name. | [VERIFIED] driver exists; [DOCUMENTED] chip is not on this board |
| Bluetooth (AIC8800DC BT) | unknown | Vendor `aic8800_btlpm` module; wiring unknown; not needed. | [UNCONFIRMED] |
| USB Wi-Fi dongle (fallback) | drivers work; **port is the problem** | Mainline: `mt7601u`, `mt76x0u`, `rtl8xxxu` (incl. RTL8188EU), `mt7921u` — all `=m` in ALARM. But the only port is USB-C in device mode, and the frame takes its power from it. See §2b. | drivers [VERIFIED]; port use [UNCONFIRMED] |
| Audio codec + speaker | works, needs data | `sun8i-a33-codec` + `sun8i-codec-analog` + `simple-audio-card` (in `sun8i-a33.dtsi`, disabled). Speaker amp enable GPIO from fex. Wes: speaker works on Android. | [VERIFIED] driver + dtsi |
| Thermal | works | A33 THS is driven by `sun4i-gpadc-iio` (`CONFIG_SUN4I_GPADC`), not `sun8i_thermal`. Zones in dtsi. | [VERIFIED] grep `sun8i-a33-ths` |
| Touch: Silead GSL | works, needs **firmware** | `silead.c` (`gsl1680/1688/3670/3675/3692`); firmware file `silead/<firmware-name>` must be extracted from the Android `gslX680*.ko` (onitake/gsl-firmware `fw_extractor`). | [VERIFIED] `silead.c:592-634`; tool [DOCUMENTED] |
| Touch: Goodix GT9xx | works | `goodix.c`, no firmware file needed. | [VERIFIED] |
| Touch: FocalTech FT5x | works | `edt-ft5x06.c` (`focaltech,ft5426`, `edt,edt-ft5406`…). | [VERIFIED] |
| Touch: Chipone ICN85xx | works, needs firmware | `chipone_icn8505.c` (ACPI-only?) / `chipone_icn8318.c`. | [VERIFIED] files exist; DT support of 8505 [UNCONFIRMED] |
| Touch: which one is fitted | **unknown** | Read `ctp_name` from fex / `lsmod` / i2c names. | — |
| USB OTG (musb) | works | Frame is powered FROM the host via the one USB-C port. Use `dr_mode = "peripheral"`, remove VBUS drive + ID detect (Wes proved this enumerates). USB gadget (NCM/ECM) gives a network link to the Mac. | [VERIFIED] Wes patch |
| USB host | unknown | EHCI0/OHCI0 exist on SoC; whether a host port is wired is unknown. | [UNCONFIRMED] |
| Buttons | needs data | LRADC keys + AXP power key (`axp20x-pek`). Frame has one power/reset button. | [VERIFIED] drivers; wiring [UNCONFIRMED] |
| RTC | works | `sun8i-a23-rtc` (needs AXP RTC LDO / battery to keep time when unplugged — probably no battery). | [VERIFIED] dtsi |
| Serial console | needs work | Reference DT uses `r_uart` (PL2/PL3, pads unknown). **Alternative with no soldering: UART0 on the SD-slot pins (PF2/PF4) with a MicroSD breakout, booting via FEL** (U-Boot `CONFIG_UART0_PORT_F`; kernel `uart0_pf_pins`). | [VERIFIED] U-Boot `arch/arm/mach-sunxi/Kconfig:905`, dtsi `uart0_pf_pins` |


### 2b. Wi-Fi: AIC8800DC (correction) — status, drivers, DT needs, fallback

**What the chip is.** Wes PR #6 (`pf1007l/README.md`, Cal Evans' unit): "AIC8800
(`aic8800_fdrv`), 2.4 GHz. No MAC in efuse, so the driver randomizes the last 2 bytes each
load". PR #15 (two more units): `insmod aic8800_fdrv.ko` in the boot log and
`/system/vendor/modules/aic_userconfig_8800dc.txt` → the **DC** variant. Two independent PRs, same
firmware build → [DOCUMENTED]. Confirm with `lsmod` + SDIO ID on your unit.

**Mainline status: none.** No `aic*` path anywhere in Linux v7.3-rc7, nothing in `MAINTAINERS`, no
AIC entry in `include/linux/mmc/sdio_ids.h` [VERIFIED: full `git ls-tree` of the v7.3-rc7 tree;
raw `MAINTAINERS`/`sdio_ids.h`]. No upstream submission found [scoped: web search; lore not
reachable here].

**Out-of-tree drivers (all are the same AICSemi vendor code, `aic8800_bsp` + `aic8800_fdrv` (+
`aic8800_btlpm`), all contain 8800DC code paths `aic8800dc_compat.*`):**

| Source | Bus | Newest kernel it claims / guards | Notes | Tag |
|---|---|---|---|---|
| **`radxa-pkg/aic8800`** (`aic8800-sdio-dkms`, `-usb-`, `-pcie-`) | SDIO+USB+PCIe | `debian/patches/fix-linux-6.1 … 6.19, 7.1, 7.2, 7.3-build.patch`; commit 2026-10-12 | **Best maintained.** Ships `firmware/aic8800DC/*` (fmacfw/patch tables, `aic_userconfig_8800dc.txt`). Generic `CONFIG_PLATFORM_UBUNTU=y` (no BSP power hooks). DKMS `Architecture: all`; Makefile maps `armv7l → ARCH=arm`. Has "build on low-memory devices" patches. | [VERIFIED: clone] |
| `nickyg666/orangepi-zero3w-aic8800` | SDIO | 7.3-rc2, "WORKING 2026-10-11" | arm64 (Allwinner A733) only; adds a fix for dropped DBG confirms (`rwnx_msg_rx.c`) — may matter for any build | [VERIFIED: README; hardware claim DOCUMENTED] |
| `LYU4662/aic8800-sdio-linux-1.0` | SDIO | guards to 6.7 | H618 (arm64), kernel 6.7.12 | [VERIFIED: grep] |
| `walnutpi/aic8800_sdio`, `0x754C/aic8800-sdio-linux`, `shawnchain/aic8800-drv` | SDIO | guards to 6.3 | older vendor drops | [VERIFIED: grep] |
| `Kiborgik/aic8800dc-linux-patched`, AUR `aic8800d80-dkms`, Gentoo `net-wireless/aic8800` | **USB** | 6.2–7.2 | USB dongles (TP-Link TX1U etc.); not our SDIO part | [DOCUMENTED] |

**32-bit armhf on 6.x/7.x: not confirmed by anyone.** Evidence for: the vendor Makefile's own
historic targets are 32-bit ARM (`KDIR … Rockchip/3126/Android6`, `ARCH ?= arm`), and the frame
itself runs `aic8800_fdrv` on a 32-bit 3.4 kernel [VERIFIED: Radxa Makefile lines 36-37; Wes PR #15].
Evidence missing: no repo or forum post found that builds it for `ARCH=arm` against 6.x/7.x
[scoped: GitHub repo search "aic8800 sdio" (12 hits, all arm64/x86 targets) + web search]. Typical
32-bit breakages to expect: 64-bit division (`__aeabi_uldivmod` link errors), pointer↔`u32` casts,
`%lx` with `u64`. **First concrete test (no hardware needed):** build `aic8800_bsp` + `aic8800_fdrv`
from Radxa's tree (patches applied) as an external module against the chosen kernel with
`ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=…`. Not run here (the brief forbids running
downloaded build systems).

**Power/DT for the SDIO part.** The vendor driver in `PLATFORM_UBUNTU` mode binds by SDIO ID
(`c8a1:c08d` for 8800DC per `aic8800_fdrv/aicwf_sdio.h:85-89`) and does not read DT for power or
MAC [VERIFIED: no `of_*` calls in Radxa `aic8800_fdrv`/`aic8800_bsp` except BT-LPM]. In
`PLATFORM_ALLWINNER` mode it calls BSP-only `sunxi_wlan_set_power()` / `sunxi_mmc_rescan_card()`,
which do not exist in mainline — **use the Ubuntu/generic mode** [VERIFIED: `aicsdio.c:31-33, 487-519`].
So the DT must, by itself:
- enable `&mmc1` (PG0–PG5, 4-bit, `non-removable`, ≤ 50 MHz on `sun7i-a20-mmc`);
- give `vmmc-supply` (reference: DLDO1 3.3 V "vcc-wifi") and, if needed, `vqmmc-supply`;
- release **WL_REG_ON** through `mmc-pwrseq-simple` `reset-gpios` (pin from fex
  `[wifi_para]`/`[wlan]`, usually a PLn on `r_pio`), with a post-power-on delay;
- optionally a 32 kHz clock (`<&rtc 1>` = "osc32k-out") and a host-wake IRQ — both unknown;
- MAC: the driver uses a fixed prefix + 2 random bytes (`rwnx_main.c:5844`) → pin it in
  userspace (systemd-networkd `.link MACAddress=` or NetworkManager), or patch one line.

**Fallback: USB Wi-Fi dongle.** Mainline drivers that suit USB 2.0: `mt7601u` (MT7601U, 2.4 GHz
1x1), `mt76x0u` (MT7610U, dual-band), `rtl8xxxu` (RTL8188EU/8192EU/8188FU/8723BU…), `mt7921u`
(Wi-Fi 6) — all `=m` in ALARM `linux-armv7` 7.2.10 [VERIFIED: config + `rtl8xxxu/Kconfig`].
**The hard part is the port, not the driver.** The only port is USB-C, used in device mode,
and the frame is powered *through* it (no CC resistors; A-to-C cable only) [VERIFIED: Wes docs].
A dongle needs the port in host mode **and** 5 V supplied to the dongle while the frame is also
powered. Options, all [UNCONFIRMED]: (a) `dr_mode = "host"` + a powered hub that back-feeds its
upstream port (most hubs do not); (b) the DC-jack variant (Unit A) has a separate OTG port —
easier; (c) open the case and use the SoC's second USB host (EHCI0/OHCI0, `usb1` PHY) if pads
exist. Host mode also removes USB-gadget networking to the Mac. Also note PR #15: a hub-powered
unit froze at `insmod aic8800_fdrv.ko` on first boot while a wall-powered one did not — a hint
that the USB power budget is tight [DOCUMENTED].

---

## 3. Closest upstream DTS + skeleton DTS

### 3.1 What to build on (all read in `linux/arch/arm/boot/dts/allwinner/`)

| File | Use it for | Notes |
|---|---|---|
| `sun8i-a23-a33.dtsi` | SoC base | MMC0/1/2, I2C0-2, TCON0 (with `lvds-alt` clock + `lvds` reset already), DE, Mali, RSB, R_PIO, pin groups. **No LVDS pin group** — add one. |
| `sun8i-a33.dtsi` | A33 overlay | OPPs, DSI/D-PHY, codec, THS, A33 compatibles, `tcon0_out` endpoint@1 → DSI. |
| `sunxi-reference-design-tablet.dtsi` | tablet commons | I2C0/1 on, LRADC volume keys, PWM0. |
| `sun8i-reference-design-tablet.dtsi` | **A23/A33 tablet board model** | `pwm-backlight` (PWM0, enable PH6, supply DC1SW), I2C0 400 kHz touchscreen@40 (irq PB5, power PH1), MMC0 cd PB4, **AXP223 on RSB @0x3a3 with full regulator map**, OTG + PH8 ID + drive-VBUS. |
| `sun8i-a33-ga10h-v1.1.dts` | **closest board** | A33 10" tablet: SDIO Wi-Fi (RTL8703AS there) on MMC1 + `ethernet0` alias for MAC, Silead GSL3675 touch with firmware-name and size, EHCI/OHCI. No Linux panel node (relies on U-Boot simplefb). U-Boot side: `ga10h_v1_1_defconfig` drives an **LVDS** panel. |
| `sun8i-q8-common.dtsi` | panel/Wi-Fi pattern | Panel node with PH7 enable, wifi `mmc-pwrseq-simple`, PL pins. **Do not include it**: it forces `lcd_rgb666_pins` on TCON0. |
| `sun8i-a83t-tbs-a711.dts` | **LVDS panel pattern** | `compatible = "tbs,a711-panel", "panel-lvds"`, `data-mapping`, `panel-timing`, `lcd_lvds_pins` PD18–PD27 `lvds0`. Same `sun4i_tcon` driver. |
| `sun8i-a33-sinlinx-sina33.dts` | audio + OPP pattern | `&codec/&dai/&sound` okay, extra OPPs, `cpu-supply = <&reg_dcdc3>`. |
| Wes: `scripts/a33-uboot/pf1007l-uboot.patch` (U-Boot DTS) | eMMC/USB facts for THIS PCB | MMC2 8-bit non-removable `cap-mmc-hw-reset`, OTG peripheral, delete `usb0_vbus-supply` and `usb0_id_det-gpios`. |

### 3.2 Turning the Android `script.bin` (sys_config.fex) into DT

The stock kernel is an Allwinner 3.4 BSP kernel; board data lives in `script.bin`, not DT.
Get it, then run `bin2fex script.bin board.fex` (sunxi-tools, already cloned at
`scratchpad/repos/sunxi-tools`). Ways to get it, cheapest first:

1. **From RAM on the running Android (root ADB exists via Wes's routes):** `script_extractor`
   (sunxi-tools, `script_extractor.c`) maps `/dev/mem` at **0x43000000, 0x20000 bytes**. Build it
   static for armv7. [VERIFIED: source lines 26-36]. linux-sunxi says it works on A33
   [DOCUMENTED: whycan.com thread, wiki]. One wiki page shows the result can have bogus entries on
   some BSPs [DOCUMENTED: Ditter_v21] — sanity-check the output.
2. **From FEL** right after a normal stock boot attempt: `sunxi-fel read 0x43000000 0x20000
   script.bin` [DOCUMENTED: wiki "Retrieving device information"; caveat: only valid if boot1
   loaded it].
3. **From the eMMC backup** (Wes's full dump): sys_config is packed in the boot package/u-boot
   area. [UNCONFIRMED: location on sun8iw5 Android 6]. Search the dump for section names
   (`lcd0`, `ctp`, `wlan`).

No maintained automatic converter exists for **mainline** bindings. `SdtElectronics/FEX2DTS`
targets Allwinner's BSP-style DT, is unverified by its author. Do it by hand. [VERIFIED: README]

**Mapping table** (fex key → DT). Fex semantics from `Fex_Guide.md` [DOCUMENTED]; TCON math from
`sun4i_tcon.c` [VERIFIED].

| Fex key (`[lcd0]`) | DT / U-Boot | Rule |
|---|---|---|
| `lcd_if` | choose branch | 0 = parallel RGB (HV), 3 = **LVDS**, 4 = **DSI** (A31+ native), 6 = external DSI bridge |
| `lcd_x`, `lcd_y` | `hactive`, `vactive` | If x<y (800x1280) the panel is native portrait → see Risks |
| `lcd_dclk_freq` (MHz) | `clock-frequency` (Hz) / U-Boot `pclk_khz` | ×1e6 / ×1000 |
| `lcd_hspw` (or `lcd_hv_hspw`) | `hsync-len` / U-Boot `hs` | as is (min 1) |
| `lcd_hbp` | `hback-porch` = `lcd_hbp − lcd_hspw` / U-Boot `le` | **Allwinner "back porch" includes the sync width** (`sun4i_tcon.c` comment: "really is the back porch + hsync") |
| `lcd_ht` | `hfront-porch` = `lcd_ht − lcd_x − lcd_hbp` / U-Boot `ri` | |
| `lcd_vspw`, `lcd_vbp`, `lcd_vt` | `vsync-len`, `vback-porch` = vbp − vspw, `vfront-porch` = vt − y − vbp / U-Boot `vs`,`up`,`lo` | **`lcd_vt` may be ×2** (wiki: "vsync total cycle * 2" on older BSPs). Control: compute `dclk / (ht × vt)`; it must give ≈ 60 Hz. If ≈ 30 Hz, halve vt. |
| `lcd_lvds_bitwidth` (0=24, 1=18) + `lcd_lvds_mode` (0=NS/VESA, 1=JEIDA) | `data-mapping` | 24+NS → `"vesa-24"`; 24+JEIDA → `"jeida-24"`; 18 → `"jeida-18"`. U-Boot `depth:18` or `24`. |
| `lcd_lvds_ch` / `lcd_lvds_if` | must be single link | A33 has one LVDS link [UNCONFIRMED but only one lvds0 pin group exists: VERIFIED] |
| `lcd_pwm_ch`, `lcd_pwm_freq`, `lcd_pwm_pol` | `pwms = <&pwm CH PERIOD_NS POL>` | period = 1e9 / freq |
| `lcd_bl_en` | backlight `enable-gpios` | `port:PH06<1>…` → `<&pio 7 6 GPIO_ACTIVE_HIGH>` (PA=0 … PH=7; PL → `&r_pio 0 N`) |
| `lcd_power` / `lcd_power1` / `lcd_gpio_N` | panel `power-supply` / `enable-gpios` | a string like `"axp22_dc1sw"` = regulator `reg_dc1sw`; a `port:` = GPIO |
| `lcd_driver_name`, `lcd_model_name` | DSI only | names the vendor init code you must port |
| `[ctp]` `ctp_name`, `ctp_twi_id`, `ctp_twi_addr` | touchscreen node: bus `&i2cN`, `reg`, `compatible` | `gslX680`→silead, `gt9xx`→goodix, `ft5x_ts`→edt-ft5x06 |
| `ctp_int_port`, `ctp_wakeup` | `interrupts` (+`interrupt-parent=<&pio>`), `power-gpios`/`reset-gpios` | |
| `ctp_screen_max_x/y`, `ctp_revert_x/y_flag`, `ctp_exchange_x_y_flag` | `touchscreen-size-x/y`, `touchscreen-inverted-x/y`, `touchscreen-swapped-x-y` | |
| `[wlan]`/`[wifi_para]` `wl_reg_on`, `wlan_power` | `mmc-pwrseq-simple` `reset-gpios`, MMC1 `vmmc-supply` | PL pins are on `&r_pio` |
| `[audio0]` `audio_pa_ctrl` / `pa_shutdown` | `simple-audio-amplifier` `enable-gpios` | |
| `[pmu1_para]`, `[power_sply]`, `[dvfs_table]` | regulator voltages, `cpu-supply`, OPP list | |
| `[dram_para]` `dram_clk`, `dram_zq` | U-Boot `DRAM_CLK`, `DRAM_ZQ` | cross-check Wes's 456 / 15291 |

### 3.3 Skeleton DTS (LVDS branch; DSI branch in comments)

File: `arch/arm/boot/dts/allwinner/sun8i-a33-pf1007l.dts`. Every `XX`/`TODO(fex: …)` is a value to
read off the device. The defaults already match the access agent's best guesses (PWM0/PH0 backlight with PH6
enable, GSL1680 @0x40 on TWI0 with INT PB5 / reset PH1, AXP223 on RSB, UART0 on PF2/PF4) — which
are the Q8 reference values, so agreement is not independent confirmation. Status: **not compiled, not tested** [UNCONFIRMED].

```dts
// SPDX-License-Identifier: (GPL-2.0+ OR MIT)
/*
 * Humblestead HM-PF1007-BK photo frame, EFERCRO PF1007L_MB_V1.0, Allwinner A33.
 * Base: sun8i reference tablet (AXP223, PWM0 backlight, I2C0 touch).
 * Facts from wesbos/photo-frame-dashboard: eMMC MMC2 8-bit, USB-C powers the frame.
 */
/dts-v1/;
#include "sun8i-a33.dtsi"
#include "sun8i-reference-design-tablet.dtsi"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/interrupt-controller/irq.h>
#include <dt-bindings/pwm/pwm.h>

/ {
	model = "Humblestead HM-PF1007-BK (PF1007L)";
	compatible = "efercro,pf1007l", "allwinner,sun8i-a33";

	aliases {
		mmc0 = &mmc0;
		mmc1 = &mmc2;		/* eMMC */
		/* U-Boot writes a SID-derived local-mac-address here. The vendor AIC8800
		 * driver does NOT read it [VERIFIED: no of_get_mac_address in Radxa aic8800_fdrv; rwnx_main.c:5844 randomises bytes 4-5] -> pin the
		 * MAC in userspace instead (systemd .link MACAddress= / NM cloned-mac). */
		ethernet0 = &wifi;
	};

	/* Overrides the reference-dtsi backlight node */
	backlight: backlight {
		compatible = "pwm-backlight";
		pwms = <&pwm 0 50000 PWM_POLARITY_INVERTED>;	/* TODO(fex: lcd_pwm_ch, 1e9/lcd_pwm_freq, lcd_pwm_pol) */
		brightness-levels = <0 10 20 30 40 50 60 70 80 90 100>;
		default-brightness-level = <8>;
		enable-gpios = <&pio 7 6 GPIO_ACTIVE_HIGH>;	/* TODO(fex: lcd_bl_en) PH6 on reference */
		power-supply = <&reg_dc1sw>;			/* TODO(fex: lcd_power) */
	};

	panel: panel {
		/* LVDS branch (fex lcd_if = 3). Keep "panel-lvds": sun4i_tcon only picks
		 * the LVDS encoder when the remote node is compatible with "panel-lvds". */
		compatible = "efercro,pf1007l-panel", "panel-lvds";
		backlight = <&backlight>;
		power-supply = <&reg_dc1sw>;			/* TODO(fex: lcd_power) */
		enable-gpios = <&pio 7 7 GPIO_ACTIVE_HIGH>;	/* TODO(fex: lcd_gpio_0 / lcd_power1) PH7 on Q8 */
		width-mm = <217>;				/* TODO: measure / panel datasheet */
		height-mm = <136>;
		data-mapping = "vesa-24";			/* TODO(fex: lcd_lvds_bitwidth + lcd_lvds_mode) */

		panel-timing {
			/* PR #6: the panel is natively 800x1280 (portrait), used rotated. Expect
			 * lcd_x=800, lcd_y=1280 in the fex; then swap hactive/vactive below.
			 * 1280x800@60, placeholders in the range of a typical 10.1" WXGA LVDS
			 * panel (cf. hannstar,hsd101pww2: 64.3-82 MHz). Replace from fex. */
			clock-frequency = <71000000>;	/* TODO(fex: lcd_dclk_freq) */
			hactive = <1280>;	/* likely 800 (native portrait) */
			vactive = <800>;	/* likely 1280 */
			hsync-len = <XX>;		/* lcd_hspw */
			hback-porch = <XX>;		/* lcd_hbp - lcd_hspw */
			hfront-porch = <XX>;		/* lcd_ht - lcd_x - lcd_hbp */
			vsync-len = <XX>;		/* lcd_vspw */
			vback-porch = <XX>;		/* lcd_vbp - lcd_vspw */
			vfront-porch = <XX>;		/* lcd_vt(/2?) - lcd_y - lcd_vbp */
			de-active = <1>;
		};

		port {
			panel_input: endpoint {
				remote-endpoint = <&tcon0_out_lcd>;
			};
		};
	};

	/* DSI branch (fex lcd_if = 4): delete the panel node above and the
	 * &tcon0 pinctrl below, then:
	 *   &dphy { status = "okay"; };
	 *   &dsi  { status = "okay";
	 *           panel@0 { compatible = "<vendor>,<panel>"; reg = <0>;
	 *                     backlight = <&backlight>; reset-gpios = <...>;
	 *                     power-supply = <...>; }; };
	 * tcon0_out endpoint@1 -> dsi already exists in sun8i-a33.dtsi.
	 * Needs a panel driver with the init sequence from the 3.4 BSP
	 * (fex lcd_driver_name). */

	wifi_pwrseq: pwrseq {
		compatible = "mmc-pwrseq-simple";
		reset-gpios = <&r_pio 0 XX GPIO_ACTIVE_LOW>;	/* TODO(fex: wl_reg_on, a PLn pin) */
		post-power-on-delay-ms = <50>;			/* TODO: tune */
	};

	speaker_amp: audio-amplifier {
		compatible = "simple-audio-amplifier";
		enable-gpios = <&pio XX XX GPIO_ACTIVE_HIGH>;	/* TODO(fex: audio pa_ctrl) */
		sound-name-prefix = "Speaker Amp";
	};
};

/* ---- CPU / power ---- */
&cpu0 {
	cpu-supply = <&reg_dcdc3>;	/* TODO(fex: dvfs / pmu): reference dtsi says dcdc2, SinA33 says dcdc3 */
};

/* Until the CPU rail is confirmed, drop the 1.2 V OPPs to be safe */
&cpu0_opp_table {
	/delete-node/ opp-912000000;
	/delete-node/ opp-1008000000;
};

&battery_power_supply {
	status = "disabled";		/* TODO: no battery on the USB-C unit? check /sys/class/power_supply */
};

&ac_power_supply {
	status = "disabled";		/* enable only on the DC-jack variant (Unit A) */
};

/* ---- Storage ---- */
&mmc2 {					/* eMMC, from Wes's verified U-Boot DTS */
	pinctrl-names = "default";
	pinctrl-0 = <&mmc2_8bit_pins>;
	vmmc-supply = <&reg_dcdc1>;
	bus-width = <4>;		/* PR #6 unit hung at 8-bit HS; 8 worked on Unit C. Start safe. */
	max-frequency = <26000000>;
	non-removable;
	cap-mmc-hw-reset;
	status = "okay";
};

/* ---- Wi-Fi: AIC8800DC on SDIO (MMC1, PG0-PG5). NO mainline driver:
 * the out-of-tree aic8800_bsp/aic8800_fdrv (Radxa DKMS, PLATFORM_UBUNTU mode)
 * binds by SDIO ID (c8a1:c08d) and does not read DT. The DT only has to
 * power the chip, release WL_REG_ON and leave the card enumerated. ---- */
&mmc1 {
	pinctrl-names = "default";
	pinctrl-0 = <&mmc1_pg_pins>;
	vmmc-supply = <&reg_dldo1>;	/* TODO(fex [wifi_para]/[wlan]: power rail, 3.3 V "vcc-wifi" on ref) */
	vqmmc-supply = <&reg_dcdc1>;	/* TODO: PG bank IO voltage (3.0/3.3 V) — confirm */
	mmc-pwrseq = <&wifi_pwrseq>;
	bus-width = <4>;
	max-frequency = <50000000>;	/* sun7i-a20-mmc: high-speed SDR25 max */
	cap-sd-highspeed;
	non-removable;
	keep-power-in-suspend;
	status = "okay";

	wifi: wifi@1 {
		reg = <1>;
		/* optional out-of-band host-wake, only if the driver is built for it:
		 * interrupt-parent = <&r_pio>; interrupts = <0 XX IRQ_TYPE_LEVEL_HIGH>;
		 * TODO(fex: wl_host_wake) */
	};
};

/* If the module needs a 32.768 kHz sleep clock (unknown for AIC8800DC on this
 * PCB), add `clocks = <&rtc 1>; clock-names = "ext_clock";` (rtc output 1 = "osc32k-out")
 * to wifi_pwrseq. [UNCONFIRMED] */

/* ---- Display ---- */
&pio {
	lcd_lvds_pins: lcd-lvds-pins {
		pins = "PD18", "PD19", "PD20", "PD21", "PD22",
		       "PD23", "PD24", "PD25", "PD26", "PD27";
		function = "lvds0";
	};
};

&de {
	status = "okay";
};

&tcon0 {
	pinctrl-names = "default";
	pinctrl-0 = <&lcd_lvds_pins>;
	status = "okay";
};

&tcon0_out {
	tcon0_out_lcd: endpoint@0 {
		reg = <0>;
		remote-endpoint = <&panel_input>;
	};
};

&simplefb_lcd {
	vcc-lcd-supply = <&reg_dc1sw>;
};

/* ---- Touch (reference dtsi already defines &touchscreen at i2c0@0x40) ---- */
&touchscreen {
	compatible = "silead,gsl1680";		/* TODO(fex: ctp_name) silead/goodix/edt */
	reg = <0x40>;				/* TODO(fex: ctp_twi_addr); move bus if ctp_twi_id != 0 */
	interrupts = <1 5 IRQ_TYPE_EDGE_FALLING>;	/* TODO(fex: ctp_int_port) PB5 on ref */
	power-gpios = <&pio 7 1 GPIO_ACTIVE_HIGH>;	/* TODO(fex: ctp_wakeup) PH1 on ref */
	firmware-name = "gsl1680-pf1007l.fw";	/* silead only; extract from Android gslX680.ko */
	touchscreen-size-x = <1280>;		/* TODO(fex: ctp_screen_max_x); panel is native portrait, so touch may report 800x1280 -> use touchscreen-swapped-x-y */
	touchscreen-size-y = <800>;
	silead,max-fingers = <5>;
	status = "okay";
};

/* ---- Audio ---- */
&codec {
	status = "okay";
};

&dai {
	status = "okay";
};

&sound {
	simple-audio-card,aux-devs = <&codec_analog>, <&speaker_amp>;
	simple-audio-card,widgets = "Speaker", "Internal Speaker";
	simple-audio-card,routing =
		"Left DAC", "DACL",
		"Right DAC", "DACR",
		"Speaker Amp INL", "LINEOUT",		/* TODO: HP vs LINEOUT from schematic/fex */
		"Speaker Amp INR", "LINEOUT",
		"Internal Speaker", "Speaker Amp OUTL",
		"Internal Speaker", "Speaker Amp OUTR";
	status = "okay";
};

/* ---- USB: the frame is powered BY the host through the only USB-C port ---- */
&usb_otg {
	dr_mode = "peripheral";
	status = "okay";
};

&usbphy {
	/delete-property/ usb0_id_det-gpios;
	/delete-property/ usb0_vbus-supply;
	status = "okay";
};

&reg_drivevbus {
	status = "disabled";
};

/* ---- Debug console without opening the case: UART0 on the SD pins via a
 * MicroSD breakout. Only when booting over FEL (SD slot is then not an SD). ----
 * &mmc0 { status = "disabled"; };
 * &uart0 { pinctrl-names = "default"; pinctrl-0 = <&uart0_pf_pins>; status = "okay"; };
 * and set aliases { serial0 = &uart0; } + chosen { stdout-path = "serial0:115200n8"; };
 */
```

Add `sun8i-a33-pf1007l.dtb` to the `CONFIG_MACH_SUN8I` list in
`arch/arm/boot/dts/allwinner/Makefile`.

---

## 4. Build steps

### 4.1 Host setup on the Mac

- Use a **Linux container or VM**: Docker Desktop, **Colima** (Wes used it on Apple silicon for
  U-Boot — [VERIFIED: `scripts/a33-uboot/build-uboot.sh`, `Dockerfile` = `ubuntu:24.04` +
  `gcc-arm-linux-gnueabihf`]), OrbStack, or Lima.
- **Build the kernel on a container volume, not a bind-mounted macOS folder.** APFS is
  case-insensitive by default; the kernel tree has paths that differ only by case (e.g.
  netfilter `xt_*` headers). Wes's U-Boot script copies `/src` to `/tmp/src` inside the container
  for the same kind of reason. [DOCUMENTED / common knowledge]
- Apple silicon cannot run AArch32 code natively. Cross-compile (`gcc-arm-linux-gnueabihf` or
  `make LLVM=1 ARCH=arm`). Running armv7 binaries (chroot) needs qemu-user (rootfs agent).
  [UNCONFIRMED: no test here]
- `sunxi-tools` (`sunxi-fel`, `bin2fex`) builds natively on macOS after
  `brew install libusb dtc pkgconf`. [VERIFIED: Wes doc §2]

### 4.2 U-Boot (SD card)

0. **Unit variance first.** Two working U-Boot recipes exist for the "same" PF1007L:
   - Merged docs (Unit C, macOS): v2025.10, Q8 base, DRAM 456/ZQ 15291, 8-bit eMMC, `ums`.
   - PR #6 (Cal Evans, unmerged): v2025.01, SinA33 base, DRAM 456 + **byte-lane-0 retrain patch**,
     **warm-up SPL** (first DRAM training after power-on fails), eMMC **4-bit 26 MHz**,
     `CONFIG_SUNXI_NO_PMIC=y`, CPU 408 MHz, video off, stdin=nulldev (floating console RX read
     as Ctrl+C), watchdog 16 s. [DOCUMENTED: `pf1007l/uboot/frame-a33.patch`,
     `frame_a33_ums_defconfig`]
   Carry the lane-0 patch in every build: it is a no-op when lane 0 is already enabled (it only
   acts if `DXnGCR0(0)` bit 0 is clear) [VERIFIED: patch text]. A boot-from-SD U-Boot cannot
   use the FEL warm-up trick; if a unit needs it, retry DRAM init inside the SPL instead
   [UNCONFIRMED].
1. Start from Wes's tested pin **v2025.10 (`e50b1e87`)** or current master (A33 DTS still
   local in `arch/arm/dts`, not `OF_UPSTREAM` — [VERIFIED]).
2. New defconfig = copy of `configs/ga10h_v1_1_defconfig` (A33 + LVDS + AXP) with:
   ```
   CONFIG_DEFAULT_DEVICE_TREE="sun8i-a33-pf1007l"   # Wes's backup DTS is a good start
   CONFIG_DRAM_CLK=456                               # verified on PF1007L
   CONFIG_DRAM_ZQ=15291
   # CONFIG_DRAM_ODT_EN is not set                   # ga10h sets it; Wes did not
   CONFIG_MMC_SUNXI_SLOT_EXTRA=2                     # eMMC on MMC2
   CONFIG_VIDEO_LCD_MODE="x:1280,y:800,depth:24,pclk_khz:<fex>,le:<hbp-hspw>,ri:<hfp>,up:<vbp-vspw>,lo:<vfp>,hs:<hspw>,vs:<vspw>,sync:3,vmode:0"
   CONFIG_VIDEO_LCD_PANEL_LVDS=y                     # only if lcd_if=3; for DSI set CONFIG_VIDEO_SUNXI off
   CONFIG_VIDEO_LCD_POWER="<fex lcd_power gpio>"
   CONFIG_VIDEO_LCD_BL_EN="<fex lcd_bl_en>"
   CONFIG_VIDEO_LCD_BL_PWM="PH0"                     # if lcd_pwm_ch=0
   # CONFIG_REGULATOR_AXP_DRIVEVBUS is not set       # frame is powered from host VBUS
   # CONFIG_USB_MUSB_HOST is not set
   CONFIG_USB_MUSB_GADGET=y                          # optional: ums/fastboot for flashing
   CONFIG_CONS_INDEX=5                               # r_uart; or CONFIG_UART0_PORT_F=y for breakout
   ```
   Keep U-Boot video OFF until the fex confirms the GPIOs — driving the wrong pin can short a
   module output (the Q8 dtsi comment on PL wifi pins says the same).
3. Build: `make CROSS_COMPILE=arm-linux-gnueabihf- <defconfig> && make -j` →
   `u-boot-sunxi-with-spl.bin`. Check the SPL end vs stack (Wes's SRAM-overlap lesson; his script
   stops if SPL code passes `0x5e00`).
4. SD card: MBR, partition 1 starts at ≥ 1 MiB (4 MiB is safer). Write U-Boot at **8 KiB**:
   `sudo dd if=u-boot-sunxi-with-spl.bin of=/dev/rdiskN bs=1024 seek=8 conv=notrunc` (macOS: use
   `/dev/rdiskN` of the positively identified card only; Wes's `fel-card-macos.py` has the guards).
5. Faster loop on units with USB data (Unit C): **boot everything over FEL** without writing
   any card:
   `sunxi-fel -v uboot u-boot-sunxi-with-spl.bin write 0x42000000 zImage write 0x43000000 pf1007l.dtb write 0x43300000 initramfs.uimg write 0x43100000 boot.scr`
   [DOCUMENTED: linux-sunxi FEL usage; addresses follow sunxi U-Boot defaults — UNCONFIRMED for
   this build]. Wes ran the same `uboot` + `write 0x43100000 script` pattern successfully.

### 4.3 Kernel

1. Source: any recent stable tree; the AIC8800 driver decides. Radxa's DKMS carries build fixes up to **7.3**. Options: **7.2.x** (matches ALARM
   `linux-armv7` 7.2.10, so its config is a drop-in base) or **6.18 LTS** (what pmOS uses).
2. Config base: `alarm-pkgbuilds/core/linux-armv7/config`. It already has [VERIFIED by grep]:
   `MACH_SUN8I, HIGHMEM, VMSPLIT_3G, CPUFREQ_DT(_PLATDEV), SUNXI_RSB, MFD_AXP20X_RSB,
   REGULATOR_AXP20X, AXP20X_POWER, CHARGER/BATTERY_AXP20X=m, INPUT_AXP20X_PEK=m,
   DRM_SUN4I=m, DRM_SUN6I_DSI=m, PHY_SUN6I_MIPI_DPHY=y, DRM_PANEL_LVDS=m, DRM_PANEL_SIMPLE=y,
   DRM_SIMPLEDRM=y, DRM_LIMA=m, DRM_FBDEV_EMULATION, BACKLIGHT_PWM, PWM_SUN4I=m,
   MMC_SUNXI, USB_MUSB_SUNXI, PHY_SUN4I_USB, SND_SUN8I_CODEC=m, SND_SUN8I_CODEC_ANALOG=m,
   SND_SUN4I_I2S=m, SUN4I_GPADC=m, KEYBOARD_SUN4I_LRADC=m, TOUCHSCREEN_SILEAD/GOODIX/EDT_FT5X06=m,
   TOUCHSCREEN_CHIPONE_ICN8318=m, INPUT_UINPUT=m, INPUT_EVDEV=m, ZRAM=m, ZSWAP, CMA (64 MB),
   CGROUPS, MEMCG, NAMESPACES, USER_NS, BPF_SYSCALL, SECCOMP, FHANDLE, AUTOFS_FS, DEVTMPFS(_MOUNT),
   TMPFS_POSIX_ACL, SYNC_FILE, PSI`.
3. Add on top (fragment for `scripts/kconfig/merge_config.sh`):
   ```
   # Wi-Fi: AIC8800DC is out of tree -> build it as an external module (4.3b).
   # Keep the USB Wi-Fi fallbacks (already =m in ALARM): MT7601U, MT76x0U, RTL8XXXU, MT7921U
   CONFIG_CFG80211=m / CONFIG_MAC80211=m   # already set; the AIC fdrv is a cfg80211 (fullmac) driver
   CONFIG_USB_CONFIGFS=m          # USB gadget network to the Mac during bring-up
   CONFIG_USB_CONFIGFS_NCM=y
   CONFIG_USB_CONFIGFS_ECM=y
   CONFIG_DMABUF_HEAPS=y          # optional (PipeWire/camera users); not required by Hyprland [UNCONFIRMED]
   CONFIG_DMABUF_HEAPS_CMA=y
   CONFIG_UDMABUF=y               # optional; not a Hyprland requirement [UNCONFIRMED]
   CONFIG_ZRAM_BACKEND_ZSTD=y     # check what ALARM sets
   # touch driver for whatever ctp_name says; CHIPONE_ICN8505 if needed
   ```
   Consider building `DRM_SUN4I`, `DRM_PANEL_LVDS`, `PWM_SUN4I`, `DRM_LIMA` as `=y` (or put them
   in the initramfs) to keep the boot display simple. Raise CMA (`cma=128M` on the cmdline) only
   if scanout allocation fails — no IOMMU on A33, so every scanout buffer must be contiguous
   [UNCONFIRMED: sizing, GPU agent].
4. Build:
   ```
   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage modules dtbs
   make ARCH=arm INSTALL_MOD_PATH=out modules_install
   ```
5. Firmware into the rootfs: AIC8800DC blobs (`/lib/firmware/aic8800DC/…` from the Radxa package or the frame's `/system/vendor/etc/firmware`/`vendor/modules` — compare them), `silead/<name>.fw` (if
   Silead), `regulatory.db`.
5b. **AIC8800DC module (out of tree), cross-built:**
   ```
   git clone --depth 1 https://github.com/radxa-pkg/aic8800.git   # then apply debian/patches/* in series order
   make -C <kernel-build-dir> ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
        M=$PWD/aic8800/src/SDIO/driver_fw/driver/aic8800 CONFIG_PLATFORM_UBUNTU=y modules
   ```
   Install `aic8800_bsp.ko`, `aic8800_fdrv.ko` and `firmware/aic8800DC/*` (path per the
   `fix-sdio-per-chip-firmware-path.patch`). Or install `aic8800-sdio-dkms` style on-device
   (DKMS on a 1 GB A7 is slow; the package carries low-memory build patches). [UNCONFIRMED:
   never built for armhf here]
6. Boot config on the SD `/boot` (U-Boot standard boot reads `extlinux/extlinux.conf`):
   ```
   LABEL omarchy
     KERNEL /zImage
     FDT /dtbs/allwinner/sun8i-a33-pf1007l.dtb
     INITRD /initramfs-linux.img
     APPEND root=PARTUUID=<uuid> rw rootwait console=tty1 loglevel=7
   ```

### 4.4 Bring-up order (smallest steps, each with a pass condition)

1. U-Boot from SD with **video ON** → panel shows the U-Boot console. (Proves lcd_if, timings,
   power/backlight GPIOs.) Only possible for LVDS/RGB.
2. Kernel + DTB with only `simplefb` + USB gadget NCM → `ssh` from the Mac over USB.
3. Add sun4i-drm + panel-lvds → `/dev/dri/card*`, `modetest` shows 1280x800 connector.
4. Add MMC1 + pwrseq → `cat /sys/bus/sdio/devices/*/uevent` shows `SDIO_ID=C8A1:C08D`; then load `aic8800_bsp` + `aic8800_fdrv` → `iw dev`, scan, then pin the MAC.
5. Touch, audio, cpufreq/thermal, lima.

---

## 5. What to read off the device

Root ADB is available via Wes's routes. Keep every dump private (it holds Wi-Fi keys/serials).

| What | How | Why |
|---|---|---|
| **`script.bin` → fex** | `sunxi-script_extractor > script.bin` (static armv7 build) or `dd if=/dev/mem bs=4096 skip=$((0x43000))+... count=32`; then `bin2fex` on the Mac | Source of every board value in §3.2 |
| `[lcd0]` section | from fex | **lcd_if (LVDS vs DSI)**, timings, LVDS bitwidth/mode, power/BL GPIOs, PWM, `lcd_driver_name` |
| Panel rotation | `getprop ro.sf.hwrotation`, `wm size`, fex `lcd_x/lcd_y` | Native portrait 800x1280 panels are common in DSI; sun4i DE1 has no hardware rotation |
| Touch controller | fex `[ctp]`; `lsmod`; `ls /sys/bus/i2c/devices/*/name`; `getevent -lp` | Driver choice, address, IRQ, axes, inversion |
| Silead firmware | `adb pull` the vendor `gslX680*.ko` (e.g. `/system/vendor/modules/`), run gsl-firmware `fw_extractor` | Needed only if Silead |
| Wi-Fi | `lsmod` (expect `aic8800_bsp`, `aic8800_fdrv`), `cat /sys/bus/sdio/devices/*/uevent` (expect `SDIO_ID=C8A1:C08D` for 8800DC [vendor header]), `ls -l /system/vendor/modules /system/vendor/etc/firmware`, fex `[wifi_para]`/`[wlan]` (power rail, `wl_reg_on`, `wl_host_wake`, `wifi_sdc_id`) | Confirms the chip + revision; pwrseq GPIO; firmware set to copy |
| PMIC | `dmesg | grep -i axp`; `ls /sys/class/regulator/*/name`; fex `[pmu1_para]`, `[power_sply]`, `[dvfs_table]` | AXP223 yes/no; **which DCDC feeds the CPU** |
| Power supply | `cat /sys/class/power_supply/*/uevent` | Battery present? ACIN used? |
| Audio | fex `[audio0]` (PA GPIO, HP vs lineout) | Speaker routing |
| Buttons | fex `[key_para]`, `getevent` while pressing | LRADC vs AXP PEK |
| DRAM | fex `[dram_para]` (`dram_clk`, `dram_zq`, `dram_para1/2` bus width) | Cross-check 456 MHz / ZQ 15291; 16- vs 32-bit bus; does your unit need the lane-0 patch? |
| Kernel config / cmdline | `zcat /proc/config.gz`, `cat /proc/cmdline`, `dmesg` (private) | Panel driver names, console UART |
| Physical (needs the case open) | Part number on the LCD back and its FPC; touch-FPC chip; UART pads; R_UART PL2/PL3 | Panel datasheet timings; serial console |

---

## 6. Risks

1. **Hyprland needs GLES ≥ 3.0; lima is GLES 2.0.** `Hyprland/src/render/OpenGL.cpp:205-226`
   tries ES 3.2 then 3.0 and `RASSERT`s if both fail [VERIFIED]. Lima = ES 2.0
   [DOCUMENTED]. So the kernel side (sun4i-drm KMS) can be perfect and Hyprland still needs
   llvmpipe (CPU rendering on 4x A7) or a different compositor. GPU agent owns this; it changes
   whether lima matters at all.
2. **DSI panel.** If `lcd_if = 4`, there is no upstream A33 DSI board, no U-Boot display, and a
   new panel driver must be written from the 3.4 BSP init table. Weeks, not hours.
3. **Native portrait panel (800x1280, used rotated)** [DOCUMENTED: Wes PR #6]. The sun4i DE1
   backend has 4 layers (1 primary + 3 overlay, no cursor plane) and **no rotation property**
   [VERIFIED: `sun4i_layer.c:228-248`, no `rotation` in `drivers/gpu/drm/sun4i/sun4i_layer.c`]. So
   the compositor rotates every frame in the renderer (Hyprland `transform`). With software
   rendering that is an extra full-screen pass per frame on 4x A7. Do NOT try to "fix" it in
   the panel timings; the panel scans in its native order.
4. **CPU regulator.** Upstream disagrees: `sun8i-reference-design-tablet.dtsi` sets
   `cpu-supply = <&reg_dcdc2>` while naming DCDC2 "vdd-sys" and DCDC3 "vdd-cpu"; SinA33 uses
   DCDC3 [VERIFIED]. Wrong rail + DVFS to 1.2 V OPPs = random crashes, or over-volting the
   wrong rail. Cap OPPs until the fex/regulator names confirm it.
5. **Wi-Fi has no mainline driver (AIC8800DC).** Every kernel update can break the
   out-of-tree module; Radxa has needed a build patch for nearly every release 6.1→7.3
   [VERIFIED: patch list]. 32-bit armhf build on 6.x/7.x is unproven. If it fails, the fallback
   USB dongle needs host mode + external 5 V on a port that also powers the frame (§2b). This
   is the biggest risk to a usable native Omarchy after the GLES issue.
6. **GPIO guesses can damage hardware.** Driving a pin that is a module output (Wi-Fi enable,
   LCD power) shorts it. Use fex values; do not copy Q8 pins blindly.
7. **USB-C power quirks.** The frame lacks CC resistors; only USB-A→C cables power it
   [VERIFIED: Wes]. Brown-out under CPU+GPU load from a weak USB-A port is possible
   [UNCONFIRMED]. The frame must stay a USB device (no VBUS drive).
8. **Writing to eMMC ends Android.** Installing U-Boot to eMMC overwrites Android's boot0 at
   8 KiB. Keeping U-Boot on the SD card forever avoids that. Keep Wes's full eMMC backup.
9. **Only 1 GiB RAM with HIGHMEM, VMSPLIT_3G, 64 MB CMA.** Scanout must come from CMA (no
   IOMMU). RAM agent owns sizing.
10. **Board variants.** Three PF1007L units already differ (DC jack vs USB-C, eMMC vendor, USB
    data). Panel/touch may also differ between batches. Read the fex on THE unit you flash.

---

## 7. Prior art

- **postmarketOS:** `inet-a33` (iNet D70, `sun8i-a33-q8-tablet` DTB, 1024x600) and
  `u-boot-q8-a33-tablet` (U-Boot 2023.01, `q8_a33_tablet_1024x600_defconfig`) are both in
  `device/archived/` = unmaintained [VERIFIED: pmaports mirror 2026-10-12]. The live
  `linux-postmarketos-allwinner` (megi-based, 6.18.3) armv7 config is a good second reference:
  sun4i-drm, DSI, panel-lvds, lima, AXP RSB, zram zstd [VERIFIED]. pmOS wiki also lists a
  "Powerway Dreamtab DRN-X500 (astar)" A33 tablet as near-mainline, not in official repos
  [DOCUMENTED: search snippet; wiki domain blocked].
- **Armbian:** no A33 tablet/frame support found (scoped: web search only).
- **Mainline A33 photo-frame project:** none found (scoped: web search + GitHub search for
  `astar-m86`, `fex2dts`). Note: `astar-m86` is Allwinner's generic A33 SDK board name (an Azpen
  A741 tablet reports the same), so it does not identify the PCB [VERIFIED: linux-sunxi archive
  `Azpen_A741.md`].
- **AIC8800 on mainline-kernel Allwinner boards:** Radxa Cubie A5E (A527, NixOS module), Orange Pi Zero 3W (A733, 7.3-rc2), H618/H313 TV boxes (Armbian) — all **arm64** [DOCUMENTED: GitHub repo search]. No armv7 (A33/H3) example found.
- **A33 10" tablets on linux-sunxi:** A33_M1016C (1024x600, GSL3676, RTL8723BS, AXP223),
  A33_Q7 (MIPI-DSI, RTL8703BS, "mainline OK but no DSI LCD") [DOCUMENTED: wiki archive].

---

## 8. Sources

Local (read in full or by grep):
- `scratchpad/repos/photo-frame-dashboard/docs/allwinner-a33-mainline-uboot.md`, `allwinner-a33-pf1007l.md`, `allwinner-a33-boot-access.md`, `allwinner-a33-sdcard-adb-wifi.md`, `android-replacement.md`, `pf1007l-start-here.md`; `scripts/a33-uboot/{pf1007l-uboot.patch,build-uboot.sh,Dockerfile}`; `scripts/a33-sdboot/{a33.config,build.sh}`. (`research-log.md` is about the Rockchip Skylight unit, not the A33.)
- Linux v7.3-rc7: `arch/arm/boot/dts/allwinner/{sun8i-a23-a33.dtsi,sun8i-a33.dtsi,sun8i-reference-design-tablet.dtsi,sunxi-reference-design-tablet.dtsi,sun8i-q8-common.dtsi,sun8i-a33-q8-tablet.dts,sun8i-a33-ga10h-v1.1.dts,sun8i-a33-inet-d978-rev2.dts,sun8i-a33-sinlinx-sina33.dts,sun8i-a83t-tbs-a711.dts}`; `drivers/gpu/drm/sun4i/{sun4i_tcon.c,sun4i_lvds.c,sun4i_drv.c,sun6i_mipi_dsi.c}`; `drivers/gpu/drm/panel/{panel-lvds.c,panel-simple.c}`; `Documentation/devicetree/bindings/display/panel/panel-lvds.yaml`; `drivers/net/wireless/realtek/rtw88/{Kconfig,rtw8723cs.c,rtw8703b.c,main.c}`; `drivers/input/touchscreen/{silead.c,goodix.c,edt-ft5x06.c}`; `drivers/mfd/axp20x*.c`; `drivers/cpufreq/cpufreq-dt-platdev.c`; `sound/soc/sunxi/sun8i-codec.c`; `arch/arm/configs/{sunxi_defconfig,multi_v7_defconfig}`.
- Linux tags via raw.githubusercontent.com: `v6.9`/`v6.10` rtw88 Kconfig; `v5.6`/`v5.7` `sun4i_tcon.c`; `drivers/pinctrl/sunxi/pinctrl-sun8i-a33.c`; `include/linux/mmc/sdio_ids.h`.
- U-Boot master: `configs/{q8_a33_tablet_1024x600_defconfig,Sinlinx_SinA33_defconfig,ga10h_v1_1_defconfig}`, `arch/arm/mach-sunxi/Kconfig`, `drivers/video/sunxi/{lcdc.c,sunxi_display.c}`.
- ALARM `core/linux-armv7/{PKGBUILD,config}` (7.2.10). pmaports `device/archived/{device-inet-a33,u-boot-q8-a33-tablet}`, `device/testing/linux-postmarketos-allwinner/`.
- sunxi-tools `script_extractor.c`, `README.md`. linux-sunxi archive: `Fex_Guide.md`, `Script.bin.md`, `Retrieving_device_information.md`, `A33.md`, `A33_Q7_V1.0.md`, `A33_M1016C-W-11Q9.md`, `Azpen_A741.md`.
- Hyprland `src/render/OpenGL.cpp` (clone by another agent).

Wes PR branches (fetched as `pull/N/head`, unmerged): PR #6 `pf1007l/README.md`, `pf1007l/uboot/frame-a33.patch`, `frame_a33_ums_defconfig`; PR #15 `docs/allwinner-a33-mainline-uboot.md` §8 (AIC8800 boot freeze, `aic_userconfig_8800dc.txt`).
AIC8800 driver clones (`scratchpad/repos/aic/`): `radxa-pkg/aic8800` (2026-10-12), `nickyg666/orangepi-zero3w-aic8800`, `LYU4662/aic8800-sdio-linux-1.0`, `walnutpi/aic8800_sdio`, `0x754C/aic8800-sdio-linux`, `shawnchain/aic8800-drv`.

Web:
- [LWN: RTL8723CS rtw88 series](https://lwn.net/Articles/960633), [v2 cover letter (yhbt lore mirror)](https://yhbt.net/lore/linux-mmc/20240227235507.781615-1-fiona.klute@gmx.de/), [linux-firmware MR 189](https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/189/pipelines), [pmaports issue 3420](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/work_items/3420)
- [openSUSE copy of "drm/sun4i: tcon: Support LVDS on the A33"](https://code.opensuse.org/kernel/kernel-source/blob/0b62bdb4751d0cd6898a3176acfedaa5d21e9d3a/f/patches.suse/0771-drm-sun4i-tcon-Support-LVDS-on-the-A33.patch), [A33 DSI nodes patch](https://lkml.iu.edu/hypermail/linux/kernel/1802.2/03243.html), [Q8 per-resolution DTS patch](https://lkml.iu.edu/hypermail/linux/kernel/1708.2/01050.html)
- [pmaports inet-a33 commit](https://ayakael.net/forge/pmaports/commit/ad438c06cfd09f5bcf80bada587c6a067f501fd6), [pmOS wiki Dreamtab (astar)](https://wiki.postmarketos.org/wiki/Powerway_Dreamtab_DRN-X500_(astar)) (search snippet only)
- [Olimex A33-OLinuXino listing (1280x800 LCD limit)](https://www.lcsc.com/product-detail/C20926818.html), [Olimex forum: A33 LVDS](https://www.olimex.com/forum/index.php?msg=27501)
- [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800), [Kiborgik/aic8800dc-linux-patched (USB)](https://github.com/Kiborgik/aic8800dc-linux-patched), [orangepi-zero3w-aic8800](https://github.com/nickyg666/orangepi-zero3w-aic8800), [Gentoo net-wireless/aic8800](https://packages.gentoo.org/packages/net-wireless/aic8800), [AUR aic8800d80-dkms](https://aur.archlinux.org/packages/aic8800d80-dkms)
- [gsl-firmware](https://github.com/NeonDaniel/gsl-firmware), [FEX2DTS](https://github.com/SdtElectronics/FEX2DTS), [whycan A33 fex from /dev/mem](https://whycan.com/t_5602.html), [rtw8703b-fw-extractor](https://github.com/airtower-luna/rtw8703b-fw-extractor)
