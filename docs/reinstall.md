# PF1007L restore guide

This guide restores the tested microSD installation. It never writes the
frame's eMMC. Keep a second card and the original card available for recovery.

## Before writing a card

The repository contains source and build instructions, not an image or keys.
It also does not contain the proprietary Silead touch firmware. Extract it
from the matching original Android card or backup with the tracked helper in
[the firmware-input guide](../image/vendor/README.md), then run
`image/build.sh` from a macOS host with Docker or OrbStack. The build
creates a new SSH key pair in `image/secrets/`; it is local to that card and is
intentionally ignored by Git.

Use the exact byte count reported by `diskutil info diskN` with the guarded
writer. For example:

```sh
python3 -I image/tools/write-card.py check disk4 31914983424
sudo python3 -I image/tools/write-card.py write disk4 31914983424
```

The writer refuses internal disks, non-removable media, the measured eMMC
size, and the project's FEL recovery card. It reads the written image back and
compares its SHA-256 before ejecting the card.

## Desktop bootstrap

The base image provides USB recovery, the exact kernel, the panel device tree,
touch firmware, and AIC8800 Wi-Fi modules. First prove that its `full` boot
label is usable. Then join Wi-Fi using the local panel or USB recovery link.

On the frame as user `frame`, clone this repository and run:

```sh
git clone https://github.com/pangoleen/ormarch-picture-frame ~/omarchy-frame
cd ~/omarchy-frame
bash port/frame/bootstrap.sh
```

`bootstrap.sh` deliberately refuses to overwrite an existing Hyprland user
configuration. It clones the exact upstream Omarchy commit, seeds the standard
user configuration, and invokes `apply.sh`. The latter installs only packages
that exist in the tested armv7h repository; it does not run Omarchy's upstream
ISO installer or updater.

Restart the frame after completion. The expected session has a 1.25 display
scale, transform 3, touch transform 6, animations disabled, and an onscreen
keyboard button in the bar. Omarchy is source-backed on this platform, so do
not remove `~/.local/share/omarchy`.

## Bluetooth

The tested AIC8800 firmware exposes a Bluetooth LE UART controller. The
desktop setup installs BlueZ and Omarchy's normal pairing agent, but it does
not change the boot DTB automatically. After a successful desktop reboot:

```sh
cd ~/omarchy-frame
sudo wifi/install-uart-bluetooth.sh --activate
sudo reboot
```

This creates a `full-bluetooth` label from the untouched `full` label, enables
the verified service, and selects it for the next boot. If a boot fails, use
USB recovery and run:

```sh
sudo pf-bootsel full
sudo systemctl disable --now pf-bluetooth-uart.service
sudo reboot
```

More evidence and the known LE-only limitation are in
[Bluetooth](bluetooth.md).

## Hardware still being brought up

Touch, Wi-Fi, Bluetooth LE, the panel backlight, and thermal monitoring work
in the tested image. The speaker, accelerometer-based rotation, and automatic
ambient-light dimming are real frame hardware but are not enabled by this
installer yet. Their documented evidence and safe next tests are in
[hardware status](hardware.md).
