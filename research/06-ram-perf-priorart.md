# 06 — Will it fit, will it be usable? RAM / CPU / storage budget and prior art

Target: Allwinner A33 photo frame — 4x Cortex-A7 (armv7, 32-bit), Mali-400 MP2 (lima, GLES 2.0 only),
1 GB RAM, ~16 GB eMMC, 1280x800 touch, RTL8723CS.
Researched 2026-10-12. Tags: **[VERIFIED]** primary source read or file inspected; **[DOCUMENTED]**
secondary source (forum, review, search summary); **[UNCONFIRMED]** my inference or estimate.
Every null result below is scoped to the searches named in "Sources".

---

## Summary (5 bullets)

1. **"Omarchy" today is not the Omarchy of the RAM questions.** The current release (v4.0.4, 2026-09-14)
   and master (4.0.0.alpha) replaced waybar/mako/walker/hyprlock/hypridle with **one Quickshell (Qt6 QML)
   process** (`omarchy-shell`), made **foot** the default terminal, and use Lua Hyprland config
   [VERIFIED: `install/omarchy-base.packages`, `docs/omarchy-shell.md`,
   `default/xdg-terminal-exec/hyprland-xdg-terminals.list`]. Omarchy supports **x86 and aarch64 only**
   ("Raspberry Pis" are named under aarch64); there is **no armv7 platform** [VERIFIED: `AGENTS.md`].
2. **The biggest usability problem is not RAM, it is the GPU.** Hyprland hard-asserts a **GLES 3.0+**
   EGL context (`RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")`)
   [VERIFIED: Hyprland `src/render/OpenGL.cpp` @663b29b], and lima is GLES 2.0 only [DOCUMENTED: Mesa
   lima docs]. So on this frame Hyprland can only run on **llvmpipe (CPU rendering)**. The one A33
   llvmpipe datapoint: glmark2 score **13** (Mesa 11.1, LLVM 3.7, 2016) [DOCUMENTED]. Expect a
   compositor that animates at single-digit to low-teens fps and steals CPU from apps [UNCONFIRMED].
   (GPU agent owns the detail; it decides the verdict here.)
3. **RAM: a terminal-centric desktop fits in 1 GB; a browser is the ceiling.** Estimated idle desktop
   on armv7 ≈ **400–550 MB** used with Hyprland(llvmpipe)+Quickshell+services; one simple browser tab
   adds **~270 MB (Chromium) / ~370 MB (Firefox)** (Pi 4, 2020) [DOCUMENTED]. That lands at 700–900 MB
   — survivable only with zram and an OOM killer. 32-bit roughly halves idle use versus 64-bit
   (Pi OS: 103 MB vs 196 MB idle) [DOCUMENTED, Phoronix].
4. **Storage: the full Omarchy set does not fit 16 GB with headroom** (~15 GB used after updates on
   v3.0.2 [DOCUMENTED]; ISO 6.2–7 GB). Drop btrfs+snapper: its rollback value comes from
   `limine-snapper-sync`, and Limine does not boot an A33 (U-Boot does) [VERIFIED that Omarchy wires
   snapper to Limine; UNCONFIRMED that it cannot be made to work]. Use ext4 (or f2fs) on eMMC.
5. **Kernel facts that change the plan:** mainline A33 CPU OPPs stop at **1.008 GHz**; 1.104/1.2 GHz at
   1.32 V exist only in two board DTS files (SinA33, BPi-M2M), not the Q8 tablet DT; **1.344 GHz is
   not in mainline** [VERIFIED: dts files]. The Arch Linux ARM `linux-armv7` kernel builds zram with
   **only the LZO backend** — Omarchy's `compression-algorithm = zstd` is not available on that kernel
   [VERIFIED: ALARM `core/linux-armv7/config`, 7.2.6].

---

## RAM budget table (1 GB, armv7)

Conditions: numbers from other platforms are scaled by judgment for 32-bit; every per-process row is
an estimate unless tagged otherwise. RSS double-counts shared libraries; budget in **PSS** terms.
Measure on the device with `smem -k -c "pss name"` before trusting any row.

| Item | Estimate on A33 (armv7) | Evidence behind the estimate |
|---|---|---|
| Physical RAM | 1024 MB | spec |
| CMA reserve | 64 MB in ALARM `linux-armv7` and `multi_v7_defconfig` (`CONFIG_CMA_SIZE_MBYTES=64`); `sunxi_defconfig` leaves the 16 MB Kconfig default [VERIFIED configs]. No `reserved-memory` node in `sun8i-a23-a33.dtsi`/`sun8i-a33.dtsi` [VERIFIED]. CMA pages are lent to movable allocations while unused, so this is not fully lost [DOCUMENTED kernel CMA design]. | A 2018 VE patch reserved up to 96 MB inside the first 256 MB for the video engine [DOCUMENTED]. Scanout at 1280x800x4 = 4 MB/buffer; 32–64 MB is ample for display only [UNCONFIRMED]. |
| Kernel text/data, page tables, slab | 50–80 MB | [UNCONFIRMED]. Note ALARM uses `VMSPLIT_3G` + `HIGHMEM` [VERIFIED], so ~250 MB of the 1 GB is highmem; harmless for user pages. |
| systemd PID1 + journald + udevd + logind + dbus | 25–40 MB | Pi OS 32-bit idle "used" minimum 103 MB total for whole OS incl. lightweight desktop (2021) [DOCUMENTED Phoronix]. |
| NetworkManager + wpa_supplicant | 15–25 MB | [UNCONFIRMED]. iwd alone ~5–10 MB [UNCONFIRMED]. Omarchy 4 ships networkmanager [VERIFIED package list]. |
| pipewire + wireplumber (+pulse) | 20–35 MB | [UNCONFIRMED] |
| xdg-desktop-portal + -hyprland + -gtk | 25–50 MB | [UNCONFIRMED]; an EndeavourOS user tied slow waybar start to portals [DOCUMENTED] |
| **Hyprland** | 60–120 MB native; **+30–80 MB** for llvmpipe/LLVM private state and CPU-side buffers | Desktop x86-64 anecdote "200–300 MB" (r/hyprland, 2025, unmeasured) [DOCUMENTED]. No armv7 figure found. |
| Sway (alternative) | 30–60 MB | 131 MB RSS (HN anecdote) and 216 MB (FreeBSD forum, method unclear) on 64-bit desktops [DOCUMENTED] |
| **omarchy-shell (Quickshell, Qt6 QML)** | **100–250 MB** — largest single risk | "a few hundred MB per display" for Noctalia v4 (another Quickshell shell) [DOCUMENTED anecdote]; Quickshell switched to jemalloc because QML heap fragmentation looked like a leak [DOCUMENTED commit msg]. |
| waybar + mako + walker (Omarchy 3-style) | waybar 15–40, mako 5–10, walker 30–80+ (GTK4) MB | Only anecdotes found (one "422 MB" waybar claim is almost certainly VSZ) [DOCUMENTED/UNCONFIRMED] |
| hypridle / hyprlock | ~5 MB / 20–40 MB while locked | No measurement found [UNCONFIRMED]. Omarchy 4 no longer ships them (lock is a Quickshell plugin) [VERIFIED]. |
| swaybg / hyprpaper | 5–15 MB (+1 decoded 1280x800 image = 4 MB) | swaybg "46 MB" in an old sway issue was ps VSZ [DOCUMENTED] |
| foot / alacritty / ghostty | ~10–20 / ~25–35 / ~80–100 MB | foot ~20 MB vs alacritty ~100 MB in one setup; alacritty ~30 MB; ghostty 80–100 MB [DOCUMENTED, mixed methods]. Ghostty needs desktop OpenGL 3.3 — a non-starter on lima [UNCONFIRMED; GPU agent]. |
| neovim (plain) / LazyVim-style with LSP | 15–30 / 100–300 MB | [UNCONFIRMED]; LSP servers (node-based) dominate |
| fcitx5, udiskie (python), power-profiles-daemon, hyprsunset, tzupdate… | 40–80 MB together | [UNCONFIRMED] — all cuttable |
| Chromium, 1 simple tab | ~270 MB | Pi 4 1 GB, Chromium 78, 2020: 267 MB + desktop 158 MB [DOCUMENTED linuxlinks]. Kiosk Chromium grows to 600–800 MB over hours on Pi 3 [DOCUMENTED]. ALARM armv7h Chromium stuck at v101 since 2022, "outdated and broken" in 2023 [DOCUMENTED forum]. |
| Firefox, 1 simple tab | ~360–390 MB | Pi 4, Firefox 68 ESR, 2020 [DOCUMENTED]; 3–4 tabs = 750–800 MB on 32-bit Pi 3B+ [DOCUMENTED] |

**Totals** [UNCONFIRMED, derived from the table]:

| Scenario | Used (approx.) | Verdict |
|---|---|---|
| Full Omarchy 4 session idle (Hyprland llvmpipe + Quickshell + NM + pipewire + portals + fcitx5 etc.) | 450–650 MB | Fits; little room |
| + foot + plain neovim | +30–50 MB | Fine |
| + one browser tab | +270–390 MB → 750–1050 MB | Only with zram; OOM-kill risk |
| Trimmed (Sway or Hyprland, no Quickshell, waybar or nothing, iwd, no portals/fcitx5) idle | 200–300 MB | Comfortable |

**32-bit vs 64-bit, the evidence:** Raspberry Pi OS idle/boot minimum 103 MB (32-bit) vs 196 MB
(64-bit); average over a 128-test run 456 MB vs 873 MB (Phoronix, 2021) [DOCUMENTED]. Roughly 0.5x,
but that compares two different distro builds, not one binary recompiled — treat as an upper bound on
the saving [UNCONFIRMED].

### Memory recommendations

- **zram:** keep zram as primary swap, size **50% of RAM (512 MB)**, not Omarchy's `zram-size = ram`
  [VERIFIED Omarchy config]. On a 1 GB box a full-size zram plus swappiness 150 risks spending the CPU
  on compression under pressure [UNCONFIRMED].
- **Algorithm:** on the stock ALARM kernel, only **lzo/lzo-rle** is compiled
  (`CONFIG_ZRAM_BACKEND_FORCE_LZO=y`, `ZRAM_DEF_COMP="lzo-rle"`) [VERIFIED]. Omarchy's
  `90-omarchy.conf` asks for zstd; what zram-generator does then is [UNCONFIRMED] — override it.
  lzo-rle is the right default on A7 anyway: no A7 zram benchmark found, but an ARMv7 1 GHz test put
  LZO and LZ4 compression at ~32 vs ~30 MB/s and a 2026 paper says LZ4's edge grows on weak ARM cores
  [DOCUMENTED]. zstd's ~3:1 ratio buys capacity at a CPU price the A7 cannot spare while llvmpipe is
  compositing [UNCONFIRMED]. If you build your own kernel, enable `ZRAM_BACKEND_LZ4` and test both.
- **Keep zswap off** (Omarchy already does via tmpfiles) [VERIFIED]; ALARM has zswap built but not
  default-on [VERIFIED].
- **Swap on eMMC:** optional 512 MB swapfile at lower priority as overflow only, on ext4 (a btrfs
  swapfile needs NOCOW and blocks snapshots of that subvolume) [DOCUMENTED btrfs rules]. Do not rely
  on it — eMMC random 4K writes are slow [UNCONFIRMED until measured].
- **OOM:** use **earlyoom** with `--prefer '(chromium|firefox|node)'` and `--avoid '(Hyprland|sway|quickshell)'`.
  systemd-oomd is possible (ALARM has `CONFIG_PSI=y`, `CONFIG_MEMCG=y` [VERIFIED]) but needs per-slice
  tuning; community reports favour earlyoom on small desktops [DOCUMENTED]. Without one, a 1 GB
  box thrashes for minutes before the kernel OOM killer acts [DOCUMENTED].
- **Keep Omarchy's sysctl set** (`vm.page-cluster=0`, watermark scale 125, dirty bytes 64M/256M)
  [VERIFIED]; `dirty_bytes` 256 MB is a quarter of RAM here — lower to 32M/64M [UNCONFIRMED].
- **Disable / do not install:** docker (+buildx/compose), cups (+filters, pk-helper), avahi/nss-mdns,
  bluez (unless BT is wanted), plymouth, sddm (use getty autologin + `uwsm start`), fcitx5 (unless
  CJK input is needed), udiskie, localsend, tzupdate, ufw (optional), power-profiles-daemon (no
  profiles on A33 cpufreq-dt) [package names VERIFIED in v4.0.4 list; cut advice UNCONFIRMED].
- **journald:** `Storage=volatile` or `SystemMaxUse=32M` + `RuntimeMaxUse=16M`.

---

## CPU / compositor performance evidence

### Raw CPU class

| Board | Core | Clock | Relative (A33 @1.008 GHz = 1.0) |
|---|---|---|---|
| Raspberry Pi 2 | 4x A7 | 0.9 GHz | ~0.9 [UNCONFIRMED, clock ratio] |
| **A33, mainline Q8 DT** | 4x A7 | **1.008 GHz max** [VERIFIED `sun8i-a33.dtsi`] | 1.0 |
| A33 with board OPPs | 4x A7 | 1.2 GHz at 1.32 V (SinA33, BPi-M2M only) [VERIFIED] | ~1.19 |
| Allwinner H3 boards | 4x A7 | 1.2 GHz | ~1.2; Phoronix called the Pi 2 "clearly the slowest" vs H3 boards [DOCUMENTED] |
| Raspberry Pi 3 | 4x A53 | 1.2 GHz | ~1.5–1.8 (sysbench: Pi 3 120 s vs Pi 2 193 s) [DOCUMENTED Geeks3D] |

So the frame is a **Pi 2-to-Pi-2-plus-20%** machine — clearly below a Pi 3 [UNCONFIRMED synthesis].

### Wayland compositors on comparable hardware

- **Hyprland on Raspberry Pi** [DOCUMENTED]:
  - Pi 5 (Gentoo forum, ~2024): ~29 fps at boot with no windows, **19–20 fps with one terminal open**;
    another user got 25–30 fps at 1080p60 after tweaks. Blamed on VC4/V3D composition handling.
  - hyprwm/Hyprland#2442: Hyprland measured ~2.3x slower than other compositors in glxgears/glmark
    on "all models of raspberry pi" (Pi Zero 2, 3B+, 4B named); also Sway 11476 vs Hyprland 6681
    (glmark2 windowed, Intel UHD 770). Closed "not planned" April 2025 [VERIFIED by reading the issue].
  - Omarchy discussion #642 (Aug 2025, Manjaro ARM base): Pi 4 4 GB "isn't horrible", Pi 5 users
    recommend 1920x1080 because higher is "still a bit laggy" [VERIFIED by reading the thread].
  These Pis all had a **GLES 3.x GPU**. The A33 does not.
- **Hyprland in software rendering:** the Hyprland wiki calls software rendering "very slow"; one
  Fedora VM user saw the Hyprland process at ~85% CPU right after login vs ~2% for GNOME
  [DOCUMENTED]. llvmpipe on an A33: glmark2 **13 fps / 76.9 ms per frame** (Mesa 11.1, LLVM 3.7,
  2016, resolution not stated) [DOCUMENTED, bug 93570]. Modern llvmpipe is faster, but four A7 cores
  are four A7 cores [UNCONFIRMED].
- **Sway / labwc / weston / wayfire:** wlroots compositors use a GLES2 renderer, so they can use lima
  [DOCUMENTED wlroots design; GPU agent to confirm]. Raspberry Pi says labwc "runs just as fast as X
  on older Raspberry Pi models" [DOCUMENTED, vendor claim]. Wayfire on Pi Zero 2 W: ~290 MB idle,
  "too slow to run a browser" [DOCUMENTED]. Sway on a CM4: window management "instantaneous"
  [DOCUMENTED]. Chromium under Weston on Pi 3+: "stable but very slow" without GPU flags [DOCUMENTED].
- **PinePhone (A64, Mali-400 MP2, same GPU family):** postmarketOS ~600 MB used, idle load ~0.2;
  Mobian/Arch ~1.4 GB [DOCUMENTED, one user]. 2024 review: Phosh "acceptable but slow" [DOCUMENTED].
  No Hyprland-on-PinePhone report found.
- **Lima speed for reference:** postmarketOS MR shows "a few hundred FPS" glmark2 on a PineTab (A64)
  at 423–500 MHz [DOCUMENTED]. A33 Mali OPPs top out at **384 MHz** [VERIFIED dtsi]. A GLES2
  compositor on lima at 1280x800 is plausible at 60 fps for simple scenes [UNCONFIRMED].

### Input latency

No measured input-latency figures found for any of these combinations (null scoped to the searches
listed). Expect llvmpipe + vsync to add at least one frame of 70–100 ms when the compositor is busy
[UNCONFIRMED from the 76.9 ms frame time above].

---

## Storage plan

- **Footprint:** Omarchy v3.0.2 used "over 15 GB" after updates (ISO 6.2 GB, +1.8 GB first-boot
  updates) [DOCUMENTED review]. v3.0.1 ISO ~7 GB with offline package mirror [DOCUMENTED]. 30–50 GB
  partitions are the community advice [DOCUMENTED]. v4.0.4 base list = 149 packages incl.
  `libreoffice-fresh`, `noto-fonts-cjk`, `dotnet-runtime`, `obsidian`, `pinta`, `tesseract`, `docker`,
  `chromium` [VERIFIED]. On the Pi, `pinta`/dotnet was reported to need "over 40GB" and hours
  [DOCUMENTED #642]. Many of these have no armv7h build at all [UNCONFIRMED; packaging agent].
- **Budget for 16 GB eMMC** (usable ~14.5 GiB after Android/boot partitions are removed) [UNCONFIRMED]:
  base system + Hyprland/Sway + foot + neovim + fonts (no CJK) ≈ 3–5 GB; one browser ≈ 0.3–0.5 GB;
  keep ≥3 GB free for pacman upgrades (cache + extraction). Run `paccache -rk1` via the pacman hook.
- **Filesystem:** **ext4** (`noatime,commit=60`) or f2fs. f2fs had ~3.6x faster random writes than
  ext4 on a 2012 Panda eMMC test (fresh FS only) [DOCUMENTED]. Drop btrfs + snapper because:
  (a) Omarchy's snapshots exist to boot old snapshots from **Limine** (`limine-snapper-sync`)
  [VERIFIED `install/config/snapper.sh`], and the A33 boots via U-Boot [kernel agent];
  (b) issue #3055 showed snapshots eating 50–70% of a disk before retention fixes [VERIFIED by reading];
  (c) btrfs CoW + checksum CPU cost on a slow core and eMMC [UNCONFIRMED]. Current Omarchy snapper
  retention is `NUMBER_LIMIT=5`, no timeline [VERIFIED] — keep that if you do keep btrfs.
- **eMMC vs SD speed:** no A33 dd/fio result found. A sunxi U-Boot commit cites ~47.5 MiB/s eMMC boot
  reads [DOCUMENTED, SoC not named]. Typical eMMC 4.5 MLC: ~80 MB/s read, ~11 MB/s write
  [DOCUMENTED, TI datasheet example]. microSD on a 4-bit 50 MHz bus caps near ~23 MB/s
  [UNCONFIRMED]. Prefer eMMC for root; **measure** with `fio --rw=randwrite --bs=4k` before choosing
  swap-on-eMMC.

---

## Thermal / power

- **Trip points (mainline `sun8i-a33.dtsi`)** [VERIFIED]: CPU passive 75 °C, CPU hot 90 °C, GPU
  passive 85 °C, GPU hot 95 °C, critical 110 °C; 250 ms passive polling.
- **The sensor is in the GPADC** (`allwinner,sun8i-a33-ths` → `sun4i-gpadc-iio`) [VERIFIED driver],
  built as a **module** in ALARM (`CONFIG_SUN4I_GPADC=m`) [VERIFIED]. If that module does not load,
  there is no thermal zone and **no throttling at all** [UNCONFIRMED consequence]. Check
  `/sys/class/thermal/thermal_zone0/temp` after boot.
- **cpufreq:** SoC OPPs 120 MHz–1008 MHz (1.04–1.2 V); 1104/1200 MHz at 1.32 V only in
  `sun8i-a33-sinlinx-sina33.dts` and `sun8i-r16-bananapi-m2m.dts` [VERIFIED]. No 1.344 GHz anywhere in
  mainline [VERIFIED by absence in these files]. ⚠ The Q8 shared DT sets `cpu-supply = <&reg_dcdc2>`
  (named "vdd-sys") while `reg_dcdc3` is named "vdd-cpu" [VERIFIED `sun8i-reference-design-tablet.dtsi`].
  Confirm the frame's real CPU rail from its Android DT/FEX before adding overvolted OPPs
  [UNCONFIRMED risk; hand to kernel agent].
- **Sustained load in a sealed frame:** no measurements found. With llvmpipe the CPU will run near
  100% during any animation, so expect to sit at the 75 °C passive trip in a closed plastic frame
  [UNCONFIRMED]. Turning animations off is also a thermal measure.
- **Power:** A33 tablets ship with 5 V/2 A adapters [DOCUMENTED]; Allwinner claims 6.5 h video on
  4000 mAh (≈2.3 W average incl. screen) [DOCUMENTED vendor claim]. Full load with backlight is
  likely 3–5 W [UNCONFIRMED]. A PC USB-2.0 port (500 mA = 2.5 W) is **not enough**; use the frame's
  own adapter or ≥2 A. Undervoltage on Allwinner tends to show as random crashes, not a warning
  [UNCONFIRMED].

---

## Prior art

- **Hyprland/Sway/Omarchy-style tiling desktop on a photo frame:** none found (null scoped to
  searches for "photo frame" + sway/weston/cage/wayland + Allwinner). Closest: a Pix-Star frame with an
  **A33** reverse-engineered to run Doom via UART + U-Boot + Buildroot + custom kernel (June 2025),
  boot-partition dump took ~48 h [DOCUMENTED, secondary only].
- **Q8 A33 tablets:** mainline has a generic `sun8i-a33-q8-tablet.dts` (Hans de Goede, 2015)
  [VERIFIED file]. Armbian/Debian Stretch booted on one in 2017 after disabling `pwm_bl` during boot
  [DOCUMENTED]. linux-sunxi notes some Q8 variants' DSI panels were unsupported [DOCUMENTED]. 2018
  comment: touchscreen usability outside GNOME "basically zero" [DOCUMENTED opinion].
- **postmarketOS:** device `inet-a33` (iNet D70, 1024x600, DT `sun8i-a33-q8-tablet`, GPU acceleration
  on) uses package `u-boot-q8-a33-tablet` [DOCUMENTED]. Which UI it was tested with, and how usable,
  was not found (wiki not reachable from here).
- **Omarchy on ARM:** Pi 5 / Pi 4 guide (Aug 2025) on Manjaro ARM: chromium unstable → Brave,
  hyprlock crashed → `hyprlock-git`, x86-only apps fail, pinta/dotnet impractical; Pi 4 4 GB
  "isn't horrible" [VERIFIED by reading #642]. Omarchy 4 now treats Raspberry Pis as the generic
  `aarch64` platform and uses Omarchy's own ALARM mirror [VERIFIED `AGENTS.md`,
  `default/pacman/aarch64*`]. **No armv7 Omarchy port found.**
- **Hyprland on 32-bit ARM exists as a package:** Alpine ships Hyprland 0.49.0 for armv7
  [DOCUMENTED pkgs.alpinelinux.org] — it compiles; it still needs GLES 3.

---

## What to cut (to stay responsive)

Ordered by payoff [all UNCONFIRMED recommendations unless tagged]:

1. **The GLES-3 dependency.** Either (a) keep Hyprland on llvmpipe with **animations off, blur/shadow
   off (already off in Omarchy 4 [VERIFIED looknfeel.lua]), no rounded corners, no
   `hyprsunset`, no video wallpaper (`owe` in master)**, or (b) run **Sway or labwc on lima** with
   Omarchy's themes/keybinds ported. (b) is the only path to a fluid 60 fps desktop on this GPU.
2. **omarchy-shell (Quickshell).** Largest RAM line and a second GL client. Replace with waybar (or
   no bar) + mako + fuzzel/tofi + swaylock/swayidle. If you keep it, run one instance, test whether Qt6
   Quick works on lima GLES2 at all (search found no confirmation either way).
3. **Browsers** as a daily tool: plan for at most one tab; prefer Firefox ESR only if Chromium armv7h is
   still stuck/broken (it was at v101 in 2022 and "broken" in 2023 [DOCUMENTED]). No web-app launchers.
4. **Packages:** libreoffice-fresh, obsidian, dotnet-runtime/pinta, docker*, tesseract, noto-fonts-cjk,
   fcitx5*, cups*, gpu-screen-recorder, moonlight-qt, localsend, superwhisper/voxtype, mise/ruby
   toolchains, base-devel (keep only for AUR builds on another machine).
5. **Services:** sddm, plymouth, avahi, bluetooth, cups, docker, udiskie, tzupdate,
   power-profiles-daemon; use iwd instead of NetworkManager if Wi-Fi-only.
6. **Storage:** btrfs + snapper + limine-snapper-sync → ext4/f2fs.
7. **Terminal/editor:** keep **foot** (already default); keep neovim but avoid node-based LSPs.
8. **zram:** 512 MB lzo-rle, not "ram" + zstd; add earlyoom.

**Realistic expectation:** a keyboard-driven tiling desktop with terminals, neovim and a clock/photo
widget is achievable and can feel snappy **only on a GLES2 compositor (Sway/labwc) on lima**. Full
Omarchy 4 as shipped (Hyprland + Quickshell + browser-centric workflow) will run, if it can be built
for armv7h at all, but on llvmpipe it will feel like a slideshow during animations and will page
heavily with a browser open [UNCONFIRMED synthesis].

---

## Sources

Primary (read / inspected):
- Omarchy repo, `basecamp/omarchy` master @defbf90 (2026-10-12) and tag v4.0.4 (2026-09-14):
  `install/omarchy-base.packages`, `install/omarchy-aarch64*.packages`, `AGENTS.md`,
  `docs/omarchy-shell.md`, `default/hypr/looknfeel.lua`, `default/hypr/autostart.lua`,
  `default/systemd/zram-generator.conf.d/90-omarchy.conf`, `etc/sysctl.d/99-omarchy-sysctl.conf`,
  `etc/tmpfiles.d/omarchy-zswap.conf`, `default/snapper/root`, `install/config/snapper.sh`,
  `default/xdg-terminal-exec/hyprland-xdg-terminals.list`, `default/pacman/`.
- Hyprland repo @663b29b (2026-10-09), `src/render/OpenGL.cpp` lines 203–227.
- Linux master DTs: `arch/arm/boot/dts/allwinner/sun8i-a33.dtsi`, `sun8i-a23-a33.dtsi`,
  `sun8i-a33-q8-tablet.dts`, `sun8i-q8-common.dtsi`, `sun8i-reference-design-tablet.dtsi`,
  `sun8i-a33-sinlinx-sina33.dts`, `sun8i-r16-bananapi-m2m.dts`; `drivers/iio/adc/sun4i-gpadc-iio.c`;
  `drivers/thermal/sun8i_thermal.c`; `arch/arm/configs/sunxi_defconfig`, `multi_v7_defconfig`.
- Arch Linux ARM `PKGBUILDs/core/linux-armv7/config` (Linux 7.2.6).
- https://github.com/hyprwm/Hyprland/issues/2442
- https://github.com/omacom/omarchy/discussions/642
- https://github.com/omacom/omarchy/issues/3055

Secondary (search summaries; pages mostly not fetchable from this sandbox):
- Phoronix 32-bit vs 64-bit Pi OS: https://www.phoronix.com/review/raspberrypi-os-64bit/2
- Gentoo forum, Hyprland Pi 5 fps: https://forums.gentoo.org/viewtopic-t-1167115.html
- linuxlinks Pi 4 memory (Chromium/Firefox): https://www.linuxlinks.com/raspberry-pi-4-chronicling-the-desktop-experience-memory-usage/2/ , https://www.linuxlinks.com/raspberry-pi-4-chronicling-desktop-experience-firefox-revisited/2/
- Pi 3B+ Firefox tabs: https://ubuntu-mate.community/t/ubuntu-mate-18-04-raspberry-pi-3b-very-slow-freezing/20131
- Chromium kiosk growth: https://github.com/vbguyny/ws4kp/issues/50
- ALARM armv7h Chromium: https://archlinuxarm.org/forum/viewtopic.php?p=69910 , https://archlinuxarm.org/forum/viewtopic.php?p=70722
- llvmpipe on A33 (glmark2 13): https://bugs.freedesktop.org/show_bug.cgi?id=93570
- Mesa lima docs (no GLES3): https://docs.mesa3d.org/drivers/lima.html
- Hyprland wiki / VM CPU: https://github.com/JaKooLit/Hyprland-Dots/discussions/86
- r/hyprland RAM thread: https://redlib.ssps.io/r/hyprland/comments/1k90v1c/is_my_ram_usage_normal
- Sway RAM: https://news.ycombinator.com/item?id=33952570 , https://forums.freebsd.org/threads/can-you-use-wayland-with-a-simple-window-manager.81606/latest , https://github.com/swaywm/sway/issues/1131
- Terminals: https://terminaltrove.com/compare/terminals/foot-terminal-vs-ghostty/ , https://git.pvv.ntnu.no/vegardbm/dwl/commit/7710cf050d1a
- Quickshell jemalloc: https://git.outfoxxed.me/poz/quickshell/commit/a8506edbb931867d881d5b854f7d15cb74e9086f ; Noctalia: https://feddit.it/post/32563506 , https://www.linuxcompatible.org/story/noctalia-501-stable-release-groundup-rewrite-and-6x-memory-reduction-for-linux/
- zram algorithms: https://repository.kpi.kharkov.ua/items/3114a498-b88b-4ebe-a122-6aef3eebf2aa , https://lkml.iu.edu/hypermail/linux/kernel/1302.3/01056.html
- earlyoom vs oomd: https://discourse.nixos.org/t/avoid-linux-locking-up-in-low-memory-situations-using-earlyoom/22072
- Pi 2 vs Pi 3 sysbench: https://glslhacker.geeks3d.com/?p=9253 ; Phoronix Pi 3 vs ARM boards: https://www.phoronix.com/review/raspberry-pi-3
- Pi Zero 2 / Wayfire: https://dev.to/aaron_rose_0787cc8b4775a0/breaking-the-rules-getting-raspberry-pi-connect-working-on-unsupported-hardware-4g6d ; https://ahsanu.is-a.dev/archlinux-wayland-installation-on-raspberry-pi-zero-2.html
- Sway on CM4: https://forum.clockworkpi.com/t/configuring-sway/12470 ; labwc: https://raspberrypi.com/news/a-new-release-of-raspberry-pi-os
- Chromium under Weston: https://archlinuxarm.org/forum/viewtopic.php?p=60205
- PinePhone pmOS RAM: https://forum.pine64.org/showthread.php?pid=118732 ; pmOS review: https://discuss.techlore.tech/t/review-postmarketos-on-the-pinephone/10292
- pmOS inet-a33: https://ayakael.net/forge/pmaports/commit/ad438c06cfd09f5bcf80bada587c6a067f501fd6 , https://pkgs.postmarketos.org/package/main/postmarketos/armv7/u-boot-q8-a33-tablet
- pmOS PineTab lima glmark2: https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/1267
- Q8 Armbian 2017: https://forum.armbian.com/topic/5846-solved-a33-tablet-unrecognizedunsupported-machine-id-r1-0x00001029/ ; CNX Tablex: https://www.cnx-software.com/2018/08/24/tablex-arm-linux-tablet-runs-armbian-ubuntu/
- A33 VE CMA 96 MB: https://lore.kernel.org/patchwork/patch/973084/
- A33 thermal series: https://lkml.iu.edu/hypermail/linux/kernel/1704.0/02495.html
- sunxi eMMC 47.5 MiB/s: https://git.iohub.dev/dany/u-boot-megous/src/commit/cae566a075eaf59b9943ae30346a9956e3973923/drivers/mmc/sunxi_mmc.c ; TI eMMC example: https://e2e.ti.com/support/processors-group/processors/f/processors-forum/409887/emmc-read-and-write-speed-measurement
- f2fs eMMC 2012: https://lwn.net/Articles/518994/
- Omarchy footprint: https://xn--gckvb8fzb.com/a-word-on-omarchy/ , https://computingforgeeks.com/install-omarchy-arch-hyprland-linux/ , https://github.com/omacom-io/omarchy-iso
- Pix-Star A33 frame: https://www.itechguides.com/?p=710978
- A33 power: https://www.cnx-software.com/2014/07/29/allwinner-a33-quad-core-tablets-are-now-available-for-60-and-up/ , https://tass.com/press-releases/742690
- Alpine Hyprland armv7: https://pkgs.alpinelinux.org/package/v3.22/community/armv7/hyprland

Not found (null results, scoped to the searches above): measured RSS/PSS for Hyprland, waybar, mako,
walker, hyprlock, hypridle, hyprpaper on any ARM; any A33 eMMC dd/fio figure; any A33 sustained-load
temperature; any input-latency measurement; Hyprland on PinePhone; Qt6 Quick on lima.
