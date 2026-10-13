# Lab notebook

One entry for each test. Each entry has the command, the numbers, the errors and the reasoning.
Newest entry at the bottom. Do not put serials, MAC addresses or full-eMMC hashes here.

Tags: **[VERIFIED]** = read in source or a primary document. **[DOCUMENTED]** = a second-hand source.
**[UNCONFIRMED]** = inference.

---

## 2026-10-12 — E001: Mac tool check (Phase 1 preparation)

**Question:** Does the Mac have the tools for Phase 1 and Phase 2?

**Commands:** `command -v adb fastboot sunxi-fel brew docker git python3`, `adb version`,
`docker info`, `brew list --formula`.

| Tool | Result |
|---|---|
| `adb` | Present. Version 1.0.41, platform-tools 37.0.1 |
| `fastboot` | Present |
| `brew` + `libusb`, `dtc`, `pkgconf` | Present |
| Docker | Present. OrbStack, server 29.4.0, aarch64 |
| `sunxi-fel` | **Not found.** Build it from source in Phase 2 |

**Result:** The Mac is ready for Phase 1. Phase 2 needs one build (sunxi-tools).

---

## 2026-10-12 — E002: Is the frame on USB? (PLAN Phase 1, step 3)

**Question:** Does the Mac see the frame? Is ADB on?

**Commands:**
```
adb devices -l
ioreg -p IOUSB -l -w0 | grep -iE '"USB Product Name"|"idVendor"|"idProduct"'
system_profiler SPUSBDataType
```

**Result:** No frame.
- `adb devices -l` gives an empty list.
- `ioreg` shows no device with vendor `0x1f3a` (decimal 7994). It shows a monitor, two Anker hubs,
  a LAN adapter, a card reader, one "USB2.0 Hub" and one Espressif debug unit (vendor `0x303a`).
- `system_profiler SPUSBDataType` prints nothing on this macOS version. Use `ioreg`.

**Reasoning:** This is a null result with a small scope. It shows only that no Allwinner device was
on the bus at the time of the test. The owner had not said that the frame was connected. It does
**not** show that ADB is off or that the cable is bad.

**Next:** The owner connects the frame with a USB-A → USB-C data cable. Then run the test again.

---

## 2026-10-12 — E003: Hyprland version in ALARM armv7h (open question 8)

**Question:** Does Arch Linux ARM armv7h ship Hyprland 0.56.2 or 0.49.0? Two search snippets disagreed.

**Command:**
```
curl -sL http://mirror.archlinuxarm.org/armv7h/extra/ | grep -oE 'href="hyprland-0[^"]*"'
```

**Error first:** The command in `CLAUDE.md` and `PLAN.md` had no `-L`. The mirror answers with a
redirect, so `curl -s` returned an empty body and `grep` found nothing. The exit code was 0.
An empty result here did **not** mean "no package". With `-L` the request ended at
`fl.us.mirror.archlinuxarm.org`, HTTP 200, 3,674,177 bytes, 25,219 package lines.

**Result [VERIFIED — mirror index, read 2026-10-12]:**

| Package | Version | Mirror date |
|---|---|---|
| `hyprland` | **0.56.2-4** armv7h | 2026-10-03 |
| `aquamarine` | 0.15.1-1 | 2026-09-17 |
| `quickshell` | **0.3.2-1** armv7h | 2026-10-09 |
| `cpptrace` | 1.0.4-2 | 2026-05-11 |
| `mesa` | 1:26.2.4-1 | — |
| `firefox` | 157.0-1 | — |
| `foot` | 1.28.0-2 | — |
| `hyprutils` / `hyprlang` / `hyprgraphics` | 0.14.2-1 / 0.6.8-5 / 0.5.1-4 | — |
| `hypridle` / `hyprlock` / `hyprpicker` / `hyprsunset` | 0.1.8-2 / 0.9.6-3 / 0.4.7-4 / 0.4.0-3 | — |
| `xdg-desktop-portal-hyprland` | 1.4.1-2 | 2026-09-04 |
| `uwsm` | 0.27.0-1 (any) | 2026-09-15 |
| `drm-info`, `glmark2`, `earlyoom` | 2.10.0-1, 2023.01-2, 1.9.0-1 | — |
| `neovim` | **0.9.1-1** | 2023-06-04 |
| `linux-armv7` (core) | 7.2.10-1 | 2026-10-11 |
| `systemd` (core) | 262-1 | 2026-09-25 |

Not found in `extra` (search scope: the `extra` index only, exact package names):
`wvkbd`, `hyprgrass`, `kmscube`, `chromium`, `yay`. The `alarm` and `aur` repos were not searched.

**Reasoning:**
- Question 8 is closed: ALARM armv7h has Hyprland **0.56.2**. The "stuck at 0.49.0" snippet was wrong
  or old. We do not need to build Hyprland for GPU option 1.
- **Surprise:** `quickshell` has an armv7h package. `PLAN.md` §4 said "No armv7 build exists". That
  was wrong. The package **builds** on 32-bit [VERIFIED]. That it **runs** correctly on 32-bit with
  Omarchy's QML is still [UNCONFIRMED] — a package in a mirror is not a test.
- The Omarchy 4 version requirement for Quickshell is not checked against 0.3.2. Check it in Phase 8.
- `neovim` 0.9.1 is three years old. Omarchy's editor setup probably needs a newer version
  [UNCONFIRMED]. Check it in Phase 8.

---

## 2026-10-12 — E004: Does Wes Bos's repo name our frame?

**Question:** Do the Wes Bos docs name "Humblestead" or `HM-PF1007-BK`?

**Command:** shallow clone of `wesbos/photo-frame-dashboard` (main @ `9dd323e`, 2026-10-11) into
`refs/`, then `grep -rniE 'humblestead|HM-PF1007|B0GGB7LWX8' --include='*.md' .`

**Result:** No match. Scope: the Markdown files on `main` only. The PR branches and the issues were
not searched.

**Reasoning:** The match between our frame and the PF1007L board is still a match by name
[UNCONFIRMED]. The About screen (Phase 1, step 1) is the first real test.

The pass condition from `docs/pf1007l-start-here.md` T1: model `PF1007L`, firmware
`YHK.F-null-A33-1001-D1024-PF1007L-321-OS-AIMOR.0.20260113`. A different date with `A33` in the
string means "untested unit: read-only tests only".

**Unknown:** Whether the AiMOR first-run screen lets you open Settings → About without Wi-Fi.
Wes's docs do not say. Find out on the device.

---

## 2026-10-12 — E005: About screen (PLAN Phase 1, step 1 = Wes T1)

**Question:** Is this unit the PF1007L / A33 board with the firmware that Wes's units have?

**Method:** The owner sent a photo of Settings → About (`IMG_2031.HEIC`, kept outside the repo).
The photo shows the MAC address and the Frame ID. They are **not** copied here (safety rule 6).

**Result [VERIFIED — read from the device's own screen]:**

| Field | This unit | Wes's units A, B, C | Match |
|---|---|---|---|
| Firmware version | `YHK.F-null-A33-1001-D1024-PF1007L-321-OS-AIMOR.0.20260113` | same string | ✅ exact |
| Model | `PF1007L` | `PF1007L` | ✅ |
| AiMOR version | 6.0.78 | 6.0.78 | ✅ |
| AiMOR updates | "Last checked for updates on: 2026-01-29 07:26" | — | — |

**Reasoning:**
- T1 passes. The Humblestead HM-PF1007-BK **is** a PF1007L with the tested firmware string. The
  "match by name" is now a match by the device's own About screen.
- The firmware string says `A33`. This is a label in a string, not a chip read. The chip test is still
  `sunxi-fel version` → `soc=00001667(A33)` (Phase 2). The A33 claim stays [DOCUMENTED] until then.
- The same firmware string does **not** mean the same eMMC content. Wes's rule: derive every hash and
  sector from this unit's own backup.
- The last update check is dated 2026-01-29, 16 days after the firmware date. It is probably a
  factory test [UNCONFIRMED]. It does not show if the frame is on Wi-Fi now.
- Settings → About opens on this unit. Open question 10 is closed if the owner did not join Wi-Fi to
  get there (to confirm with the owner).

## 2026-10-12 — E006: USB test, second run

**Commands:** `adb devices -l`; `ioreg -p IOUSB -l -w0` filtered for vendor 7994 (`0x1f3a`).

**Result:** Empty list. No `1f3a` device. Same scope limit as E002: the owner has not said that the
frame is connected to the Mac with a data cable.

## 2026-10-12 — E007: USB test with the included cable through the monitor

**Setup (owner's report):** The included cable goes from the frame to the monitor (the Mac names it
"MateView"). The frame turns on there. With the cable direct to the MacBook, the frame does not turn on.

**Commands:** `adb devices -l`; `ioreg -p IOUSB -w0` (full tree).

**Result:** The frame has power, but the Mac sees no frame.
- `adb devices -l`: empty.
- The monitor's "USB2.0 Hub" lists only its own two devices (`MateView Combo HID`, `MateView`).
- No `1f3a` device on any controller.

**Reasoning:**
- "No power direct from the MacBook" agrees with Wes's unit C: a USB-C host port gives no power to
  this frame (no CC pull-down resistors) [DOCUMENTED]. It is not a fault of this unit. This applies
  if the cable has USB-C on the Mac end; the cable type is not confirmed yet.
- "Power but no data" has three possible causes, not separated yet: (1) the included cable is
  charge-only, (2) the monitor port gives power but does not pass data for this device, (3) USB data
  is off on the frame. Wes's units showed `1f3a:1000` on stock firmware, so (3) is the least probable.
- Not a result about ADB.

**Next:** Same cable in a USB-A port of the Anker hub. Then a known data cable (USB-A → USB-C).

## 2026-10-12 — E008: Do the monitor's USB-A ports pass data?

**Setup (owner's report):** The included cable is USB-C → USB-A. The USB-A end is in the monitor.

**Commands:** `system_profiler SPDisplaysDataType`; `ioreg -p IOUSB -l -w0 -n "USB2.0 Hub"`;
`ioreg -r -c AppleUSB20Hub -l -w0`. Then a web search for the monitor's port list.

**Result:**
- The monitor is a **Huawei MateView** (the Mac reports vendor "HUAWEI", products `MateView` and
  `MateView Combo HID`).
- It has a real USB hub that the Mac sees: VIA Labs "USB2.0 Hub", `2109:2820`, 480 Mbit/s.
  The hub has **4 ports**. Ports 3 and 4 hold the monitor's own two devices. **Ports 1 and 2 are
  empty** [VERIFIED — ioreg on this Mac].
- Reviews and shop listings: two USB-A ports for external devices, built-in hub, USB 3.2 Gen 1; the
  side USB-C port is the link to the computer; the rear USB-C port is power only [DOCUMENTED].

**Reasoning:**
- The monitor passes data. Two free hub ports + two USB-A sockets on the monitor agree. So cause (2)
  from E007 is improbable.
- The frame is USB 2.0 only. The hub's USB 2.0 half is on the bus, which is the half that the frame needs.
- With the frame powered from one of those sockets, both free hub ports show no device. So no data
  signal comes from the frame through this cable. The remaining causes are: the included cable is
  charge-only (most probable), or the frame's USB data is off.
- Not tested: that the exact socket in use has working data lines. A USB stick in that socket would test it.

**Next:** A USB-A → USB-C cable that is known to carry data, in the same monitor socket.

## 2026-10-12 — E009: Control test — Android phone on the included cable

**Question:** Does the included cable carry data? Control: a device that is known to send data.

**Setup (owner's report):** Android phone on the USB-C end of the included cable. USB-A end in the
monitor socket (same path as E007).

**Commands:** `ioreg -p IOUSB -w0`; `adb devices -l`.

**Result:** No new device. The USB tree is the same as in E008. The monitor hub still shows only its
own two devices. `adb devices -l` is empty.

**Reasoning:**
- An Android phone normally shows as a USB device, also in "charge only" mode [DOCUMENTED — general
  Android behaviour, not tested for this phone model]. It did not show. So the path
  "monitor socket + included cable" carries no data.
- This moves the suspicion from the frame to the path. The frame's USB data is **not** tested yet.
- Two causes remain and one cable cannot separate them: the cable is charge-only (most probable), or
  that monitor socket has no working data lines.

**Next:** A second USB-A → USB-C cable. Test it with the phone first. When the phone shows on the
Mac, move that cable to the frame.

## 2026-10-12 — E010: Second cable, same monitor socket

**Setup (owner's report):** "Changed cable." The device on the cable (phone or frame) was not stated.

**Commands:** `ioreg -p IOUSB -w0`; `adb devices -l`.

**Result:** No new device. Same tree as E008 and E009. `adb devices -l` is empty.

**Reasoning:**
- Two different cables now give no data through the monitor socket. Two charge-only cables in a row
  is possible, but the **monitor socket** is now an equal suspect. E008 showed that the hub has two
  free ports; it did not show that the socket in use has working data lines.
- The control for the socket is a port that is known to carry data: the Anker hub (the LAN adapter,
  the card reader and a disk are live on it).

**Next:** Phone + cable in a USB-A port of the Anker hub. This separates "cable" from "monitor socket".

## 2026-10-12 — E011: The phone shows — a working data path exists

**Setup (owner's report):** "Try now." What the owner changed since E010 was not stated.

**Commands:** `ioreg -p IOUSB -w0`; `adb devices -l`.

**Result:**
- New device `Redmi Note 11` (Xiaomi, `2717:ff08`) on the **monitor hub, port 2** (`@01120000`).
  It is on the monitor, not on the Anker hub.
- `adb devices -l` lists the phone as `device` (USB debugging is on in the phone).

**Reasoning:**
- This is the control that passes: the monitor socket and the cable now in use **both carry data**.
  The monitor-socket suspicion from E010 is wrong for this socket.
- So at least one earlier test failed for a different reason: a charge-only cable, a different
  socket, or a locked phone. Not separated, and no longer important.
- The frame's USB data is still not tested. The test is now clean: same cable, same socket, frame
  in place of the phone.
- ⚠ The phone is an ADB device. With the phone and the frame both connected, a plain `adb` command
  can go to the wrong device. Disconnect the phone before any frame test, or use `adb -s <id>`.

**Next:** Move this exact cable from the phone to the frame. Same monitor socket.

## 2026-10-12 — E012: The frame on USB (PLAN Phase 1, step 3 = Wes T3)

**Question:** Does the Mac see the frame? Is ADB on over USB?

**Setup:** The cable and the monitor socket that passed the control in E011. Frame in place of the
phone. The frame was booting.

**Commands:** `ioreg -p IOUSB -w0` (first read, then a poll each 3 s); `adb kill-server`,
`adb start-server`, `adb devices -l`; `ioreg -r -c IOUSBHostInterface -l -w0`.

**Result [VERIFIED — read from the device over USB]:**

| Item | Value |
|---|---|
| First read (early in the boot) | No device |
| Poll | Device on the monitor hub, port 2, at the first poll step |
| Vendor : product | **`1f3a:1000`** (decimal 7994 : 4096) |
| Product name / vendor name | "Android" / "USB Developer" |
| Interfaces | One. Class 8, subclass 6, protocol 80 = USB mass storage (SCSI, bulk-only) |
| ADB interface (class 255, subclass 66, protocol 1) | **Not present** |
| `adb devices -l` (after a server restart) | Empty |

The USB serial number string is visible to the Mac. It is not copied here (safety rule 6).

**Reasoning:**
- `1f3a` is the Allwinner vendor ID. This is the second sign of an Allwinner chip, after the `A33` in
  the firmware string. It is still not the chip read (`sunxi-fel version`, Phase 2).
- `1f3a:1000` "Android" with no ADB is the stock state of all Wes's tested units
  (`docs/pf1007l-start-here.md` T3 table). Wes's next step for this result: T3b (network ADB), then
  **Route U**. We skip T3b: it needs Wi-Fi, and safety rule 1 says no Wi-Fi before the lock-down.
- "ADB is off" has this scope: no ADB interface on USB, in normal Android boot. Network ADB (port
  5555) is not tested.
- USB data works on this unit with a USB-A → USB-C data cable through the monitor's hub. So Route U
  (FEL over USB) is possible from this desk. The monitor hub reports 2100 mA; that it is strong enough
  for a full eMMC backup is [UNCONFIRMED].
- The frame takes power and data on a USB-C port. The DC jack / TF slot / button question is not
  answered by the owner yet.

**Phase 1 gate:** "We know the variant, and we know if ADB is on."
- ADB: **off on USB.** ✅ known.
- Variant: firmware and model match Wes's units; the port is USB-C. The TF (microSD) slot is not
  confirmed by the owner. Route U needs that slot.

---

## 2026-10-12 — E013: Build sunxi-tools on the Mac (PLAN Phase 2, Route U step 2U.1)

**Owner's answers before this step:** the frame has a microSD (TF) slot; a spare card is available.
Phase 1 gate: passed.

**Commands** (in `refs/photo-frame-dashboard`, as Wes's guide says):
```
git clone https://github.com/linux-sunxi/sunxi-tools.git diagnostics/sunxi-tools
git -C diagnostics/sunxi-tools checkout d7bbd172a5da601a08f94479de308c6fb714a19a
make -C diagnostics/sunxi-tools sunxi-fel
make -C diagnostics/sunxi-tools sunxi-fexc bin2fex
```

**Result:**
- `sunxi-fel v1.4.2-208-gd7bbd17` built with no error. No `SDKROOT` change was necessary on this Mac
  (Wes's issue #13 said that some Xcode versions need it).
- `bin2fex` / `sunxi-fexc` built (for Phase 3).
- FEL stub `bin/fel-sdboot.sunxi`: 8192 bytes, magic `eGON.BT0`, SHA-256
  `2ccec08a026840571f3804671ba72afae840db27112a43f2b1f122075bc808bc`. This is the hash in Wes's guide
  and in `fel-card-macos.py` [VERIFIED].
- Control: `sunxi-fel version` with the frame in normal Android gives
  `ERROR: Allwinner USB FEL device not found!`. This is the expected answer: the frame is `1f3a:1000`,
  not FEL (`1f3a:efe8`). It shows that the tool runs and does not report a false device.

**External disks now** (`diskutil list external physical`): only `disk10`, the owner's 2.0 TB disk.
No card is in the reader. ⚠ `disk10` must never be the target of a card command.

## 2026-10-12 — E014: Build the read-only backup U-Boot (Route U step 2U.4)

**Question:** Does Wes's recipe build on this Mac, and is the result the same as on Wes's unit C?

**Command:** `scripts/a33-uboot/build-uboot.sh` in `refs/photo-frame-dashboard` (Docker on OrbStack,
Ubuntu 24.04 image, cross-compiler `arm-linux-gnueabihf-`). Source: U-Boot v2025.10, commit
`e50b1e8715011def8aff1588081a2649a2c6cd47`, + `pf1007l-uboot.patch`.

**Result — build A (Wes's recipe, no change):**

| Item | Value |
|---|---|
| Output | `diagnostics/a33-uboot-out/u-boot-sunxi-with-spl.bin`, 537,976 bytes |
| Config | `DRAM_CLK=456`, `DRAM_ZQ=15291`, `MMC_SUNXI_SLOT_EXTRA=2`, `BOOTDELAY=-2`, `CRC32_VERIFY`, `CMD_USB_MASS_STORAGE`, `USB_MUSB_GADGET` |
| SPL code end | `0x456a` — the same value as in Wes's guide. Limit: `0x5e00` |
| SHA-256 (binary) | `65c0624acc79c9f1ba5271c175bdccae70883a98bd56819d039a6266bf4ca9eb` |
| SHA-256 (`ums-readonly.scr`) | `234b0fb3979e75c7c03ceb3c9ae50b5ba5e2d8323f830006034657ed6e667310` |
| Compiler warnings / errors | 0 / 0 |
| Read-only layer 1 | The string `ums: refused write of %lx blocks at %lx` is in the binary [VERIFIED] |
| eMMC bus | 8-bit, driver default maximum 52 MHz |

The binary hash is not comparable with Wes's: the build has a time stamp
(`U-Boot 2025.10 (Oct 12 2026 - 10:12:06 +0000)`).

**Result — build B (fallback, our change):** the same source, with the `&mmc2` node changed to
`bus-width = <4>; max-frequency = <26000000>;`. Output in `diagnostics/a33-uboot-out-4bit/`.
SPL code end `0x456a`. SHA-256 `08d0eaf907113b35abcc2001dcdbb550a558160b2bb20842c9cf2c3a30a2830d`.
The built DTB shows `bus-width = <0x04>`. The read-only string is present.

**Reasoning:**
- Why build B: Wes's issues #18/#24/#27 report that the eMMC dropped off USB during the read at
  8-bit / 52 MHz on some units [DOCUMENTED]. U-Boot's driver-model path calls `mmc_of_parse`
  (`drivers/mmc/sunxi_mmc.c:696`), so the DT values take effect [VERIFIED in source]. It is not tested
  on a device.
- Plan: start with build A (the tested recipe). If the backup drops or the two read passes differ,
  change to build B. One change at a time.
- Both builds are RAM payloads. FEL loads them into DRAM. Nothing is written to the eMMC or the card.
- Not checked on the device: that the read-only layer 2 (write-protect flag on the LUN) shows on the
  Mac. `diskutil info` must show "Media Read-Only: Yes" before any backup command.

**Next:** FEL stub card. The owner puts the spare card in the Mac's reader. Then
`fel-card-macos.py backup` and `write` (they need `sudo`, so the owner runs them).

## 2026-10-12 — E015: Save the spare card's contents, then give it the layout the stub script needs

**Owner's request:** save the contents of the card before it is formatted and rewritten.

**Card (read with `diskutil info`):** `disk12`, 15,939,928,064 bytes (31,132,672 sectors), USB card
reader, removable, MBR. One FAT32 partition "NO NAME", start at **sector 2048**, 91 MB used.
Contents: e-books and two e-reader firmware files.

**Step 1 — file backup.** Commands: `rsync -a` (without `.Spotlight-V100`, `.fseventsd`,
`.Trashes`) to `backups/sdcard-16gb-original/files/`; then `shasum -a 256` of each file on the card
and of each file in the copy.

| Item | Value |
|---|---|
| Files on the card | 256 |
| Files in the copy | 256 |
| Checksum lists | Equal (`cmp` of the two sorted lists) |
| Size of the copy | 77 MB |

Scope: this is a file copy, not a sector image. `/dev/rdisk12` is `root:operator`, mode `r-----`,
so a raw read needs `sudo`. Deleted files are not in the backup. A restore note is in
`backups/sdcard-16gb-original/README.md`. The folder is git-ignored.

**Step 2 — layout problem found before the write.** `fel-card-macos.py` stops if a partition starts
before sector 8192 (`check_layout`: "too close to the stub"). This card's partition started at 2048.
The stub goes to sectors 16–31, so there is no real overlap, but Wes's guide says: "If that check
fails, stop; do not overwrite the partition table to force a match", and our rule is not to edit a
guard. The owner had agreed to a format. So the fix is a new partition table with a 4 MiB gap.

Command (after a guard on size 15,939,928,064, removable, USB, not internal):
```
diskutil partitionDisk disk12 2 MBR "Free Space" gap 4M "MS-DOS FAT32" FELCARD R
```

**Result:** MBR, one FAT32 partition "FELCARD", **Partition Offset 4,194,304 bytes = sector 8192**
(`newfs` printed `hid=8192`). This is the layout that the script accepts.

**Observation, cause unknown:** after this step the owner's 2 TB disk (`disk10`, "My Passport
Wireless") was not on the USB bus and its volume was not mounted. No command of this session named
`disk10`; the partition command was guarded to `disk12` and its output lists only `disk12`. The
system log (25 minutes, kernel + disk arbitration) has no line for it. Probable causes: the owner
disconnected it, or the disk (it has a battery) went off [UNCONFIRMED]. Told the owner.

**Found for later — disk space:** `emmc-macos.py backup` writes the full raw image (about 15.6 GB) to
`refs/photo-frame-dashboard/backups/` and then makes the gzip. The Mac's internal disk has **11 GB
free**. This is not enough. Fix before the backup step: free 20 GB, or put that `backups` folder on
the external disk.

**Next:** the owner runs `fel-card-macos.py backup disk12 15939928064`, then `... write ...` (both
need `sudo`).

## 2026-10-12 — E016: Write the FEL stub to the card (Route U step 2U.2)

**Commands** (the owner ran them; they need `sudo`):
```
sudo python3 -I scripts/a33-uboot/fel-card-macos.py backup disk12 15939928064
sudo python3 -I scripts/a33-uboot/fel-card-macos.py write  disk12 15939928064
```

**Result — `backup`:**
```
Unmount of all volumes on disk12 was successful
  partition type 0x0b starts at sector 8192
Card prefix backed up: .../refs/photo-frame-dashboard/backups/a33-fel-card-prefix.bin.gz
SHA-256: 956e172cfcdc3e87fb80f683c16e141830c438e182a9487b1b6da49bf6b06cb8
```
**Result — `write`:**
```
Unmount of all volumes on disk12 was successful
  partition type 0x0b starts at sector 8192
Exactly 8192 bytes changed at byte offset 8192. Readback verified.
```

**Reasoning:**
- Both commands passed all of the script's guards: external, removable, USB, exact size, MBR,
  partition at or after sector 8192, two equal reads, stub hash, and a full readback of the first
  4 MiB after the write.
- The layout line confirms E015: the new partition starts at sector 8192.
- The prefix backup (8,912 bytes gzip) is owned by `root`, mode `0600`, because `sudo` made it.
  `restore` puts the original 8 KiB back.
- The card was ejected with `diskutil eject disk12` after a size check.
- This is a write to the **card** only. Nothing has been written to the frame.
- Not tested yet: that the frame's boot ROM accepts the stub. That is the secure-boot test (next).

**Next (Route U step 2U.3):** cable out of the frame, card in the frame, cable in.
Expect a dark screen, USB ID `1f3a:efe8`, and `sunxi-fel version` → `soc=00001667(A33)`.

## 2026-10-12 — E017: FEL test — chip identity and secure boot (Route U step 2U.3, open question 2)

**Question:** Does the boot ROM run the unsigned stub from the card? Which chip is it?

**Setup (owner):** cable out, stub card in the TF slot, cable in. Same cable and monitor socket as E012.

**Commands:** `ioreg -p IOUSB -l -w0`; `diagnostics/sunxi-tools/sunxi-fel version`.

**Result [VERIFIED — read from the chip's boot ROM over USB]:**
```
AWUSBFEX soc=00001667(A33) 00000001 ver=0001 44 08 scratchpad=00007e00 00000000 00000000
```
- USB ID: vendor 7994 : product 61416 = **`1f3a:efe8`** (FEL). On the monitor hub, port 2. The device
  has no name string in `ioreg` (`IOUSBHostDevice`), which is normal for the boot ROM.
- The line is the same as the one in research/01 ("FEL identity to expect") and in Wes's issues
  #18/#19/#24, field for field.

**Reasoning:**
- **The chip is an Allwinner A33** (SoC ID `0x1667`). This was [DOCUMENTED] from the firmware string;
  it is now [VERIFIED] from the boot ROM. So the target is **32-bit armv7** (4× Cortex-A7). The "ARM64
  ABI" line in one of Wes's docs does not apply to this unit.
- **The boot ROM ran an unsigned eGON image from the SD card, before the eMMC.** So secure boot does
  not block us on this unit, and "SD first" is confirmed on this unit. Open question 2 is closed.
- Scope: this shows the boot ROM stage only. It does not show that U-Boot's DRAM setup works on this
  unit (Wes's PR #6 unit needed a DRAM lane-0 fix). The U-Boot RAM load is the next test.
- The SID (chip serial) was not read. It is an identifier (safety rule 6).

**Next:** load build A of the read-only U-Boot into RAM over FEL (`sunxi-fel -p uboot ... write
0x43100000 ums-readonly.scr`). Needs the owner's go. First fix the disk space for the backup.

## 2026-10-12 — E018: Read-only U-Boot in RAM over FEL; the eMMC shows on the Mac (Route U step 3.1)

**Question:** Does Wes's U-Boot (build A) start on this unit (DRAM setup), and does `ums` show the eMMC?

**Preparation:** The owner connected a 5 TB disk. Volume `PAOLO_BACKUP` (HFS+, 45 GB free) holds the
backup folder `omarchy-frame-backups/`. `refs/photo-frame-dashboard/backups` is now a symlink to it.
The card prefix backup from E016 stays on the Mac in `backups-card-prefix/` (a symlink in the new
folder points to it, so `fel-card-macos.py restore` still finds it).
⚠ The new disk is `disk10` — the number that the old 2 TB disk had. Disk numbers mean nothing; use sizes.

**Command (11:29:15):**
```
sunxi-fel -v -p uboot diagnostics/a33-uboot-out/u-boot-sunxi-with-spl.bin \
  write 0x43100000 diagnostics/a33-uboot-out/ums-readonly.scr
```
**Output:**
```
found DT name in SPL header: sun8i-a33-pf1007l-backup
Stack pointers: sp_irq=0x00002000, sp=0x00005E08
MMU is not enabled by BROM
=> Executing the SPL... done.
Writing image "U-Boot 2025.10 for sunxi board", 505144 bytes @ 0x4A000000.
Passing boot info via sunxi SPL: script address = 0x43100000, uEnv length = 0
Starting U-Boot (0x4A000000).
```

**Result [VERIFIED on this unit]:**
- USB device "USB download gadget" on the monitor hub about 4 s after the start. Two disks:

| Disk | Media name | Size | Read-only | What |
|---|---|---|---|---|
| `disk14` | UMS disk 0 | 15,939,928,064 bytes | **Yes** | The stub card (FELCARD) |
| `disk15` | UMS disk 1 | **15,634,268,160 bytes = 30,535,680 sectors** | **Yes** (`WritableMedia` = false) | **The eMMC** |

- eMMC partition table as macOS shows it: MBR; FAT16 "Volumn" 33.6 MB; 12 Linux partitions
  (16.8 MB, 33.6 MB, 1.1 GB, 33.6 MB, 33.6 MB, 805.3 MB, 16.8 MB, 33.6 MB, 524 KB, 16.3 MB, 83.9 MB,
  16.8 MB); FAT32 13.4 GB (the user data partition).
- macOS mounted `Volumn` and `FELCARD` read-only by itself.

**Reasoning:**
- "Executing the SPL... done" + a running U-Boot gadget: **Wes's DRAM values (456 MHz, ZQ 15291) work
  on this unit** for this load. The lane-0 fix of Wes's PR #6 unit was not necessary here. Scope: one
  start, no memory test.
- The eMMC has **30,535,680 sectors: the same size as Wes's units B and C** (16 GB class). The Amazon
  listing said 32 GB. Open question 1 (eMMC size) is closed: it is 16 GB, not 32 GB.
- Both read-only layers show on the Mac side: macOS reports "Media Read-Only: Yes".
- Stability: the gadget was still on the bus more than 60 s after the start, so this unit did not do
  the "reset to FEL after 41–50 s" that Wes's issues #17/#19 report. (One observation.)
- Observed: `pmset` lists `backupd` — a Time Machine backup may run on the same external disk. It can
  make the copy slower. It is on a different volume.

**Next:** the owner runs `sudo python3 -I scripts/a33-uboot/emmc-macos.py backup disk15 15634268160`.
Expected time: about 50–60 minutes (two full reads at about 12 MB/s, one image check, gzip).

## 2026-10-12 — E019: Full eMMC backup, run 1 (build A, 8-bit) — FAILED at 3 %

**Command (the owner ran it, 11:33):**
`sudo python3 -I scripts/a33-uboot/emmc-macos.py backup disk15 15634268160`

**Numbers:**

| Item | Value |
|---|---|
| Speed at the start | 5.0 MB/s, steady for the first minute (Wes's unit C: about 12.6 MB/s) |
| Last progress line | `pass 1 (copy):   3%    2.3 MB/s` (average since the start) |
| Bytes copied | 473,956,352 = 113 chunks of 4 MiB = 452 MiB |
| End | about 11:37, 3.5–4 minutes after the start |
| Error | `OSError: [Errno 6] Device not configured` in `source.read(...)` (line 68) |

**State after the error:**
- `disk14` and `disk15` are gone. The "USB download gadget" is gone from the monitor hub.
- **No `1f3a` device at all**: not the gadget, not FEL. Checked for 35 s. `sunxi-fel version` →
  "Allwinner USB FEL device not found".
- The macOS kernel log has no USB or disk line for that minute (the query found nothing).
- No backup exists. The script made no `.sha256` file. Its guards worked: it did not report success.

**Reasoning:**
- The average speed fell from 5.0 to 2.3 MB/s. So the read **stalled** for a time before the device
  left. A stall followed by a drop looks like read timeouts on the eMMC, not like a clean unplug.
- The frame did **not** come back in FEL. A power loss with a restart would boot the stub card again
  and show `1f3a:efe8`. So "brown-out and reboot" is less probable than "U-Boot stopped or hung".
  With `BOOTDELAY=-2` and a failed `ums`, U-Boot ends at a prompt with no USB device — this fits.
- Power as the cause is not excluded: the hub's port limit reads 500 mA. But the frame ran Android
  with the backlight on from this same port (E012), which needs more current than U-Boot with a
  dark screen [UNCONFIRMED, not measured].
- This is the failure that Wes's issues #18/#24/#27 report for some units at 8-bit / 52 MHz
  [DOCUMENTED]. The planned answer is build B (4-bit, 26 MHz). One change at a time.
- Not known: whether the owner touched the cable or the frame.

**Kept as a control:** the 452 MiB that were read are saved as
`run1-buildA-8bit-dropped.first-452MiB.img` on the backup disk. The same range of the next run must
be equal. If it is not, the reads are not stable.

**Next:** power-cycle the frame (cable out, cable in) → FEL → load build B → backup again.
If build B also drops: change the power path (powered hub or Anker hub), and nothing else.

## 2026-10-12 — E020: Try to restart the hung frame from the Mac (owner away)

**Question:** Can the Mac power-cycle the frame's USB port?

**Commands and results:**
1. `brew install uhubctl` (2.6.0). `uhubctl` lists the monitor hub as
   `hub 1-1 [2109:2820 VIA Labs USB2.0 Hub, 4 ports, ppps]` ("ppps" = per-port power switching).
2. `uhubctl -l 1-1 -p 2 -a off`, 6 s, `-a on`. Then `uhubctl -n 2109:2820 -p 2 -a off`, 12 s, `on`.
   The hub reported `Port 2: 0000 off`, then `0100 power`. **The frame did not return** (no `1f3a`
   device for 30 s each time).
3. Display sleep (idle timer, 11:44:27) and wake (`caffeinate -u`): the monitor hub stayed on the bus;
   the frame did not return.

**Error of this session:** both `uhubctl` commands also switched **port 2 of the Anker USB 3 hub**
(the LAN adapter) off and on. Cause: `uhubctl` pairs a USB 2 hub with a USB 3 "dual" hub and acts on
both; it paired the monitor's USB 2 hub with the Anker hub. The `-l` and `-n` filters do not stop
this. The option `-e` (exact, no USB 3 duality) does. The LAN adapter reconnected each time; the
Mac's default route was Wi-Fi (`en0`). Told the owner. **Rule: use `uhubctl -e` always.**

**Reasoning:** the hub accepts the power command but the frame does not restart. The probable
reading: this hub does not switch VBUS for real [UNCONFIRMED]. So the frame cannot be restarted
without a hand on the cable.

## 2026-10-12 — E021: Build B (4-bit, 26 MHz, ZQ 15291) — did not start

**Setup:** the owner replugged the frame (11:54). `sunxi-fel version` → A33, as in E017.

**Command (11:54:58):** `sunxi-fel -v -p uboot diagnostics/a33-uboot-out-4bit/u-boot-sunxi-with-spl.bin
write 0x43100000 diagnostics/a33-uboot-out-4bit/ums-readonly.scr`

**Result:** "Executing the SPL... done", "Starting U-Boot (0x4A000000)". Then nothing: no "USB download
gadget", no UMS disk, no FEL, for 2 minutes. A wait of 9 more minutes for a replug found no FEL
(the owner was away).

**Reasoning:** the boot script has a fallback (`ums 0 mmc 0,1 || ums 0 mmc 1 || ums 0 mmc 0`), so a
bad eMMC setting alone should still show the SD card. No device at all means U-Boot stopped or hung
before or in the USB start. This does not fit "the 8-bit bus is the problem". It fits an unstable
system: power or memory. Build B itself may also be at fault; build A was not run again to compare.

## 2026-10-12 — E022: The owner's report on power

**Owner:** "When I first connected it to USB only it died after a while" (in normal Android, on the
monitor socket).

**Reasoning:**
- This reverses the argument in E019 ("Android ran from this port, so power is less probable").
  Power is now the first suspect for the drops.
- The monitor hub's ports report a 500 mA limit (E019). Wes's issues #16/#24: backups died on weak
  hubs and a powered hub fixed it [DOCUMENTED]. PLAN.md lists a powered hub as a must-have; this
  session went on without it.
- Not measured: the frame's current. Not known: the rating of the frame's own power adapter.

## 2026-10-12 — E023: Hardware config from the partial dump (PLAN Phase 3, early) — ⚠ the screen is DSI

**Idea:** run 1 failed, but its first 452 MiB hold the vendor boot chain. The config file is there.

**Method:** scan the dump for section names; walk back to the `script.bin` header; `bin2fex`.

**Layout found in the dump (this unit):**

| Item | Where |
|---|---|
| MBR | sector 0. Partitions: FAT32 at 4,366,336; FAT16 at 73,728; extended at 1 |
| `boot0` (`eGON.BT0`, 32,768 bytes) | sector 16 |
| Vendor U-Boot (`uboot` header) | sector 38,192 |
| `script.bin` | **sector 40,144** (U-Boot + 0xF4000), 40,076 bytes, 78 sections, version 1.2 |
| Android boot image (`ANDROID!`) | **sector 172,032** — the same sector as on Wes's units |

`bin2fex` decoded it with no error and the size in the header equals the size read. Clean copy:
`dumps/sys_config.fex` (916 lines).

**Scope:** one read, from a run that later failed. The file passed its own structure check, and it is
far from the place of the drop (20 MiB vs 452 MiB). Read it again from the verified backup. Tag:
[VERIFIED, single read].

**Values (this unit):**

| Section | Value | Meaning |
|---|---|---|
| `[product]` | `machine = "U708HC"`, `version = "A33-Tablet"` | Board name inside the vendor config |
| `[lcd0_para]` | **`lcd_if = 4`** | **MIPI-DSI.** Not LVDS. |
| | `lcd_driver_name = "yhk_zr789_sq9365_101"` | The vendor panel driver that holds the init sequence |
| | `lcd_x = 800`, `lcd_y = 1280`, `lcd_dclk_freq = 67` | Native portrait panel, 67 MHz |
| | `lcd_dsi_lane = 4`, `lcd_dsi_if = 0`, `lcd_dsi_format = 0` | 4 lanes, video mode, RGB888 |
| | `ht 854`, `hbp 36`, `hspw 18`, `vt 1314`, `vbp 14`, `vspw 4` | Timings |
| | `lcd_bl_en = PH06`, `lcd_gpio_0 = PH07`, PWM ch 0 on PH00, 50 kHz, pol 0 | Backlight and (probably) reset |
| | `lcd_power = axp22_dc1sw`, `lcd_power1 = axp22_eldo3` | Panel supplies |
| `[ctp_para]` | `ctp_name = "gsl_m86_hd"`, TWI0, addr `0x40`, INT PB05, wake PH01, `axp22_ldoio1` 3.3 V | Silead GSL touch; revert X and Y; max 1024×600 |
| `[wifi_para]` | `wifi_sdc_id = 1`, `wl_reg_on = PL06`, `wl_host_wake = PL07` | Wi-Fi on SDIO MMC1 (PG pins). No chip name here |
| `[rf_para]` | `module_num = 10`, power `axp22_dldo1` + `dldo2` 3.3 V, `chip_en = PL02` | |
| `[pmu1_para]` | `pmu_twi_addr = 52` (0x34); `[s_rsb0]` used, PL00/PL01 | AXP22x on RSB |
| `[power_sply]` | `dcdc1 3300`, `dcdc2 1200`, `dcdc3 1200`, `dcdc5 1500`, `aldo1 3300`, `eldo3 3300`, `dc1sw 3300` | Does not say which DCDC feeds the CPU |
| `[dvfs_table]` | `max_freq = 1200 MHz`; 1008 MHz at 1200 mV; 1200 MHz at 1320 mV | `boot_clock = 1008` |
| `[mmc0_para]` | 4-bit, PF00–PF05, detect PB04 | SD slot |
| `[mmc2_para]` | 8-bit, PC05–PC16; `[card2_boot_para] card_line = 4` | eMMC: the kernel uses 8 lines, the vendor boot uses 4 |
| `[uart_para]` | debug TX PF02, RX PF04 | Shared with the SD slot, as expected |
| `[usbc0]` | `usb_port_type = 2` (OTG), ID PH08, VBUS detect `axp_ctrl` | |
| `[gsensor_para]` | TWI1, addr `0x19`, INT PB06 | An accelerometer is declared |
| **`[dram_para]`** | `dram_clk = 456`, **`dram_zq = 0x7bfb` (31739)**, `dram_odt_en = 1` | See below |

**DRAM finding.** The frame's own `boot0` header (sector 16, offset 0x38) says the same:
`dram_clk = 456`, **`dram_zq = 31739 (0x7bfb)`**, `dram_para1 = 0x10f40400`, `dram_tpr13 = 0x101`.
Wes's recipe, and all four A33 defconfigs in U-Boot, use `CONFIG_DRAM_ZQ=15291` (`0x3bbb`).
U-Boot writes both bytes of this value to `zqcr1` (`dram_sun8i_a33.c:244` and `:249`): byte 0 is
`0xfb` here vs `0xbb`, byte 1 is `0x7b` vs `0x3b`. **So builds A and B ran this unit's memory with an
impedance calibration that is not the vendor's.**

**Reasoning:**
- **Screen link = DSI. This is the hard branch of the Phase 3 gate.** No upstream A33 board uses DSI
  (research/02). The work: a panel driver with the vendor init sequence. The sequence is in the
  vendor kernel driver `yhk_zr789_sq9365_101`; the kernel is in the boot image at sector 172,032,
  which is inside this dump. Also: U-Boot cannot light this panel, so the first picture comes from
  the kernel.
- "sq9365" may be a JD9365-class controller; mainline has `panel-jadard-jd9365da-h3` for 800×1280
  panels [UNCONFIRMED — a name resemblance only].
- The DRAM ZQ difference is a second, independent suspect for the drops (run 1 after 8 minutes, run 2
  at the start). It does not explain the owner's report from Android (Android uses the vendor
  `boot0`), so power stays the first suspect. Project rule: the device's value beats the reference.
- Touch is Silead GSL (as expected); it needs the firmware from the vendor module.
- The Wi-Fi chip is not named in the fex.
- CPU regulator (DCDC2 vs DCDC3): still open.

## 2026-10-12 — E024: U-Boot builds C and D with the frame's own DRAM ZQ

Same source and method as E014. One config change: `CONFIG_DRAM_ZQ=31739`.

| Build | ZQ | eMMC bus | Folder | SPL end | SHA-256 |
|---|---|---|---|---|---|
| A | 15291 | 8-bit | `a33-uboot-out/` | `0x456a` | `65c0624a…` |
| B | 15291 | 4-bit, 26 MHz | `a33-uboot-out-4bit/` | `0x456a` | `08d0eaf9…` |
| **C** | **31739** | 8-bit | `a33-uboot-out-C/` | `0x456a` | `60e63ccfc61c8d0bb10cebe2785bdd6eeedcfeca40166b87b4fae2d9493109cb` |
| **D** | **31739** | 4-bit, 26 MHz | `a33-uboot-out-D/` | `0x456a` | `699a19de94174d3dbb808110b7183347f22c69dd0b09c05d701dd525cf1ed8aa` |

All four have the read-only string. None of C and D has run on the frame.

**Test plan for the next visit (no `sudo` needed for steps 1–3):**
1. Stronger power port first (E022).
2. Memory test over FEL: run only the SPL (`sunxi-fel spl`), write a random block to DRAM, read it
   back, compare. Do it with SPL A (ZQ 15291) and SPL C (ZQ 31739).
3. Idle test: load build C, watch for 10 minutes that the disks stay.
4. Backup with the build that passes.

## 2026-10-12 — E025: The DSI panel init sequence, from the vendor module (no frame needed)

**Question:** DSI needs the vendor init sequence (E023). Is it in the dump, and which controller is it?

**Method:**
1. Android boot image at sector 172,032 of the dump: kernel 10,221,784 bytes (a plain ARM `Image`),
   ramdisk 5,660,297 bytes (gzip cpio), page size 2048, empty command line.
2. Kernel: `Linux version 3.4.39 ... #1 SMP PREEMPT Tue Jan 13 19:38:12 CST 2026`. It has the strings
   `aic8800`, `rtl8723bs`, `rtl8723au`.
3. The ramdisk holds `lcd.ko`, `disp.ko`, `gslX680new.ko`, `nand.ko`, `sw-device.ko`,
   `sunxi-keyboard.ko`.
4. `lcd.ko` is an ARM ELF module, **not stripped, with debug info**. A small symbol-table parser lists
   the symbols of the source file `drivers/video/sunxi/lcd/panels/yhk_zr789_sq9365_101.c`.

**Result [VERIFIED from this unit's module; single read of the dump]:**

| Symbol | Kind | Size |
|---|---|---|
| `wjwx8006a_initialization` | data, `.data+0x36e40` | 14,688 bytes |
| `LCD_panel_init` | function | 320 bytes |
| `LCD_power_on`, `LCD_open_flow`, `LCD_bl_open`, `LCD_cfg_panel_info`, `LCD_close_flow`, … | functions | 28–248 bytes |
| `yhk_zr789_sq9365_101_panel` | global data | 48 bytes |

- Table layout: 204 records of 72 bytes: `{u32 cmd; u32 count; u8 para[64]}`.
- **201 register writes, each with 1 parameter.** Then `11` (sleep out), special `0xff0` count 120
  (a 120 ms delay), `29` (display on), special `0xff0` count 20 (20 ms), special `0xff1` (end).
- First writes: `E0 00`, `E1 93`, `E2 65`, `E3 F8`, `80 03`, `E0 01`, … Last: `E0 00`, `E6 02`,
  `E7 0C`, `11`, `29`.
- Full text: `dumps/panel/sq9365_init_sequence.txt`.

**Check against mainline** (`drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c`, torvalds/linux
master, fetched today to `refs/linux-snippets/`): lines 56–67 send page select `E0`, then `E1 93`,
`E2 65`, `E3 F8`, and `80 03` for 4 lanes. **This is the same unlock sequence.** The driver has 15
panels, among them 800×1280 10.1" panels (`chongzhou,cz101b4001`, `kingdisplay,kd101ne3-40ti`,
`radxa,display-10hd-ad001`). Mainline `sun8i-a33.dtsi` has `dsi@1ca0000`
(`allwinner,sun6i-a31-mipi-dsi`) and the D-PHY node, both `status = "disabled"`.

**Reasoning:**
- **"sq9365" is a Jadard JD9365DA-class controller** [VERIFIED by the sequence match]. The panel part
  of the DSI work is now: add one panel entry (this table + the fex timings) to an existing mainline
  driver. That is days, not weeks.
- What stays hard and untested: (1) no upstream A33 board enables the DSI host, so `sun6i_mipi_dsi`
  on this board is unproven; (2) U-Boot cannot light the panel, so the first picture comes late, from
  the kernel; (3) with a dark screen and no serial console, a failed boot gives no information. A
  3.3 V USB-UART adapter moves from "optional" to "strongly recommended". Note that the debug UART
  pins (PF02/PF04) are the SD slot's pins.
- Not done yet: the power-on order and delays (`LCD_power_on`, `LCD_open_flow`: `dc1sw`, `eldo3`,
  reset on PH07, backlight PH06). They need a disassembly of about 600 bytes of ARM code.
- Not done yet: the touch firmware table inside `gslX680new.ko` (same method).
- The kernel string `aic8800` supports "Wi-Fi = AIC8800" [VERIFIED string only; the SDIO ID is not read].

## 2026-10-12 — E026: Tools for the next visit (written and tested without the frame)

**Why:** a backup run takes about 2 hours at 5 MB/s, and Wes's script starts from zero after a drop.
The owner's time at the desk is short.

**1. `scripts/emmc-backup-resumable.py`** — chunked backup, 256 MiB chunks. Each chunk: read, read
again, compare, reject 0xCC filler, check the stored file, then record the SHA-256 in
`manifest.json`. A drop loses one chunk. `assemble` checks all chunks and writes the image, the gzip
and the `.sha256` with the file names that Wes's tools use. `compare` checks a control file against
the start of the backup. The disk guards (`UMS disk N`, exact size, external USB, not writable) are
copied from Wes's `emmc-macos.py`. It only reads the disk.

Test with a fake disk (700 MiB file, the disk guard replaced by a stub):

| Test | Result |
|---|---|
| Simulated drop in chunk 1 (`OSError 6`) | Stops with a clear message; chunk 0 kept; no partial file left |
| Second run | "1 of 3 chunks are done. 2 to read." → all done |
| `compare` with a good control (300 MiB) | "Equal: the first 314572800 bytes…" |
| `compare` with one changed bit at 270 MiB | "STOP: difference at byte 283115520" (correct position) |
| `assemble` | Image equals the fake disk; `.sha256` equals the real hash |
| Different disk size | "STOP: manifest is for a disk of …" |
| One changed bit in a chunk file | "STOP: chunk 1 does not match the manifest" |

Not tested: the real disk guard (`open_disk`) and a real UMS disk. The first real run is the test.

**2. `scripts/frame-check.py`** — no `sudo`:
- `fel`: checks FEL and the A33 line.
- `memtest <build>`: runs only the SPL, then writes random 2 MiB blocks at 5 DRAM addresses
  (0x42000000 … 0x7F000000), reads them back after all are written (this also finds a wrong DRAM
  size), then copies an 8 MiB block through 24 places inside the frame and compares.
- `load <build>`: loads a build, waits for the two UMS disks, stops if a disk is writable, prints
  the backup command.
- `watch`: logs each change of the frame's USB identity with a time stamp to `dumps/raw/usb-watch.log`.

Tested without the frame: `fel` stops with the correct message; an unknown build is refused;
`usb_state` → "absent"; `ums_disks` → empty; all four build folders resolve. The `memtest` and
`load` paths are not tested (they need the frame).

**3. Three agents run in parallel** (the owner asked for this): panel power sequence from `lcd.ko`;
touch firmware from `gslX680new.ko`; draft panel patch + board DTS. Their results get their own
entries after review.

**Plan for the next visit:** stronger power port → replug → `frame-check.py memtest C` →
`frame-check.py load C` (after `memtest` the SPL runs a second time; if the load fails, replug and
load directly) → `watch` in the background → the owner runs the resumable backup with `sudo`.

## 2026-10-12 — E027: Panel power sequence from the vendor module (agent result, reviewed)

**Method:** an agent disassembled the ten functions of `yhk_zr789_sq9365_101.c` in `lcd.ko` (ARM A32)
with the `.rel.text` relocations applied, and the helper functions in `disp.ko`. Files:
`dumps/panel/power-sequence.md` (306 lines) and `dumps/panel/lcd-ko-disassembly.txt` (2,938 lines).
Review by the main session: the `LCD_panel_init` listing (0xa850–0xa974) shows the calls and the
constants that the tables below give.

**Power-on [VERIFIED in the disassembly; not a hardware test]:**

| Step | Action | Delay after (ms) |
|---|---|---|
| 0 | (display driver, before the flow) reset PH07 is an output at level 1 | 0 |
| 1 | `axp22_dc1sw` on | 10 |
| 2 | `axp22_eldo3` on | 0 |
| 3 | D-PHY on, lanes in LP-11 | 50 |
| 4 | reset 1 → 10 ms → **0 → 20 ms** → 1 → 60 ms → **0 → 30 ms** → 1 | 30 |
| 5 | The init table (201 writes, then `11 00`) | 120 |
| 6 | `29 00` | 20, then 150 |
| 7 | DSI high-speed clock on | 300 |
| 8 | TCON on, high-speed video on | 100 |
| 9 | PWM on, then backlight enable PH06 high | 0 |

**Power-off:** backlight enable off, PWM off, video off, reset 0, 20 ms, D-PHY off, 30 ms,
`eldo3` off, `dc1sw` off. No `28` / `10` command is sent.

**DSI details:**
- Each write is a **DCS short write with one parameter (type 0x15)**, sent in **low-power mode**,
  before the high-speed clock starts. `11` and `29` also carry a `00` parameter.
- Table markers confirmed in code: `0xff0` = delay `count` ms, `0xff1` = end.
- `lcd_dsi_if = 0` = video mode, **non-burst**; RGB888; 4 lanes; EoT packet off.
- The backlight order is PWM first, then the enable GPIO.

**Surprises:** two reset pulses, not one; reset is high before the supplies come on; the code also
writes `lcd_gpio_1`, which this frame's fex does not define (no effect).

**Not proven** (the agent's own list): (1) on a cold boot the vendor boot loader probably lights the
panel and the kernel skips this flow, so the boot loader's sequence can differ; (2) real delays can
be one timer tick shorter than nominal; (3) sync-pulse vs sync-event; (4) every statement about how
mainline orders these steps — the agent did not read the mainline sources. The panel/DTS agent got
this file and checks the mainline side.

## 2026-10-12 — E028: Touch firmware from the vendor module (agent result, reviewed)

**Method:** an agent read `gslX680new.ko` (in the boot ramdisk, with DWARF). Files in `dumps/touch/`:
`README.md`, `extract_gsl_fw.py` (reproduces the result), `gsl_m86_hd.fw`, the raw vendor array and
the config data. The `.fw` / `.bin` files are vendor blobs; `.gitignore` now keeps them local.

**Result [VERIFIED in the binary; not a hardware test]:**
- The module has a table `gslx680_fw_grp[33]`: `{name, size, firmware pointer}`. `init_module`
  compares the fex `ctp_name` with each name. `"gsl_m86_hd"` is entry 4: 4,620 records,
  firmware `GSLX680_FW_M86HD` (36,960 bytes), config `gsl_config_data_id_m86_1024600` (2,048 bytes).
- Record layout: `{u32 register; u32 value}`, 8 bytes. 140 pages × (1 page-select record + 32
  registers). **This is already the layout that mainline `silead.c` loads**, so `gsl_m86_hd.fw` is
  the vendor array byte for byte.
- SHA-256 of `gsl_m86_hd.fw`: `e11ffa8a33a56b78f8d2f57925fef1b67ea9a58c264bb5f3a8553ea52b14a9e6`.
- Review by the main session: the file has 4,620 records; a page record at each 33rd record; each
  page has registers 0x00–0x7c in order; the hash is reproduced; `extract_gsl_fw.py --list` runs.
- The config data is for Silead's host-side point library (15 drive × 10 sense lines, 5 fingers).
  Mainline does not use it.
- Android rotation: `init.sun8i.rc` has `setprop ro.sf.rotation 90`.

**Not proven:**
- The chip type. The vendor driver does not read the ID register. Best estimate GSL1680
  [UNCONFIRMED]. The mainline driver prints the chip ID at probe.
- The raw coordinate range (estimate 960 × 640), axis swap and inversion. The fex values
  (1024×600, revert X and Y) describe the vendor library's output, not the raw data.
- That the firmware starts with the mainline start sequence (the vendor writes 0x03 to register
  0x80; mainline writes 0x0A) and the touch quality without the vendor library.

**Next (needs a booted mainline kernel):** `dmesg | grep -i silead`, then `evtest`: record the chip
ID, the maximum of each axis, and which axis follows the long edge.

## 2026-10-12 — E029: Draft panel patch and board device tree (agent result, reviewed)

**Method:** an agent wrote the drafts from this frame's fex, the vendor init sequence and the power
sequence (E027), and read the mainline sources (`sun6i_mipi_dsi.c`, `panel-jadard-jd9365da-h3.c`,
the A33 dtsi files; mainline master `24a19b95`) and the Allwinner 3.4 BSP for the fex convention.
Files: `kernel/patches/0001-…add-pf1007l-panel.patch` (generated by `kernel/tools/gen_jd9365_init.py`),
`kernel/dts/sun8i-a33-pf1007l.dts` (480 lines) + a debug variant with UART0 on the SD pins,
`kernel/README.md` (348 lines), `kernel/tools/check_dts.sh`.

**Review by the main session:** `check_dts.sh` run again → all three variants: `dtc: OK, 0 warning(s)`.
This is a syntax check. No kernel was built. Nothing ran on the frame.

**Correction to E025:** the table has **199** register writes, then `11 00` and `29 00` = 201 writes
in total (E025 said "201 writes, then sleep-out and display-on").

**Display timings** (fex convention checked in the BSP source: `lcd_hbp` and `lcd_vbp` include the
sync width):

| | Sync | Back porch | Front porch | Total |
|---|---|---|---|---|
| Horizontal (800) | 18 | 36 − 18 = 18 | 854 − 800 − 36 = 18 | 854 |
| Vertical (1280) | 4 | 14 − 4 = 10 | 1314 − 1280 − 14 = 20 | 1314 |

Clock 67 MHz → 59.7 Hz. 135 × 216 mm, 4 lanes, RGB888.

**Findings:**
- **The panel is almost a known one.** The vendor table equals mainline's `cz101b4001_init_cmds`
  and `waveshare_10_1_a_init` in 188 of 193 register writes. A new entry is still necessary for the
  timings, the flags and the 5 different registers.
- **Mode flags must not include burst.** Chosen: `VIDEO | VIDEO_SYNC_PULSE | NO_EOT_PACKET | LPM`.
  With `VIDEO_BURST`, `sun6i_mipi_dsi.c:457-464` computes a negative value into a `u16` for this
  mode. So an existing compatible with the driver's default flags would fail on this host.
- For the non-burst mode, the mainline and BSP formulas give the same packet sizes (HSA/HBP/HFP/HBLK
  44/48/38/2498) [calculated, not measured].
- Mainline sends commands in low-power mode, as the vendor does.

**Where mainline differs from the vendor sequence (cannot be changed from the device tree):**

| Item | Vendor | Mainline |
|---|---|---|
| Reset pulses | Two | One, fixed in the driver's common code |
| HS clock → video | 300 ms | 1 ms |
| Backlight | After video | Before the HS clock (a flash at start is possible) |
| Power-off | No commands | `28` and `10` |
| `11` / `29` | With a `00` parameter | No parameter (the generator has an option for the vendor form) |

**Risks for the first picture (from the source, with line references in `kernel/README.md`):**
1. No upstream A33/R16 board enables DSI.
2. `vcc-dsi-supply` is not known (DCDC1 is a placeholder). A wrong supply gives no error message.
3. The pixel clock will probably be 66.0 MHz, not 67 [calculated].
4. Short DSI writes are not checked: a dead link gives a clean log. A 1-byte DCS read can test the link.
5. `CONFIG_DRM_PANEL_JADARD_JD9365DA_H3` must be on; not checked in the ALARM kernel config.
6. U-Boot cannot show a picture, and the debug UART shares the SD pins.

**Board facts found on the way:**
- **Trap:** the reference-design dtsi puts a UART on PL2/PL3. On this board PL2 is an output
  (`[rf_para] chip_en`). The draft disables `r_uart`.
- Backlight: period 20,000 ns, normal polarity (fex + BSP). The reference value (50,000 ns, inverted)
  is wrong for this board.
- DCDC1 and ALDO1 are 3.3 V in the fex; the reference design has 3.0 V.
- The draft keeps the eMMC node **disabled** by default (safety rule 3). `-DPF1007L_ENABLE_EMMC` enables it.
- The draft sets no `cpu-supply`: DCDC2 and DCDC3 stay at 1.2 V and only the frequency changes, up
  to 1.008 GHz. Safe for both answers to the DCDC2/DCDC3 question.

**Open (the agent's list):** compatible names are placeholders; `vcc-dsi-supply`; which of DC1SW and
ELDO3 is VDD; `rotation` 90 or 270; CPU supply; touch details; accelerometer chip; Wi-Fi power
sequence; AXP chip type; consumers of `dldo4` and `eldo1`; audio amplifier (PH09) and keys not
modelled; kernel build and `dtbs_check` not done.

## 2026-10-12 — E030: Facts from the vendor boot chain (agent result, reviewed)

**Method:** an agent analysed the vendor kernel (with its kallsyms table), the arisc firmware inside
it, the ramdisk, the sunxi partition table, the env partition and the readable part of `/system`
in the 452 MiB dump. Files: `dumps/vendor-facts/` (`README.md`, evidence files, partition table,
`build.prop.redacted`, U-Boot env, init scripts, the scripts used).

**Review by the main session:**
- SHA-256 of the 15,886,336-byte boot image at sector 172,032 of our dump:
  `d71c313ddaa4693948acb20af7740ccb56c88bf9376746a47fce2d00c14fc6a4`. **Equal to the value in Wes Bos's
  docs.** So this frame has his exact vendor kernel and ramdisk. It also shows that this part of the
  single-read dump is bit-exact.
- The strings `axp22_dcdc2`, `axp22_dcdc3` and `[cpu_freq] ERR:%s: could not get cpu vdd` are in the
  kernel image at 0x7fe42e, 0x7fe43a, 0x8033fa.
- The agent's text files hold no serial number and no MAC address (searched).

**Answers:**

| Question | Answer | Tag |
|---|---|---|
| CPU supply | **DCDC3** (AXP register 0x23). `sunxi_cpufreq_initcall` does `regulator_get(NULL, "axp22_dcdc3")`; the arisc firmware's DVFS routine sets voltage type 3 = register 0x23. DCDC2 is used by the DDR frequency driver. | VERIFIED in two vendor binaries. The board wiring is not measured. |
| Wi-Fi modules | `aic8800_bsp.ko` (loaded by `init.sun8i.rc` line 151), then `aic8800_fdrv.ko` (named in `libhardware_legacy.so`). Both in `/system/vendor/modules/`. | Names VERIFIED |
| Wi-Fi chip variant, SDIO ID, firmware names | **Not found.** `/system/vendor` is in blocks after the cut of the dump. No file in the dump says "DC". | Null result, scope: the first 452 MiB |
| Wi-Fi power-on | `chip_en` (PL02) on, a wait (reads as about 125 ms), then `wl_reg_on` (PL06) on | VERIFIED order; the delay is read from code, not measured |
| Rotation | `ro.sf.hwrotation` is not set. The init script sets `ro.sf.rotation 90`. | VERIFIED |
| Partitions | 14 partitions; env 139,264, boot 172,032, system 237,568, recovery 2,400,256 — all equal to Wes's values; 4 of 4 table CRCs correct | VERIFIED |
| Vendor console | `console=ttyS0,115200`, `loglevel=8`, root `/dev/mmcblk0p7` | VERIFIED (env CRC correct) |
| `build.prop` | `ro.es_frame.product=PF1007L`; fingerprint `AEEZO/astar_m86_8723cs/…6.0.1/MOB30R/20260113:eng/test-keys`; `armeabi-v7a`; `lcd_density=160`; `ro.opengles.version=131072` (ES 2.0); `low_ram=true`; `ro.secure=0`, `ro.debuggable=1`, `ro.adb.secure=0`; `persist.sys.usb.config=mass_storage` | One read, no checksum |
| USB gadget IDs | `1f3a:1000` mass storage, `1001` adb, `1002` both | VERIFIED in the init script |
| Sensor at 0x19 | `sc7a20` is the best match (the init script loads `sc7a20`, `mir3da`, `msa`) | Inference |
| Backlight | No backlight class device in the vendor kernel; an ioctl on `/dev/disp` | VERIFIED |

**Reasoning:**
- Open question 6 is closed for the vendor software: **the CPU rail is DCDC3**. This agrees with the
  two upstream A33/R16 boards that use DCDC3. The DTS draft can now set `cpu-supply = <&reg_dcdc3>`
  — after one check on the device (read AXP registers 0x22 and 0x23 at two CPU frequencies).
- The match with Wes's PF1007L is now by the device's About screen (E005), the eMMC size (E018), the
  partition table and the **equal boot image hash**.
- "Wi-Fi = AIC8800**DC**" is still [DOCUMENTED] only. The family (`aic8800`) is verified. The variant
  needs the full backup (`/system/vendor`) or the SDIO ID from a running kernel.
- ⚠ Privacy: the `bootloader` partition holds `device_uid.txt`, `vuid.txt`, `vuid_cert.txt`. The
  agent did not read them. They are in the dump and will be in the full backup: keep both private.

**The full verified backup will add:** `/system/vendor` (Wi-Fi modules and firmware, Mali blobs), the
sensor config, `recovery`, and a second read of everything above.

## 2026-10-12 — E031: AIC8800 SDIO driver builds for 32-bit ARM (agent result, reviewed)

**Question:** Does the out-of-tree AIC8800 SDIO driver build for armv7 against Arch Linux ARM's
`linux-armv7`? Nobody had shown a 32-bit build.

**Method:** an agent built `radxa-pkg/aic8800` (commit `e9e43ed79c50483080e9bcdfb08caeeb869d7191`,
with the SDIO hunks of its Debian patch series) natively in an armv7 Arch Linux ARM container
(`menci/archlinuxarm:base-devel`, `--platform linux/arm/v7`, QEMU) against `linux-armv7-headers`
7.2.10-1. Files: `wifi/README.md`, `wifi/build.sh`, `wifi/logs/`, `wifi/out/` (git-ignored).

**Result [VERIFIED by a build; never run with the chip]:**

| Item | Value |
|---|---|
| Build | **0 errors.** 3 modules: `aic8800_bsp.ko`, `aic8800_fdrv.ko`, `aic8800_btlpm.ko`. About 90 s. Two clean runs give the same SHA-256. |
| Our own patches | **0.** The Radxa series is enough. |
| 32-bit problems | None (no 64-bit division, no pointer-cast or format warning). 110 warnings, vendor style. |
| Control | The vendor tree with no patch: 51 errors, all kernel API drift, none from 32-bit. |
| `vermagic` | `7.2.10-1-armv7-ARCH SMP preempt mod_unload modversions ARMv7 p2v8` |
| Symbols | 0 unresolved, 0 CRC mismatch |
| Load test in an emulator | Real `linux-armv7` kernel in `qemu-system-arm -M orangepi-pc`: `bsp` and `btlpm` load; `fdrv` ends with "No such device" (correct with no chip); no oops |
| SDIO IDs in `aic8800_fdrv` | **`c8a1:c08d` (AIC8800DC/DW)**, `5449:0145` (AIC8801), `c8a1:0082`, `c8a1:9081`–`9086`, `c8a1:2082` |
| Firmware | `/lib/firmware/aic8800_fw/SDIO/aic8800DC/` (`fmacfw_patch_8800dc_u02.bin`, `…_tbl_…`, `…calib…`, `aic_userconfig_8800dc.txt`, …). The driver opens the files itself (`filp_open`). **Radxa ships the files for chip revision U02 only, not for U01.** |

Review by the main session: the three `.ko` files are 32-bit ARM ELF; `modinfo.txt` shows the
`vermagic` and the SDIO aliases above; the build log ends with the three `LD [M]` lines.

**More vendor-kernel facts (the agent disassembled `rf_pm` / `wifi_pm`):** at boot DLDO1 + DLDO2 on
(3.3 V) and **AXP GPIO0 = 1** (`power_switch`); Wi-Fi on = **PL2 (`chip_en`) = 1, a wait, PL6
(`wl_reg_on`) = 1**, both active high. The driver uses the in-band SDIO interrupt, so PL7 (host
wake) is not used. The MAC address is a fixed 4-byte prefix + 2 random bytes at each load.

**Disagreement to resolve:** this agent reads the wait between PL2 and PL6 as **5 ms**; the
vendor-facts agent (E030) read it as about **125 ms**. Both are from code. Not resolved. A longer
wait is the safe choice for the DTS.

**Follow-up for `kernel/dts`:** the board DTS drives only PL6. It must also drive PL2 and set AXP
GPIO0. The fragment is in `wifi/README.md` (`dtc` syntax check only). Not merged yet.

**Observation about our U-Boot builds:** Wes's defconfig has `CONFIG_CONS_INDEX=5`, the R_UART on
PL2/PL3. **On this unit PL2 is the Wi-Fi `chip_en` pin.** So U-Boot builds A–D send console text on
the Wi-Fi enable line. Effect on the hangs: unknown, probably none while the Wi-Fi supplies are off
[UNCONFIRMED]. It is a third, weak suspect. Any U-Boot that we use to boot Linux must use a
different console.

**Still unknown:** Wi-Fi on the frame (SDIO traffic, firmware download, radio); this unit's SDIO ID
and chip revision (first test: `cat /sys/bus/sdio/devices/*/uevent` before any driver load); a
kernel with a different release string needs a new module build.

## 2026-10-12 — E032: FEL hangs after the SPL of build C → the supply voltages differ from the vendor's

**Setup:** the owner reconnected the frame "through another cable". The Mac shows it on a different
hub: `0bda:5411` "4-Port USB 2.0 Hub", port 3 (a dock; the Anker hub is no longer connected). If
this hub has its own power supply is not known. `frame-check.py fel` (12:56:05) → A33 line, as in E017.

**Test:** `python3 -I scripts/frame-check.py memtest C` (12:56:14).

**Result:**
```
12:56:14 run the SPL of build C (DRAM setup only)
12:56:16 the SPL returned to FEL
STOP: FEL read failed at 0x42000000
```
The five 2 MiB writes returned with no error. The first read failed. By hand at 12:57:06:
`sunxi-fel version`, `read` and `readl` all give `usb_bulk_send() ERROR -7: Operation timed out`.
The USB watcher logged no change: the device `1f3a:efe8` stays on the bus but does not answer.
So the frame hung less than 50 s after the SPL. No memory result exists.

**Reasoning:**
- **FEL is boot ROM code that runs from ROM and SRAM. It does not use the DRAM.** A wrong DRAM
  calibration cannot hang it. So the DRAM ZQ value (E023) is not the cause of this hang. It can
  still be wrong, but it is not suspect 2 for the hangs any more.
- FEL was stable for minutes before any SPL ran (E017, E021: several minutes each). It hangs only
  after an SPL ran: build A after about 8 minutes of work (E019), build B within seconds (E021),
  build C within 50 s (this entry). So the cause is something that the SPL changes and that stays:
  clocks, the PMIC voltages — or the higher current after the SPL (CPU at 1008 MHz) on weak USB power.
- The voltages (`.config` of our builds vs this frame's `[power_sply]`):

| Rail | Vendor (fex) | Our builds A–D |
|---|---|---|
| DCDC2 (system core; the vendor DDR-frequency driver also uses it, E030) | **1200 mV** | **1100 mV** |
| DCDC1 (I/O, SD, eMMC) | 3300 mV | 3000 mV |
| ALDO1 | 3300 mV | 3000 mV |
| DCDC3 (CPU) | 1200 mV | 1200 mV |
| DCDC5 (DRAM) | 1500 mV | 1500 mV |
| ALDO2 / ALDO3 | 2500 / 3000 mV | 2500 / 3000 mV |

  The U-Boot defaults (1.1 V core, 3.0 V I/O) are the generic A33 values. This board's vendor config
  uses 1.2 V and 3.3 V. **Our builds ran the SoC core rail 100 mV under the vendor value.** This is a
  new first suspect, at the same level as weak USB power. It would also explain Wes's open issues
  #17/#19 ("resets about 41–50 s after `ums` comes up, even idle") [UNCONFIRMED].
- The script had a fault: it did not print the tool's error text. Fixed.

**Build E** = build C + `CONFIG_AXP_DCDC1_VOLT=3300`, `CONFIG_AXP_DCDC2_VOLT=1200`,
`CONFIG_AXP_ALDO1_VOLT=3300` (the frame's own values; the other rails were already equal).
Folder `a33-uboot-out-E/`, SPL end `0x456a`, SHA-256
`6da99a8e763f54fba396fc975fae74155cafd2e438b18e9b6b34d70f0269aab3`, read-only string present.

**New test, no `sudo`:** `frame-check.py stay <build> <minutes>` runs only the SPL, then asks FEL
for its version each 5 s. It separates "SPL settings" from "eMMC/USB load".
Control data so far: build C stopped in < 50 s (with FEL traffic from the memtest).

**Next:** replug → `stay E 5`. PASS → voltage was the cause → `memtest E`, `load E`, backup.
FAIL → power is the cause → stronger supply.

## 2026-10-12 — E033: `stay E` passes; the memtest "hang" was an error of the test script

**Test 1 (after a replug at 13:01:30):** `python3 -I scripts/frame-check.py stay E 5`
```
13:01:37 the SPL of build E ran. Now a FEL check each 5 s for 5.0 min.
13:06:40 STAY build E: PASS. FEL answered for 5.0 min after the SPL.
```

**Test 2 (13:06:58, same power cycle, no new SPL):** `frame-check.py memtest E nospl`
```
STOP: FEL read failed at 0x42000000: usb_bulk_recv() ERROR -7: Operation timed out (USB state: 1f3a:efe8 FEL)
```
After it, `sunxi-fel version` → `usb_bulk_send() ERROR -7: Operation timed out`. The same step failed
in the same way with build C (E032).

**Cause: the test script, not the frame.**
- `sunxi-fel` receives a whole `read` in one USB transfer with a 10 s limit
  (`fel_lib.c:34` `USB_TIMEOUT 10000`; `fel_lib.c:106` `libusb_bulk_transfer(usb, ep, data, length, …)`).
  Writes are cut into 512 KiB pieces; reads are not.
- FEL on the A33 runs with no MMU and no caches. The measured FEL speed is 160–190 kB/s (E018, E021).
- 2 MiB at 190 kB/s is 11 s. That is more than 10 s. The transfer times out in the middle and the
  FEL protocol is out of step. Each later command then times out. The frame looks hung; it is not.
- The failure is at the first read both times, also after 5 stable minutes. A random hang does not
  do that.

**Corrections to E032:**
- ❌ "Build C hung less than 50 s after the SPL" — **not valid.** The script caused it.
- ❌ "The DRAM ZQ value is not a suspect any more" — the argument used the invalid result. ZQ is
  again an open suspect (weaker than power; the vendor value is used in builds C, D and E).
- ✅ Still true, read from the configs: builds A–D set DCDC2 to 1100 mV, DCDC1 and ALDO1 to 3000 mV;
  the vendor uses 1200 / 3300 / 3300 mV.
- "The low core voltage caused the hangs" is a hypothesis with no test behind it. There is no
  `stay` result for builds A–D to compare with E.

**What is measured:** with build E's SPL, FEL answers for 5 minutes with no load. Valid evidence for
the hangs is only: build A dropped after 8 minutes under eMMC read load (E019); build B never came
up (E021).

**Fix:** `frame-check.py` now reads DRAM in 256 KiB pieces (1.4 s each). Not tested on the frame yet.

**Lesson:** I reported a "strong clue" to the owner from one failed run of a new, untested script,
with no control. The control (the same test on a build that had just passed) showed the script was
at fault. Run the control before the conclusion.

**Next:** replug → `load E` → resumable backup (the owner, `sudo`). The backup is the load test.
The comparison of builds (A against E with `stay`, and the fixed memtest) can be done later, when
the owner's time is not short.

## 2026-10-12 — E034: Backup run 2 (build E, resumable script) — dropped after 7 min; 8 chunks kept

**Setup:** replug at 13:11:32 (FEL). `frame-check.py load E` at 13:11:35: U-Boot up at 13:11:45
(`1f3a:1010` "USB download gadget"); `disk12` = card, `disk14` = eMMC, 15,634,268,160 bytes, both
read-only. Hub: `0bda:5411` 4-port USB 2.0 hub, new cable.

**Command (the owner, about 13:12):**
`sudo python3 -I scripts/emmc-backup-resumable.py backup disk14 15634268160 /Volumes/FRAME_BACKUP/omarchy-frame-backups/run2`

**Numbers:**

| Item | Value |
|---|---|
| Speed | 11.5 MB/s (run 1: 5.0 MB/s) |
| Chunks done (each read two times, equal) | **8 of 59 = 2,147,483,648 bytes** |
| USB watcher | `13:18:47 absent` — the hub saw a disconnect |
| Process end | 13:18:47 |
| U-Boot start → off | 13:11:45 → 13:18:47 = **7 min 2 s** |
| After the drop | No `1f3a` device. Not FEL. |

The resumable script did its job: 8 verified chunks and the manifest are kept; no partial file.

**Comparison of the two runs:**

| | Run 1 (E019) | Run 2 |
|---|---|---|
| Build | A: ZQ 15291, DCDC2 1.1 V, DCDC1 3.0 V | E: ZQ 31739, DCDC2 1.2 V, DCDC1 3.3 V |
| Cable, hub | First data cable, monitor hub (500 mA ports) | Second cable, `0bda:5411` hub |
| Read speed | 5.0 MB/s | 11.5 MB/s |
| SPL start → dead | 11:29:15 → between about 11:35 (the read stalled) and 11:37:25 (error) = 6–8 min | 13:11:37 → 13:18:47 = 7.2 min |
| Read load before the drop | about 4 min | about 6.5 min |

**Reasoning:**
- **The voltages and ZQ (build E) did not fix the drop. The second cable and hub did not fix it.**
  Both ideas of E032 fail as the single cause. The higher speed came with one of them; not separated.
- The time from the SPL to the drop is about 7 minutes in both runs. The time from plug-in is not
  equal (run 1: plug-in at about 11:24, so 11–13 min; run 2: 7.3 min). So the trigger is something
  that starts with our SPL / U-Boot, not with the power-on. No run has shown a frame that is alive
  more than 8 minutes after an SPL. (`stay E 5` covered only 5 minutes.)
- After the drop the frame does not return in FEL. A reset or a crash of the SoC with power present
  would boot the stub card again and show `1f3a:efe8`. In run 2 the hub saw a clean disconnect.
  **So the frame loses power: the PMIC (AXP223) switches off, or its input collapses.** Only a new
  VBUS edge (cable out and in) starts it again.
- Candidates, none tested: PMIC over-temperature; a charger or battery-detect function with no
  battery; an under-voltage cut-off; something that U-Boot's `axp_init()` changes — it sets AXP
  GPIO0 and GPIO1 to input (`drivers/power/axp221.c`), and on this board the vendor drives AXP
  GPIO0 high (`[rf_para] power_switch`, E031); heat of the SoC at 1008 MHz in a busy loop.
- Wes's issues #17/#19 ("some units reset about 41–50 s after `ums` comes up, even idle", unresolved)
  may be the same class of problem [UNCONFIRMED].

**New tool:** `frame-check.py axp <build> <minutes>` runs the SPL, then reads AXP223 registers over
the RSB controller with FEL `readl`/`writel` (status 0x00/0x01, IRQ status 0x48–0x4c, die temperature
0x56/0x57, charge/discharge current 0x7a–0x7d, GPIO 0x90/0x94; one full list of the supply and
charger registers at the start). **Read only: it writes no PMIC register.** Log:
`dumps/raw/axp-telemetry.log`. Not tested on the frame before this run.

**Next:** replug → `axp E 15` → read the last lines before the frame goes off.

## 2026-10-12 — E035: What the 8 verified chunks already cover

**Owner's question:** "Do we really need the backup? Can we get it from somewhere else?"

**Method:** compare the range of the 8 verified chunks of run 2 (sectors 0 – 4,194,303 = 2 GiB) with
this unit's partition table (`dumps/vendor-facts/partitions.tsv`, 4 of 4 CRCs correct).

| Area | Sectors | In the 2 GiB? |
|---|---|---|
| MBR, `boot0`, vendor U-Boot, sunxi partition table | 0 – 73,727 | ✅ complete |
| `bootloader` (holds the device ID files) | 73,728 – 139,263 | ✅ complete |
| `env`, `boot` | 139,264 – 237,567 | ✅ complete |
| `system` (1 GiB; `/system/vendor` with the Wi-Fi modules and firmware) | 237,568 – 2,334,719 | ✅ complete |
| `misc`, `recovery`, `cache`, `metadata`, `private`, `frp`, `empty` | 2,334,720 – 4,169,727 | ✅ complete |
| `alog` (80 MiB, Android logs) | 4,169,728 – 4,333,567 | First 12 MiB only |
| `media_data` (16 MiB) | 4,333,568 – 4,366,335 | ❌ |
| `UDISK` (12.8 GiB, user data) | 4,366,336 – 30,633,983 | ❌ |

**Reasoning:**
- Every partition of the vendor firmware is already saved, read two times with equal hashes. What is
  missing is the user-data area and two small partitions.
- A factory reset in the vendor recovery normally makes the user-data area again [DOCUMENTED —
  general Android behaviour; not tested on this frame]. So "firmware partitions + a factory reset"
  is probably enough to go back to stock. It is not the same as a full image: a restore from it has
  not been tested, and the full-image tools of Wes need the complete file.
- "From somewhere else": no public firmware image for this frame is known to this project (not
  searched for today — a scoped null). Wes's units have the same boot image (E030), but his rules
  keep backups private, and the `bootloader`/`private` partitions are specific to a unit. We have ours.
- **The backup does not block the project.** Safety rule 2 says "before any write", and no eMMC
  write happens before PLAN Phase 9. Phases 4–8 boot from the SD card.
- **The 7-minute power-off is not a backup problem.** It comes after our SPL / U-Boot start, with or
  without read load known. A Linux boot from the card starts with the same SPL. It must be solved
  for Phase 4 in any case.

**Decision proposed to the owner:** stop the work for a complete image now. Keep the 2 GiB, make a
second copy of it, and finish the remaining 13.6 GiB later (before Phase 9), when the power-off is
solved. Then one run of about 25 minutes is enough.

**With the 2 GiB we can now read:** the Wi-Fi modules and firmware in `/system/vendor`, the SDIO IDs
in them, and a second read of the `script.bin` and `boot` areas (control for E023/E025/E030).

## 2026-10-12 — E036: Owner's decision on the backup; prior art for the drops (web search)

**Owner's decision (their words, 2026-10-12):** "to be clear i dont care about ever running the
original firmeare we do wither omarchy or the wes bos implementaiton".

**Interpretation (the session's, told to the owner):** a complete eMMC image is not necessary. The
Wes Bos route runs **on** the vendor Android (root + kiosk), so that fallback needs the firmware
partitions. The 8 verified chunks hold all of them (E035). The 13.6 GiB that are missing are user
data. So: stop the backup work; keep the 2 GiB; make a second copy of it.

**Prior art (search of general sources + the issues of `wesbos/photo-frame-dashboard`, read with
`gh issue view`):**

| Source | Observation | Their fix |
|---|---|---|
| Issue #24 (firmware 20260519, 30,777,344-sector eMMC) | Frame left the USB tree during long reads and did not return in FEL, **also with a hardware watchdog armed** → they concluded: power loss | A **powered USB hub**; then a full pass with no drop |
| Issue #24 | `mmc read` errors at 8-bit / 52 MHz; one transient read error later | 4-bit / 26 MHz; up to 8 read retries in `ums_read_sector` |
| Issues #24, #16, #6, #27 | "macOS eject / console noise could end `ums`" | Ignore START STOP UNIT and CTRL+C in `f_mass_storage.c`. #27: removing the `ctrlc()` abort "let a full pass complete" |
| Issue #19 (same firmware as ours, 20260113) | Reset to FEL about 45–50 s after "Starting U-Boot", every time, also on a powered hub; "FEL itself is stable for long periods" | Open |
| Issue #17 (firmware 20260410) | Drop about 41–42 s after the UMS disks show, with no reads; a replug did not reset the frame, the reset button did | Used the SD-only route |
| Issue #16 | `ums` unstable on a bus-powered hub; stable on a USB-C-to-A adapter direct in the Mac | Off the bus-powered hub; `SUNXI_NO_PMIC` + 408 MHz |

General web search (U-Boot AXP221 history, LKML, forums): **no report of this exact symptom**
(scope: three searches). One related item: an LKML thread about an A33 tablet that does not power
off fully (RSB and PMIC order) — a kernel matter, not ours.

**Issue #24's method to debug with no serial console** [DOCUMENTED; worked on their unit]:
1. Keep U-Boot's console in SRAM A2 (`0x48000`, 16 KiB); it survives a SoC reset.
2. Arm the A33 watchdog from the boot script (`mw.l 0x01c20cb4 1; mw.l 0x01c20cb8 0xb1`: 16 s,
   system reset). Only the `ums` wait loop feeds it.
3. If `ums` ends or U-Boot hangs → reset → the stub card gives FEL → `sunxi-fel read 0x48000 0x4000`.
   **A hang or an exit comes back in FEL. A power loss does not.**

**Correction to E034:** "the frame loses power: the PMIC switches off" was stated too strongly. The
observation (the gadget leaves the bus and no FEL returns) has a second explanation of equal
strength: `ums` ended (`ctrlc()` from noise on the console RX pin, or a host eject) and U-Boot then
waits with no USB function. Nothing resets it, so no FEL. Our U-Boot console is the R_UART on
PL2/PL3 (`CONS_INDEX=5`); PL3 (RX) has no known driver on this board.
- If this is the cause, it is a problem of U-Boot's `ums` command only. **A Linux boot is not affected.**
- If it is power, a Linux boot is affected, and a powered hub is necessary.

**Build F** = build E + the issue #24 patch (saved as `scripts/uboot/wesbos-issue24-ums-diag.diff`;
the 4-bit dtsi hunk and their low-power defconfig are left out) + `CONSOLE_RECORD`. Boot script
`scripts/uboot/ums-diag.cmd`: `ums_ignore_ctrlc`, `ums_ignore_eject`, the watchdog lines, then `ums`.

**Next:** replug → load build F → watch. FEL returns → read the log at `0x48000`. No FEL → power.

## 2026-10-12 — E037: Stock kernel audit, panel module and DTBs built (agent result, reviewed)

**Question:** Can the stock Arch Linux ARM kernel be used, with our parts as add-ons?

**Method:** an agent read the config inside `linux-armv7-headers 7.2.10-1`, built the panel driver
as an out-of-tree module natively in the armv7 container (the method of E031), and compiled the DTS
with the kernel's own `dtc` and v7.2.10 include files. Files: `kernel/config-audit.md`,
`kernel/build.sh`, `kernel/out/`, `kernel/bootcard/`, `kernel/README.md` sections 8–14.

**Result:**
- **The stock `linux-armv7 7.2.10-1` kernel is enough. No kernel build.** One item is missing:
  `DRM_PANEL_JADARD_JD9365DA_H3` is not set. Our module fills it. `DRM_SUN4I`, `DRM_SUN6I_DSI`,
  `DRM_LIMA`, `PWM_SUN4I`, `TOUCHSCREEN_SILEAD`, `CFG80211` are modules in the package; the D-PHY,
  PWM backlight, AXP/RSB, MMC, pwrseq and MUSB (dual role) are built in; USB gadget: configfs
  NCM/ECM/RNDIS/ACM and `g_cdc`/`g_ether`/`g_ncm`, `U_SERIAL_CONSOLE=y`.
- Things to know: `psi=1` is necessary; zram has LZO only; the A33 thermal sensor is
  `sun4i-gpadc-iio` (module); the accelerometer `sc7a20` is in `st_accel_i2c`.
- **Panel module:** base = the driver file at tag v7.2.10 (master does not build against the stock
  headers: one helper has a new name). 0 errors, 0 warnings; `vermagic` equal to the stock modules;
  0 CRC mismatches; loads and unloads on the stock kernel in QEMU; a copy with a wrong CRC is refused.
- **DTBs:** control — the upstream `sun8i-a33-ga10h-v1.1.dts` built by the same method is byte-equal
  to the DTB in the stock package. Ours: `dtc` 0 warnings; dt-schema 6 messages from 3 known causes
  (two placeholder compatibles; the AXP GPIO hog binding).
- **Merged into the DTS:** Wi-Fi power (PL2 as a fixed regulator with a 150 ms start delay, PL6 as
  the pwrseq reset, AXP GPIO0 hog, DLDO1/2 always on); touch node with the extracted firmware name;
  the CPU supply behind a switch (`-DPF1007L_CPU_DVFS_DCDC3`, off by default); eMMC still disabled.
- **The 5 ms / 125 ms disagreement (E031) is closed: 5 ms.** The constant in the vendor code is
  `udelay(1000)` scaled for `HZ=100`; the 125 ms reading used the wrong scale factor.

| File in `kernel/out/` | SHA-256 |
|---|---|
| `panel-jadard-jd9365da-h3.ko` | `2342541c5c52b3481a56e2db0f0d9c096abcb00441e461fa6a23669843543dbf` |
| `sun8i-a33-pf1007l.dtb` | `db88666274df153cf513bb4f5b97b0e0be1e85ffc053043e5da1233ca6b4ff40` |
| `sun8i-a33-pf1007l-uart0-sd.dtb` | `b0f59dac0c0ae48e0867feb45a13727901325c638fbddf74b665d226a5ec71c2` |

Review by the main session: the module is 32-bit ARM, `vermagic=7.2.10-1-armv7-ARCH …`, alias
`yhk,zr789-sq9365-101`; the decompiled default DTB has the panel, touch and `dr_mode = "peripheral"`
nodes, and the eMMC node `mmc@1c11000` has `status = "disabled"`.

**Blind-boot plan from this agent (drafts, not run):** stage 1 boots with the display, lima and
Wi-Fi modules blacklisted, so that only USB comes up (`g_cdc`: network + serial); the display
modules are then loaded by hand with the log visible. Reason: the DSI host has never run on an A33
upstream, and a crash there must not hide the USB console.

**Not tested:** everything on the frame. The module is valid only for kernel `7.2.10-1`: hold the
kernel package, or rebuild after an update.

## 2026-10-12 — E038: The partial dump of run 1 equals the verified data; Wi-Fi chip variant from `/system/vendor`

**1. Control for all facts taken from the run-1 dump.**
`python3 -I scripts/emmc-backup-resumable.py compare <run2> run1-buildA-8bit-dropped.first-452MiB.img`
→ `Equal: the first 473956352 bytes of the backup are the control file.`

The 452 MiB of run 1 (one read, build A, 5 MB/s, a run that failed) are equal, byte for byte, to
chunks of run 2 that were each read two times with equal hashes (build E/F, 11.5 MB/s). So the
entries E023 (fex), E025 (panel table), E027 (power sequence), E028 (touch firmware), E030 (vendor
facts) rest on data read three times. Their tag "single read" is lifted.

**2. Wi-Fi files.** The `system` partition (sectors 237,568–2,334,719) was put together from the
verified chunks and read with `debugfs` (e2fsprogs). `/system/vendor/modules/` holds:

| File | Bytes |
|---|---|
| `aic8800_bsp.ko`, `aic8800_fdrv.ko` (vermagic `3.4.39`, driver version 6.4.3.0) | 850,551 / 6,039,898 |
| `aic_userconfig_8800dc.txt` | 1,056 |
| `fmacfw_patch_8800dc_h_u02.bin`, `fmacfw_patch_tbl_8800dc_h_u02.bin`, `fmacfw_calib_8800dc_h_u02.bin` | 17,900 / 528 / 40,444 |
| `fw_adid_8800dc_u02h.bin`, `fw_patch_8800dc_u02h.bin`, `fw_patch_table_8800dc_u02h.bin` | 1,476 / 11,760 / 512 |

Also there: `8188eu.ko`, `8723bs.ko`, `8723bs-vq0.ko`, `8723cs.ko`, `bcmdhd.ko`, `xradio_wlan.ko`
(the vendor image carries drivers for other boards too). No other AIC firmware file is present.

- SDIO aliases in the vendor `aic8800_fdrv.ko`: `c8a1:c08d`, `c8a1:0082`, `5449:0145`.
- Copies are in `dumps/raw/wifi-vendor/` (git-ignored).

**Reasoning:**
- The vendor driver knows the names for several variants (`…8800dc.bin`, `…_u02.bin`, `…_h_u02.bin`,
  `…8800d80…`), but the image ships **only the `8800dc` "H" U02 set**. So this frame's chip is an
  **AIC8800DC, "H" variant, revision U02** [inference from the shipped files; the SDIO ID and the
  chip revision register are not read yet]. "Wi-Fi = AIC8800DC" moves from [DOCUMENTED] to
  [VERIFIED from this unit's files, by inference].
- The risk of E031 ("Radxa has firmware for U02 only; a U01 chip would have none") is gone: U02.
- The Radxa tree has the same six file names. `fw_adid_8800dc_u02h.bin` and
  `aic_userconfig_8800dc.txt` are equal to the vendor's. The four patch/calibration files differ in
  size (a different firmware version). Use Radxa's firmware with Radxa's driver; keep the vendor
  files as the fallback. The equal `userconfig` means the transmit-power table needs no change.

## 2026-10-12 — E039: Omarchy 4 shell on 32-bit Arch Linux ARM, in an emulator (agent result, reviewed)

**Question (open question 9):** Does Quickshell, and Omarchy's own shell, start on armv7h?

**Method:** an agent ran an Arch Linux ARM armv7 userland in Docker (`--platform linux/arm/v7`,
QEMU) with a headless sway compositor on Mesa llvmpipe, and the same tests on a native `linux/arm64`
container as the control. Files: `port/smoke-test.md` (489 lines), `port/packages-armv7h.tsv`
(239 rows), `port/Dockerfile`, `port/run-all.sh`, `port/logs/` (logs and 7 screenshots).

**Review by the main session:** the logs show `uname -m: armv7l` for the armv7 runs; the screenshot
`armv7l-omarchy-v4.0.4-qtquick611-menu.menu.jpg` shows the Omarchy bar, wallpaper and menu at
1280×800.

**Results [VERIFIED in QEMU with software rendering; not on the frame]:**
- **Quickshell 0.3.2-1 from ALARM `extra` starts on armv7h**: QML loads, a layer-shell bar draws,
  timers, child processes, IPC, D-Bus and PipeWire work.
- **Omarchy's shell loads on armv7h — with one fix.** Tag v4.0.4 as it is gives 222 QML errors and
  a black bar: Qt 6.12 added `QtQuick/Color`, which hides Omarchy's own `Color` singleton.
  **Not a 32-bit fault:** the arm64 control has the same 222 errors. Fix A: pin `import QtQuick` to
  6.11 in 102 files → 0 errors. Fix B: upstream branch `quattro` (commit `defbf90e`) → 0 errors on
  the stock Quickshell.
- **No error specific to 32-bit was found**: the armv7l and aarch64 logs are equal after addresses,
  PIDs and times are removed (scope: what the tests opened).
- Packages (147 base names in v4.0.4): 116 fine, 3 older, 1 broken, 26 missing, 1 not applicable.
  Must build: `omarchy`, `omarchy-settings`, `omarchy-keyring`. Replace `chromium` → `firefox 157`.
  For touch: `wvkbd` and `hyprgrass` are in no repo; **`squeekboard 1.43.1-6` is in `extra`** as an
  on-screen keyboard that needs no build.
- **`neovim` is broken on armv7h** (open question 11): `0.9.1-1` cannot be installed (it needs
  `libtermkey`, which no armv7h repo has), and LazyVim needs ≥ 0.11.2. Build neovim, or use `helix`
  / `vim` / `micro`, which install.
- Memory of the Quickshell process (QEMU + llvmpipe, read as ±20 %):

| Case | armv7l RSS |
|---|---|
| Trivial bar | 197 MiB |
| v4.0.4 shell, default 6016×3384 wallpaper | 408 MiB |
| `quattro` shell, same wallpaper | 294 MiB |
| v4.0.4 shell, wallpaper scaled to 1280×800 | 220–260 MiB |
| Same, Qt Quick software backend | 105 MiB |
| v4.0.4 after the image picker opened one time | 730 MiB |

  The default wallpaper costs 150–185 MiB (no size limit in v4.0.4). The v4.0.4 image picker keeps
  about 450 MiB after it closes; on `quattro` about 25 MiB. llvmpipe itself costs about 55–65 MiB in
  each process, which the real GPU driver will not cost in the same way.

**Corrections to our research:**
- `research/04-omarchy-port.md` describes branch `quattro` at its head, **not tag v4.0.4**: v4.0.4
  has no `bin/omarchy-hw-platform` and no aarch64 files, and its base list has 147 names, not 161.
- "Quickshell must be built" was wrong (also `xdg-terminal-exec`, `plymouth`).

**Not tested:** Hyprland past its start (the container has no DRM device, so aquamarine stops with
"no allocator available"; the same on arm64) — so there is no answer on Hyprland with the GLES
override; the lock screen, polkit, portals; anything on the Mali-400; Firefox; speed.

**Recommendation of the agent (the owner or a later session decides):** fork `quattro` at a pinned
commit in place of tag v4.0.4. It has the Qt 6.12 fix, the memory fixes and the platform code that
the port edits need. There is no release tag after v4.0.4.

## 2026-10-12 — E040: Owner's facts — power adapter rating; second SD card

**Power adapter of the frame (owner read the label):** 5 V, 2 A.

**Reasoning:**
- The vendor sized the supply for 10 W. A USB 2.0 port gives 0.5 A by the standard (the monitor's
  ports report 500 mA, E019); a USB 3 port 0.9 A.
- This fits the owner's report that the frame "died after a while" in Android on the monitor socket
  (E022): Android runs with the backlight on.
- In U-Boot the screen is dark, and build F has run more than 35 minutes under read load on the
  present hub with no drop. So the U-Boot drops were not a simple "port too weak" [E036: open until
  the log is read].
- **For the Linux phases with the backlight on, plan for a supply that gives 2 A with data**: a
  powered USB hub. Start the backlight at a low PWM value.

**Second SD card (in the Mac's reader, read only so far):** `disk15`, "USB3.0 CRW -SD",
**31,914,983,424 bytes** (62,333,952 sectors), MBR. Partitions: `bootfs` FAT32 536.9 MB (89 MB
used) and a Linux partition of 31.4 GB. Content: Raspberry Pi OS ("Raspberry Pi reference
2025-10-01"); its `cmdline.txt` still has `systemd.run=/boot/firmware/firstrun.sh`, which the first
boot removes — so the card was probably written and never booted [UNCONFIRMED]. The owner said that
this card can be formatted. `firstrun.sh` can hold a Wi-Fi password; it was not opened.
Nothing was written to the card. It gets the boot image when the image agent has finished.

⚠ Disk numbers at this moment: `disk10` backup disk, `disk12` FEL card (through the frame),
`disk14` the frame's eMMC (through the frame, read-only), `disk15` the new card. Use the exact size
as the guard for any write: 31914983424.

## 2026-10-12 — E041: Full backup complete on build F; watchdog restart works; the SRAM log does not

**Backup (run 2 continued).** Build F loaded at 13:36:08 after one replug. Idle + light read load
until 13:50; then the owner ran the resumable backup (`sudo`), which continued at chunk 9.

| Item | Value |
|---|---|
| Chunks | **59 of 59 = 15,634,268,160 bytes**, each read two times with equal SHA-256 |
| Speed | 11.4–11.6 MB/s for the full run |
| Build F uptime | 13:36:08 → 14:31:03 = **54 min 55 s, no drop** (builds A and E: about 7 min) |
| End | "All chunks are read two times and stored." |

A compressed image (`a33-emmc-full.img.gz`) with a readback check is being written from the chunks.

**Watchdog restart [VERIFIED on this unit, two times]:**
1. After the backup: `diskutil eject` of the two UMS disks at 14:29:57 → the gadget left the bus at
   14:31:03 (66 s: the patch ends `ums` after 60 s with no host command) → `1f3a:efe8` FEL at
   14:31:21 (18 s: the 16 s watchdog + boot ROM + stub card). **No cable pull.**
2. From FEL: `sunxi-fel writel 0x01c20cb4 1 writel 0x01c20cb8 0xb1` at 14:32:39 → FEL stops at
   14:32:56 → FEL answers again at 14:32:58.

So the Mac can restart the frame into FEL by itself, from build F and from FEL.

**SRAM console log [VERIFIED on this unit: it does not work]:**
- `sunxi-fel read 0x48000 0x4000` after restart 1: 16,384 bytes with 256 distinct values, 67 zero
  bytes, no text, no "UMS diag" string. The same for the full range 0x44000–0x54000.
- Control: the area is real RAM in FEL — a pattern written to 0x48000, 0x4c000 and 0x50000 reads
  back equal, and stays stable.
- Test: write the pattern at 0x48000, restart with the watchdog (step 2), read again →
  **14 of 4,110 bytes equal** (chance level).
- So SRAM A2 does not keep its content over a watchdog restart on this unit. On the unit of issue
  #24 it did [DOCUMENTED]. Cause not known (perhaps the restart path removes the supply of that
  memory for a moment). The method of issue #24 to read U-Boot's log is not available here.

**What is still not known:** why builds A and E dropped at about 7 minutes. Build F differs from
E in: CTRL+C ignored, host eject ignored, read retries, the watchdog feed, the 60 s idle exit.

**A/B test started 14:34 (no owner action, uses the watchdog restart):** "build G" = the binary of
build F with a boot script that sets `ums_ignore_eject` but **not** `ums_ignore_ctrlc`
(`scripts/uboot/ums-diag-noctrlc.cmd`). `frame-check.py diag G 20` with light read load. A drop
with a return to FEL → the cause is CTRL+C from the console (noise on the R_UART RX pin, PL3).

## 2026-10-12 — E042: Full eMMC image verified; two copies (PLAN Phase 2 gate)

**Method:** each of the 59 chunk files was hashed again and compared with `manifest.json`; the
chunks were written in order through `gzip -6`; the gzip was unpacked again and hashed.

| Item | Value |
|---|---|
| Chunk check | All 59 chunks match the manifest |
| Image size | 15,634,268,160 bytes (= the eMMC size of E018) |
| Compressed image | `a33-emmc-full.img.gz`, 369,103,676 bytes (Wes's unit C: 372 MB) |
| Readback | The unpacked gzip has the whole-image SHA-256 (the hash is in `a33-emmc-full.sha256`; not copied here, safety rule 6) |
| Copy 1 | `/Volumes/FRAME_BACKUP/omarchy-frame-backups/run2/` — the 59 raw chunks + manifest + gzip |
| Copy 2 | `backups/pf1007l-emmc-full/` on the Mac (git-ignored) — gzip + manifest + hash. Verified: it unpacks to the whole-image hash. |

Each byte of the eMMC was read two times from the device with equal hashes (the chunk rule), and
the first 452 MiB a third time (E038). The older 2 GiB copy on the Mac was removed; the full image
replaces it.

**PLAN Phase 2 gate ("two verified backups exist"): passed.**

**Privacy:** the image holds the device ID files and can hold account data. Both copies are outside
git. Do not upload them.

**Restore has not been tested** (it would be an eMMC write; not before Phase 9 and not without the
owner's go). The raw image can be made from the chunks with
`python3 -I scripts/emmc-backup-resumable.py assemble <run2 dir>` if Wes's tools are needed.

## 2026-10-12 — E043: A/B trials — the same U-Boot with CTRL+C not ignored ("build G")

**Question:** which protection of build F stops the drop? Test the first candidate: CTRL+C from the
console.

**Method:** build G = the binary of build F; the boot script sets `ums_ignore_eject` but not
`ums_ignore_ctrlc`, and arms the watchdog. Load over FEL, watch the USB identity each 1–2 s.
Light read load only (macOS auto-mount). Same hub and cable as the 55-minute run of build F.

| Run | Start | Result |
|---|---|---|
| G-1 | 14:33:27 | FEL left the bus at 14:33:31; **no gadget appeared**; FEL was back at 14:33:48 (watchdog). So `ums` ended at once, about 0–4 s after the start. |
| G-2 | 14:34:33 | Gadget up after about 10 s. **Still up at 600 s** (14:44:41). Two watcher processes then ejected the disks; the gadget stayed (the 60 s idle exit of the patch needs more than 256 MiB read first), macOS mounted the volumes again. Still up at 14:47:35 (13 min). A passive watch continues. |

**Errors of the test tooling (no effect on the frame):** the first loop runner seemed to have
ended with no output, so a second runner was started; both were alive and watched the same run.
Cause: the output of two task files was read as one. Both wrote equal observations. The runner is
now a script, `scripts/ab-trials.py`, with a log file (`dumps/raw/ab-trials.log`).

**Reasoning:**
- With CTRL+C not ignored, the life of `ums` is random: 0 s in one run, more than 13 minutes in the
  next. Builds A and E (also not ignored): about 6–8 min and 7 min; build B: never came up (E021).
  Build F (ignored): 55 minutes under full load, and it started at the first try each time.
- A random stop that goes away when CTRL+C is ignored fits **noise on the console RX pin** (the
  R_UART RX on PL3, no known driver on this board), as Wes's issues #27 and #24 describe. It does
  not fit a power problem: same hub, same cable, same binary.
- Sample size: 2 runs of G, 1 long run of F. This is evidence, not proof. The equal 7 minutes of
  runs 1 and 2 may be chance.
- **Consequences:** (1) a Linux boot is not affected by this; (2) any U-Boot for this board must not
  take console input from a floating pin: no R_UART console, or `ums`/autoboot made immune (the
  image agent was told); (3) the power question for U-Boot with a dark screen is closed for this
  hub: 55 minutes of full read load passed.

**E043, addition (15:32):** the passive watch of run G-2 ended at its 45-minute limit. The gadget was
still up: run age about 3,490 s (58 min) with CTRL+C **not** ignored, no load. So the life of `ums`
with that setting was 0 s, about 7 min, about 7 min, and more than 58 min in four runs — random, with
a wide spread. The two 7-minute values were chance. The frame was left in that U-Boot.

## 2026-10-12 — E044: Is our emulation method current? (owner's question; web search + local check)

**Local facts:** `qemu-system-arm --version` → **11.1.0**. Homebrew lists 11.1.2 as the newest stable.
The QEMU site lists 11.1.0 (2026-08-11) as the newest feature release [VERIFIED: qemu.org]. Docker
runs on OrbStack 2.2.3; a `--platform linux/arm/v7` container reports `armv7l`.

**Allwinner machine models in QEMU 11.1** (`qemu-system-arm -M help`): `cubieboard` (A10),
`orangepi-pc` (H3, Cortex-A7), `bpim2u` (R40, Cortex-A7, has an AXP221 model). **There is no A33
model**, and the search found none in any release or in 2026 patches (scope: one extended search).

**What we use, and for what:**

| Method | Used for | Limit |
|---|---|---|
| Docker `--platform linux/arm/v7` (user-mode emulation of 32-bit ARM) | Arch Linux ARM userland: package checks, the Wi-Fi and panel module builds, the Omarchy shell test | Slow for large builds. Apple M-series cores cannot run 32-bit ARM code natively, so some emulation is always necessary on this Mac. |
| `qemu-system-arm -M orangepi-pc` | Booting the real stock `linux-armv7` kernel, module load tests, the boot card image test | A cousin SoC (H3). Not the A33: no DSI, no MUSB gadget, different PMIC |
| `qemu-system-arm -M bpim2u` | The AXP GPIO hog test | AXP221 on I2C, not the AXP223 on RSB |
| Native cross-compiler in an arm64 container | U-Boot | None; this runs at full speed |

**Gaps that a better method can close:**
- Hyprland could not start in the container test (E039): no DRM device. A full VM with a virtual
  display card (`qemu-system-arm -M virt` + `virtio-gpu`) gives a DRM/KMS device, so Hyprland can
  start on software GL. Not done yet. GPU acceleration for such a guest on a macOS host is still
  experimental (an RFC patch series by the UTM developer, December 2025) [DOCUMENTED].
- Large builds (Neovim, Hypoland): cross-compile with a native arm64 compiler, or distcc, in place
  of compiling inside the emulated userland.

**Limits that no emulator removes:** the Mali-400 GPU with the lima driver, the DSI panel, the
AIC8800 Wi-Fi chip, the frame's USB port and its power behaviour. These need the frame.

**Not found by the search:** how OrbStack runs 32-bit ARM images, and any speed comparison.

## 2026-10-12 — E045: Boot card image built (agent result) and reviewed before the first write

**Agent result:** `image/` — `build.sh` (one command, 6–12 min), U-Boot build "L", an initramfs that
starts the USB gadget, an Arch Linux ARM armv7 root, the stock kernel `linux-armv7 7.2.10-1`, three
device trees (`min`, `pmic`, `full`), `image/out/pf1007l-sd.img` (3,221,225,472 bytes, sparse),
`image/README.md` (682 lines: design, test, procedure, decision table).
QEMU test of this image (`-M orangepi-pc`, a test build of the same U-Boot source): 52 of 52 checks
(`image/test/results.txt`). The test found five real faults in the first image (a getty on `ttyGS0`
that blocked systemd for 20 minutes with no USB host; `machine-id`; `pacman-key` and the clock;
a mount timeout; a wait in `pf-gadget down`); all fixed and tested again.

**Design points:**
- U-Boot L = build E's DRAM and voltages; **no eMMC device** (`MMC_SUNXI_SLOT_EXTRA=-1`, `&mmc2`
  disabled); console on UART0 with **no pin switched** (each A33 console choice drives a pin with
  another job on this board); `stdin=nulldev`, `BOOTDELAY=-2`, `ums` immune to CTRL+C and eject.
- Layout: MBR; U-Boot at 8 KiB; FAT32 `PFBOOT` 256 MiB at sector 8192; ext4 root (grows at first boot).
- Blind boot: the initramfs starts a composite USB gadget (CDC ACM serial + CDC NCM network,
  `1d6b:0104`); the frame is `10.55.0.1` with a small DHCP server; `ssh -F image/secrets/ssh_config frame`;
  key login only. Marker files and logs go to `/pf/` on the FAT partition.
- Fallback: if the last Linux start was not confirmed over USB, the next power-on is "USB disk mode":
  the Mac sees the card read-only and can read the markers.
- Default boot label `min`: a small device tree with SD + USB only, no PMIC node. The other labels
  (`pmic`, `full-stage1`, `full`) add hardware step by step.

**Review by the main session (before the owner writes the card):**

| Check | Result |
|---|---|
| SHA-256 of the image | `a9bea449d53c10159fb6fbdf18e9f60bd6afb2d0f838decc45756c5000cefe82`, equal to the agent's file |
| Partition table | MBR; FAT32 at sector 8192 (256 MiB); Linux at 532,480 (2,812 MiB) |
| Bytes at 8192 | Equal to `out/u-boot-pf1007l-L.bin` (536,544 bytes, `eGON.BT0`); SPL end `0x450a` |
| U-Boot L config | `DRAM_ZQ=31739`, `DRAM_CLK=456`, DCDC1 3300, DCDC2 1200, DCDC3 1200, DCDC5 1500, ALDO1 3300, ALDO2 2500, ALDO3 3000; `MMC_SUNXI_SLOT_EXTRA=-1`; `CONS_INDEX=1` + `SUNXI_CONSOLE_NO_PINMUX`; `BOOTDELAY=-2`; `CMD_UMS_NO_ABORT`; `FAT_WRITE` |
| Strings in U-Boot L | `stdin=nulldev`; `ums: refused write…`; boot command: load `/boot.scr`, then `ums 0 mmc 0` in a loop |
| The three frame DTBs on the FAT partition | eMMC node `mmc@1c11000` `status = "disabled"` in each; `dr_mode = "peripheral"` |
| `boot.scr` | Storage commands only on `mmc 0:1`; two `fatwrite` of `/pf/uboot.env` |
| Boot menu | `DEFAULT min` |

**Not checked by the review:** the contents of the ext4 root (the agent's QEMU run covers it).
**Never run on the frame:** all of it. Known open risks (the agent's list): the SPL of build L
started by the boot ROM from the card (all starts so far were over FEL); UART0 with no pins; the
`min` device tree; macOS binding ACM + NCM; power under Linux load; `fatwrite` on this board.

**Owner's go:** "yes when it's ready write to the second sd card" and "we need to deploy to the
frame asap" (2026-10-12). Card: `disk15`, 31,914,983,424 bytes (E040). Writer:
`scripts/sd-write-macos.py` (guards tested against the connected disks; refuses the frame's disks,
the backup disk, a wrong size).

## 2026-10-12 — E046: FIRST LINUX BOOT ON THE FRAME (PLAN step C) — passed at the first try

**Card write (the owner, `sudo`):** `scripts/sd-write-macos.py write image/out/pf1007l-sd.img disk15
31914983424` → write 22.6 MB/s, read back 77.7 MB/s, "Written and verified: 3221225472 bytes",
SHA-256 of the written bytes = the image hash (`a9bea449…cefe82`).

**Boot:** FEL stub card out, boot card in, cable in (same hub and cable as today's backup).

| Mac time | Observation |
|---|---|
| 15:51:37 | The old U-Boot gadget leaves the bus (cable out) |
| 15:52:11 | USB device **`1d6b:0104` "PF1007L Linux"**; serial port `/dev/cu.usbmodemPF1007L00011` |
| 15:52:25 | The Mac has `10.55.0.13` on the new interface (`en14`, hardware port "PF1007L Linux") |
| 15:52:35 | `ssh -F image/secrets/ssh_config frame` works (second try) |
| 15:53:16 | `systemctl is-system-running` → `running`; 0 failed units |

**Read from the frame over SSH [VERIFIED on the device]:**
- `Linux pf1007l 7.2.10-1-armv7-ARCH #1 SMP PREEMPT … armv7l` — the stock Arch Linux ARM kernel.
- Device tree model "Humblestead HM-PF1007-BK (EFERCRO PF1007L), minimal"; boot label `min`.
- 4 CPUs, "ARMv7 Processor rev 5 (v7l)", features include `neon vfpv4 idiva idivt lpae`.
- Memory: `Memory: 930184K/1048576K available`; `free -m`: 978 MB total, 83 used, 815 free; zram swap 488 MB.
  **U-Boot found the full 1 GiB with DRAM ZQ 31739.**
- Storage: `mmcblk0` = the card (29.7 GiB), `/` grown to 29 GB, `/boot` FAT 256 MB. **No eMMC block
  device exists** (only host `mmc0`).
- Gadget: up at kernel time 2.16 s (`serial=1 net=ncm` on `musb-hdrc.2.auto`); the host configured it
  at 17.0 s ("start 1 is confirmed").
- First boot work: clock set from the build stamp, root grown, pacman keyring made at the first
  try, done at 40.9 s. The clock is about 33 minutes behind (no RTC, no network time).
- CPU clock 1,008,000 kHz.
- **`lima` loaded and found the GPU:** `gp - mali400 version major 1 minor 1`, `pp0` and `pp1`
  (= **Mali-400 MP2**), `l2_cache0 64K`, bus 200 MHz, mod 384 MHz, `[drm] Initialized lima 1.1.0 for
  1c40000.gpu on minor 0`. One message: `error -ENODEV: _opp_set_regulators: no regulator (mali)
  found` — expected with the `min` device tree (no PMIC node).
- Kernel log saved: `dumps/boots/2026-10-12-first-boot-min/dmesg.txt` (375 lines; the two MAC
  addresses in it are the gadget's made-up constants).

**What this proves:**
- The boot ROM starts U-Boot build L from the SD card (all earlier starts were over FEL).
- This unit's DRAM and voltage values carry a complete Linux boot.
- UART0 with no pins, `stdin=nulldev`, `fatwrite`, the extlinux flow: all work on the frame.
- macOS binds CDC ACM + CDC NCM of the composite gadget with its built-in drivers.
- The hub gives enough power for Linux with a dark screen (short test: some minutes).
- Mali-400 MP2 is confirmed on the device (was [DOCUMENTED]).

**What it does not prove:** PMIC, regulators, DSI panel, backlight, touch, Wi-Fi, eMMC, audio — the
`min` label uses SD + USB only. Open risks 1, 2, 3 and 4 of the image agent's list are closed.

**Recovery note:** a boot label that fails gives "USB disk mode" at the next power-on, and the card
is read-only there. To go back to `min` then, the card must go into the Mac's reader to edit
`/extlinux/extlinux.conf` (FAT, no `sudo`).

## 2026-10-12 — E047: The label ladder, the Wi-Fi chip ID, the touch chip, and THE FIRST PICTURE (PLAN step D)

All steps over SSH on the USB link; the frame restarted by `sudo systemctl reboot` (no cable pull).

**Label `pmic` (restart requested 15:54:45, SSH back 15:56:45):**
- `axp20x-rsb sunxi-rsb-3a3: AXP20x variant AXP223 found` — **the PMIC is an AXP223 on RSB** [VERIFIED].
- Regulators as in this unit's fex: `vdd-sys` 1200 mV, `vdd-cpu` 1200 mV, `vcc-dram` 1500 mV, `vcc-io`
  3300 mV, `vcc-3v3` 3300 mV, `vcc-pll-avcc` 3000 mV, `vdd-dll` 2500 mV.
- `axp20x-usb`: online, `input_current_limit=900000` (µA). `axp22x-ac`: online. `axp20x-battery`:
  "present, Charging", voltage 0 (the frame has no battery; the flag is not reliable here).
- Observation: the shutdown took about 90 s before the USB device left (a stop job at its time limit;
  not examined).

**Label `full-stage1` (the kernel work's DTB; display, lima and Wi-Fi modules blacklisted):**
- **Wi-Fi chip on SDIO [VERIFIED on the device]:** `mmc1:e37c:1` `SDIO_ID=C8A1:C08D`, function 2
  `C8A1:C18D`. This is the ID that the driver lists for the AIC8800DC. So the Wi-Fi power sequence of
  the DTS works (PL2 regulator, PL6 reset, AXP GPIO0, DLDO1/2). Open question 5 is closed for the
  chip identity.
- **Touch [VERIFIED]:** `silead_ts 0-0040: Silead chip ID: 0x50910000`; input device `silead_ts`
  (`event2`) 2.8 s later, so the extracted firmware `gsl_m86_hd.fw` loaded. Not tested with a finger yet.
- Thermal zone 37–38 °C (`sun4i-gpadc-iio`). cpufreq: `schedutil`, 120 MHz … 1008 MHz.
- No eMMC block device. systemd `running`, 0 failed units.

**The display, loaded by hand in this boot (16:00–16:01):**
```
modprobe pwm-sun4i            → /sys/class/backlight/backlight (max 10, was 8, power off)
echo 2 > brightness
modprobe panel-jadard-jd9365da-h3, sun6i_mipi_dsi, sun4i-frontend, sun4i-backend, sun6i_drc, sun4i-tcon
modprobe sun4i-drm
```
Kernel log:
```
sun4i-drm display-engine: bound 1e00000.display-frontend … 1e60000.display-backend … 1e70000.drc
sun4i-drm display-engine: No panel or bridge found... RGB output disabled      (expected: no RGB endpoint)
sun4i-drm display-engine: bound 1c0c000.lcd-controller … bound 1ca0000.dsi (ops sun6i_dsi_ops)
[drm] Initialized sun4i-drm 1.0.0 for display-engine on minor 0
Console: switching to colour frame buffer device 100x80
sun4i-drm display-engine: [drm] fb0: sun4i-drmdrmfb frame buffer device
sun6i-mipi-dsi 1ca0000.dsi: Attached device zr789-sq9365-101
```
State: `card0-DSI-1` connected, enabled, DPMS On; CRTC active; mode
`"800x1280": 60 67000 800 818 836 854 1280 1300 1304 1314`; `fb0` 800×1280, 32 bpp; backlight power
on at level 2, then 4 of 10.

A banner was written to `/dev/tty1`, and a noise band and a white band to `/dev/fb0`.

**Owner (at the frame): "it says if you an read this the dsi panel works!"**

**Result: the MIPI-DSI panel shows a picture with mainline Linux 7.2.10, the stock Arch Linux ARM
kernel, our out-of-tree panel module and our device tree — at the first try.** [VERIFIED on the
device, by the owner's eyes; picture quality, colours and orientation not described yet.]

**What this means:**
- The largest risk of the project (E029 risk 1: "no upstream A33 board enables DSI") is passed for
  the basic function: `sun6i_mipi_dsi` drives this panel on an A33 in non-burst video mode.
- The guesses of the DTS that could have stopped the picture were right or harmless:
  `vcc-dsi-supply`, the DC1SW/ELDO3 mapping, one reset pulse in place of the vendor's two, the
  backlight before video, 0x11/0x29 with no parameter.
- The data chain from this unit is confirmed end to end: fex timings → init table from `lcd.ko` →
  generated panel entry → picture.
- Power: the frame runs with the backlight at level 4 of 10 on the present hub, AXP input limit
  900 mA. Higher levels are not tested.

**Not known yet:** orientation on the frame (expected: sideways, the panel is portrait), colour
order, tearing, the pixel clock (66 or 67 MHz), behaviour over blank/unblank and reboot with the
modules loaded by the normal path (label `full`), brightness range, current draw.

## 2026-10-12 — E048: Internet for the frame through SSH; GPU baseline on the real panel (PLAN step F)

**Owner's report on the first picture:** the banner text is readable and both test bands (noise,
white) are visible. So the text console and raw writes to `fb0` reach the panel.

**Internet with no change on the Mac:** `ssh -N -R 1080 frame` (a remote dynamic forward: a SOCKS
proxy on the frame at `127.0.0.1:1080` that goes out through the Mac). On the frame:
`ALL_PROXY=socks5h://127.0.0.1:1080`. Test: `curl` to the ALARM mirror → HTTP 302 in 0.22 s.
`sudo ALL_PROXY=… pacman -Sy` works. The frame's clock was set from the Mac over SSH.

**Packages installed on the frame (about 2 minutes):** `mesa 1:26.2.4-1` (has `lima_dri.so` and
`sun4i-drm_dri.so`), `mesa-utils 9.0.0-7`, `glmark2 2023.01-2`, `evtest 1.36-1`, `libdrm 2.4.134-1`.

**`modprobe lima`** (blacklisted in this boot label, loaded by hand):
`[drm] Initialized lima 1.1.0 for 1c40000.gpu on minor 1`; `/dev/dri/card1`, `renderD128`.
The message `_opp_set_regulators: no regulator (mali) found` stays (the GPU node has no supply in
our DTS; the GPU runs at its fixed clock: bus 200 MHz, mod 384 MHz).

**`eglinfo -B -p gbm` [VERIFIED on the device]:**
- OpenGL ES profile renderer: **Mali400**; version: **OpenGL ES 2.0 Mesa 26.2.4-arch1.1**;
  shading language: OpenGL ES GLSL ES 1.0.16. Desktop profile: 2.1.
- This confirms the research: GLES 2.0 only on this GPU.

**`glmark2-es2-drm` on the DSI panel (full screen 800×1280, 8 s each scene):**

| Scene | FPS | Frame time |
|---|---|---|
| `build` (use-vbo) | 215 | 4.65 ms |
| `shading` (phong) | 75 | 13.46 ms |
| `texture` (linear) | 139 | 7.24 ms |
| Score | 142 | |

No error in the kernel log. Temperature: 41.1 °C before, 48.9 °C after 24 s of load. Backlight level 4.

**PLAN Phase 6 gate ("`kmscube` spins on lima"): passed with `glmark2`** (`kmscube` is not in the
ALARM repos). The GPU draws on the real panel through `sun4i-drm` + `lima` (render-only GPU + KMS).

**Not tested:** rotated output, a compositor, long runs, GPU frequency scaling (no supply in the DTS).

## 2026-10-12 — E049: HYPRLAND RUNS ON THE MALI-400 (PLAN step G, GPU option 1)

**Packages on the frame:** `hyprland 0.56.2-4`, `aquamarine 0.15.1-1`, `foot 1.28.0-2`,
`seatd 0.9.3-1`, `quickshell 0.3.2-1`, `grim 1.5.0-2` (109 MiB download, 393 MiB installed, 2 min
through the SSH SOCKS tunnel). `seatd` enabled; user `frame` in groups `seat video input render`.
Display stack and `lima` loaded by hand as in E047/E048. Hyprland started from an SSH session.

**Control — Hyprland with no override:** it aborts (signal 6). Its log:
```
CDRMRenderer(drm): Using device /dev/dri/card1
[EGL] Command eglCreateContext errored out with EGL_BAD_MATCH: dri2_create_context
CDRMRenderer: eglCreateContext failed with GLES 3.2, retrying GLES 3.0
CDRMRenderer: Can't create renderer, eglCreateContext failed with both GLES 3.2 and GLES 3.0
drm: initMgpu: no renderer
```
This is the behaviour that research/05 read in the source (aquamarine `Renderer.cpp`).

**Test — `MESA_GLES_VERSION_OVERRIDE=3.0 Hyprland`:**
```
CDRMRenderer: eglCreateContext failed with GLES 3.2, retrying GLES 3.0
Using: OpenGL ES 3.0 Mesa 26.2.4-arch1.1
Vendor: Mesa
Renderer: Mali400
```
- **Hyprland 0.56.2 starts and stays up.** `hyprctl monitors`: `DSI-1`, 800×1280@59.706, physical
  size 135×216 mm. `wayland-1` socket present. No shader, GL or "ERR ]" line in its log (only
  aquamarine's EDID note).
- The **generated default config** was in use: rounding 10, shadows on, **blur on** (size 3, 1 pass),
  all animations on. So the base shaders, the border gradient, shadow and the default blur compile and
  run on lima with the override.
- `foot` opens and shows a shell prompt. The Qt welcome window (`hyprland-welcome`) draws.
- **The owner sees it on the frame:** "welcome to hyperland there text".
- Screenshots taken on the frame with `grim`: `dumps/boots/2026-10-12-first-picture/hyprland-first.png`
  (800×1280) and `hyprland-rotated.png` (1280×800).
- **Rotation works:** `scale = 1, transform = 1` in `hl.monitor({…})` of `~/.config/hypr/hyprland.lua`,
  `hyprctl reload` → `transform: 1`, screenshot 1280×800 landscape. (`hyprctl keyword` does not work
  with the Lua config: "keyword can't work with non-legacy parsers".) If the picture is upright or
  upside down on the frame is for the owner to say (the other value is 3).
- Memory with Hyprland + one `foot` + the welcome window: `free -m` used 281 MB of 978 MB; RSS
  Hyprland 119 MiB, foot 13 MiB. Temperature 44–47 °C.

**PLAN Phase 7 gate ("Hyprland shows a terminal on lima at a usable speed"):** a terminal is shown;
speed is not measured yet (no frame-rate number, no input test).

**What this means:** GPU option 1 works for the default feature set, on real hardware, with the
stock Arch Linux ARM `hyprland` package. Hypoland (option 2) is not necessary for a first desktop.
As far as the research found, this is the first Hyprland on a Mali-400 and on 32-bit ARM hardware.

**Not tested:** the blur styles and effects that research/05 lists as not possible on GLES 2
(integer bit operations, `texelFetch`, multiple render targets = screen sharing), fp16 banding,
long runs, touch input in Hyprland, speed under animation, the Omarchy config.

## 2026-10-12 — E050: Touch — raw range, orientation, and the correct Hyprland setting (PLAN step E)

**Raw test (`evtest /dev/input/event2`, device `silead_ts`):** `ABS_MT_POSITION_X` 0–959,
`ABS_MT_POSITION_Y` 0–639, slots 0–9. So the raw range is **960 × 640**, as the firmware analysis
estimated (E028). The owner touched the corners with the frame upright in landscape:

| Touch (owner's order) | Raw x | Raw y |
|---|---|---|
| Top-left | 39–98 | 548–605 |
| Top-right | 911 | 618 |
| Bottom-right | 907 | 53 |
| Bottom-left | 39 | 29 |
| Centre | 488 | 281 |

So raw X goes left → right and raw Y goes **bottom → top**, in the landscape view. No axis swap.

**In Hyprland (monitor `transform = 3`):**
1. `touchdevice = { transform = 0 }` + udev `LIBINPUT_CALIBRATION_MATRIX="1 0 0 0 -1 1"` → the owner:
   the highlighted window was not the touched one (top and bottom swapped).
2. `transform = 0`, udev rule off → the owner: left correct; top right selected the bottom window;
   bottom right selected the top-right window. Still top and bottom swapped.
   **Reasoning:** the udev matrix changed nothing. Hyprland sets the libinput calibration matrix
   itself from `touchdevice.transform`, and that replaces the udev value. With transform 0 the raw
   orientation (Y up) goes to the screen unchanged.
3. **`touchdevice = { transform = 6, output = "DSI-1" }`** (6 = flipped + 180° = a vertical flip).
   Measured with `wev -f wl_touch` in a window at (22,22):

| Touch | Screen position reported by Hyprland (1280 × 800) |
|---|---|
| Top-left | (28, 30) |
| Top-right | (1241, 41) |
| Bottom-right | (1239, 771) |
| Bottom-left | (40, 775) |

**Result: the touch mapping is correct with `transform = 6`.** [VERIFIED on the device with numbers.]
The udev rule file `/etc/udev/rules.d/90-pf1007l-touch.rules` is left in place with its line
commented out.

**Errors on the way:** two rounds with the owner were spent on a focus test that could not show
the mapping exactly. The coordinate viewer (`wev`) gave the answer in one round. Measure first.

**For the DTS (later):** `touchscreen-size-x = <960>`, `touchscreen-size-y = <640>` are right;
`touchscreen-inverted-y` in the DTS would make the raw data match a landscape screen, and then a
compositor would need no flip. Not changed now.

**Not tested:** multi-touch, gestures, drift, the touch firmware's start sequence under suspend.

## 2026-10-12 — E051: THE WI-FI DRIVER WORKS WITH THE REAL CHIP (scan)

**Setup:** label `full-stage1`, Hyprland running, backlight level 4, the present hub.
`pf-wifi-check` → `SDIO_ID=C8A1:C08D` (function 2: `C8A1:C18D`). Then `pf-wifi-check --load`
(`modprobe aic8800_bsp`, `aic8800_fdrv`; the modules of E031, built for `7.2.10-1-armv7-ARCH`).

**Kernel log (short):**
```
aicbsp_sdio_probe:1 vid:0xC8A1 did:0xC08D
the device is PRODUCT_ID_AIC8800DC
aicbsp: Set SDIO Clock 50 MHz
rwnx_load_firmware … fw_patch_table_8800dc_u02h.bin, fw_adid_8800dc_u02h.bin, fw_patch_8800dc_u02h.bin
h_u02 is loaing
rwnx_load_firmware … fmacfw_patch_8800dc_h_u02.bin, fmacfw_calib_8800dc_h_u02.bin, fmacfw_patch_tbl_8800dc_h_u02.bin
############ rwnx_plat_patch_load done
```
- **The driver itself selects the "H" U02 firmware set** — the variant that E038 inferred from the
  vendor's files. Chip = AIC8800DC "H", revision U02 [VERIFIED by the driver on the device].
- `wlan0` exists (`type managed`). No oops, no freeze. Temperature 43 °C.

**Scan:** `systemctl start iwd`; `iwctl station wlan0 scan`; `get-networks` → **7 networks**;
`iw dev wlan0 scan` → 9 BSS entries, signal −33 dBm to −82 dBm. (Network names are not recorded.)

**Result:** the out-of-tree `radxa-pkg/aic8800` driver, built for 32-bit ARM with no patch of ours,
runs on this frame's chip with Radxa's firmware: it loads the firmware, makes the interface and
receives. [VERIFIED on the device.] The third big risk of PLAN §0 is passed for "load and scan".

**Not tested:** a connection to a network (it needs the owner's Wi-Fi password, which the owner must
type), throughput, stability, suspend, the freeze under weak power that Wes's PR #15 reports,
Bluetooth. The driver is still blocked from loading at boot (`/etc/modprobe.d/pf1007l-wifi.conf`).

## 2026-10-12 — E052: Resume the live Omarchy desktop; wallpaper, menu, keyboard, themes and boot

The prior agent stopped after manually launching Quickshell. On reconnect, Hyprland and Quickshell were alive. The screenshot showed the bar over a blank background. `/tmp/qs-manual.log` reported WebP unsupported, PipeWire unavailable and no network backend. Memory was 428 MB used / 978 MB total, with 550 MB available.

**Changes on the SD card:** installed `qt6-imageformats`, NetworkManager, BlueZ/tools, `xdg-terminal-exec`, desktop folders/icons and the missing icon font. Started PipeWire/WirePlumber; configured NetworkManager to leave `usb0` unmanaged; selected the already-installed Foot terminal. The wallpaper was a 6016×3384 WebP; the Qt decoder fixed it without changing the image. The normal Omarchy shell launcher also rendered successfully with the compositor's GLES override; the prior manual unset is not required by these observed desktop functions.

**Touch keyboard:** Squeekboard rendered and accepted input. The owner confirmed "Letters appear"; the terminal screenshot contains the typed letters. A local `frame.keyboard` Omarchy bar plugin calls `pf-keyboard-toggle`. The `pf-keyboard.service` uses D-Bus readiness and is started after importing the Wayland display from Hyprland's user autostart. Its measured systemd memory was 13.8 MB (22.1 MB peak). Toggle calls changed `Visible` true then false. The button was present in the inspected theme screenshots. Text size 18 uses Omarchy's own user override and survives theme changes. Stay-awake disables idle locking while the frame has no physical keyboard.

**Theme gate:** the normal theme command changed Tokyo Night → Gruvbox → Tokyo Night. Screenshots verified the changed wallpaper, bar and terminal colors. `hyprctl configerrors` was empty. Foot plus the theme-switch test used 565 MB, 412 MB available, no swap used. Missing optional `owe` video-intro tooling and the `/usr/bin` browser-policy helper produced warnings in theme hook logs; ordinary still-image themes worked. This is a reduced experimental desktop, not a complete package/update port.

**Boot gate:** rebooted into the separate UART1 `bluetooth-test` entry made by the subagent. The owner saw Omarchy. USB SSH was transiently unavailable during re-enumeration; USB serial logged into the running system and restored the next boot default to `full`. SSH then worked. Hyprland, Quickshell, NetworkManager, the keyboard, PipeWire socket and WirePlumber were active without manual desktop launch. UART1 mapped to `ttyS1` at `1c28400`.

**Boot finding:** Wi-Fi did not load because the old bring-up `blacklist aic8800_bsp` / `aic8800_fdrv` still applied to systemd-modules-load. Merely adding modules-load entries was insufficient. `port/frame/unblacklist-wifi.py` comments only those two blacklist lines, preserving a backup and leaving the untested Bluetooth sleep module blocked. After explicit modprobe, `wlan0` appeared and NetworkManager could scan. A further reboot must verify the blacklist fix and saved Wi-Fi reconnect.

**Other errors corrected:** the first terminal launch failed because `xdg-terminal-exec` was missing; installing it fixed the same Omarchy launch command. A shell-restart notification-readiness check briefly reported failure while plugins were still starting; later IPC, menu rendering and notification rendering worked. Some unprivileged file moves reported `security.SMACK64` attribute warnings; files and live configuration were verified afterwards. A manual shell "kill" IPC method did not exist; the supported `omarchy-restart-shell` command was used instead.

**Reproducible files:** `port/frame/` contains the setup script, keyboard plugin/service and platform-detector patch. The detector now reports `armv7`, preventing helpers from choosing the wrong x86 templates. Full armv7 packaging and update templates remain future work. Screenshot evidence is under `dumps/boots/2026-10-12-first-picture/codex-*.png`. Earlier screenshots retain the old terminal-failure toast; Omarchy restores popup history at boot, so that stale toast needed dismissal through its notification command. No eMMC write, kernel upgrade, frame-side compilation or Wi-Fi credential in project files.

Bluetooth results are being recorded separately by the subagent in `docs/bluetooth.md`; a real HCI version reply has been received. Wi-Fi association has also succeeded through a hidden `nmcli --ask` password prompt; internet and reboot checks follow in E053.

## 2026-10-12 — E053: Wi-Fi internet and native Bluetooth LE; combined reboot passes

**Wi-Fi:** the owner named their network and authorized password entry. The agent used `sudo nmcli --ask device wifi connect … ifname wlan0` in a PTY. The password went through nmcli's hidden prompt, not a process argument or project file. NetworkManager saved the profile with autoconnect enabled and WPA-PSK security. Network names, credentials and private addresses are omitted here.

`wlan0` became connected and received a DHCP route and DNS servers. HTTPS forced through `wlan0`, with all proxies bypassed, returned **HTTP/2 200** from `https://example.com`. Three pings through `wlan0` to `1.1.1.1` all returned: **0% loss**, 4.104–6.564 ms, mean 5.217 ms. The USB management interface remained unmanaged by NetworkManager and reachable through systemd-networkd. [VERIFIED on the device.]

**Native Bluetooth:** the owner's requested subagent enabled UART1 on PG6–PG9 in a separate DTB. With the normal AIC Wi-Fi BSP loaded, UART at 1.5 Mbaud returned HCI Read Local Version, version 0x0b = Bluetooth 5.2. No PL8/PL10 GPIO toggles were necessary. BlueZ exposed a powered LE controller with secure-connections/privacy support. A bounded 12-second BLE scan found ten unique devices, then discovery stopped. Nearby device identifiers were suppressed.

The packaged BlueZ 5.87 `btattach` had a glibc 2.42+ baud-constant incompatibility: it set the wrong UART speed and HCI reset timed out. `wifi/bt-uart-attach.py` uses the current termios API and verifies 1,500,000 baud before attaching H4. `wifi/pf-bluetooth-uart.service` loads normal Wi-Fi firmware, verifies the UART reply, and supervises this helper. It is installed and enabled. The separate `full-bluetooth` boot label is now default; original `full` and its DTB remain untouched. Detailed source evidence and rollback are in `docs/bluetooth.md`.

**Combined final reboot:** without manual startup commands, all of these were active: `pf-hyprland`, NetworkManager, `pf-bluetooth-uart`, BlueZ, `pf-keyboard`, PipeWire socket and WirePlumber. The saved Wi-Fi profile auto-connected, and direct HTTPS over `wlan0` returned HTTP/2 200 again. Omarchy shell ping answered. BlueZ powered the controller automatically; a fresh eight-second LE scan found ten devices, then stopped. Both system and user `systemctl --failed` lists were empty. `hyprctl configerrors` was empty. [VERIFIED on the device.]

After plugins settled, with the menu open: **491 MB used / 978 MB total, 486 MB available, no swap used**. RSS: Hyprland 109,828 kB, Quickshell 185,436 kB, Squeekboard 24,124 kB. Temperature shortly after boot was 52.974 °C. The canonical session uses `LANG=C.UTF-8` and a five-second shell IPC timeout for this slow ARM board. The clean desktop screenshot is `dumps/boots/2026-10-12-first-picture/codex-verified-desktop.png`.

**Limits:** BLE peripheral pairing and reconnect still need an actual mouse or keyboard; none is present. Classic Bluetooth BR/EDR is not exposed by this firmware and is not proved. The SDIO-Bluetooth fallback was built locally but never deployed; normal Wi-Fi modules remain in use. Long-run load/suspend tests, complete armv7 packaging/update support and internal-storage installation remain future work. No eMMC write or kernel upgrade was made. The working live SD card has changes not yet integrated into the generic image rebuild.

## 2026-10-12 — E054: Everyday apps and PF1007L display/performance tune

**Question:** Can the standard Omarchy Bluetooth path be completed, and what
explains the oversized UI and poor responsiveness with browser windows open?

**Changes:** Installed Omarchy's `bluez-tools`, copied and enabled its supplied
`bt-agent.service`, rebooted, then removed the old incomplete MX Keys record.
The owner paired and typed successfully through Omarchy's normal Bluetooth
panel. Installed the armv7 everyday set: Firefox, Nautilus, MPV, imv, Noto and
emoji fonts, Fastfetch, btop and ripgrep. Chromium is not packaged by the
configured armv7 repository; Firefox is the usable full browser replacement.

**Display evidence:** The Mali-400 DRM renderer is active. Hyprland reported
`allow_tearing = false`, direct scanout disabled and no active tearing. The
panel was at 800×1280@59.706 Hz, transform 3, scale 1.6 and GTK scale 2, which
left only a 500×800 logical desktop. `port/frame/tune-hypr.py` changes this to
scale 1.25 and GTK scale 1 (640×1024 logical desktop) and disables animations;
Hyprland reloaded it with no config errors.

**Performance evidence:** During two blank Firefox test windows, available RAM
was 152 MiB and swap use 401 MiB; memory full-pressure was nonzero and Firefox
used roughly one CPU core. Closing the two test windows left the desktop plus a
terminal with 542 MiB available and 168 MiB swap used. The primary slowdown is
browser memory pressure, not software rendering. Actual visual tearing requires
owner observation after the tuning; the compositor configuration itself does
not permit tearing.

## 2026-10-12 — E055: Close the rebuild gap, no eMMC

**Question:** Can a clean card reach the live desktop without hand steps?

**Result (Mac side, frame offline):** the two scripts named in docs but absent
are now present and pass syntax checks. `port/frame/bootstrap.sh` fetches
pinned Omarchy `quattro` `defbf90e`, refuses to overwrite an existing Hyprland
config, seeds user config only when absent, then runs `apply.sh`. It checks
user `frame`, `armv7l`, boot config, and kernel `7.2.10-1`. `wifi/install-uart-bluetooth.sh --activate`
rebuilds the Bluetooth DTB from the live `full` DTB with `fdtoverlay`, installs
the probe plus attach helpers and the service, adds `full-bluetooth` without
touching `full`, and sets it as default. `--rollback` restores `full` and stops
the service. The extlinux insert passed on a copy of the template: new label
present, `full` block intact.

**Port guard:** `port/frame/armv7-packages.txt` lists the E052-E054 tested set.
`port/frame/guard-updater.py` patches bulk helpers on armv7 and writes a pacman
`PreTransaction` hook that blocks `linux-armv7`, headers, and `chromium`.
The same hook plus `pf-pacman-guard` now ship in `image/rootfs/` for future
clean images. `apply.sh` installs `woff2-font-awesome`, the guard, `pf-health-check`,
and suspend masks. `bash -n` passes on all shell scripts; `py_compile` passes;
`dtc -@` passes on the Bluetooth overlay; guard patch passed on a fake Omarchy
tree. Frame was not reachable over USB (`10.55.0.1` timeout), so no live run.
No eMMC write. Kernel stays pinned.

## 2026-10-12 — E056: Hard reset after wedged session; desktop back

**State before:** SSH showed load 550, then SSH banner timed out. USB serial
gave a shell. A `sudo systemctl reboot` over serial got SIGINT from my own
check and never ran. The owner then pulled the cable and plugged it back in.
No write was in progress, so the cut was safe.

**State after:** up 0 min, load 4.11 falling to 0.37. Temp 60.5 C. RAM 345 MiB
used, 632 MiB free, no swap used. No failed units. All session units active:
keyboard, PipeWire socket, WirePlumber, bt-agent, Hyprland, NetworkManager,
Bluetooth UART service.

**Screen:** first `grim` shot was black plus cursor only (3.7 KB). Shell ping
was `ok`, layers showed background, bar, notifications from pid 943, no open
windows. Monitor DSI-1 active, scale 1.25, transform 3. Second shot after
settle shows Tokyo Night wallpaper, bar, and two notifications (1 MB).
Proof: `dumps/boots/2026-10-12-first-picture/codex-after-reboot-desktop.png`.
The grey-plus-top-bar the owner saw matches a live shell with no windows.
Do not tap "Update System" on armv7; the E055 guard blocks it.

## 2026-10-12 — E057: Perf moves, tearing, sensors, YouTube

**Perf 1/3 (wallpaper):** active wallpaper was 6016x3384 WebP, 653 KB.
Backed up to `.before-frame-shrink`, resized to 1280x720, 58 KB.
Reloaded shell. New screenshot looks the same at panel size.

**Perf 3/3 (Hyprland flags):** checked live with `hyprctl getoption`.
Blur off, shadow off, `allow_tearing` false, direct scanout 0 — already cheap.
`misc:vfr` has no such option in 0.56 (wiki tip is old; VFR is now automatic).
`damage_tracking` was 2 (partial). Owner saw tearing, so set 0 (full repaint)
in `looknfeel.lua` with backup, `hyprctl reload` ok. `tune-hypr.py` now holds
the same block. Needs owner eyes: tearing is motion-only, screenshots miss it.

**Perf 2/3 (Firefox):** interrupted. Stock launch to example.com took over
120 s to show a window (tool timeout; window did appear). One tab cost about
560 MB across 4 processes. Profile now exists, so `user.js` can land next.

**Sensors:** fex has no light-sensor node, so the frame has no ALS. The Android
light/temperature XMLs are stock leftovers, not hardware. No auto-brightness
from light; use time schedule instead. Accelerometer SC7A20 exists on TWI1
0x19 [VERIFIED fex] and mainline `st_accel` lists `silan,sc7a20` [VERIFIED
torvalds source]. Unused today; candidate for auto-rotate via a DT node.
Camera fex lists gc2035 but `vip_used = 0` and vendor modules are commented
out, so treat as absent. Thermal, touch, LRADC keys, AXP ADC already in use.

**YouTube:** bottleneck is CPU software video decode. Firefox gets VP9,
which 4xA7 at 1 GHz cannot decode in real time. RAM and Wi-Fi are fine.
Fix path: `mpv` plus `yt-dlp` at 480p H.264, or force H.264 in browser.
Not tested yet. No eMMC write in any step.

## 2026-10-12 — E058: Light sensor hunt, accel proof, lines, streams

**Light sensor:** the owner pushed back, and the fex proves the design has
one: `[ls_para]` on TWI1, addr `0x23`, int PB07, but `ls_used = 0`.
`[ls_list_para]` names `ltr_501als` plus `jsa1212`. Addr 0x23 is Lite-On
LTR-501ALS. Mainline `ltr501.ko` ships in the stock kernel [VERIFIED file].
But a root I2C scan of bus 1 shows no 0x23, so this unit has no chip fitted.
Wes's docs name no ALS on PF1007L. Result: no light-driven auto-brightness
on this unit. Time schedule stays the fix.

**Accelerometer:** bus 1 shows **0x19**, the SC7A20 [VERIFIED live scan].
`st_accel.ko` plus `st_accel_i2c.ko` ship in the stock kernel [VERIFIED
files]. Next: one DT node (`silan,sc7a20`), then `iio_info` reads.

**Lines:** dmesg has no DSI or underflow errors. `damage_tracking = 0` is
live since E057. Vertical lines every so often are still owner-observed;
screenshots miss motion faults. Next test is backlight level steps, to split
PWM/power path from pipeline path.

**YouTube without download:** `mpv` streams (nothing is saved), but YouTube
gates block this board today. Android-client URLs give HTTP 403 from
googlevideo over IPv4 and IPv6. Web-client formats are SABR-only (storyboard
images, no media; known yt-dlp #12482). Piped and Invidious public instances
returned empty, 502, or disabled. `yt-dlp` 2025.12.08 is installed from extra.
Local proof instead: a generated 640x480 H264 clip played in `mpv` on screen
at 72% of one core. Proof: `dumps/boots/2026-10-12-first-picture/codex-mpv-local-playback.png`.
So 480p H264 streams play; only the YouTube URL gate is open. No eMMC write.
