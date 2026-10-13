# Live frame desktop setup

This is the small, repeatable setup for the SD-card desktop. It uses Omarchy `quattro` pinned at `defbf90e893e741067e48f4a27d2ec694c71358e`, copied into `/home/frame/.local/share/omarchy`. It does not install an upstream ISO or write the eMMC.

Prerequisites: the boot card from `image/` and the tested AIC8800 modules and firmware. `bootstrap.sh` installs and enables `pf-hyprland.service`. Keep the kernel at `7.2.10-1-armv7-ARCH`; the panel and Wi-Fi modules were built for that version.

Primary path (fetches pinned Omarchy, seeds config, runs apply):

```sh
COPYFILE_DISABLE=1 tar --no-xattrs -C port/frame -cf - . | ssh -F image/secrets/ssh_config frame 'mkdir -p ~/frame-desktop-setup; tar -xf - -C ~/frame-desktop-setup; bash ~/frame-desktop-setup/bootstrap.sh'
```

Direct path (Omarchy tree already present):

```sh
COPYFILE_DISABLE=1 tar --no-xattrs -C port/frame -cf - . | ssh -F image/secrets/ssh_config frame 'mkdir -p ~/frame-desktop-setup; tar -xf - -C ~/frame-desktop-setup; bash ~/frame-desktop-setup/apply.sh'
```

Package downloads use direct Wi-Fi. For USB-recovery bring-up only, an existing
`ALL_PROXY` environment variable is passed through to pacman; it is never saved.
The installer does not require a reverse SOCKS tunnel.

```sh
ALL_PROXY=socks5h://127.0.0.1:1080 bash ~/frame-desktop-setup/apply.sh
```

The script adds Qt's image decoders, NetworkManager, PipeWire/WirePlumber, the terminal launcher, desktop icons, icon font, and the keyboard service. NetworkManager leaves `usb0` unmanaged so systemd-networkd keeps USB recovery access. The verified Wi-Fi modules load at boot. Wi-Fi credentials are entered on the frame; the script stores none.
It also installs `woff2-font-awesome`, suspend masks, `pf-health-check`, a pacman guard hook, and an Omarchy helper guard. See `armv7-packages.txt` for the tested set.

It also installs an armv7-friendly everyday app set: Firefox, Nautilus, MPV, imv, Noto and emoji fonts, Fastfetch, btop, ripgrep, and lightweight terminal/screenshot tools (`bat`, `eza`, `fd`, `fzf`, `tldr`, `tmux`, `slurp`). Chromium is not packaged for this Arch Linux ARM armv7 repository. Omarchy itself has no armv7 default package manifest, so do not run its upstream bulk reinstall command on this frame.

The Omarchy Agents panel is included with the pinned shell, but Claude Code is
not available on this machine. Anthropic's native Linux package supports x64
and arm64, not 32-bit armv7. `patch-platform.py` makes the launcher explain
that limitation instead of trying the unavailable `mise` installer.

## YouTube

The installer adds the tested extractor and player helper. To reinstall the
extractor or play a video:

```sh
pf-install-yt-dlp
pf-youtube 'https://www.youtube.com/watch?v=VIDEO_ID'
```

The helper uses the pinned `yt-dlp` 2026.08.19 release and asks YouTube for an
H.264/AAC stream at 480p or below, avoiding expensive VP9 software decoding.
An eight-second 480p MPV playback test passed on 2026-10-13. The frame's
speaker remains unfinished, so the current proof is video-only.

The keyboard button uses a local Omarchy plugin, `frame.keyboard`. It runs `pf-keyboard-toggle`, which starts the Squeekboard user service and toggles its D-Bus `Visible` property. The user autostart file imports the Wayland display before starting the keyboard service. No polling is used.

Omarchy's own `bt-agent` user service supplies BlueZ pairing. The custom ARM setup must install `bluez-tools` and copy Omarchy's unit into the user configuration; the normal upstream image provisioning does that automatically.

Text size is set to 18 through Omarchy's own display command; that override survives theme changes. Idle locking is disabled with Omarchy's stay-awake setting. The panel uses monitor transform 3 and touch transform 6, measured in E050.

The display tune uses a 1.25× compositor scale with 1× GTK scale, while retaining transform 3, and disables Hyprland animations. This gives a 640×1024 logical workspace and reduces composition work on the Mali-400. The scripts retain one local `.before-frame-performance` backup beside each changed configuration file.

`patch-platform.py` changes only the live architecture result to `armv7`. Upstream's unmodified detector wrongly reports `x86` on this machine. `armv7-packages.txt` lists the tested set. `guard-updater.py` blocks bulk reinstall helpers plus kernel and chromium transactions. Do not run the upstream full installer or updater on this experimental image. Missing desktop apps and video-intro tooling are not included in this setup.

Bluetooth stays opt-in: `sudo wifi/install-uart-bluetooth.sh --activate` creates the `full-bluetooth` label from `full`, installs the probe plus attach helpers and the service, and sets it as default. Rollback is `sudo wifi/install-uart-bluetooth.sh --rollback`. Use `pf-health-check` on the frame for temp, RAM, failed units, and guard state.

Checks and device measurements are in `docs/experiments.md`. Bluetooth work is separate, in `docs/bluetooth.md` and `wifi/`.

The live frame now uses the separate `full-bluetooth` boot label. Its permanent UART service uses the normal Wi-Fi firmware and a helper that fixes the packaged BlueZ attach tool's baud-rate problem. Desktop, Wi-Fi internet/reconnect and Bluetooth LE discovery passed after a reboot. The original `full` label and DTB remain untouched for rollback. The generic image build does not yet include all these live changes; preserve the working SD card.

Because this is a source-backed Omarchy setup, `patch-first-run.py` disables
the package-oriented first-run task in the copied Omarchy defaults. It otherwise
retries on every login after looking for missing package-owned user units, which
creates duplicate welcome and update notifications. `apply.sh` starts the
frame's keyboard, Bluetooth, PipeWire, and WirePlumber services explicitly.
