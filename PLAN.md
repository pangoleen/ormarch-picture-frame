# Omarchy on a £50 photo frame — build plan

Frame: Humblestead 10.1" HM-PF1007-BK (Amazon UK B0GGB7LWX8), AiMOR app.
Probable board: EFERCRO PF1007L_MB_V1.0, the board Wes Bos documented.
Plan date: 2026-10-12. Evidence: the six reports in `research/`. Read `CLAUDE.md` first.

Tags: **[V]** = read in source code or a primary doc. **[D]** = a second-hand source says so.
**[U]** = our inference; test it.

---

## Plan update — 2026-10-12 (end of day 1)

**Continuation (E052–E053):** steps C–G passed on hardware. Step H's desktop/menu/theme-switch gate passed on the SD card, and the owner typed with the touch keyboard. The complete armv7 packaging/update port is still unfinished. Wi-Fi association, direct internet and automatic reconnect passed. Native Bluetooth LE powers on and discovers devices; the final reboot checked desktop, Wi-Fi and Bluetooth startup together. Step I remains a later, explicit decision; no eMMC write was made.

Details and evidence: `docs/experiments.md` (E001–E036) and the **Status** section of `CLAUDE.md`.

### Done

| Phase | Result |
|---|---|
| 1 Look | Model `PF1007L`, firmware `…AIMOR.0.20260113`, USB-C + TF slot, ADB off on USB |
| 2 Backup | A33 confirmed over FEL; unsigned code runs from the SD card. All firmware partitions saved and verified (first 2 GiB, two copies). The owner decided that the user-data area is not necessary. |
| 3 Read the hardware | Done early, from the backup data, with no root on Android: `dumps/sys_config.fex`. **Gate result: the screen is MIPI-DSI** (the hard branch). Decision: continue — the panel is a Jadard JD9365DA class panel, its init sequence and power order are extracted, and mainline has a driver family for it. |

Also done ahead of plan: touch firmware extracted; CPU rail = DCDC3 (vendor code); the AIC8800 Wi-Fi
driver builds for armv7 with no extra patch; draft panel patch and board device tree.

### What changed in the plan

- **Root ADB on Android is no longer necessary.** The config came from the storage dump. We do not boot Android again, so the AiMOR lock-down (old Phase 2 step 5) is not necessary as long as the frame stays off Wi-Fi under Android.
- **Phase 4 and 5 become one step: a blind first boot.** U-Boot cannot light a DSI panel, and there is no serial adapter. The boot card must make the frame show on the Mac as a USB serial console + USB network, and write marker files to the card.
- **Use the stock Arch Linux ARM kernel if possible**, with our panel driver and Wi-Fi driver as extra modules and our own DTB. A full kernel build only if the config audit says so.
- **U-Boot for this board needs three things from this unit:** DRAM ZQ 31739, the vendor voltages (DCDC2 1.2 V, DCDC1/ALDO1 3.3 V), and a console that is not on PL2/PL3 (PL2 is the Wi-Fi enable pin; noise on that console probably ended `ums` in the first runs).

### Next steps, in order

| # | Step | Needs the owner? | Gate |
|---|---|---|---|
| A | Finish the running backup, assemble it, read U-Boot's log from SRAM | No (running) | "Verified full eMMC backup" + the reason for the old drops |
| B | Review the three agent results: `kernel/out/` (panel module, DTB), `image/` (boot card image), `port/` (Omarchy shell on 32-bit) | No | Image file ready; list of missing packages |
| C | **First Linux boot from a second SD card** | Yes: write the card, put it in the frame, connect the cable | The Mac sees a USB serial console; `ssh` works |
| D | **First picture**: load the DSI panel module, debug with `dmesg` over USB | A little (look at the screen) | Kernel console on the screen |
| E | Check the hardware from Linux: touch (`evtest`), Wi-Fi SDIO ID then the driver, CPU voltage registers, eMMC visible read-only | A little (touch the screen) | Touch events; Wi-Fi scan; values recorded |
| F | GPU baseline: `kmscube` and `glmark2` on lima | No | `kmscube` spins |
| G | Hyprland on the Mali-400: version override first, Hypoland second | A little | A terminal in Hyprland at a usable speed |
| H | Omarchy armv7 port (fork v4.0.4, 14 edits, own package repo) | No | Omarchy desktop, menu, theme switch |
| I | Move to the internal storage | Yes: a clear go | Boots with no card |

The three big risks, updated: **(1) the DSI host driver on this board — now the largest**, (2) Hyprland on
a GLES 2 GPU, (3) Wi-Fi with the real chip (the driver builds; it has never run).

### Shopping list, updated

| Item | Why | State |
|---|---|---|
| Second microSD card, 8 GB or more | The Linux boot card. The first card stays the FEL recovery card. | **Necessary for step C** |
| 3.3 V USB-UART adapter | Step D is much easier with a console. The debug pins are the SD-slot pins, so it also needs an SD breakout or the board's pads. | Strongly recommended |
| Powered USB 2.0 hub | Wes's users needed one. Today's result decides: if build F finishes the backup on the present hub, it is optional. | Decide after step A |

---

## 0. The one-minute version

- **Yes, it is possible.** No part of it is proven impossible. Nobody has done it before.
- **We never write the internal storage until the end.** The chip boots our code from the SD card first. [V, Wes docs]
- **Three big risks decide the project.** We test each one early and cheaply:
  1. **Screen link**: LVDS is easy; MIPI-DSI is weeks of work. Only the frame's own config file can tell us. (Phase 3)
  2. **GPU**: Hyprland wants OpenGL ES 3, and the Mali-400 has ES 2. There are three ways around this. (Phase 7)
  3. **Wi-Fi**: the AIC8800DC chip has no mainline driver. The fallback is network over the USB cable to the Mac. (Phase 5)
- **We build the software on the Mac or in GitHub Actions, never on the frame.**

---

## 1. Hardware facts (expected — confirm on YOUR unit)

| Part | Expected | Source | Mainline Linux |
|---|---|---|---|
| SoC | Allwinner A33, 4× Cortex-A7, **32-bit armv7** | [V] Wes, FEL id `00001667` | ✅ |
| RAM | 1 GB | [V] Wes | — |
| Storage | ~16 GB Samsung eMMC (2 variants). Listing says 32 GB → check | [V] Wes | ✅ (use 4-bit, 26 MHz) |
| GPU | Mali-400 MP2 → `lima`, **GLES 2.0 only** | [D] Mesa docs | ✅ |
| Screen | 1280×800, panel is **native 800×1280, rotated** | [D] Wes PR #6 | ✅ if LVDS/RGB, ⚠ if DSI |
| Touch | Probably Silead GSL1680 (needs a firmware file) | [U] Q8 reference | ✅ driver, firmware needed |
| PMIC | Probably AXP223 | [U] | ✅ |
| Wi-Fi | **AIC8800DC on SDIO** (not Realtek) | [D] Wes PR #6, #15 | ❌ out-of-tree only |
| USB | One USB-C port, device mode, also powers the frame | [V] Wes | ✅ gadget mode |
| CPU speed | Mainline stops at 1.008 GHz | [V] `sun8i-a33.dtsi` | ✅ |

---

## 2. Shopping list

| Item | Why | Must have? |
|---|---|---|
| USB-A → USB-C **data** cable (known good) | USB-C ↔ USB-C gives no power and no data on this frame | ✅ |
| **Powered** USB 2.0 hub | Backups failed on bus-powered hubs | ✅ |
| 2–3 microSD cards, 4–32 GB, SDHC | Boot media. U-Boot cannot read exFAT, so use FAT32/ext4 | ✅ |
| USB microSD card reader | To write cards from the Mac | ✅ |
| 3.3 V USB-UART adapter + jumper wires | Kernel console if the screen stays dark. Pins are shared with the SD slot | Optional |
| USB Wi-Fi dongle (mt7601u / mt76x0u / rtl8xxxu chip) | Only if USB host mode plus separate power works [U] | Later, maybe |

Software on the Mac: Homebrew (`libusb dtc pkgconf`), sunxi-tools built from source, `adb`,
Docker (or OrbStack) with `--platform linux/arm/v7`.

---

## 3. The phases

Each phase has a **gate**. Do not start the next phase until the gate passes.

### Phase 1 — Look, offline (10 minutes)
⛔ **Do not connect the frame to Wi-Fi.** The AiMOR app gives the vendor server a root shell
with no password (TCP 7806). [V, Wes `aimor-remote-root-shell.md`]

1. Settings → About: photograph the model and firmware line. Expect `PF1007L` and `A33`.
2. Ports: DC jack + USB, or USB-C only + TF slot?
3. Connect the A-to-C cable. Run `adb devices`. Many units already give root ADB.

**Gate:** we know the variant, and we know if ADB is on.

### Phase 2 — Full backup + root (1 evening)
1. If ADB is off: use Wes's **Route U** (FEL over USB). Mac scripts exist:
   `scripts/a33-uboot/fel-card-macos.py` and `emmc-macos.py`. [V]
2. Confirm the chip: `sunxi-fel version` → `soc=00001667(A33)`.
   ⚠ If the stub does not enter FEL, the unit may have secure boot. Stop and rethink.
3. **Take a full eMMC backup. Verify its hash. Store 2 copies.**
   Use eMMC at 4-bit / 26 MHz and a powered hub (8-bit dropped off on real units). [D]
4. Then root ADB (Route U patch, about 5 MiB) only if needed.
5. Lock down Android: block port 7806; `pm disable` the AiMOR, `com.yhk.qeota`, `com.DeviceTest` apps.

**Gate:** two verified backups exist. We can always go back to stock.

### Phase 3 — Read the hardware (1 evening) — ⚠ BIG DECISION HERE
Run the commands in `research/01-access-backup-hwid.md` §"Commands to run on the device". The key one:
```
adb -d shell 'dd if=/dev/mem bs=1 skip=$((0x43000000)) count=$((0x20000))' > script.bin
bin2fex script.bin sys_config.fex
```
Read these sections: `[lcd0_para]`, `[ctp_para]`, `[wifi_para]`, `[pmu1_para]`, `[dvfs_table]`, `[dram_para]`.
Also: `lsmod`, `/sys/bus/sdio/devices`, `getprop ro.sf.hwrotation`, the touch firmware inside the `gslX680` module.

**Gate — the screen link (`lcd_if`):**
- `3` (LVDS) or `0` (RGB) → ✅ easy. Continue.
- `4` (MIPI-DSI) → ⚠ weeks more work (panel init sequence). Decide then if we continue.

### Phase 4 — Boot mainline Linux from the SD card (1–2 weekends)
1. **U-Boot**: Wes's working recipe (DRAM 456 MHz, ZQ 15291). Add his PR #6 safe mode:
   the DRAM lane-0 fix and the warm-up init. [D, one unit]
2. **First milestone:** U-Boot lights the panel (LVDS) → `simpledrm` shows the kernel console.
3. **Kernel**: start from Arch Linux ARM's `linux-armv7` 7.2 config, not `sunxi_defconfig`. [V]
   It already has sun4i-drm, lima, AXP, Goodix/Silead, cgroups, uinput, zram.
4. **Device tree**: base on `sun8i-a33-ga10h-v1.1.dts` + `sun8i-reference-design-tablet.dtsi`.
   Skeleton in `research/02-uboot-kernel-dt.md`. Fill it from `sys_config.fex`.
   ⚠ **LVDS trap:** the panel node needs `compatible = "...", "panel-lvds"`. With `panel-simple`
   the driver silently uses the RGB path. [V, `sun4i_tcon.c:1251`]
   ⚠ **CPU supply:** upstream files disagree (DCDC2 vs DCDC3). Keep the CPU at ≤1.008 GHz until the fex says which.
5. USB port: `dr_mode = "peripheral"` (Wes proved this enumerates).

**Gate:** console on screen, `evtest` shows touches, eMMC visible (read-only).

### Phase 5 — Arch Linux ARM root filesystem + network (1 weekend)
1. Build on the Mac: Docker `--platform linux/arm/v7` (runs under QEMU — M-series has no 32-bit ARM). [V]
2. Unpack `ArchLinuxARM-armv7-latest.tar.gz` → `mkfs.ext4 -d` → write to the SD card.
3. First boot: set the clock first (no RTC), then `pacman-key --init && pacman-key --populate archlinuxarm`.
4. **Network, in this order:**
   - a. **USB gadget network (NCM) to the Mac + Mac Internet Sharing.** Sure to work. Use this for bring-up. [V driver; D Wes]
   - b. **AIC8800DC Wi-Fi**: compile `radxa-pkg/aic8800` for 32-bit. Nobody has shown this yet. [U]
   - c. USB dongle: needs host mode + separate 5 V on the single port. [U]
5. Memory: zram 512 MB with **lzo-rle** (the ALARM kernel has only LZO for zram; Omarchy asks for zstd). Add `earlyoom`. Add `psi=1` to the kernel command line. [V]

**Gate:** `ssh` into the frame from the Mac, `pacman -Syu` works.

### Phase 6 — GPU baseline (1 evening)
Run: `drm_info`, `eglinfo`, `kmscube`, `glmark2-es2-drm`. Check `pacman -Ql mesa | grep lima`.

**Gate:** `kmscube` spins on lima.

### Phase 7 — Get a Hyprland that draws (1–2 weekends)
Try in this order. Stop at the first that works well:

| # | Option | What it is | Status |
|---|---|---|---|
| 1 | **Hyprland 0.56 + `MESA_GLES_VERSION_OVERRIDE=3.0`** | Mesa reports ES 3 without a check. Normal Omarchy shaders should compile; some blur styles, motion blur and screen-share will not. | Plausible from code [V]. Prior art on an old Intel GPU (Omarchy PR #14764). |
| 2 | **Hypoland** (`github.com/hegjon/hypoland`) | A GLES 2 fork of Hyprland 0.56, same Lua config, README shows Omarchy 4 at 1280×800 | Never built for ARM. One-person project. |
| 3 | Hyprland on llvmpipe (CPU) | Works for sure, slow | Test reference only |
| 4 | Sway/SwayFX + Omarchy theme | Most robust | Not real Omarchy. Last resort. |

Method: first compile Hyprland's real shaders under the override, with llvmpipe as the known-good control.
Turn off blur and animations at first. Watch for fp16 banding on rounded corners.
Note: the panel is rotated, and the display hardware cannot rotate, so the compositor rotates every frame.

**Gate:** Hyprland shows a terminal on lima at a usable speed.

### Phase 8 — The Omarchy armv7 port (2–3 weekends)
1. Fork Omarchy at tag **v4.0.4** (`basecamp/omarchy`). Pin it — upstream changes fast.
2. Add an `armv7` platform the same way upstream added `aarch64`. About **14 edits**
   (list in `research/04-omarchy-port.md`). **Edit #1:** `omarchy-hw-platform` says "x86" for any
   non-aarch64 CPU, and would then overwrite `pacman.conf` with x86 mirrors.
3. Skip the ISO parts: no LUKS, no btrfs/snapper, no Limine, no Plymouth. Use U-Boot + ext4.
4. Copy the method of the aarch64 port (`hotschmoe/omarchy-arm`). Read its `docs/arm64-port.md` first (20 install failures, each explained).
5. Swap and drop: Chromium → **Firefox** (no 32-bit Chromium since 2022 [V]). Drop about 45 packages
   (Docker, LibreOffice, CUPS, fcitx5, dev tools, intro videos).
6. Touch: **wvkbd** on-screen keyboard, **hyprgrass** gestures. **Turn off the idle lock**
   (the lock screen probably cannot show the on-screen keyboard [U] → you could not unlock it).

**Gate:** Omarchy desktop, menu and theme switch work from the SD card.

### Phase 9 — Move to the internal storage (1 evening)
Only when Phase 8 is stable. Write the image to eMMC through U-Boot `ums` from the Mac.
Keep the SD card and both backups.

---

## 4. What we must build (our own armv7h package repo)

| Package | Why | Where to build |
|---|---|---|
| U-Boot (A33, Wes recipe + PR #6 fixes) | Boot loader | Docker on Mac (cross-compile) |
| Linux kernel + our board DTB | Hardware support | Docker on Mac (cross-compile) |
| `aic8800` module | Wi-Fi | With the kernel |
| ~~Hyprland 0.56.x~~ | **No build needed.** ALARM armv7h ships `hyprland 0.56.2-4` [V, mirror index 2026-10-12] | — |
| Hypoland | GPU option 2 | QEMU armv7 container |
| ~~Quickshell (+ cpptrace)~~ | **No build needed (probably).** ALARM armv7h ships `quickshell 0.3.2-1` and `cpptrace 1.0.4-2` [V]. **Nobody has shown that it runs on 32-bit** [U]. Build only if Omarchy 4 needs a newer version. | — |
| `omarchy`, `omarchy-settings` (our fork) | Omarchy itself | `any` arch — easy |
| wvkbd, hyprgrass | Touch | QEMU armv7 container |
| yay | AUR helper | Prebuilt armv7h exists [V] |

Build farm: a QEMU armv7h `base-devel` container on the Mac (or GitHub Actions) that publishes a
small pacman repo the frame reads over the network. Slow but simple. Faster option later: distcc.

---

## 5. Budget and expectations

- **Disk:** a frame-sized Omarchy is about 2.5–3.5 GB. It fits in 16 GB. [U]
- **RAM:** an idle Omarchy session on 32-bit: about 450–650 MB [U]. One Firefox tab adds about 360 MB [D].
  So: terminals and neovim — fine. One simple web page — the limit.
- **CPU:** about a Raspberry Pi 2. Slower than a Pi 3. [U]
- **Power:** use a 5 V 2 A supply. A laptop USB port is not enough. [U]
- **Heat:** the temperature sensor driver is a module in the ALARM kernel. Make sure it loads, or there is no throttling. [U]

---

## 6. Open questions (answered only by the device)

1. Port variant? eMMC size (16 or 32 GB)? Firmware hash?
2. Does the FEL stub work (no secure boot)?
3. **`lcd_if`: LVDS, RGB or DSI?** ← decides the project
4. Touch chip and firmware?
5. Wi-Fi SDIO ID — is it really AIC8800DC?
6. CPU regulator: DCDC2 or DCDC3?
7. ~~Hyprland version in ALARM armv7h today?~~ **Answered 2026-10-12: 0.56.2-4** [V]. The command needs `-L`:
   `curl -sL http://mirror.archlinuxarm.org/armv7h/extra/ | grep -oE 'href="hyprland-0[^"]*"'`

---

## 7. Why this is worth a post

- First native Omarchy on a photo frame. First Omarchy on 32-bit ARM. First Hyprland on a Mali-400.
- Each gate is a good short video: "the frame boots Linux", "Hyprland on a £50 frame", "Omarchy on 1 GB of RAM".

## Research reports
- `research/01-access-backup-hwid.md` — access, backup, AiMOR risk, device commands
- `research/02-uboot-kernel-dt.md` — U-Boot, kernel, device tree skeleton, Wi-Fi
- `research/03-arch-rootfs.md` — Arch Linux ARM 32-bit, rootfs from a Mac, build farm
- `research/04-omarchy-port.md` — Omarchy 4 internals, package table, port edits
- `research/05-gpu-hyprland.md` — Hyprland on lima, override hack, Hypoland
- `research/06-ram-perf-priorart.md` — RAM budget, speed, prior art
