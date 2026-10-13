# 01 — Safe access, full backup, hardware identification

Humblestead HM-PF1007-BK / PF1007L, Allwinner A33. Research date 2026-10-12. The frame has NOT been
examined yet; every value below comes from other units.

Tags: **[VERIFIED]** = read in source or primary doc (path/URL cited). **[DOCUMENTED]** = a secondary
report (WB issue/PR, forum, search) says so. **[UNCONFIRMED]** = inference.

"WB" = the Wes Bos clone at `scratchpad/repos/photo-frame-dashboard` (main @ `9dd323e`). Issue/PR
numbers are `github.com/wesbos/photo-frame-dashboard`; PR branches were fetched locally as
`pr6 pr13 pr14 pr15 pr20 pr28`.

---

## Summary (5 bullets)

1. **A zero-eMMC-write path to running our own code exists.** The A33 Boot ROM reads the microSD
   slot before eMMC and runs any *unsigned* eGON image there; every reported unit ran the unsigned
   `fel-sdboot.sunxi` stub and unsigned mainline U-Boot. Secure boot is effectively OFF on this
   population [VERIFIED WB docs; DOCUMENTED #8/#13/#18/#24]. From FEL (USB) we RAM-boot U-Boot; from
   SD we boot U-Boot + a whole rootfs. Neither touches eMMC.
2. **A full verified eMMC backup works on macOS with published tools** (WB "Route U": FEL stub card →
   RAM-loaded read-only U-Boot `ums` disk → `emmc-macos.py backup`). But the population varies a lot:
   two eMMC sizes, ≥5 firmware dates, and several units needed eMMC at 4-bit/25–26 MHz and a POWERED
   USB hub or the backup dropped mid-read [DOCUMENTED #8/#16/#18/#24].
3. **Many units already have root ADB or can get it without any flash.** The firmware ships
   `ro.secure=0`, `ro.debuggable=1`, a setuid `su`. Try, in order: stock USB ADB; stock network ADB
   (5555); then — only if both fail — a one-line boot/`build.prop` patch written from SD or FEL.
   Some May-2026 units ship ADB fully on [DOCUMENTED #8].
4. **The hardware is a Q8-class A33 tablet board.** Best mainline match is the Q8 A33 tablet design:
   AXP223 PMIC on RSB, GSL1680 I2C touch at 0x40 on TWI0 / INT PB5 / reset PH1, AIC8800DC SDIO Wi-Fi
   (NOT RTL8723CS — the `8723cs` in the product string is a vendor leftover), LVDS-ish 1280x800 panel
   via TCON0, PWM backlight on PH0/enable PH6. **All must be confirmed from the live `script.bin`.**
5. **On-Android identification is easy once rooted:** pull `script.bin` from `/dev/mem` at
   `0x43000000` (or the boot/bootloader partition) and decode with `bin2fex`; cross-check with
   `dmesg`, `/sys/bus/i2c`, `/proc/partitions`, `lsmod`, `getprop`. **UART is not required** for
   access or backup — FEL+SD is enough — but 3.3 V UART on the debug pads is the cheapest insurance
   if a write ever bricks boot.

---

## How access works, and why it is safe

**Boot order (A33 sun8i).** The BootROM searches SD (MMC0) first, then eMMC (MMC2), then drops to FEL
(USB recovery) if neither has a valid eGON boot image [DOCUMENTED linux-sunxi BROM/Boot pages via
WebSearch; barebox sunxi doc]. WB confirms it on these frames: "The A33 Boot ROM tries the SD card
before the eMMC" and the FEL stub card gives persistent FEL with the screen dark
(`docs/pf1007l-start-here.md`, `docs/allwinner-a33-pf1007l.md` §2) [VERIFIED].

**Secure boot.** The eGON FEL/SD-boot stub requires *non-secure* boot, and it worked on every
reported unit — so these ship with secure boot disabled. WB states the stub "requires non-secure
boot; it is not guaranteed to work on another board or a secure-boot unit"
(`docs/allwinner-a33-pf1007l.md` §2) [VERIFIED]. The firmware itself is `eng/test-keys`, `ro.secure=0`,
`ro.debuggable=1`, SELinux `Disabled`/permissive (`docs/allwinner-a33-pf1007l.md` §3,
`aimor-remote-root-shell.md`) [VERIFIED]. **Must still be checked on the physical unit** — a fused
secure-boot unit would refuse the stub and the whole route changes.

**Forcing FEL.** Three ways, cheapest first:
- **FEL stub SD card (preferred, reliable):** write `fel-sdboot.sunxi` (8192 bytes, SHA-256
  `2ccec08a0268...808bc`) to byte offset 8192 of a spare card; insert, power on → persistent FEL,
  `1f3a:efe8`, screen dark. Card out = normal boot. [VERIFIED `docs/...pf1007l.md` §2; stub is
  `sunxi-tools/bin/fel-sdboot.sunxi`.]
- **RESET/boot button:** WB saw `1f3a:efe8` for ~3 s on the recessed button but version queries
  failed — too short to use; not reliable (`docs/allwinner-a33-pf1007l.md` §2) [VERIFIED]. Generic
  A33 tablets use VOL+ held at power-on [DOCUMENTED linux-sunxi FEL]; this frame has no VOL buttons.
- **No valid eMMC boot image** → BootROM falls through to FEL by itself.

**FEL identity to expect:** `AWUSBFEX soc=00001667(A33) ... ver=0001 44 08 scratchpad=00007e00`
[VERIFIED across #18/#19/#24]. sunxi-tools A33 record: `soc_id 0x1667`, sram 32 KiB, sid_base
`0x01C23800`, thunk `0x46E00` (`sunxi-tools/soc_info.c`) [VERIFIED].

---

## Step-by-step procedure (both port variants, macOS-first)

### Phase 0 — identify and lock down BEFORE any network

0.1 Settings → About. Record model (expect `PF1007L`), firmware string
(`YHK.F-null-A33-1001-D1024-PF1007L-...`), AiMOR version (expect 6.0.78). [T1 in WB start-here.]
0.2 Note ports: **Variant A** = DC jack + USB-OTG port (unit A). **Variant B/C** = USB-C only + TF
slot + one button. The Amazon B0GGB7LWX8 / "HM-PF1007-BK" is most likely USB-C-only (verify).
0.3 **Do NOT join Wi-Fi yet.** AiMOR opens an unencrypted TCP link to `imsconnect.efercro.com:7806`
and will run server-sent shell commands as root (see Risks). Keep it offline until Phase 4.

### Phase 1 — try ADB with zero changes (stop at first success)

1.1 **USB ADB.** Use a **USB-A→USB-C data cable** into a USB-A port/hub (USB-C↔C gives no power on
these — missing CC pull-downs). The frame is USB 2.0 only; ensure a "USB2.0 Hub" shows in the tree.
```
system_profiler SPUSBDataType | grep -i -B4 -A6 '0x1f3a'   # macOS
ioreg -p IOUSB -l -w0 | grep -i 1f3a                       # macOS fallback (system_profiler often blank)
adb devices -l
```
- `1f3a:1002` or `adb device` + `uid=0(root)` → **done**, go to Phase 3 backup. (May-2026 units
  ship ADB on [DOCUMENTED #8].)
- `1f3a:1000` "Android", no ADB → USB data works but ADB off; go to Phase 2 (Route U).
- nothing → try other A-to-C cables, direct USB-A port, USB-2 hub, replug, another computer; if still
  nothing go to Phase 2 (Route S).

1.2 **Network ADB** (only if you must; needs Wi-Fi → block 7806 at the router first):
`nc -vz -w3 <ip> 5555; adb connect <ip>:5555; adb -s <ip>:5555 shell id`. Closed on tested units.

### Phase 2 — get root ADB without touching eMMC data (choose ONE route)

**Route U (USB, macOS, PREFERRED — it also takes the verified backup):**
2U.1 `brew install libusb dtc pkgconf`; build sunxi-tools at commit `d7bbd172a5da...` (`make sunxi-fel`);
verify the 8192-byte stub hash above. On recent Xcode you need `SDKROOT=.../MacOSXNN.sdk` to link
[DOCUMENTED #13].
2U.2 Make the FEL stub card: `sudo python3 -I scripts/a33-uboot/fel-card-macos.py backup diskN <bytes>`
then `... write diskN <bytes>` (writes only 8 KiB to the card's boot area; MBR-only, re-reads to
verify, refuses to clobber a backup) [VERIFIED script].
2U.3 Insert card, replug cable (cable = power switch on USB-C units) → `sunxi-fel version` should show
`soc=00001667(A33)`.
2U.4 Build read-only U-Boot: `scripts/a33-uboot/build-uboot.sh` (mainline v2025.10 `e50b1e87` +
`pf1007l-uboot.patch`, in Docker/Colima). The patch: eMMC on MMC2 8-bit, OTG forced peripheral, VBUS
drive + id-det removed, video off, `BOOTDELAY=-2`, `CRC32_VERIFY`, and **two-layer read-only `ums`**
(`ums_write_sector` refuses, LUN reports write-protect) [VERIFIED `pf1007l-uboot.patch`].
2U.5 Go to Phase 3 (backup). Then build the boot patch from YOUR backup and do the guarded write
(Phase 5). Result: `1f3a:1002`, `adb -d shell id` = root.

**Route S (SD only, no USB data — for Variant B units that show no USB device):**
WB scripts here are **Windows + WSL** (`fel-sdcard.py` is Windows-only; U-Boot build needs Linux/WSL).
PR #14 adds a **macOS** three-command flow (`scripts/pf1007l-macos/card.py prepare|root|verify diskN`)
that builds U-Boot in Docker, dumps the first 2 GiB to the card, and writes a Wi-Fi-ADB boot patch
[VERIFIED pr14]. Route S writes the WHOLE boot image (31,028 sectors) — higher risk, do not cut power.

**macOS equivalent of Wes's "Windows-only SD script":** there are two.
(a) Route U `fel-card-macos.py` (FEL stub) + `emmc-macos.py` (backup/verify) — the clean macOS path.
(b) PR #14 `scripts/pf1007l-macos/card.py` — the macOS port of the SD-only dump+patch flow.
On plain Linux: use `lsblk`/`dd` per `docs/allwinner-a33-pf1007l.md` §2 and the SD guide.

### Phase 3 — full verified eMMC backup (do before ANY write)

3.1 Route U: `sunxi-fel -v -p uboot .../u-boot-sunxi-with-spl.bin write 0x43100000 .../ums-readonly.scr`.
U-Boot runs `ums 0 mmc 0,1`; eMMC appears as a read-only "UMS disk". Identify by size.
3.2 `sudo python3 -I scripts/a33-uboot/emmc-macos.py backup diskN <exact-bytes>` — refuses a writable
disk, copies whole eMMC, independent re-read, rejects `0xCC` filler, gzips, verifies readback
[VERIFIED script header].
3.3 **Known reliability traps (check on the device):**
   - eMMC drops off USB mid-read at 8-bit/52 MHz on several units → set `&mmc2 bus-width=<4>;
     max-frequency=<25-26000000>;` (and `CMD_HASH`) [DOCUMENTED #18/#24/#27].
   - Backup dies after N MiB on a bus-powered hub → use a **powered** hub, or a direct Mac port;
     power delivery, not the radio, is the usual cause [DOCUMENTED #16/#24].
   - Some units reset to FEL ~41–50 s after `ums` comes up, even idle → use SD-only Route S, or the
     #24 SRAM-console / read-retry / watchdog experiments (unresolved; #17/#19) [DOCUMENTED].
   - Also back up the hardware boot partitions `mmcblk0boot0` / `mmcblk0boot1` once you have root ADB
     (`emmc-macos.py` / `ums` give the main LUN only) [DOCUMENTED #8].
3.4 Keep the image PRIVATE (holds Wi-Fi creds, serial, AiMOR device cert). Make a second copy on
another disk.

### Phase 4 — lock down AiMOR (first thing after you have root)

Do WB `aimor-remote-root-shell.md` §8: block outbound TCP 7806 (+ 10546-10550, 3478) at the router;
install a launcher; `pm disable com.efercro.os.aimor com.yhk.qeota com.DeviceTest`; confirm
`enabled="2"` in `/data/system/users/0/package-restrictions.xml` before reboot; re-check
`netstat -an | grep :7806` is empty after reboot [VERIFIED].

### Phase 5 — (only if you had to patch) the guarded write

Build patch from YOUR backup (`boot-patch.py` / PR#14 `build-root.py`); it changes only the ramdisk
USB-init action (adds `adb` to functions) or appends ADB props; guards on CRC-32 + the eMMC still
holding original bytes; writes ramdisk first, header last; host re-verifies whole eMMC against backup
+ plan [VERIFIED `scripts/a33-uboot/boot-patch.py`, `emmc-macos.py verify`]. Keep the restore script.

---

## Commands to run on the device (once root ADB)

### Core identity
```
adb -d shell id
adb -d shell getprop ro.build.fingerprint        # AEEZO/astar_m86_8723cs/astar-m86_8723cs:6.0.1/...
adb -d shell getprop ro.product.cpu.abi           # armeabi-v7a (32-bit armv7)
adb -d shell getprop ro.hardware                  # sun8i
adb -d shell getprop ro.board.platform; getprop ro.build.version.sdk  # 23
adb -d shell getenforce                           # Disabled / Permissive
adb -d shell cat /proc/cpuinfo /proc/meminfo
```

### The hardware config: script.bin → fex  (the key step for the device tree)
On Allwinner Android the live sys_config lives as a binary `script.bin` loaded into DRAM at
**0x43000000**, length 0x20000, and is also on a partition. Two ways to grab it:
```
# A) from DRAM via /dev/mem (SELinux is permissive/disabled here, so this works):
adb -d shell 'dd if=/dev/mem bs=1 skip=$((0x43000000)) count=$((0x20000))' > script.bin
#    (sunxi-tools ships script_extractor.c that mmaps exactly 0x43000000/0x20000 — same region.)
# B) from storage: find the config/boot/bootloader partition:
adb -d shell 'ls -l /dev/block/by-name; cat /proc/partitions; cat /proc/cmdline'
adb -d shell 'find / -name "script.bin" -o -name "sys_config*.fex" 2>/dev/null'
#    On some units it is in the FAT /bootloader partition; check `mount`.
```
Decode on the host with sunxi-tools (`bin2fex` is a symlink to `sunxi-fexc`):
```
bin2fex script.bin sys_config.fex        # then read the sections below
```
`script.bin` header is `{sections,filesize,version[2]}` then 32-byte-named sections of GPIO entries
(`sunxi-tools/script_bin.h`) [VERIFIED]. The decoded `.fex` has the same sections as the A33 tablet
fex files in `sunxi-boards/sys_config/a33/*.fex` [VERIFIED clone]. Read specifically:
- `[lcd0_para]` → `lcd_if` (0=HV/RGB, 3=LVDS, 4=MIPI-DSI), `lcd_x/lcd_y`, `lcd_dclk_freq`,
  `lcd_hbp/ht/hspw/vbp/vt/vspw` (timings), `lcd_lvds_if/colordepth/mode`, `lcd_driver_name`,
  `lcd_pwm_ch/freq/pol`, `lcd_bl_en` (backlight enable GPIO), `lcd_power`, the `lcdd*`/`lvds*` pins.
- `[ctp_para]` → `ctp_name` (e.g. `gsl1680e_101`), `ctp_twi_id`, `ctp_twi_addr` (e.g. 0x40),
  `ctp_int_port` (e.g. PB5), `ctp_wakeup`/reset (e.g. PH1), `ctp_power_ldo`.
- `[wifi_para]` → `wifi_mod_sel`, `wifi_sdc_id` (SDIO controller index), power rails, regon/host-wake
  GPIOs. (Vendor fex may still say `rtl8723bs_*`; the running driver is the truth — see dmesg/lsmod.)
- `[pmu1_para]` → `pmu_twi_addr` (0x34 typical for AXP), `pmu_twi_id`.
- `[uart_para]`/`[jtag_para]` → debug UART tx/rx pins (usually PF2/PF4 — shared with the SD slot!),
  JTAG on PF.
- `[mmc2_para]`/`[nand0_para]`, `[gsensor_para]`, `[audio0]`/`[i2s0]`, `[usbc0/1]`, `[key_detect_en]`.

### Cross-check against the live kernel (the capture, not the schema — CLAUDE rule 1)
```
adb -d shell dmesg > dmesg.txt      # grep -iE 'gsl|goodix|gt9|ctp|tp |touch|aic8800|rtl87|axp|
                                    #   lcd|tcon|lvds|dsi|backlight|pwm|mmc[012]|sunxi|disp'
adb -d shell 'ls -l /sys/bus/i2c/devices/; for d in /sys/bus/i2c/devices/*/; do
      echo $d; cat $d/name 2>/dev/null; done'
adb -d shell 'ls /sys/bus/platform/devices | grep -iE "twi|i2c|lcd|disp|pwm|gpio|mmc"'
adb -d shell lsmod                 # module names: aic8800_fdrv? gsl? mali?
adb -d shell 'cat /proc/bus/input/devices'   # touch device name/vendor/product
adb -d shell 'cat /sys/class/net/wlan0/address; ls /system/vendor/modules 2>/dev/null'
adb -d shell 'dumpsys display | head -40; wm size; wm density'
adb -d shell 'ls -l /dev/block/by-name; cat /proc/partitions'
```
Also pull the stock kernel + DTB (`boot` partition) for the real `fdt` if the vendor shipped a
device tree, and `/system/vendor/modules/*` for the Wi-Fi `.ko` + firmware blob names.

---

## Expected hardware (Q8 A33 reference design — CONFIRM each from the live script.bin/dmesg)

| Part | Expected | Evidence | Confirm on device |
|---|---|---|---|
| SoC | Allwinner A33, quad A7, armv7, Mali-400MP2 | FEL `0x1667`; fingerprint | `cat /proc/cpuinfo`, FEL |
| RAM | 1 GiB DDR3 16-bit; **byte lane 0 may boot disabled** | WB PR#6 DRAM patch [VERIFIED] | U-Boot DRAM train |
| eMMC | Samsung 16 GB on MMC2 8-bit; 30,535,680 OR 30,777,344 sectors; name `016G92`/`KLMAG2WE` | #8/#18/#24 [DOCUMENTED] | `/proc/partitions`, `ums` size |
| PMIC | **AXP223** (X-Powers) on RSB, TWI/RSB addr 0x34/0x3a3 | mainline `axp223` in `sun8i-reference-design-tablet.dtsi` [VERIFIED]; fex `pmu_twi_addr=52`(0x34) | `/sys/bus/i2c`, dmesg `axp` |
| Touch | **GSL1680 (Silead)** I2C 0x40 on TWI0, INT PB5, reset/wake PH1, power axp22 ldoio1 | A33 fex `ctp_name=gsl1680e_101`; mainline touchscreen@40 INT PB5 reset PH1 [VERIFIED] | `script.bin`, `/proc/bus/input/devices`, dmesg |
| Wi-Fi/BT | **AIC8800DC** SDIO (NOT RTL8723CS); random MAC each boot; module `aic8800_fdrv` | WB PR#6 + #15 [VERIFIED/DOCUMENTED] | `lsmod`, `/system/vendor/modules`, dmesg |
| Display | 1280x800 (panel 800x1280 used rotated); TCON0; interface LVDS likely (`lcd_if=3`) but some A33 use RGB(0) or DSI(4) | WB PR#6 "800x1280 rotated" [VERIFIED]; fex varies [VERIFIED] | **script.bin `lcd0_para`** — decisive |
| Backlight | PWM ch0 on PH0, enable PH6, ~50 kHz, inverted polarity | mainline backlight `pwm 0 50000 INVERTED`, enable PH6; fex `lcd_pwm_*` [VERIFIED] | `script.bin`, `/sys/class/pwm` |
| Debug UART | UART0 PF2(tx)/PF4(rx) OR R_UART PL2/PL3; **PF pins are shared with the SD slot** | fex `uart_debug_tx=PF02`; mainline `uart0_pf_pins PF2/PF4`, `r_uart PL2/PL3` [VERIFIED] | board inspection |
| Audio | A33 internal `audiocodec`; working speaker; no mic declared | WB mainline-uboot §8 [VERIFIED] | dmesg, `dumpsys audio` |
| USB | MUSB OTG (`usbc0`), peripheral in our U-Boot | WB [VERIFIED] | — |
| Buttons | one power/reset (USB-C units); no VOL keys | WB [VERIFIED] | — |

**Mainline Linux support exists** for all the hard bits: A33 TCON0 has `has_lvds_alt` + LVDS PHY
(`drivers/gpu/drm/sun4i/sun4i_tcon.c` `sun8i_a33_quirks`) [VERIFIED]; MIPI-DSI node is in
`sun8i-a33.dtsi` [VERIFIED]; AXP223, GSL1680 (`silead` driver), Mali-400 (Lima) all upstream. The
**Wi-Fi (AIC8800DC) is the weak spot**: no mainline driver, only out-of-tree vendor/Radxa DKMS, and
no confirmed 32-bit armhf build [DOCUMENTED search]. Flag this to the Wi-Fi/networking research
topic — it is the main risk to a usable native Omarchy.

---

## Shopping list

- **USB-A → USB-C data cable** (known-good data cable; the box cable is often power-only). Plug into a
  USB-A port/adapter — USB-C↔C gives no power on these frames [VERIFIED].
- **Powered USB 2.0 hub** (not bus-powered) — fixes the mid-backup dropouts [DOCUMENTED #16/#24].
- **2+ microSD cards**, 4-32 GB, SDHC, MBR, FAT32 (U-Boot cannot read exFAT; cards >32 GB often ship
  exFAT). One FEL stub card, one for Route-S dumps. 2.2 GB free needed for a Route-S dump [VERIFIED].
- **USB microSD card reader**.
- **3.3 V USB-UART adapter** (CP2102 / FT232RL / CH340, **must be 3.3 V logic**) + jumper wires —
  *optional*; only if you want console insurance for the eMMC-write step or to debug a bad boot.
  Allwinner UART is 3.3 V; 5 V will damage the SoC.
- (Have already) a Mac with Homebrew + Docker/Colima; `adb` (Android platform-tools).

---

## Risks

1. **AiMOR remote root shell (block this first).** `com.efercro.os.aimor` keeps an **unencrypted**
   TCP link to `imsconnect.efercro.com:7806`; vendor command 12009 is piped straight to `su` with no
   auth — the vendor (or anyone MITM-ing that link) gets arbitrary root on your LAN. It also
   `setenforce 0` on every start, trusts all TLS certs, can silently `pm install -r`, and change the
   serial/`android_id`. `com.DeviceTest` has an unprotected receiver any app can poke to enable/disable
   components. **Mitigation:** keep offline until rooted; block 7806 (and 10546-10550, 3478) at the
   router; then `pm disable` AiMOR, `com.yhk.qeota`, `com.DeviceTest` (WB `aimor-remote-root-shell.md`)
   [VERIFIED]. Note the port: WB PR#6 README once said "8086"; the decompiled code and all later docs
   say **7806** — trust 7806 and verify with `netstat`.
2. **Bricking on an eMMC write.** The guarded scripts refuse mismatched content and verify readback,
   but an interrupted boot-partition write (esp. Route S, whole 15.9 MB image) can leave a
   non-booting frame that only a board-specific restore (not a factory menu) fixes. Do not cut power;
   keep the verified backup + restore script; prefer Route U (patches 5 MiB, not 15.9) [VERIFIED].
3. **Firmware/eMMC variance = a backup/patch from one unit is NOT valid for another.** Two eMMC
   sizes, ≥5 boot hashes, differing `build.prop` sectors. Always derive hashes/sectors from THIS
   unit's own backup; never edit a guard to force a match [VERIFIED WB rules, #16].
4. **Bundle/grant loss** is an Android-app concern on the vendor side, not relevant to a full
   Omarchy replace — but note WebView/trust-store quirks are documented if an interim Android kiosk is
   wanted.
5. **UART pins are shared with the SD card slot** on the PF variant (PF2/PF4). You cannot use a
   UART-on-SD-breakout and an SD card at the same time; if a real debug UART is wanted, find the
   board's dedicated pads (unconfirmed location) instead [VERIFIED pin sharing; UNCONFIRMED pads].

---

## Open questions for the device (what to check physically)

1. **Which port variant** is B0GGB7LWX8? (DC jack+OTG vs USB-C-only+TF+button.) Decides Route U vs S.
2. **eMMC size** (30,535,680 vs 30,777,344 sectors) and **firmware date/boot hash** — read from About
   and from the first backup; picks which reports apply.
3. **Does secure boot really stay off?** Confirm the FEL stub card enters FEL and `sunxi-fel version`
   answers `A33`. A no-answer = possible secure-boot or a different board.
4. **Display interface and timings** — decode `lcd0_para` from THIS unit's `script.bin`: is it LVDS
   (`lcd_if=3`), RGB (0) or MIPI-DSI (4)? Exact `lcd_driver_name` and the h/v timings. This is the
   single most load-bearing unknown for the mainline DT.
5. **Touch controller** — confirm `ctp_name` (GSL1680 vs GT911 vs FocalTech), I2C bus/addr, INT/reset
   pins from `script.bin` + `/proc/bus/input/devices` + dmesg. GSL1680 needs a per-panel firmware blob.
6. **Wi-Fi chip** — confirm `aic8800_fdrv` in `lsmod`/dmesg and the firmware blob name in
   `/system/vendor/modules`. If truly AIC8800DC, the mainline-driver gap is the project's biggest risk.
7. **PMIC** — AXP223 on RSB (addr 0x3a3) vs something else; needed for regulators in the DT.
8. **eMMC reliability** — does `ums` survive idle, and does lowering MMC clock to 25 MHz / using a
   powered hub give a clean full backup?
9. **Debug UART pads** — are there labelled TX/RX/GND pads on `PF1007L_MB_V1.0`? (No public pinout
   found; inspect under the back cover.)
10. **Is ADB already on** (May-2026 builds)? If yes, skip all flashing.

---

## Sources

Primary (read in full):
- WB clone `scratchpad/repos/photo-frame-dashboard`: `docs/pf1007l-start-here.md`,
  `docs/allwinner-a33-pf1007l.md`, `docs/allwinner-a33-mainline-uboot.md`,
  `docs/allwinner-a33-boot-access.md`, `docs/allwinner-a33-sdcard-adb-wifi.md`,
  `docs/aimor-remote-root-shell.md`; scripts `a33-uboot/*` (`pf1007l-uboot.patch`, `emmc-macos.py`,
  `fel-card-macos.py`, `boot-patch.py`), `a33-sdboot/*`.
- WB PR branches: `pr6` (`pf1007l/README.md` — hardware facts, AIC8800, DRAM lane-0, build.prop
  sector, `frame-a33.patch`, `frame-fixmac.sh`), `pr14` (`scripts/pf1007l-macos/*` — macOS SD flow),
  `pr15`/`pr20`/`pr28`/`pr13` (unit reports, AiMOR network-ADB).
- WB issues/PRs (via WebFetch github.com): #8, #13, #16, #18, #19, #24, #27 (firmware/eMMC/USB/power
  variance), #20 (AiMOR temp-root).
- sunxi-tools clone: `soc_info.c` (A33 `0x1667`), `script_bin.h`, `script_extractor.c`,
  `fel-sdboot.S`, Makefile (`bin2fex`/`fex2bin`).
- u-boot clone: `arch/arm/mach-sunxi/board.c` (UART muxing), `configs/q8_a33_tablet_*`,
  `include/configs/sunxi-common.h` (load addrs).
- linux clone files: `sun8i-reference-design-tablet.dtsi`, `sun8i-a33.dtsi`, `sun8i-a23-a33.dtsi`,
  `sun8i-a33-q8-tablet.dts`, `drivers/gpu/drm/sun4i/sun4i_tcon.c`, `pinctrl-sun8i-a33.c`.
- sunxi-boards clone: `sys_config/a33/*.fex` (GSL1680, AXP, lcd_if, UART PF2/PF4, wifi_para).

Secondary (WebSearch summaries; linux-sunxi.org not directly fetchable in this env):
- linux-sunxi BROM/Boot/FEL pages (SD-before-eMMC order, FEL button, non-secure boot).
- script.bin at 0x43000000 via /dev/mem + bin2fex (whycan/cnx-software/banana-pi forum summaries).
- AIC8800DC driver status (GitHub Kiborgik/asanrivas, Radxa pkg, Armbian/Radxa forums) — out-of-tree
  only, no confirmed armhf.
- Homebrew has no `sunxi-tools` formula (core 404); build from source with `brew install libusb dtc
  pkgconf`.
- FCC ID 2AW9M-PF1007 (grantee Shenzhen Efercro); internal photos not located.
