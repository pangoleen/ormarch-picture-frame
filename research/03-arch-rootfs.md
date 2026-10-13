# 03 — Arch Linux ARM (armv7h) root filesystem for the A33 photo frame

Research date: 2026-10-12. Agent 3 of 6. Topic: the rootfs, its health, its packages, how to build and install it from a Mac, and where to compile.

Tags: **[VERIFIED]** = read in a primary source (file, PKGBUILD, package database) and cited. **[DOCUMENTED]** = secondary source (search-index snippet of a package page, a forum post, a wiki). **[UNCONFIRMED]** = inference. A null result applies only to what was searched.

Constraint on method: archlinuxarm.org, every ALARM mirror tried (10), archlinux.org, aur.archlinux.org, pkgs.omarchy.org, alpinelinux.org and repology were **blocked** from this sandbox. Primary evidence comes from: the `archlinuxarm/PKGBUILDs` git repo (cloned; HEAD 2026-10-12), the AUR's GitHub mirror (`github.com/archlinux/aur`, one branch per package), and the **pacman local database inside a daily-built armv7h Docker image** (`menci/archlinuxarm:base`, `linux/arm/v7`, built 2026-10-12 06:57 UTC by pacstrapping from the official ALARM mirrors). Package availability for leaf apps is from search-index snippets of archlinuxarm.org package pages, which are **[DOCUMENTED]** at best, and snapshots of different ages disagree.

---

## Summary (5 bullets)

1. **armv7h is alive, not dying.** ALARM still builds armv7h daily: packages in the armv7h base image were built as recently as **2026-10-12** (sqlite), systemd **262** was built 2026-09-24, and `linux-armv7` gets an update about every 1–2 weeks (7.2.10 on 2026-10-11). No announcement drops armv7. The risks are a **one-and-a-half-person project** (Kevin Mihelich + graysky = 92% of 2026 commits), a **shrinking mirror list** (21 → 13 entries 2021→2026, HTTP only), and some heavy packages that **do not build on v7** (Chromium). [VERIFIED]
2. **The Hyprland stack exists for armv7h.** `hyprland 0.56.2-4` (built 2026-10-03), `aquamarine`, `hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `hyprwire`, `hyprtoolkit`, `hyprland-guiutils`, `hyprland-protocols`, `xdg-desktop-portal-hyprland`, `waybar`, `firefox` and `go` all have armv7h package pages. `uwsm` is `arch=any`. Mesa is built with `gallium-drivers=all`, which in Arch's own build includes `lima_dri.so`. Not found in the index (may exist; unconfirmed): `hyprlock`, `hypridle`, `hyprpaper`, `hyprpicker`, `hyprsunset`, `mako`, `swaybg`, `quickshell`. [DOCUMENTED/VERIFIED, see table]
3. **Two blockers that are not the rootfs's fault, flagged for other agents:** (a) **Hyprland needs GLES 3.0 minimum** (`RASSERT(false, "EGL: failed to create a context with either GLES3.2 or 3.0")`), but Mali-400/lima is a GLES 2.0 GPU — so Hyprland will run on **llvmpipe (CPU)**, not lima. (b) **Chromium is not built for armv7h at all** (`buildarch=8` = aarch64 only); the armv7h page shows Chromium 101 from **April 2022**. Omarchy's default browser and web-app launcher assume Chromium → use Firefox (157 builds on v7). [VERIFIED]
4. **Rootfs build on a Mac:** use Docker Desktop with `--platform linux/arm/v7` (QEMU user-mode emulation; Apple M-series cores have **no AArch32**). Either unpack `ArchLinuxARM-armv7-latest.tar.gz` (still published; mirror timestamp Feb 2026) or pacstrap a custom package set in the container, then make an ext4 image with `mkfs.ext4 -d` (no loop mount needed) and `dd` it to the SD card or to the eMMC exposed by U-Boot `ums`. Boot via U-Boot `extlinux.conf` or ALARM's `boot.scr` template. [VERIFIED for templates/tools; UNCONFIRMED end-to-end]
5. **Build farm:** do not compile on the frame. Build armv7h packages in an emulated ALARM `base-devel` container on the Mac (simple, reliable), and add a native-speed tier if needed: either a Raspberry Pi 4/5 (Cortex-A72/A76 run AArch32 EL0) with an armv7h nspawn container, or distcc to ALARM's official `x-tools7h` cross-compiler (GCC 16.1.1, matches the armv7h `gcc-libs 16.1.1`). `yay` and `yay-bin` both list `armv7h`. Use zram, but note `linux-armv7` has **only the LZO zram backend**, while Omarchy configures **zstd**. [VERIFIED]

---

## 1. armv7h health verdict

**Verdict: maintained and current as of 2026-10-12. Use it. Plan for the specific gaps, not for an end-of-life.**

Evidence:

| Signal | Value | Tag / source |
|---|---|---|
| Last commit to `archlinuxarm/PKGBUILDs` | 2026-10-12 04:26 (`linux-aarch64-rc`) | [VERIFIED] git clone |
| Commits in 2026 | 2,327 (Kevin Mihelich 1,690, graysky 448, David Beauchamp 152, everyone else < 10) | [VERIFIED] `git log --since=2026-01-01` |
| `linux-armv7` cadence | 40+ releases since 2026-03; 7.2.10-1 on 2026-10-11; `buildarch=4` (armv7h-only package) | [VERIFIED] `core/linux-armv7/PKGBUILD`, git log |
| armv7h base system freshness | 124 of 137 base packages are `armv7h` builds; build months: 25 in 2026-09, 11 in 2026-10; newest `sqlite 3.54.0-1` built 2026-10-12; `systemd 262-1` 2026-09-24; `bash 5.3.20-1` 2026-09-20; `glibc 2.43` 2026-05-03; `gcc-libs 16.1.1` 2026-05-03; `pacman 7.1.0` 2026-05-07 | [VERIFIED] `/var/lib/pacman/local/*/desc` from `menci/archlinuxarm:base` arm/v7 layer (pacstrapped from official ALARM mirrors on 2026-10-12) |
| Deprecation announcement | Only one: Dec 2021, **ARMv5/v6 EOL** (Feb 2022) and ARMv7 moved to **NEON** by default (drops Tegra 2, Marvell PJ4). A33 (Cortex-A7 with NEON/VFPv4) is unaffected. Nothing found for armv7 itself. | [DOCUMENTED] forum t=15721; null result scoped to WebSearch |
| Generic tarball | `ArchLinuxARM-armv7-latest.tar.gz` listed on the downloads page; a mirror index shows it dated **16-Feb-2026** | [DOCUMENTED] archlinuxarm.org/about/downloads, repository.pietma.com mirror index |
| Mirror health | Official mirrorlist shrank: 21 `Server` lines (2021-11) → 17 (2023-02) → **13** (2026-04-11). All `http://`, not https (packages are signed, so integrity holds). | [VERIFIED] `core/pacman-mirrorlist/mirrorlist` history |
| Keyring | `archlinuxarm-keyring 20240419-2` (repackaged 2026-04-19) | [VERIFIED] |
| Packages restricted away from v7 | `chromium`: `buildarch=8` (aarch64 only) | [VERIFIED] `extra/chromium/PKGBUILD` |
| RAM-limited v7 builds | `firefox`, `rust`, `qt6-webengine`: `highmem=1`, "disable rust lto for v7", "build v6/v7 with -j2 – RAM constraints", "restrict job count on v7" | [VERIFIED] PKGBUILD headers |

Wider 32-bit-ARM context (not ALARM-specific): Home Assistant proposed dropping armv7 [DOCUMENTED]; LinuxServer.io reduced armhf [DOCUMENTED]; postmarketOS removed **armhf = ARMv6** in June 2026 — its **armv7** is unaffected [DOCUMENTED, postmarketos.org/edge/2026/06/22/armhf-removed]; the kernel is removing ~22 legacy ARM **board files** in 7.5 (early 2027); sunxi is **not** in the published removal list [DOCUMENTED, Phoronix/LKML summaries]. The long-term risk is industry drift, not an ALARM decision.

### Alternatives if ALARM ever dies (none keeps Omarchy's assumptions)

Omarchy assumes pacman + Arch package names + AUR/yay + systemd. Only ALARM provides all four on armv7.

| Distro | armv7 Hyprland? | Package manager / init | Fit | Tag |
|---|---|---|---|---|
| **Arch Linux ARM armv7h** | 0.56.2 (Oct 2026) | pacman / systemd | Native fit | [DOCUMENTED] |
| Debian armhf (forky/sid) | 0.53.3 (forky), 0.54.x (sid); **not in trixie** (removed by maintainers) | apt / systemd | Rewrite all install scripts | [DOCUMENTED] packages.debian.org snippets |
| Alpine / postmarketOS armv7 | 0.49 (v3.22), 0.51 dev pkgs (v3.23); edge index did not show `hyprland` | apk / OpenRC (pmOS has a systemd flavour) | musl; rewrite everything | [DOCUMENTED] |
| Fedora armhfp | Dropped (F37, 2022) | — | No | [UNCONFIRMED] not re-verified this session |
| Void armv7l | Hyprland not in official repos (policy) | xbps / runit | No | [UNCONFIRMED] |
| Manjaro ARM | aarch64 only | — | No | [UNCONFIRMED] |

---

## 2. Package availability table (armv7h)

How ALARM works matters for reading this table: **unmodified Arch packages are not in the PKGBUILDs repo**; ALARM's builder takes them straight from Arch and builds them for every architecture unless a `buildarch` override restricts them (README: "Without being specified, the package will build for all architectures") [VERIFIED README]. So "absent from the search index" is weak evidence of absence; "absent from the override list" is not evidence either way.

| Package | armv7h status | Version / date | Tag & source |
|---|---|---|---|
| `hyprland` | Present, [extra] | 0.56.2-4, built 2026-10-03 (an older index snapshot shows 0.49.0-3 / 2025-07-08) | [DOCUMENTED] archlinuxarm.org/packages/armv7h/hyprland |
| `aquamarine` | Present | 0.10.0-4, 2026-03-31 | [DOCUMENTED] |
| `hyprutils` | Present | 0.12.0-1 / 0.13.1-1 (2026-05-09), snapshots differ | [DOCUMENTED] |
| `hyprlang` | Present | 0.6.8-3 (2026-03) | [DOCUMENTED] |
| `hyprcursor`, `hyprgraphics`, `hyprwayland-scanner`, `hyprwire`, `hyprtoolkit`, `hyprland-protocols`, `hyprland-guiutils` | Present | 0.1.13, 0.5.1, 0.4.5, 0.3.0, 0.5.4, 0.6.4, 0.2.1 | [DOCUMENTED] |
| `xdg-desktop-portal-hyprland` | Present | 1.3.12-2 (1.3.11-4 built 2026-03-31) | [DOCUMENTED] |
| `uwsm` | Present as `arch=any` | 0.21.6-1 | [DOCUMENTED] archlinuxarm.org/packages/any/uwsm |
| `waybar` | Present | page shows build 2024-04-23 (snapshot may be stale) | [DOCUMENTED] |
| `hyprlock`, `hypridle` | **Not found** in index for armv7h (aarch64 hyprlock 0.9.1 exists) | — | null result, WebSearch only. Pure C++ on hyprlang/hyprutils/hyprgraphics → expected to build. [UNCONFIRMED] |
| `hyprpaper`, `hyprpicker`, `hyprsunset`, `swaybg`, `mako` | **Not found** in index for armv7h (aarch64 pages exist for hyprpicker/mako) | — | null result, WebSearch only [UNCONFIRMED] |
| `quickshell` (Omarchy's current shell, see note) | **Not found** for armv7h (aarch64 0.3.0-2 exists) | — | null result [UNCONFIRMED]. Needs Qt6 Declarative; `qt6-base` has an ALARM override so Qt6 does build on v7 [VERIFIED] |
| `walker` / `elephant` | Not in Arch [extra]; Omarchy's own repo | — | see Omarchy agent |
| `mesa` (incl. **lima**) | Present; ALARM PKGBUILD 26.2.4-1 (2026-10-02) uses `-D gallium-drivers=all`; ALARM only changes `intel-rt=disabled`, `teflon=true`. Arch's x86_64 mesa built the same way ships `usr/lib/dri/lima_dri.so`. armv7h mesa 26.x split packages exist (e.g. `vulkan-virtio 26.1.3-2` built 2026-06-19) | [VERIFIED] PKGBUILD; [DOCUMENTED] Arch file list; **lima inside armv7h mesa is [UNCONFIRMED] until `pacman -Ql mesa \| grep lima` on the device** |
| `firefox` | Present, current | 150.0.3-1 page (2026-05-14); PKGBUILD now 157.0.1-1 with v7-specific tweaks | [DOCUMENTED] + [VERIFIED] override |
| `chromium` | **Not built for armv7h** | page frozen at 101.0.4951.41 (2022-04-26); PKGBUILD has `buildarch=8` | [VERIFIED] |
| `qt6-webengine` | Builds on v7 (job count restricted) | 6.11.2-2 (2026-10-07) | [VERIFIED] override |
| `go` | Present | 2:1.26.2-1 (2026-04-08) | [DOCUMENTED] |
| `yay` / `yay-bin` (AUR) | Both list `armv7h` | 13.0.1 (2026-06-19); `yay-bin` downloads `yay_13.0.1_armv7h.tar.gz` from Jguer/yay releases; `yay` needs `go>=1.24` | [VERIFIED] AUR mirror PKGBUILDs |
| `systemd` | Present | 262-1 (2026-09-24) | [VERIFIED] local DB |
| `zram-generator` | Not checked | — | [UNCONFIRMED]; Rust, small; expected |
| `linux-armv7` | Present | 7.2.10-1; has `MACH_SUN8I=y`, `DRM_SUN4I=m`, `DRM_LIMA=m`, `MMC_SUNXI=y`, `TOUCHSCREEN_GOODIX/SILEAD=m`, `MFD_AXP20X=y`, `HIGHMEM=y`, `VMSPLIT_3G=y`; **`RTW88_8723CS` not set** | [VERIFIED] `core/linux-armv7/config` |
| `uboot-sunxi` | Present but **no A33 board** in its list (A10/A13/A20 boards only, U-Boot 2024.07) | — | [VERIFIED] PKGBUILD |

Note on Omarchy's package set (as of the clone at 2026-10-12, `basecamp_omarchy`): `install/omarchy-base.packages` no longer lists waybar, mako, walker, swaybg, hyprpaper or hypridle; it uses **`quickshell`** (34 references) plus many packages from its own `[omarchy]` repo (`pkgs.omarchy.org/stable/$arch`, x86_64 and aarch64 only; `omarchy-x86_64-only.packages` already excludes `gliff` and `superwhisper-bin` from aarch64). Every `[omarchy]` and `-bin` package would need an armv7h rebuild or a drop. [VERIFIED] file contents. Detail belongs to the Omarchy-packaging agent.

---

## 3. Rootfs build + install steps (Mac-friendly)

### 3.0 Facts the steps rely on

- Apple M-series cores implement **AArch64 only — no AArch32 at any exception level**, so armv7 code on a Mac always runs under **QEMU user-mode** emulation (Docker Desktop's binfmt) or a full QEMU system VM. [DOCUMENTED] Asahi/Fedora-Asahi issue (box86 cannot run on M1 because M1 cannot run armv7), Parallels forum. Docker Desktop's *VM-manager* QEMU was deprecated in 4.44, which is a different thing from binfmt `qemu-user`. [DOCUMENTED] docs.docker.com/desktop/vmm. **Check once:** `docker run --rm --platform linux/arm/v7 menci/archlinuxarm:base uname -m` should print `armv7l`. [UNCONFIRMED until run]
- macOS cannot create or write ext4 natively; everything filesystem-related happens inside a Linux container. `mkfs.ext4 -d <dir>` builds a populated image **without a loop mount**, so it works in an unprivileged container. [UNCONFIRMED for xattrs: verify `getcap /usr/bin/ping` etc. after first boot; fallback is a privileged container with `losetup` + `bsdtar --xattrs`]
- Ready-made armv7h container: `menci/archlinuxarm` (`base`, `base-devel`; platforms amd64/arm64/**arm/v7**/riscv64), rebuilt daily on GitHub Actions by pacstrapping from the official ALARM mirrorlist with the ALARM keyring fetched from `archlinuxarm/PKGBUILDs`. [VERIFIED] `Menci/docker-archlinuxarm/Dockerfile`, Docker Hub tags (last 2026-10-12). Third-party: use it as a **build tool**, or reproduce it from the Dockerfile (Debian sid + `arch-install-scripts` + `pacman-package-manager`), which needs no trust in the image.
- On the A33 unit, mainline **U-Boot v2025.10 over FEL** already works from macOS, and its `ums` command exposes the **eMMC as a USB disk** (30,535,680 sectors ≈ 14.6 GiB) [VERIFIED] `photo-frame-dashboard/docs/allwinner-a33-mainline-uboot.md`. That gives a way to write the rootfs to eMMC from the Mac with `dd`, after the backup the access agent covers.

### 3.1 Option A — stock ALARM tarball (simplest, closest to the ALARM docs)

On the Mac (download is outside this sandbox; verify the `.sig`/md5):

```sh
curl -LO http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz      # + .md5 / .sig
docker run --rm -it --privileged -v "$PWD":/work debian:sid bash
# inside the container:
apt-get update && apt-get install -y libarchive-tools e2fsprogs dosfstools
mkdir /rootfs && bsdtar -xpf /work/ArchLinuxARM-armv7-latest.tar.gz -C /rootfs   # -p keeps perms/owners
truncate -s 3G /work/root.img
mkfs.ext4 -L ALARM_ROOT -d /rootfs /work/root.img
```

Then build the full card image with the U-Boot SPL at 8 KiB (see 3.3).

### 3.2 Option B — pacstrap a custom rootfs (recommended: bake the package set in)

Inside an emulated armv7h ALARM container (`--platform linux/arm/v7`), install exactly what the frame needs into `/rootfs`, so first boot does not download 1–2 GB over a weak Wi-Fi:

```sh
docker run --rm -it --platform linux/arm/v7 -v "$PWD":/work menci/archlinuxarm:base-devel bash
pacman-key --init && pacman-key --populate archlinuxarm
pacman -Syu --noconfirm arch-install-scripts e2fsprogs
mkdir /rootfs
# pacstrap needs mount; in an unprivileged container use pacman --root (or Menci's pacstrap-docker):
pacman -r /rootfs --cachedir /var/cache/pacman/pkg -Sy --noconfirm \
    base archlinuxarm-keyring linux-firmware-realtek? \
    networkmanager iwd openssh sudo zram-generator \
    mesa hyprland xdg-desktop-portal-hyprland uwsm firefox ...
cp /etc/pacman.d/mirrorlist /rootfs/etc/pacman.d/
# hostname, locale, fstab, users, enable services:
arch-chroot /rootfs ...   # or systemd-firstboot --root=/rootfs; systemctl --root=/rootfs enable NetworkManager sshd
truncate -s 6G /work/root.img && mkfs.ext4 -L ALARM_ROOT -d /rootfs /work/root.img
```

(`linux-firmware-realtek?` is a placeholder: the RTL8723CS firmware file name and package depend on the driver the kernel agent picks.) Package-install scriptlets and hooks run armv7 binaries in the chroot, which is why this container must be `linux/arm/v7`, not arm64. [UNCONFIRMED end-to-end; method matches Menci's Dockerfile, which does `pacstrap` + `chroot locale-gen` the same way]

### 3.3 Card / eMMC layout and boot files

Allwinner BootROM loads the SPL from **8 KiB** on the SD card or eMMC. Leave the first 1–4 MiB unpartitioned (the A33 guides in `photo-frame-dashboard` already insist on partitions at ≥ 4 MiB).

```
0       8 KiB          ~1 MiB         4 MiB                      end
| MBR | u-boot-sunxi-with-spl.bin |  (gap)  | p1 ext4 "ALARM_ROOT" (/boot inside) |
```

```sh
dd if=u-boot-sunxi-with-spl.bin of=card.img bs=1024 seek=8 conv=notrunc   # from the U-Boot agent
# p1 starts at sector 8192 (4 MiB); dd root.img into it
```

ALARM's own convention puts `/boot/zImage`, `/boot/dtbs/<fdtfile>` and optional `/boot/initramfs-linux.img` **on the root ext4 partition**, and boots them with this script (from `alarm/uboot-sunxi/boot.txt`, compiled with `mkimage -A arm -O linux -T script -C none -d boot.txt boot.scr`) [VERIFIED]:

```
if test -n ${distro_bootpart}; then setenv bootpart ${distro_bootpart}; else setenv bootpart 1; fi
part uuid ${devtype} ${devnum}:${bootpart} uuid
setenv bootargs console=${console} root=PARTUUID=${uuid} rw rootwait
load ${devtype} ${devnum}:${bootpart} ${kernel_addr_r} /boot/zImage
load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} /boot/dtbs/${fdtfile}
bootz ${kernel_addr_r} - ${fdt_addr_r}     # or with initramfs
```

Equivalent `extlinux.conf` (mainline U-Boot distro boot / bootstd reads `/boot/extlinux/extlinux.conf`; simpler to edit, no `mkimage`):

```
label arch
  kernel /boot/zImage
  fdt /boot/dtbs/sun8i-a33-<board>.dtb
  append root=LABEL=ALARM_ROOT rw rootwait console=ttyS0,115200 consoleblank=0
```

Write to SD from macOS: `diskutil unmountDisk /dev/diskN && sudo dd if=card.img of=/dev/rdiskN bs=4m` (raw device is much faster). Write to eMMC: same, against the `ums` disk, only after the full backup and only with the owner's explicit approval (it destroys Android).

### 3.4 Using our own kernel instead of `linux-armv7`

- `linux-armv7` **already enables the A33 basics** (sun8i, sun4i DRM, lima, sunxi MMC, AXP PMIC, Goodix/Silead touch) [VERIFIED config]. Cheapest first boot: keep `linux-armv7`, supply only the right **DTB**. Missing for this frame: `RTW88_8723CS` (in-tree rtw88 SDIO driver), and zram backends other than LZO.
- If the kernel agent ships a custom kernel, package it as a pacman package (`linux-a33`, `provides=(linux)`, `conflicts=(linux-armv7)`) built in the same armv7h container, so `pacman -Syu` cannot overwrite `/boot/zImage`. Otherwise add `IgnorePkg = linux-armv7 linux-armv7-headers` to `/etc/pacman.conf` after removing it. Built-in (`=y`) MMC + ext4 means no initramfs is needed (`MMC_SUNXI=y`, `EXT4_FS=y` already are in `linux-armv7`). [VERIFIED config; packaging advice UNCONFIRMED]

### 3.5 First boot

```sh
# login alarm/alarm, su root/root (ALARM defaults) — change both at once
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu
timedatectl set-ntp true        # A33 has no battery RTC on most frames; TLS + pacman need the right time
```

Defaults and the keyring commands: [DOCUMENTED] ALARM install docs and forum threads (the keyring fix is the standard answer to "unknown trust" errors). `fake-hwclock` is in ALARM's `alarm/` repo if there is no RTC [VERIFIED directory exists].

### 3.6 AUR on armv7h

- `yay`: `arch=(... 'armv7h' ...)`, builds with Go ≥ 1.24 (armv7h has Go 1.26.2). `yay-bin`: `arch=('x86_64' 'aarch64' 'armv7h')`, prebuilt armv7h tarball — **use `yay-bin` on the frame**, no compile. [VERIFIED]
- Most AUR PKGBUILDs say `arch=('x86_64')` only. On ALARM they need `makepkg --ignorearch` (yay: `--mflags --ignorearch`) or an edited `arch=`; `-bin` packages that ship x86_64/aarch64 binaries cannot work on armv7. [UNCONFIRMED in practice; standard makepkg behaviour]

---

## 4. Build-farm recommendation

**Never build on the frame except for trivial packages.** 1 GB RAM with ~760 MB lowmem (`VMSPLIT_3G` + `HIGHMEM`) and four 1.2 GHz Cortex-A7s cannot build C++26 Hyprland-class code in reasonable time; ALARM itself needs `highmem=1` builders (> 2 GB) for firefox/rust/qt6-webengine and throttles v7 jobs for RAM. [VERIFIED README + PKGBUILDs; time estimate UNCONFIRMED]

Recommended tiers:

1. **Default — emulated armv7h ALARM container on the Mac.** `docker run --platform linux/arm/v7 menci/archlinuxarm:base-devel` (or the same Dockerfile built locally), `makepkg -s` as an unprivileged user, collect `*.pkg.tar.*` into a local repo with `repo-add`, and serve it on the LAN (`python3 -m http.server`) as a `[frame]` repo in the frame's `pacman.conf`. It is slow per core (QEMU user-mode), but the Mac has many fast cores and lots of RAM, so it should still beat the frame by a wide margin. Same container runs in **GitHub Actions** (x86_64 runner + QEMU) for reproducible builds. Note: a 32-bit process under qemu-user still has a 4 GB address space, so Chromium-class links fail here too. [UNCONFIRMED speed]
2. **Accelerator — distcc to ALARM's official cross toolchain.** AUR `distccd-alarm` packages ALARM's `x-tools7h` (GCC **16.1.1**, 2026-05-17; armv7h port 3635), which matches armv7h `gcc-libs 16.1.1`. It is built for **x86_64 hosts only**, so on Apple silicon run it in an amd64 container under Rosetta/QEMU. The emulated armv7h container is the distcc client (configure, link, packaging); compile jobs go to the cross compiler. Worth it only if tier 1 is too slow for a specific heavy package. [VERIFIED toolchain facts; Rosetta setup UNCONFIRMED]
3. **Native-speed alternative — real ARMv8 hardware with AArch32 EL0.** A Raspberry Pi 4 (Cortex-A72) or Pi 5 (Cortex-A76), 8 GB, aarch64 kernel, armv7h userland in `systemd-nspawn`. This is the approach an ALARM forum user reported for building armv7h Chromium. Cloud: Ampere Altra (Neoverse N1) is believed to support AArch32 EL0; GitHub's arm64 runners (Cobalt 100 / Neoverse N2) are believed **not** to, so they would need QEMU too. Check with `lscpu`/`setarch linux32 true` before paying. [DOCUMENTED forum; CPU claims UNCONFIRMED]

Do **not** try: a native aarch64→armv7 cross-compile of whole Arch packages with Debian's `gcc-arm-linux-gnueabihf` — GCC version and glibc must match ALARM's exactly, and makepkg scriptlets still need armv7 execution.

---

## 5. systemd on 1 GB armv7

systemd is fine here: ALARM ships systemd 262 for armv7h [VERIFIED], and its idle footprint (PID 1 + journald + logind + udevd + networkd/resolved) is in the tens of MB [UNCONFIRMED figure]. The pressure comes from Hyprland on llvmpipe, Firefox and Qt/QML shells, not from systemd. The Android build on this frame already ran with **256 MiB zram** and showed ~700 MB free/reclaimable with a light kiosk [VERIFIED `allwinner-a33-pf1007l.md` §8].

Recommendations:

- **zram swap via `zram-generator`** (Omarchy adds it on aarch64; do the same). **Trap:** Omarchy's `default/systemd/zram-generator.conf.d/90-omarchy.conf` sets `zram-size = ram` and `compression-algorithm = zstd` [VERIFIED], but **`linux-armv7` compiles only the LZO zram backend** (`CONFIG_ZRAM_BACKEND_FORCE_LZO=y`, ZSTD/LZ4 backends not set) [VERIFIED]. Either set `compression-algorithm = lzo-rle` (and LZ4 if the custom kernel adds it — cheaper on Cortex-A7 than zstd), or enable `CONFIG_ZRAM_BACKEND_ZSTD`/`LZ4` in our kernel. Size: start at `zram-size = ram / 2`, measure, raise.
- **zswap off** when using zram (Omarchy already ships `etc/tmpfiles.d/omarchy-zswap.conf` for this; `linux-armv7` has `ZSWAP=y`) [VERIFIED].
- **No disk swap on eMMC/SD** except a small emergency swapfile; flash wear and latency are poor. [UNCONFIRMED best practice]
- **journald:** `Storage=volatile` + `RuntimeMaxUse=16M` (or `persistent` with `SystemMaxUse=50M` if logs must survive reboots) to cut flash writes and RAM. Mount root with `noatime`.
- **Early OOM handling:** enable `systemd-oomd` — but `linux-armv7` has `CONFIG_PSI_DEFAULT_DISABLED=y` [VERIFIED], so add `psi=1` to the kernel command line or oomd has no pressure data. `CONFIG_LRU_GEN` (MGLRU) is not set in `linux-armv7` [VERIFIED]; enabling it in the custom kernel helps low-RAM desktops [UNCONFIRMED benefit].
- Mask what a photo frame does not need (e.g. `systemd-homed`, `systemd-userdbd`, `man-db.timer`, printing/avahi from Omarchy's list) and use `pacman`'s `NoExtract` for docs/locales to save eMMC space.

---

## 6. Risks

1. **GLES 3 vs Mali-400 (cross-agent, high).** Hyprland asserts a GLES 3.2 or 3.0 context [VERIFIED `Hyprland/src/render/OpenGL.cpp:213–226`]; lima is GLES 2.0. Expect llvmpipe software rendering at 1280×800 on four A7 cores. The GPU agent must confirm; it decides whether "full Omarchy" is usable at all.
2. **Chromium unavailable on armv7h (high for Omarchy).** `buildarch=8` [VERIFIED]. Omarchy's web apps and default browser must switch to Firefox, or Chromium must be self-built on a > 4 GB AArch32-capable host (days per build per forum reports).
3. **Leaf packages unconfirmed.** hyprlock, hypridle, hyprpicker, hyprsunset, mako, swaybg, quickshell were not found in the index for armv7h. First action on a real system: `pacman -Sl extra | grep -E 'hypr|quickshell|mako|swaybg|uwsm|walker'`.
4. **Bus factor.** Two people do 92% of ALARM commits; the mirror list is shrinking. A sudden stop would freeze the armv7h repos. Mitigation: keep a local repo of every package installed (`pacman -Sw` cache) so the frame can be rebuilt.
5. **[omarchy] repo is x86_64/aarch64 only.** Every Omarchy-own and `-bin` package needs an armv7h rebuild or a drop (Omarchy agent).
6. **zram compressor mismatch** (above) — silent loss of swap if not handled; verify with `zramctl` and `swapon --show` after boot.
7. **Time.** No RTC → wrong clock → pacman signature / TLS failures on first boot. Enable NTP before `pacman -Syu`.
8. **Kernel HIGHMEM future.** 1 GB on armv7 needs `HIGHMEM`; upstream discussions about trimming 32-bit ARM features continue. No removal found affecting sunxi or highmem this session. [UNCONFIRMED]
9. **Search snapshots disagree** (e.g. hyprland 0.49 vs 0.56; mesa 25.0.5 vs 26.x split packages). Treat every version in the table as approximate until checked on a device.
10. **Unit identity.** `photo-frame-dashboard/docs/android-replacement.md` reports an **ARM64 ABI** on the unit it assessed, while the PF1007L A33 docs report `armeabi-v7a`. Make sure the target frame is really the A33 (`sunxi-fel version` → `soc=00001667(A33)`) before choosing armv7h over aarch64.

---

## 7. Sources

Primary (read in this session):
- `github.com/archlinuxarm/PKGBUILDs` @ 5951a4b (2026-10-12): `README.md` (buildarch/highmem), `extra/mesa/PKGBUILD`, `core/linux-armv7/{PKGBUILD,config}`, `alarm/uboot-sunxi/{PKGBUILD,boot.txt,mkscr,uboot-sunxi.install}`, `extra/{chromium,firefox,rust,qt6-webengine}/PKGBUILD`, `core/pacman-mirrorlist/mirrorlist` history, `core/archlinuxarm-keyring`. Local clone: `/tmp/claude-0/-home-user-EvenMic/63f83b92-da7d-5160-aa2f-bd1e6d9245ac/scratchpad/repos/alarm-pkgbuilds`
- `menci/archlinuxarm:base` image, `linux/arm/v7` manifest `sha256:9c43138e…`, layer `sha256:43dac85f…` (pacman local DB, `/etc/pacman.conf`, mirrorlist, os-release). Extract: `scratchpad/dl/menci/`
- `github.com/Menci/docker-archlinuxarm` Dockerfile and README
- AUR mirror `github.com/archlinux/aur` branches `yay`, `yay-bin`, `distccd-alarm`
- `basecamp/omarchy` clone (`install/*.packages`, `default/systemd/zram-generator.conf.d/90-omarchy.conf`, `default/pacman/pacman-stable.conf`)
- `hyprwm/Hyprland` clone (`src/render/OpenGL.cpp`)
- `photo-frame-dashboard/docs/{allwinner-a33-mainline-uboot.md, allwinner-a33-pf1007l.md, android-replacement.md}`

Secondary (search snippets of pages this sandbox could not open):
- [End of life for v5/v6, changes for v7](https://archlinuxarm.org/forum/viewtopic.php?f=3&t=15721)
- [hyprland (armv7h)](https://archlinuxarm.org/packages/armv7h/hyprland), [aquamarine](https://archlinuxarm.org/packages/armv7h/aquamarine), [hyprutils](https://archlinuxarm.org/packages/armv7h/hyprutils), [hyprlang](https://archlinuxarm.org/packages/armv7h/hyprlang), [xdg-desktop-portal-hyprland](https://archlinuxarm.org/packages/armv7h/xdg-desktop-portal-hyprland), [hyprland-guiutils](https://archlinuxarm.org/packages/armv7h/hyprland-guiutils), [hyprtoolkit](https://archlinuxarm.org/packages/armv7h/hyprtoolkit), [uwsm (any)](https://archlinuxarm.org/packages/any/uwsm), [waybar](https://archlinuxarm.org/packages/armv7h/waybar), [mesa](https://archlinuxarm.org/packages/armv7h/mesa), [vulkan-virtio](https://archlinuxarm.org/packages/armv7h/vulkan-virtio), [chromium](https://archlinuxarm.org/packages/armv7h/chromium), [firefox](https://archlinuxarm.org/packages/armv7h/firefox), [go](https://archlinuxarm.org/packages/armv7h/go)
- [Arch mesa file list (lima_dri.so)](https://archlinux.org/packages/extra/x86_64/mesa/files/)
- [ALARM downloads](https://archlinuxarm.org/about/downloads), [pietma mirror index](https://repository.pietma.com/nexus/content/sites/archlinux/os/)
- [Chromium not working again (ALARM forum)](https://archlinuxarm.org/forum/viewtopic.php?f=15&t=15001&start=0), [armv7h Chromium and a bug in Node](https://archlinuxarm.org/forum/viewtopic.php?t=16264)
- [Distcc Cross-Compiling (ALARM wiki)](https://archlinuxarm.org/wiki/Distcc_Cross-Compiling)
- [Fedora Asahi issue #7 (M1 cannot run armv7)](https://pagure.io/fedora-asahi/project/issue/7), [Parallels forum: 32-bit ARM in VM](https://forum.parallels.com/threads/32bit-arm-not-supported-in-a-linux-vm.356516/), [Docker VMM docs](https://docs.docker.com/desktop/vmm)
- [postmarketOS armhf removal](https://postmarketos.org/edge/2026/06/22/armhf-removed/), [Phoronix: old ARM platforms removal](https://www.phoronix.com/news/Linux-Dropping-Old-ARM-Ahead)
- [Debian hyprland](https://packages.debian.org/hyprland), [Alpine hyprland armv7 v3.22](https://pkgs.alpinelinux.org/package/v3.22/community/armv7/hyprland)
- [Home Assistant: deprecating armv7](https://github.com/home-assistant/architecture/discussions/1230), [LinuxServer: End of an Arch](https://www.linuxserver.io/blog/end-of-an-arch)
