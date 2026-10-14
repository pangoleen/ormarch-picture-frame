# Audio bring-up and SD recovery — 2026-10-13

**Resolved later the same day (E062):** the speaker works. The failed boots ran out of memory in
user space (hundreds of `omarchy-audio-output-*` processes), and the playback I/O error came from a
closed mixer switch (`AIF1 Slot 0 Digital DAC Playback Switch`). The text below is the record of the
earlier state.

Update after a physical unplug/replug: the frame exposed a writable UMS SD
disk. A small FAT-file write and readback passed. The saved normal `uEnv.txt`
was restored through USB, `DEFAULT full-bluetooth` was verified, and the recovery
disk was safely ejected. A further physical replug is required for Linux boot.
The earlier software restart did not establish a real power reset. The normal
image builder still uses read-only build L; writable recovery has one successful
hardware enumeration/write test and is not yet qualified for default use.

## Recorded state

- Last confirmed healthy Linux boot: `full-bluetooth`, no failed system units.
- SD device was verified as `/dev/mmcblk0`, type `SD`, before the loader write.
- Default boot label remains `full-bluetooth`.
- `/boot/uEnv.txt` was temporarily changed to `pf_mode=ums` for the USB test.
  The exact saved normal file has now been restored over writable USB recovery.
  The forced-test settings were retained separately as `uEnv.txt.forced-ums-test`.
- A complete backup of the original, sector-aligned loader was saved on the SD:
  `/boot/u-boot-pf1007l-L.before-writable-recovery.bin`.
- Exactly 536,576 bytes were written and read back at SD offset 8 KiB. The
  readback matched the transferred writable-recovery payload.
- eMMC was not addressed. Both loader configurations disable the extra MMC slot
  and use `sun8i-a33-pf1007l-linux`, whose eMMC controller is disabled.

Local comparison confirms identical `.config` files and identical first 32 KiB
(including SPL) between the original and writable builds. Both eGON checksums
are valid. These checks establish file integrity, not successful hardware boot.

## Recovery when the physical card is available

1. Insert the Linux microSD in the Mac card reader. Re-identify its whole disk
   and FAT partition with `diskutil list` and `diskutil info`. Do not reuse an
   old disk number. The expected card size is 31,914,983,424 bytes; the device
   must be external, removable and writable, with a PFBOOT FAT partition.
2. Read `/extlinux/extlinux.conf` on that partition and verify
   `DEFAULT full-bluetooth`. Save a backup before correcting it if needed.
3. Restore `/uEnv.txt` from `/uEnv.txt.before-writable-recovery-test` if present.
   Otherwise remove the test's `pf_mode=ums` line. Verify no active `pf_mode=ums`
   override remains. Leave the default recovery policy `auto` in effect.
4. Restore only the SD loader region. The guarded local helper compares the
   current region against the exact known artifacts, saves another backup,
   writes at 8 KiB, and verifies every written byte:

   ```sh
   sudo python3 -I image/tools/switch-ums-recovery.py disable diskN 31914983424
   ```

   Replace `diskN` only after the checks in step 1. If its expected binary does
   not match, stop and inspect the saved SD backup; do not bypass the guard.
5. Safely eject, return the card to the frame and physically reconnect power.
   Confirm `pf.label=full-bluetooth`, SSH connectivity and no failed units.

The helper modifies no partition table, Linux root filesystem or eMMC.

## USB hub caution

The earlier E020 experiment already found that a hub can report port power
`off` without restarting this frame. The later software power-cycle output did
not prove a physical power reset. A blank screen also does not prove the frame
is safely running recovery: it may be hung. Diagnose these states separately.

If hub control is used later, use the exact-location option `-e`, verify the
current frame port first, and establish a real reset from fresh boot markers.
Do not infer a reset from the port status alone.

## Audio evidence and next test

The vendor fex enables internal audio and specifies PH09 for the speaker
amplifier. The standard A33 topology is already in the kernel's SoC DTS.
An isolated overlay enabled only DAI, codec and sound. On one boot it registered
an ALSA card, but playback stalled and returned I/O errors. Subsequent attempts
did not reach SSH reliably. The Vstar routing variant also failed to boot.

PH09 was read live as pin 233, mux and GPIO unclaimed in the stable boot.
No runtime PH09 write was performed. The pin remains a candidate for amplifier
enable only after PCM playback is shown to advance reliably.

Next steps, in order:

1. Physically replug to boot the restored stable entry and capture existing boot markers/logs privately.
2. Determine where an audio-enabled boot stops, using a minimal diagnostic
   boot and individual driver loading if needed. Do not select the failed
   Vstar label again.
3. Separate three hypotheses: early boot/driver failure, PCM clock or DMA
   failure, and a muted amplifier path. An amplifier pin cannot explain a
   failure before user space or by itself prove a PCM transfer problem.
4. Establish continuous PCM progress with a short, local sample and bounded
   diagnostics before changing the amplifier state.
5. Test PH09 only through a reversible runtime GPIO request, at modest volume,
   after verifying ownership again. No GPIO hog is required for this test.

Upstream references:

- [A33 codec binding](https://www.kernel.org/doc/Documentation/devicetree/bindings/sound/sun8i-a33-codec.txt)
- [A33 SoC device tree](https://github.com/torvalds/linux/blob/master/arch/arm/boot/dts/allwinner/sun8i-a33.dtsi)
- [Digital audio interface driver](https://github.com/torvalds/linux/blob/master/sound/soc/sunxi/sun4i-i2s.c)
- [Analog mixer and headphone routes](https://github.com/torvalds/linux/blob/master/sound/soc/sunxi/sun8i-codec-analog.c)

These describe the upstream mechanism. They do not establish which failure
occurred on this frame.
