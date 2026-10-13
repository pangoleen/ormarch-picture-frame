# 04 — Omarchy: what it is, and how to port it to armv7h

Target: Allwinner A33 photo frame. Quad Cortex-A7, 32-bit armv7, Mali-400 MP2 (GLES 2.0 only), 1 GB RAM, ~16 GB eMMC, 1280x800 touch, no keyboard. Base OS: Arch Linux ARM (ALARM) armv7h.

Tags: **[VERIFIED]** = I read it in source (path given). **[DOCUMENTED]** = secondary source (search snippet, port write-up). **[UNCONFIRMED]** = my inference. A null result is scoped to what I searched.

Clones used (all under `scratchpad/repos/`):
- `basecamp_omarchy` — official repo, default branch `quattro`, HEAD `defbf90e` (2026-10-12).
- `omarchy-v4.0.4` (latest release tag) and `omarchy-v3.8.4` (last pre-Quickshell release line).
- `omacom_omarchy-pkgs` (the PKGBUILDs behind `pkgs.omarchy.org`), `omacom_omarchy-iso` (the installer ISO).
- `hotschmoe_omarchy-arm` = `alexisraitano-myffu_omarchy-arm` (identical HEAD `579f15c6`), `happybigmtn_omarchy-arm-fixes`.
- `hyprgrass`, `wvkbd`. Also read (not modified) `alarm-pkgbuilds` and `Hyprland` that other agents cloned.

---

## Summary (5 bullets)

1. **Omarchy changed shape. Version 4 ("quattro", tag v4.0.4) is not the Omarchy of most blog posts.** It is now two Arch packages (`omarchy`, `omarchy-settings`) plus a package list. The desktop is ONE Quickshell (Qt6/QML) process: bar, menu/launcher, notifications, OSD, lock screen, polkit agent, idle. Waybar, Walker/Elephant, Mako, SwayOSD, hyprlock, hypridle and swaybg are **removed** (`bin/omarchy-upgrade-to-quattro:863-912`). The Hyprland config is **Lua** (`config/hypr/hyprland.lua`), so it needs Hyprland **≥ 0.55**; Omarchy itself ships and tests **0.56.2**. Default terminal is **foot**. [VERIFIED]
2. **Upstream already supports aarch64 officially** (`AGENTS.md` "Platforms": `x86`, `aarch64`, `aarch64-apple`; `pkgs.omarchy.org/edge/aarch64`; `arm-mirror.omarchy.org` for ALARM). There is **no armv7 support**, and one trap: `bin/omarchy-hw-platform` prints **`x86`** for any CPU that is not `aarch64`. On armv7l it would pick the x86 package set and **overwrite `/etc/pacman.conf` with x86 mirrors and `[multilib]`** (`install/post-install/pacman.sh`). This is the first edit. [VERIFIED]
3. **The Omarchy core is mostly portable.** The payload (bin/, shell/, config/, themes/) is architecture-independent shell + QML + Lua. ALARM armv7h has hyprland 0.56.2-4, qt6-declarative, qt6-wayland, waybar, mako, firefox 157, libreoffice-fresh, docker, nautilus [DOCUMENTED]. Missing on armv7h: **Chromium** (ALARM builds it for aarch64 only: `buildarch=8`) [VERIFIED], **Quickshell** (no armv7h page found) [DOCUMENTED null], and all Omarchy first-party packages (Omarchy builds only x86_64 + aarch64) [VERIFIED].
4. **The hard blocker is NOT the port. It is the GPU.** Hyprland creates a GLES **3.2**, then **3.0** context, and asserts if both fail (`Hyprland/src/render/OpenGL.cpp:205-226`; 33 shaders are `#version 300 es`). Mali-400 (lima) is GLES 2.0. So Hyprland can only run on **Mesa llvmpipe** (CPU rendering) on this frame. Omarchy's own Hyprland build carries a backport that detects llvmpipe as "software rendering" (`omarchy-pkgs/pkgbuilds/hyprland/software-renderer.patch`, upstream PR #16343) — worth reusing. Quickshell + Firefox + llvmpipe in 1 GB RAM on 4x A7 is the real risk (GPU/RAM agents own this). [VERIFIED for the code; the performance is UNCONFIRMED]
5. **Port effort is moderate and well-mapped.** Copy the approach of `omarchy-arm` (an `install.sh` that runs on a live ALARM system, package manifests `packages.{replace,aur,unavailable,extra}`, boot chain left alone, x86 hardware leaves gated). Add an `armv7` platform, build ~10 small packages ourselves (`omarchy`, `omarchy-settings`, `quickshell`, `xdg-terminal-exec`, `mise` armv7 binary, fonts/icons, `wvkbd`, `hyprgrass`), drop ~45 packages that make no sense on a photo frame. Estimated root size: **~2.5–3.5 GB** for a frame-sized Omarchy, **~5–6 GB** for "everything that exists on armv7h". Both fit 16 GB. [UNCONFIRMED estimate, method in Port plan]

---

## How the Omarchy installer works

### v4 (current, `quattro` branch, tags v4.0.x)

**There is no `install.sh` any more.** The ISO is "the only supported way to install Omarchy" (`omacom_omarchy-iso/README.md`). [VERIFIED]

Flow [VERIFIED, paths below]:

1. **ISO configurator** (`omarchy-iso/configs/airootfs/root/configurator`) asks questions, then partitions: FAT32 ESP + **LUKS2** root (optional) + **btrfs** with subvolumes `@ @home @log @pkg`, mounted `noatime,compress=zstd` (lines 685-770). Bootloader is **Limine** (`efi_binary: limine_x64.efi`, lines 809-810, 1152-1153). It drives **archinstall** with `builder/archinstall.packages` = `alsa-firmware amd-ucode base base-devel efibootmgr intel-ucode linux-firmware linux limine omarchy-keyring openssh pipewire snapper sof-firmware tailscale`.
2. **pacstrap** of `install/omarchy-base.packages` (161 names) from an offline mirror in the ISO (`omarchy-base.packages` header comment).
3. In the chroot: **`omarchy-apply-system`** (`bin/omarchy-apply-system`) sources `install/config/all.sh` → `omarchy-apply-hardware` (`install/hardware/all.sh`, ~40 vendor leaves gated by PCI/DMI) → `install/login/all.sh` (SDDM PAM tweak) → `install/post-install/all.sh` (pacman.conf, udev, localdb).
4. **`omarchy-provision-user`** sources `install/user/all.sh` (theme, chromium, git, xcompose, input method, mise, keyring, dictation, platform-setup).
5. Optional deferred mode: `omarchy-provision-owner.service` creates the user on first boot on tty1, re-keys LUKS, and writes SDDM **autologin** (`bin/omarchy-provision-owner:843-849`: `[Autologin] User=… Session=omarchy.desktop`; encrypted installs keep autologin permanently, unencrypted only for the first boot).
6. Prebuilt images: an image manifest `/var/lib/omarchy/image/target` defers all hardware leaves to the first boot (`docs/file-layout.md`, `install/helpers/image-target.sh`).

**Where things live** [VERIFIED]:

| Item | Location |
|---|---|
| Package lists | `install/omarchy-base.packages` (everyone), `omarchy-aarch64.packages` (adds `zram-generator`), `omarchy-aarch64-apple.packages`, `omarchy-x86_64-only.packages` (`gliff`, `superwhisper-bin`), `omarchy-other.packages` (ISO cache: limine, snapper, nvidia, intel, T2…). Composed by `bin/omarchy-pkg-defaults`. |
| Omarchy repo | `[omarchy] Server = https://pkgs.omarchy.org/<channel>/$arch`, channels `edge → rc → stable` (`default/pacman/pacman-stable.conf`). aarch64 gets **edge only** plus `[core] [extra] [alarm] [aur]` from `https://arm-mirror.omarchy.org/$arch/$repo` (`default/pacman/aarch64/*`, `install/helpers/pacman.sh`). |
| Omarchy packages | `omacom/omarchy-pkgs/pkgbuilds/*` — 179 recipes, "Architectures: x86_64 and aarch64" (README). |
| Hard runtime deps | `omarchy` PKGBUILD: `omarchy-keyring omarchy-settings=$pkgver hyprland quickshell uwsm sddm xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl fakeroot pacman-contrib ttf-jetbrains-mono-nerd-basic`; x86_64 adds `limine limine-mkinitcpio-hook limine-snapper-sync snapper`; aarch64 adds `networkmanager`. `omarchy-settings` depends on `bash curl gum hicolor-icon-theme plymouth`. |
| Session | `default/wayland-sessions/omarchy.desktop`: `uwsm start -g -1 -e -D Hyprland hyprland.desktop`. SDDM greeter itself runs under Hyprland (`etc/sddm.conf.d/10-wayland.conf`: `CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua`). |
| Services | `install/config/enable-services.sh`: cups, avahi-daemon, linux-modules-cleanup, docker.socket, systemd-resolved, NetworkManager (wait-online masked), power-profiles-daemon, sddm, systemd-oomd. UFW in `firewall.sh`. Snapper + `limine-snapper-sync` in `install/config/snapper.sh` (ungated — fails without snapper). |
| Commands | 512 files in `bin/`, all `omarchy-*`; groups listed in `bin/omarchy` `GROUP_DESCRIPTIONS`. Package helpers: `omarchy-pkg-add/-drop/-present/-missing/-aur-add`. Arch predicates: `omarchy-hw-x86`, `omarchy-hw-aarch64`, `omarchy-hw-platform`. |
| Boot-chain hooks | `bin/omarchy-lifecycle-dispatch` (`docs/lifecycle-dispatch.md`): a platform package can own boot ops; `x86`/`aarch64` are no-ops. A U-Boot board can register here. |
| Hyprland version | Lua config ⇒ ≥ 0.55 (Lua introduced in 0.55 [DOCUMENTED, hypr.land news]). Omarchy pins **0.56.2** with a patch (`omarchy-pkgs/pkgbuilds/hyprland/PKGBUILD`, `arch=(aarch64)` — they rebuild it for ALARM). Comments in `default/hypr/qconsole.lua:172` say "Measured on Hyprland 0.56.2". |

**Arch checks in v4.** There is no "refuse non-x86_64" guard in the target scripts any more. Architecture enters only via `omarchy-hw-platform` (`bin/omarchy-hw-platform`). Its last branch is:

```bash
if [[ $machine == "aarch64" ]]; then echo aarch64; else echo x86; fi
```

So **armv7l → `x86`**. Then `omarchy-pkg-defaults` returns the x86 list, `omarchy_pacman_templates x86` returns `default/pacman/` (x86 mirrors + `[multilib]`), and `install/post-install/pacman.sh` copies it over `/etc/pacman.conf`. Result: a machine that cannot resolve any package. The image manifest path also hard-fails (`contradiction "... the CPU is $machine"`) for any non-aarch64 ARM platform. [VERIFIED]

`omarchy-hw-x86` and `omarchy-hw-aarch64` both return false on armv7l. The 20 call sites use them to HIDE x86-only items (Windows VM, Edge, Spotify, Dropbox, Minecraft, Heroic, Superwhisper — `default/omarchy/omarchy-menu.jsonc`), so "both false" is mostly safe. `bin/omarchy-update-keyring:28` installs `archlinuxarm-keyring` only `if omarchy-hw-aarch64` → must include armv7. [VERIFIED]

### v3.8.x (for comparison — the "classic" Omarchy)

`boot.sh` (curl | bash) → clones repo to `~/.local/share/omarchy` → `install.sh` sources `helpers → preflight → packaging → config → login → post-install`. [VERIFIED, `omarchy-v3.8.4/`]

- `install/preflight/guard.sh` requires: `/etc/arch-release`, not Cachy/Endeavour/Garuda/Manjaro, not root, **`uname -m == x86_64`**, Secure Boot off, no GNOME/KDE, **limine installed**, **btrfs root**. Each failure calls `abort`, which offers `gum confirm "Proceed anyway…"` — a soft gate, not a hard refusal.
- `install/login/limine-snapper.sh` writes mkinitcpio hooks (`plymouth … encrypt … btrfs-overlayfs`), `/etc/default/limine`, UKIs, snapper config.
- 149 base packages, including `waybar walker(omarchy-walker) mako swayosd hyprlock hypridle swaybg alacritty 1password-beta spotify signal-desktop obsidian typora kdenlive obs-studio`.
- Config is hyprlang `.conf`. Hyprland 0.55+ deprecates hyprlang and plans to drop it "1–2 releases" later [DOCUMENTED]. So v3 on Hyprland 0.56 is living on borrowed time. **Recommendation: port v4, not v3.** [UNCONFIRMED judgement]

---

## Package table

Source: `install/omarchy-base.packages` at `quattro` HEAD (161 names) + `omarchy-aarch64.packages` + what the ports found missing. Status codes:

- **(a)** in ALARM armv7h repos. **(b)** builds from source on armv7 (AUR, Omarchy PKGBUILD, or upstream). **(c)** binary-only / x86-only / no armv7 path → replace or drop. **(d)** not relevant on a photo frame → drop.
- **Core** = needed for the "Omarchy experience". Evidence tag in brackets: V / D / U.

Note on (a): ALARM's rule is "everything from Arch ABS builds unless overridden" (`alarm-pkgbuilds/README`) [VERIFIED]. I could not reach `archlinuxarm.org` (DNS blocked), so most (a) rows are **[U]** = "Arch package, no arch-specific code, expected in ALARM armv7h". **Run `pacman -Si <list>` on the device (or in an armv7h chroot) before trusting any (a)-U row.**

### Core desktop (keep)

| name | purpose | armv7h status | action |
|---|---|---|---|
| hyprland | compositor | (a) 0.56.2-4 [D] | Keep. Consider rebuilding with Omarchy's `software-renderer.patch` (llvmpipe detection) [V]. Needs GLES ≥3.0 → llvmpipe on Mali-400 [V] |
| hyprland-guiutils | Hyprland dialogs | (a) 0.2.1-6 [D] | keep |
| xdg-desktop-portal-hyprland | portal | (a) 1.3.11-4 [D] | keep |
| xdg-desktop-portal-gtk | portal fallback | (a) [U] | keep |
| quickshell | THE Omarchy shell (bar, menu, OSD, notify, lock, idle, polkit) | (b) no armv7h page found [D null]; aarch64 has 0.3.1 [D]. Omarchy builds 0.3.2 from source, `CRASH_REPORTER=Off` [V] | **Build ourselves.** Deps: qt6-base/declarative/svg/wayland, cpptrace, jemalloc (armv7h 5.3.0 [D]), pipewire, pam, polkit. cpptrace on armv7h [U] |
| qt6-base, qt6-declarative, qt6-wayland, qt6-svg, qt6-imageformats, qt6-multimedia | Qt runtime for Quickshell + Omarchy apps | (a) qt6-declarative 6.10.2, qt6-wayland 6.12.0, qt6-base 6.10.0 (stale cache?) [D]; svg/imageformats/multimedia [U] | keep (multimedia only if hype/monologue kept). Watch for Qt version skew between armv7h packages [D] |
| uwsm | session manager | (a) `any` 0.26.6 [D] | keep |
| sddm | login/greeter (runs its own Hyprland) | (a) 0.21.0-6, built Jan 2025 [D] | **Replace on frame** with SDDM autologin only, or getty autologin + `uwsm start`. A second Hyprland for a greeter costs RAM [U] |
| foot | default terminal (`default/xdg-terminal-exec/xdg-terminals.list`) [V] | (a) `foot-terminfo` armv7h exists, same pkgbase [D] → foot [U] | keep. CPU-rendered — good for llvmpipe [U] |
| xdg-terminal-exec | terminal launcher (TERMINAL=) | (b) AUR `arch=(any)` [V via github.com/archlinux/aur mirror] | build (trivial). omarchy-arm marks it load-bearing [D] |
| pipewire, wireplumber, **pipewire-pulse** | audio | (a) [U] | keep; add pipewire-pulse (omarchy-arm found pactl dead without it) [D] |
| networkmanager | network | (a) ALARM has an override recipe [V dir list] | keep |
| bluez, bluez-utils, bluez-tools | BT | (a) [U] | keep only if the frame has BT |
| gnome-keyring, libsecret | secrets | (a) [U] | keep |
| brightnessctl | backlight | (a) [U] | keep (frame backlight) |
| gum, jq, git, perl, fakeroot, pacman-contrib, socat, inotify-tools, less, unzip, expac | required by omarchy-* scripts | (a) gum AUR lists armv7h [V]; rest [U] | keep |
| wl-clipboard, wtype, grim, slurp, hyprpicker, hyprsunset | Wayland utils used by menu/binds | (a) [U] | keep wl-clipboard, wtype (OSK fallback), grim/slurp; others optional |
| udiskie | automount (autostart) | (a) [U] | keep |
| power-profiles-daemon | power menu | (a) [U] | keep (Omarchy autostarts `omarchy-powerprofiles-init`) |
| plymouth | boot splash; **hard dep of omarchy-settings** [V] | (a)? old forum: not on armv7h; aarch64 has it [D] [U now] | If missing: build it, or drop the dep in our omarchy-settings |
| zram-generator | compressed swap (aarch64 list) [V] | (a) [U] | **keep — critical at 1 GB.** Check `zstd` is in the A33 kernel's zram (omarchy-arm saw only lzo on `linux-aarch64`) [D] |
| ttf-jetbrains-mono-nerd-basic | UI font (hard dep) | (b) Omarchy `any` [V] | build from omarchy-pkgs, or replace with `ttf-jetbrains-mono-nerd` (a) [D omarchy-arm] |
| noto-fonts, noto-fonts-emoji, woff2-font-awesome | fonts | (a) `any` [U] | keep |
| yaru-icon-theme | icons | (b) Omarchy `any` [V] | build (trivial) |
| omarchy, omarchy-settings, omarchy-keyring | the product | (b) Omarchy PKGBUILDs; payload arch-independent; arch=(x86_64 aarch64) [V] | **build ourselves** with `armv7h` added |
| owe, owe-lockfeed | video wallpaper engine + lock-screen video feed | (b) meson/cmake C/Qt [V] | optional. Shell draws still backgrounds itself (`omarchy-background` layer) [V]; OWE only for video [U]. Theme intro videos are 215 MB of mp4 [V] → drop |
| omarchy-hyprland-titlebars | Hyprland plugin | (b) cmake [V] | optional |
| starship, eza, bat, fd, ripgrep, fzf, zoxide, btop, fastfetch, bash-completion, tmux, man-db, tldr, plocate, vi | shell/CLI set | (a) [U] (ALARM overrides exist for btop, eza, fd [V]); `vi` Omarchy lists armv7h [V] | keep the small ones; they ARE part of the Omarchy feel and are tiny |
| mise-bin | tool manager; `install/user/mise.sh` needs it | (b) AUR arch=(x86_64 aarch64) [V]; **upstream ships `linux-armv7` binaries** [D, release v2026.10.8] | write a 10-line armv7h PKGBUILD around the upstream binary; or stub out mise.sh on a frame |
| yay | AUR helper | (b) arch includes armv7h [V] | build. On-device builds are slow; prefer an off-device build host |
| ufw | firewall | (a) [U] | keep |
| ufw-docker | docker firewall rules | (b) `any` [V] | drop with docker AND gate `install/config/firewall.sh` (aborted omarchy-arm install) [D] |
| alsa-utils, pamixer | audio CLI | (a) [U] | keep |
| avahi, nss-mdns | mDNS | (a) [U] | keep (handy to reach the frame) |
| kernel-modules-hook, wireless-regdb, dosfstools, exfatprogs, inetutils, whois | system | (a) [U] | keep |
| imv, mpv, mpv-mpris, ffmpeg, ffmpegthumbnailer, imagemagick, libvips | media | (a) [U] | **keep imv/mpv** — they are the photo-frame app. Rest optional |
| python-gobject, lua51, luarocks, ruby | runtimes used by scripts | (a) ruby has ALARM override [V]; [U] | keep python-gobject; lua51/luarocks only for nvim; ruby only for tobi-try |

### Omarchy apps (optional — buildable, but not core)

| name | purpose | armv7h status | action |
|---|---|---|---|
| omacalc, omawrite, omacut | Qt Quick calculator / writer / video trimmer | (b) C++/Qt6 source [V] | optional build |
| hype, signed, monologue | Qt6 slides / PDF signer / webcam recorder | (b) C++/Qt6 [V] | drop on frame (d) |
| omasnap | screenshot + annotate (Qt6, tesseract) | (b) cmake [V] | optional |
| ttfx | screensaver text effects (Rust) | (b) cargo [V] | optional. Without it the screensaver path exits cleanly in omarchy-arm [D] |
| tzupdate | timezone by IP (Rust) | (b) cargo [V] | keep (cheap, useful on a frame) |
| aether | theme designer (Go + webkit2gtk; Omarchy ships prebuilt amd64/arm64 binaries) | (c) no armv7 binary [V]; source build [U] | drop |
| cliamp | terminal music player (Go) | (b) go [V] | drop (d) |
| herdr | AI-agent terminal manager (Rust + Zig 0.16) | (b) but Zig/LLVM build filled a 15 GB disk on aarch64 [D] | **drop** |
| disktree-bin | disk treemap (prebuilt, Vulkan) | (c) x86_64/aarch64 binaries only [V] | drop |
| hyprland-preview-share-picker | screen-share picker (Rust) | (b) cargo [V] | drop (d); comment out its line in `config/hypr/xdph.conf` [D omarchy-arm] |
| omarchy-nvim, nvim (→ neovim), tree-sitter-cli, lazygit, usage | editor setup / dev | (b) omarchy-nvim `any` [V]; neovim (a) [U] | drop on frame (d); keep neovim if you want SSH editing |
| tobi-try, ttf-ia-writer | dev dir tool / font | (b) `any` [V] | drop / optional |
| tesseract, tesseract-data-eng, zbar, qrencode | OCR, QR (text extraction, wifi QR) | (a) [U] | optional |
| yt-dlp | video download | (a) `any` [U] | optional |

### Not relevant on a photo frame (drop) — (d)

| name | why | armv7h status |
|---|---|---|
| base-devel | build toolchain (~250 MB) | (a) — build off-device instead [U] |
| docker, docker-buildx, docker-compose | containers | (a) docker 1:29.5.2, 114 MiB [D] |
| libreoffice-fresh | office suite | (a) 26.8.0, 406 MiB [D] |
| cups, cups-filters, cups-pk-helper, system-config-printer | printing | (a) [U] |
| nautilus, nautilus-python, sushi, gnome-disk-utility, evince, gvfs-mtp, gvfs-nfs, gvfs-smb, gnome-themes-extra | GNOME file manager stack | (a) nautilus 49.4 [D]; rest [U]. Keep nautilus only if you want a file browser |
| fcitx5, fcitx5-gtk, fcitx5-qt, fcitx5-chewing, -chinese-addons, -hangul, -mozc | CJK input | (a) [U]; mozc (Bazel) on armv7h doubtful [U] |
| noto-fonts-cjk | CJK font (~300 MB) [U] | (a) `any` |
| mariadb-libs, postgresql-libs, libyaml, python-poetry-core | Ruby/Rails dev libs | (a) [U] |
| bolt, ddcutil, asdcontrol | Thunderbolt, external-monitor DDC, Apple display | n/a |
| qemu-user-static-binfmt | runs x86 binaries | (c) [D] |
| moonlight-qt | game streaming client | [U] |
| gpu-screen-recorder | screen recording (needs real GPU) | [U] — drop; `wf-recorder` is Omarchy's own fallback for Apple [V] |
| inxi | hardware report | (a) [U] |

### x86-only / binary-only — (c)

| name | why | replacement |
|---|---|---|
| **chromium** | default browser (`mimeapps.list`) [V]. ALARM PKGBUILD has `buildarch=8` = aarch64 only [V, `alarm-pkgbuilds/extra/chromium/PKGBUILD`]; last armv7h build 101 (2022) [D] | **firefox** — ALARM armv7h 157.0, 272 MiB [D]; ALARM builds it with `-j1` and LTO off for RAM on armv7h [V `extra/firefox/PKGBUILD:172-178`]. `omarchy-install-browser` already knows firefox [V]. Web apps (`omarchy-launch-webapp`) use Chromium `--app`; needs a Firefox path (happybigmtn did this) [D] |
| obsidian | Electron, Omarchy ships aarch64 only [V] | drop |
| pinta, dotnet-runtime | .NET; Arch has no armv7h .NET [D omarchy-arm] | drop |
| localsend | Flutter app [V]; Flutter has no linux-armv7 desktop target [U] | drop |
| superwhisper-bin | x86_64-only (Omarchy's own list) [V] | drop (already gated by `omarchy-hw-x86`) |
| gliff | GPU H.264 remote desktop; in `omarchy-x86_64-only.packages` [V] | drop |

### Classic v3 components (only if you choose v3 instead of v4)

| name | armv7h status |
|---|---|
| waybar | (a) 0.15.0-2 [D] |
| mako | (a) 1.11.0-1 [D] |
| hyprlock, hypridle | aarch64 pages only; no armv7h page found [D null] → (b) cmake, same hypr* libs. hyprlock also needs GLES3 [U] |
| swayosd | aarch64 only [D]; AUR swayosd-git lists x86_64/aarch64/i686 [V] → (b) |
| walker / elephant | AUR `walker-bin`, `elephant-bin` x86_64 only [V]; Omarchy's `walker` recipe is a cargo source build [V] → (b) |
| alacritty | aarch64 page only [D]; Rust, has a GLES2 renderer [U] → (b) |
| ghostty | not in ALARM [D]; needs OpenGL 3.3 [U] → (c) on Mali-400 |

### Is there a browser for armv7h?

- **Firefox: yes.** ALARM armv7h `firefox 157.0-1`, built 2026-09-30, 272 MiB installed [D]. ALARM's recipe has an armv7h branch [V].
- **Chromium: no** current build. ALARM recipe is aarch64-only (`buildarch=8`) [V]. `qt6-webengine` (Chromium-based) does exist for armv7h 6.11.2 [D], so a QtWebEngine shell is a lighter fallback [U].
- Expect Firefox to be very slow on A7 + llvmpipe with 1 GB RAM [U]. For a frame, keep the browser optional.

---

## What the aarch64 ports changed

### 1. `omarchy-arm` (hotschmoe = alexisraitano-myffu, branch `arm64`, 2026-08-24)

Base: Omarchy `quattro` (v4) **before** upstream added aarch64. Diff vs its `quattro` base: **54 files, +4000/−52** (`git diff --stat quattro arm64`) [VERIFIED]. Full write-up: `docs/arm64-port.md` [VERIFIED]. What it did:

| Change | Files | aarch64-specific? |
|---|---|---|
| **New `install.sh`** that installs onto a running ALARM system. Phases: preflight → package plan → deploy to `/usr/share/omarchy` → settings (what `omarchy-settings` would own) → `omarchy-apply-system --install-user $USER --first-install` → `omarchy-provision-user`. Every mutation goes through one `run()` so `--dry-run` cannot drift. | `install.sh` | Only the guard: `if [[ $arch != "aarch64" ]]; then die` (line 146). Change to accept `armv7l`. |
| **Package manifests** instead of logic: `packages.replace` (`nvim→neovim`, `ttf-jetbrains-mono-nerd-basic→ttf-jetbrains-mono-nerd`), `packages.aur` (optional AUR builds), `packages.aur-required` (`xdg-terminal-exec mise-bin ufw-docker`), `packages.unavailable` (13 names), `packages.extra` (`zram-generator pipewire-pulse`), `packages.exclude` (`yay`, bootstrapped). A test fails if manifests drift from the base list. | `install/arm/packages.*` | Content is aarch64-measured; the **mechanism** is arch-neutral. Re-measure for armv7h. |
| **pacman.conf edited in place**, never replaced; `[multilib]` and `[omarchy]` stripped. | `install/arm/pacman.sh`, `install/post-install/pacman.sh` | Neutral. Copy as-is. |
| **ALARM keyring** bootstrap (pacstrap from archboot lacked it → 200 "unknown trust"). | `install/arm/keyring.sh` | Neutral. |
| **x86 hardware leaves gated** with `run_logged_x86` (29 of 39); 3 ARM leaves added (Vulkan per board, Apple speakers, Pi zram). `install/config/snapper.sh` gated. | `install/hardware/all.sh`, `install/hardware/arm/*` | Gating is neutral. Leaves are board-specific — write an `allwinner-a33.sh` leaf. |
| **Boot chain untouched**: no limine, no mkinitcpio drop-ins, no snapper; `omarchy-refresh-limine` made safe. | `install/arm/settings.sh`, `bin/omarchy-refresh-limine` | Neutral. Exactly what a U-Boot frame needs. |
| **Platform detection** from `/proc/device-tree` (`raspberry-pi-5`, `apple-silicon`, `generic-aarch64`). | `bin/omarchy-hw-*` | Add `allwinner,sun8i-a33` → e.g. `armv7`. |
| **`omarchy-pkg-add` resolves names on ARM**: refuses known x86-only apps with a reason, offers AUR builds instead of silent compiles. | `bin/omarchy-pkg-add`, `bin/omarchy-pkg-arm-{name,source}`, `install/arm/apps.unavailable` | Neutral mechanism; lists are aarch64-measured. |
| **Home seeding**: `/etc/skel` only fires at `useradd`; on a live system the user already exists → seed `$HOME` once, back up, never clobber on re-run. | `install/arm/seed-home.sh` | Neutral. **Needed for us too.** |
| **Keyboard layout** from `vconsole.conf`/`localectl`. | `install/arm/keyboard.sh` | Neutral (irrelevant for touch-only). |
| **Migrations** made tolerant of `omarchy-pkg-add` failures (one failed migration blocked all later ones forever). | `bin/omarchy-migrate` | Neutral. **Needed.** |
| **Screensaver** exits cleanly if `ttfx` is missing (it spun a core and cancelled the lock). | `bin/omarchy-screensaver`, `bin/omarchy-launch-screensaver` | Neutral. |
| **Raspberry Pi Lua profile**: animations, blur, shadows, rounding off. | `default/hypr/platform/raspberry-pi.lua`, `default/hypr/platform.lua` | Concept is exactly what llvmpipe needs. Copy and extend. |
| Agent skill `arm.md`. | `default/agents/skills/omarchy/arm.md` | Optional. |

Its "first real install" table lists 20 fatal surprises with a clean log (no PATH to `bin/`, no `/etc/skel`, missing `pipewire-pulse`, `ufw` exit 1 before first start, `herdr` filling 15 GB, etc.) — **read `docs/arm64-port.md` "What the first real install found" before writing our installer.** [VERIFIED]

Note: upstream `quattro` now has official aarch64 platform code (`omarchy-hw-platform`, `omarchy-aarch64.packages`, `default/pacman/aarch64/`, `arm-mirror.omarchy.org`). So for armv7 we should fork **current upstream** and add a sibling `armv7` platform the upstream way, and borrow `omarchy-arm`'s live-system installer + manifests. [VERIFIED for upstream state; plan is UNCONFIRMED]

### 2. `happybigmtn/omarchy-arm-fixes` (2025-08-27, Omarchy v2/v3 era, Asahi M1/M2, Hyprland 0.49)

Patches on top of `nilszeilon/armarchy` [VERIFIED `README.md`, `patches/`]:
- `packages.patch`: an `OMARCHY_ARM=true` branch with a hand-pruned package list (no 1password, obs, obsidian, spotify…).
- `webapp-launcher.patch`, `mimetypes.patch`: **Firefox instead of Chromium**; web apps via `firefox --new-window` because Firefox has no `--app`.
- `install-script.patch`: skip `tte` animations when missing.
- Config fixes: missing `zoom.conf`, invalid `noscreenshare` rule.

Nothing here is aarch64-specific except the package list. The Firefox web-app idea is directly reusable for armv7h (Chromium is gone there too). The rest is obsolete under v4.

### 3. FydeOS / Fydetab Duo (`Linux-for-Fydetab-Duo/imagebuild`, release `prod-omarchy-v0.1.5`) [DOCUMENTED, release page + forum]

- Omarchy **4.0.0**, Hyprland 0.56, Quickshell shell, **SDDM autologin**, on ALARM aarch64 (RK3588S).
- **Image-based**, not ISO: U-Boot → ext4 root, custom `linux-fydetab` 6.12.43 kernel. **No LUKS, no btrfs/snapper/Limine, no Plymouth** (text boot).
- Portrait DSI panel: 2x scaling + **touchscreen mapping** configured.
- They build Omarchy packages for aarch64 themselves (before upstream did).
- Lessons for us: an image build with U-Boot + ext4 is the proven pattern for an SBC-class device; skipping LUKS/btrfs/snapper/plymouth is accepted.

---

## Touch-only additions

Omarchy is keyboard-first: 228 keybindings loaded on the omarchy-arm VM [D]. The menu opens with `Super+Alt+Space`. Bar widgets do take clicks (workspaces, clock, update, mic) [V `shell/plugins/bar/widgets/*.qml`]; Qt Quick turns a touch tap into a left click. Right/middle-click actions are unreachable by touch [U]. `omarchy toggle touchscreen` exists [V `manual/13-toggles-idle-screensaver.md`]. There is **no** on-screen keyboard or gesture plugin in Omarchy (grep for `wvkbd|squeekboard|hyprgrass` = 0 hits in the repo) [VERIFIED null].

What to add:

1. **On-screen keyboard: `wvkbd`** (recommended).
   - Tiny C program; deps `wayland-client xkbcommon pangocairo` [V `wvkbd/Makefile`]. Uses `zwlr_layer_shell_v1` + `zwp_virtual_keyboard_manager_v1` [V `main.c`], both supported by Hyprland [U].
   - AUR `wvkbd` arch=`('x86_64' 'i686' 'armv7h' 'aarch64')` [V via github.com/archlinux/aur mirror].
   - Show/hide by signal: `SIGUSR1` hide, `SIGUSR2` show, `SIGRTMIN` toggle [V `README.md:24,70`]. Bind a bar button or an edge swipe to `pkill -RTMIN wvkbd-mobintl`.
   - `squeekboard`: AUR arch `(x86_64 aarch64)` only [V]; Rust + GTK3, heavier; ALARM has it for aarch64 only [D]. Second choice.
2. **Gestures: `hyprgrass`** (horriblename/hyprgrass, v0.8.2, last commit 2026-09-25) [V].
   - Meson + C++, deps `glm` and the `wf-touch` subproject [V `README.md`, `subprojects/`]. No architecture-specific code found by grep [VERIFIED null, scoped to meson.build and wraps].
   - **Already migrated to Hyprland's Lua config** (`hl.plugin.hyprgrass.gesture{…}`, `docs/lua_migration.md`) [V], so it matches Omarchy v4.
   - Gives: edge swipes, multi-finger swipes, long-press move/resize, custom commands [V]. Map: swipe-from-bottom → toggle wvkbd; swipe-from-top → open Omarchy menu; 3-finger horizontal → workspace.
   - Build: `hyprpm add` compiles against Hyprland headers on the device [V README]. On 1 GB RAM, build it off-device against the exact same hyprland package [U]. Not found in the AUR mirror (`hyprgrass` / `hyprland-plugin-hyprgrass` → 404) [VERIFIED null, scoped to those two names].
   - Warning from upstream: a bug can make the touch device unusable until unload — keep SSH or a USB keyboard for first tests [V README].
3. **Lock screen + OSK conflict.** Omarchy's lock is Quickshell `WlSessionLock` [V `shell/plugins/lock/Service.qml:445`], locking after 300 s idle (`config/omarchy/shell.json`) [V]. Under ext-session-lock, the compositor shows only lock surfaces, so a layer-shell OSK will not appear on the lock screen [U, from the protocol design]. → On the frame: **disable idle lock** (`omarchy-toggle-idle` / set `idle.lock` off), or add a touch PIN pad inside the lock QML.
4. **Autologin**: SDDM `[Autologin]` drop-in (`/etc/sddm.conf.d/autologin.conf`, same format Omarchy writes [V]) or replace SDDM with getty autologin → `uwsm start`.
5. **Touch-friendly Hyprland Lua profile** (copy `omarchy-arm`'s Pi profile idea): animations/blur/shadows off for llvmpipe; larger `gaps`/border grab area; `input.touchdevice.transform`/`output` mapping for the 1280x800 panel (Fydetab did this for their DSI panel [D]).
6. **Bigger targets**: bar height and menu font scale via Omarchy's shell settings — or a scale of 1.25 on 1280x800 [U].

---

## Port plan — fork `omarchy-armv7`

### Approach

Fork **upstream `basecamp/omarchy` `quattro`** (not v3, not omarchy-arm). Add an `armv7` platform the upstream way. Install onto a live ALARM armv7h system (no ISO), borrowing `omarchy-arm`'s `install.sh` and manifests. Leave the boot chain (U-Boot + kernel from agent 02) alone.

### Edits to the Omarchy repo

1. `bin/omarchy-hw-platform`: add a branch — `armv7l` → print `armv7` (optionally `armv7-allwinner` via device tree `allwinner,sun8i-a33`). Allow `armv7` in the image-manifest regex and contradiction check.
2. `bin/omarchy-hw-armv7` (new predicate). Update `bin/omarchy-update-keyring:28` to include armv7 for `archlinuxarm-keyring`.
3. `bin/omarchy-pkg-defaults`: add `armv7) lists=(base armv7)`; and apply an `omarchy-armv7-excludes.packages` filter (like the x86_64-only filter).
4. New `install/omarchy-armv7.packages` (adds `zram-generator pipewire-pulse firefox wvkbd`) and `install/omarchy-armv7-excludes.packages` (the (c)+(d) rows above).
5. `install/helpers/pacman.sh`: `armv7` → `default/pacman/armv7/`, default channel = our own. New `default/pacman/armv7/pacman-<ch>.conf` + mirrorlist: `[core] [extra] [alarm] [aur]` from `mirror.archlinuxarm.org/$arch/$repo`, plus **our** `[omarchy-armv7]` repo for the packages we build. No `[multilib]`.
6. `install/post-install/pacman.sh`: treat `armv7` like generic aarch64 (ALARM keyring, init/populate).
7. Gate x86/boot leaves: `install/config/snapper.sh` (no snapper), `install/config/docker.sh`, `firewall.sh` docker rules, `install/hardware/all.sh` x86 leaves (copy `run_logged_x86` from omarchy-arm), `omarchy-refresh-limine`, `omarchy-hibernation-*`, `omarchy-system-factory-reset` (btrfs-only).
8. Register `armv7` in `bin/omarchy-lifecycle-dispatch` as a no-op (generic) platform, or with a tiny `omarchy-frame-boot` package later.
9. `install/user/chromium.sh` → skip; set Firefox as default in `default/applications/mimeapps.list` on armv7; teach `omarchy-launch-webapp` a Firefox path (happybigmtn).
10. `config/hypr/xdph.conf`: comment out the share-picker line.
11. `default/hypr/platform/armv7.lua`: animations/blur/shadows/rounding off (llvmpipe), touch device mapping, hyprgrass gestures, wvkbd autostart hidden (`wvkbd-mobintl --hidden`).
12. Shell config: idle lock off by default on the frame; bigger bar.
13. Port from omarchy-arm: `install.sh` (live install, `--dry-run`), `install/arm/seed-home.sh`, `keyring.sh`, `pacman.sh`, migration tolerance, screensaver fix. Change its guard from `aarch64` to `armv7l`.
14. Drop theme intro videos from the package (215 MB of mp4 [V]) or ship them as an optional `omarchy-theme-videos` package.

### Packages to build ourselves (armv7h repo `[omarchy-armv7]`)

| package | how | effort |
|---|---|---|
| omarchy, omarchy-settings | Omarchy PKGBUILDs, add `armv7h` to `arch=()`; settings: make `plymouth` optional if ALARM lacks it | low |
| omarchy-keyring, ttf-jetbrains-mono-nerd-basic, yaru-icon-theme, ttf-ia-writer, xdg-terminal-exec, ufw-docker | `any` packages — rebuild or just add to repo | trivial |
| quickshell (+ cpptrace if missing) | Omarchy PKGBUILD (cmake/ninja, Qt6) | medium: C++/Qt build; do on a build host |
| mise-bin (armv7h) | wrap upstream `mise-…-linux-armv7.tar.xz` | trivial |
| yay | AUR (Go) | low |
| wvkbd | AUR (C) | trivial |
| hyprgrass | meson against the exact hyprland package headers | low–medium; rebuild on every Hyprland bump |
| hyprland (optional) | ALARM recipe + Omarchy `software-renderer.patch` | medium |
| tzupdate, ttfx, omacalc, omawrite, omasnap, owe (optional) | Omarchy PKGBUILDs | low–medium each |

Build host: an x86_64 machine with an armv7h chroot under `qemu-user-static` (slow but simple), or a Pi 4/5 running ALARM armv7h natively [U]. Do **not** compile Qt/Rust on the A33 itself (1 GB RAM; omarchy-arm already learned to keep AUR builds off by default [D]).

### Size estimate (root filesystem) [UNCONFIRMED — rough sums of typical Arch installed sizes; measured anchors marked D]

| block | frame-sized Omarchy | "everything available on armv7h" |
|---|---|---|
| ALARM base + kernel modules + only-needed firmware | 0.6–0.9 GB | 1.2 GB (full linux-firmware) |
| Mesa + LLVM libs (llvmpipe) | 0.25 GB | 0.25 GB |
| Qt6 runtime (base, declarative, wayland, svg, imageformats) | 0.15 GB | 0.2 GB |
| Hyprland + hypr libs + Xwayland + portals + uwsm + Quickshell | 0.1 GB | 0.1 GB |
| GTK3/4 stack (pulled by portals, keyring, nautilus…) | 0.1 GB | 0.3 GB |
| PipeWire, NetworkManager, BlueZ, avahi, ufw | 0.1 GB | 0.15 GB (+cups ~0.1) |
| Fonts (noto, emoji, JetBrains) | 0.13 GB | 0.45 GB (+noto-cjk) |
| Media (mpv, imv, ffmpeg, imagemagick) | 0.15 GB | 0.25 GB (+tesseract, libvips) |
| Python/Ruby/Lua runtimes | 0.1 GB | 0.15 GB |
| CLI set (git, btop, eza, bat, fd, rg, fzf, starship…) | 0.1 GB | 0.2 GB (+neovim, lazygit) |
| Omarchy payload (bin/shell/config/themes) | 0.08 GB (no videos) | 0.3 GB (with 215 MB videos [V]) |
| Firefox | 0.27 GB [D 272 MiB] (optional) | 0.27 GB |
| LibreOffice | — | 0.41 GB [D 406 MiB] |
| Docker (+buildx/compose) | — | 0.2 GB [D docker 114 MiB] |
| base-devel | — | 0.25 GB |
| pacman cache, logs, headroom | 0.3 GB | 1 GB |
| **Total** | **~2.5–3.5 GB** | **~5–6 GB** |

Both fit a 16 GB eMMC (~14.5 GiB usable, less any kept Android/recovery partitions). Upper anchor for comparison: the full x86_64 Omarchy VM image is "a 4 to 5 GB download" (`omarchy-iso/README.md`) [V]. A 1–2 GB zram swap costs RAM, not disk.

---

## Risks

1. **GPU (biggest).** Hyprland needs GLES ≥3.0 [V]. Mali-400/lima is GLES 2.0. Only Mesa llvmpipe can run it → every frame is CPU-rendered on 4x Cortex-A7. Quickshell (Qt Quick) and Firefox also render on the CPU. Expect low FPS; static photo display may still be fine [U]. GPU agent must confirm. If llvmpipe is too slow, "full native Omarchy" is not reachable on this SoC; a GLES2 compositor (e.g. sway/labwc with wlroots GLES2 or pixman renderer) + Omarchy theming would be the fallback [U].
2. **RAM.** 1 GB with Hyprland + Quickshell (+ SDDM's own Hyprland greeter) + PipeWire + Firefox. Use autologin without greeter, zram (check zstd in the A33 kernel), no browser at idle [U].
3. **armv7h is ALARM's lagging architecture.** Qt pages show mixed versions (qt6-base 6.10.0 vs qt6-wayland 6.12.0) [D]; SDDM last built Jan 2025 [D]; Chromium dropped [V]. A partial upgrade can break Qt ABI. Pin and test updates.
4. **Quickshell on 32-bit is untested by anyone I could find** [UNCONFIRMED null — no armv7h package, no report]. Possible 64-bit assumptions in Quickshell or cpptrace.
5. **Hyprland 0.56 armv7h build is untested on hardware by us.** ALARM publishes it [D]; whether it starts on sun4i-drm (display) + llvmpipe (render) is for the GPU agent. Omarchy's llvmpipe-detection patch exists because KMS can be display-only [V patch comment].
6. **Upstream churn.** Omarchy `quattro` has hundreds of branches and moves daily (`git ls-remote`) [V]. Pin a release tag (v4.0.4) and rebase deliberately. `omarchy update` assumes Omarchy's pacman layout and was untested on ARM even by omarchy-arm [D].
7. **Silent half-installs.** omarchy-arm's lesson: a compositor with no `omarchy-*` on PATH, or a user with no seeded config, starts "fine" with a clean log [D]. Verify by checking `hyprctl configerrors`, `hyprctl binds | wc -l`, and that the bar is up.
8. **Touch lock-out.** Idle lock + OSK under session-lock = no way to type the password [U]. Disable lock first. hyprgrass can make touch unusable until unloaded [V README].
9. **Plymouth / omarchy-settings dep** may not exist on armv7h [U]; patch the dependency.
10. **Bootloader assumptions.** Limine/UKI/LUKS/btrfs/snapper are baked into v4's ISO, `omarchy` x86 deps and several `bin/` tools [V]. All must stay gated off for a U-Boot board; factory reset and snapshots will not exist (same as Fydetab [D]).

---

## Sources

Local clones (all under `/tmp/claude-0/-home-user-EvenMic/63f83b92-da7d-5160-aa2f-bd1e6d9245ac/scratchpad/repos/`):
- `basecamp_omarchy/` (github.com/basecamp/omarchy, `quattro` @ defbf90e): `AGENTS.md`, `install/*.packages`, `install/*/all.sh`, `bin/omarchy-hw-platform`, `bin/omarchy-pkg-defaults`, `bin/omarchy-apply-system`, `bin/omarchy-provision-owner`, `bin/omarchy-upgrade-to-quattro`, `install/helpers/pacman.sh`, `install/post-install/pacman.sh`, `default/pacman/`, `docs/file-layout.md`, `docs/lifecycle-dispatch.md`, `docs/omarchy-shell.md`, `config/hypr/hyprland.lua`, `etc/sddm.conf.d/`, `shell/plugins/lock/Service.qml`, `config/omarchy/shell.json`.
- `omarchy-v3.8.4/`: `boot.sh`, `install.sh`, `install/preflight/guard.sh`, `install/login/limine-snapper.sh`, `install/omarchy-base.packages`.
- `omacom_omarchy-pkgs/` (github.com/omacom/omarchy-pkgs): `README.md`, `pkgbuilds/{omarchy,omarchy-settings,hyprland,quickshell,…}/PKGBUILD`, `pkgbuilds/hyprland/software-renderer.patch`.
- `omacom_omarchy-iso/`: `README.md`, `builder/archinstall.packages`, `configs/airootfs/root/configurator`, `plans/aarch64-support.md`.
- `hotschmoe_omarchy-arm/` (github.com/hotschmoe/omarchy-arm = github.com/alexisraitano-myffu/omarchy-arm, branch `arm64`): `docs/arm64-port.md`, `install.sh`, `install/arm/*`.
- `happybigmtn_omarchy-arm-fixes/`: `README.md`, `patches/*`.
- `hyprgrass/` (github.com/horriblename/hyprgrass): `README.md`, `hyprpm.toml`, `docs/lua_migration.md`, `docs/configuration.md`.
- `wvkbd/` (github.com/jjsullivan5196/wvkbd): `README.md`, `Makefile`, `main.c`.
- `alarm-pkgbuilds/` (github.com/archlinuxarm/PKGBUILDs, read-only): `README.md` (buildarch bitmask), `extra/chromium/PKGBUILD` (`buildarch=8`), `extra/firefox/PKGBUILD:172-178`.
- `Hyprland/` (github.com/hyprwm/Hyprland main, 0.56.0): `src/render/OpenGL.cpp:205-226`, `src/render/shaders/`.

AUR PKGBUILDs via the GitHub mirror `https://raw.githubusercontent.com/archlinux/aur/<pkg>/PKGBUILD`: yay, xdg-terminal-exec, mise-bin, wvkbd, ufw-docker, gum, bluetui, impala, lazydocker, squeekboard, localsend-bin, satty, swayosd-git, walker-bin, elephant-bin.

Web:
- [mise release v2026.10.8 assets](https://github.com/jdx/mise/releases/expanded_assets/v2026.10.8) — linux-armv7 binaries.
- [Fydetab Duo Omarchy release v0.1.5](https://github.com/Linux-for-Fydetab-Duo/imagebuild/releases/tag/prod-omarchy-v0.1.5); [FydeOS forum post](https://community.fydeos.io/t/topic/43275).
- ALARM package pages (search snippets only; site DNS-blocked here): [hyprland armv7h](https://archlinuxarm.org/packages/armv7h/hyprland), [firefox armv7h](https://archlinuxarm.org/packages/armv7h/firefox), [qt6-declarative armv7h](https://archlinuxarm.org/packages/armv7h/qt6-declarative), [qt6-wayland armv7h](https://archlinuxarm.org/packages/armv7h/qt6-wayland), [qt6-base armv7h](https://archlinuxarm.org/packages/armv7h/qt6-base), [jemalloc armv7h](https://archlinuxarm.org/packages/armv7h/jemalloc), [waybar armv7h](https://archlinuxarm.org/packages/armv7h/waybar), [mako armv7h](https://archlinuxarm.org/packages/armv7h/mako), [sddm armv7h](https://archlinuxarm.org/packages/armv7h/sddm), [uwsm any](https://archlinuxarm.org/packages/any/uwsm), [foot-terminfo armv7h](https://archlinuxarm.org/packages/armv7h/foot-terminfo), [libreoffice-fresh armv7h](https://archlinuxarm.org/packages/armv7h/libreoffice-fresh), [docker armv7h](https://archlinuxarm.org/packages/armv7h/docker), [nautilus armv7h](https://archlinuxarm.org/packages/armv7h/nautilus), [hyprland-guiutils armv7h](https://archlinuxarm.org/packages/armv7h/hyprland-guiutils), [xdg-desktop-portal-hyprland armv7h](https://archlinuxarm.org/packages/armv7h/xdg-desktop-portal-hyprland), [quickshell aarch64](https://archlinuxarm.org/packages/aarch64/quickshell), [chromium aarch64](https://archlinuxarm.org/packages/aarch64/chromium), [squeekboard aarch64](https://archlinuxarm.org/packages/aarch64/squeekboard), [hyprlock aarch64](https://archlinuxarm.org/packages/aarch64/hyprlock), [plymouth aarch64](https://archlinuxarm.org/packages/aarch64/plymouth).
- Hyprland Lua in 0.55: [hypr.land news](https://hypr.land/news/26_lua/), [linuxiac](https://linuxiac.com/hyprland-0-55-brings-lua-configs-and-user-defined-layouts/), [wiki 0.55 Configuring](https://wiki.hypr.land/0.55.0/Configuring/Start/).

Not reachable from here (DNS/proxy): archlinuxarm.org, aur.archlinux.org, archlinux.org, pkgs.omarchy.org, arm-mirror.omarchy.org, api.github.com for non-attached repos. Every ALARM availability claim above is therefore a search snippet [D] or an inference [U] — **confirm with `pacman -Si` in an armv7h chroot before building the manifests.**
