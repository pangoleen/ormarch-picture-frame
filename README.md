# Omarchy on the PF1007L photo frame

This repository recreates the working SD-card installation of Omarchy on a
PF1007L-based 10.1-inch photo frame: Arch Linux ARM `armv7h`, Hyprland on the
Mali-400 GPU, touch input, Wi-Fi, and Bluetooth LE peripherals.

The live configuration has been tested on the frame described below. A freshly
built card from this repository remains a device-specific hardware test; the
original image-build validation was performed in QEMU. Keep the original card
and firmware backup before trying it.

It has been tested on the Humblestead HM-PF1007-BK / EFERCRO PF1007L board
with an Allwinner A33, 1 GB RAM, a native 800x1280 DSI panel, Silead touch,
and AIC8800DC Wi-Fi/Bluetooth. It is hardware-specific, experimental, and
does **not** support installing to eMMC. Keep the original card and a verified
backup before starting.

## What works

- Booting the custom Arch Linux ARM image from microSD.
- Hyprland and the pinned Omarchy `quattro` source on the Mali-400 renderer.
- Rotated display, calibrated touch, touch keyboard, Wi-Fi, PipeWire, Firefox,
  file manager, image/video viewers, and standard Omarchy Bluetooth pairing.
- Native Bluetooth LE over UART1. A mouse and keyboard have been paired on the
  tested frame. Classic Bluetooth is not verified.

## Deliberate limits

- The Agents button is present because it comes from Omarchy. Claude Code
  cannot be installed on this frame: its current native Linux releases support
  x64 and arm64, but not 32-bit armv7. The frame overlay reports that clearly
  instead of attempting Omarchy's unavailable `mise` installer.
- This is a source-backed Omarchy installation, rather than the upstream x86
  package. The installer skips its package-only first-run routine and enables
  the frame services directly, avoiding repeating welcome/update notifications.
- YouTube is supported through the tested 480p-or-lower H.264 path. The
  installer adds `pf-youtube <URL>` and a pinned user-local extractor. The
  speaker still needs its separate device-tree bring-up, so this currently
  verifies video rather than frame audio.

## Reinstall path

The project deliberately separates the boot image from desktop provisioning.
That makes it possible to return to the known-good `full` boot label if a
desktop or Bluetooth change fails.

1. On macOS, install `git`, `curl`, Docker Desktop or OrbStack, Python 3, and
   Xcode Command Line Tools. Extract the matching proprietary touch firmware
   from the frame's original Android backup as described in
   [the firmware-input guide](image/vendor/README.md). Then clone this
   repository and build the image:

   ```sh
   export PF1007L_TOUCH_FIRMWARE=/path/to/gsl_m86_hd.fw
   image/build.sh
   ```

   The builder recreates the pinned kernel and AIC8800 Wi-Fi artifacts when
   they are absent. The touch firmware is intentionally the only non-Git
   input.

2. Write `image/out/pf1007l-sd.img` to a spare microSD card using the guarded
   writer described in [the image guide](image/README.md). It refuses the
   PF1007L eMMC size and checks the card after writing.

3. Boot the card and use the USB gadget/serial recovery link described in the
   image guide. Once the `full` label is working and the frame has network
   access, clone this repository onto the frame and run:

   ```sh
   bash port/frame/bootstrap.sh
   ```

   The script fetches exactly Omarchy `quattro`
   `defbf90e893e741067e48f4a27d2ec694c71358e`, installs the compatible
   armv7 packages, creates the normal Omarchy user configuration, and applies
   the frame overlay. Reboot when it finishes.

4. Bluetooth is opt-in. After the desktop has booted successfully, run
   `sudo wifi/install-uart-bluetooth.sh --activate` and reboot. The script
   keeps the original `full` label intact; rollback is `sudo pf-bootsel full`
   followed by `sudo systemctl disable --now pf-bluetooth-uart.service`.

Wi-Fi passwords, SSH keys, full storage backups, vendor firmware blobs, and
generated images are excluded from Git. Enter Wi-Fi credentials locally in
the Omarchy network panel.

## Project layout

- [`image/`](image/README.md): reproducible SD-card image and guarded macOS
  card writer.
- [`port/frame/`](port/frame/README.md): Omarchy desktop bootstrap and the
  display, touch, keyboard, and performance overlay.
- [`wifi/`](wifi/README.md): AIC8800 Wi-Fi and the optional UART Bluetooth
  integration.
- [`docs/`](docs/experiments.md): measured hardware evidence and limits.

Read [the frame restore guide](docs/reinstall.md) before using a different
PF1007L variant. The kernel, panel DTB, Wi-Fi modules, and firmware are pinned
to `7.2.10-1-armv7-ARCH`; do not run a normal kernel upgrade.

## License

Original scripts, configuration, and documentation in this repository are
released under the [MIT License](LICENSE). Upstream software and any firmware
remain under their own licenses.
