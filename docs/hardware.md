# PF1007L hardware status

This page separates hardware confirmed in the preserved Android firmware from
what the SD Linux image currently exposes. It is not an instruction to enable
unfinished device-tree nodes on a daily-use frame.

| Feature | Hardware evidence | Linux status | Next safe step |
| --- | --- | --- | --- |
| Speaker | Android plays through the A33 codec. The vendor `[audio0]` configuration sets the speaker-amp enable to PH09. Wes Bos independently recorded a working PF1007L speaker. | No ALSA card yet. | Create an audio-only DTB from the known-good Bluetooth DTB. Do not use a PH09 GPIO hog; its previous test disrupted the SD-root boot. |
| Accelerometer | Vendor config puts it on I2C1 at `0x19`, interrupt PB06. Android names it `sc7a20 detect Accelerometer`. | Confirmed: the stock `st-accel-i2c` driver created `iio:device1` (`sc7a20`) and returned all three raw axes in the 2026-10-13 test boot. | Calibrate the axes for the frame's physical orientation, then add an orientation service with automatic rollback. |
| Ambient light | Android ships a light-sensor HAL and declares the Android light-sensor feature. The vendor config reserves I2C1 `0x23`, PB07 and the LTR-501ALS detector; the original image also contains `ltr_501als.ko` for the LTR-558ALS family. | No Linux device is bound. The saved vendor configuration sets `ls_used = 0`; on 2026-10-13 the LTR ID and status registers at `0x23` returned no response. | Trace the sensor power/enable path and verify the physical chip's address before adding the mainline LTR-501 binding. |
| Touch | Silead GSL at I2C0 `0x40`. | Working. | None. |
| Thermal | A33 thermal block. | Working through Linux thermal/IIO. | None. |
| Buttons | AXP power key and LRADC input. | Present. | Map only after identifying desired actions. |
| Internal Wi-Fi | AIC8800 SDIO radio. | Working at 2.4 GHz. | None. |
| Internal Bluetooth | AIC8800 UART controller. | Working for LE HID pairing. | Keep the installed `full-bluetooth` label. |

## 5 GHz Wi-Fi

The internal radio does not expose a 5 GHz band: the live Linux PHY lists only
2.4 GHz channels. This cannot be changed by a package, firmware setting, or
Omarchy service. A powered USB 5 GHz adapter could be investigated later, but
would require separate USB-host and power work because the current port is
used for the USB recovery gadget.

## Original firmware evidence

Private preserved files remain outside Git because they can contain device
identifiers and network credentials. The relevant public-safe observations
come from the vendor configuration and extracted metadata:

- `[audio0]`: `audio_used = 1`, `audio_pa_ctrl = PH09`.
- `[gsensor_para]`: bus 1, address `0x19`, interrupt PB06; the enabled
  detector list includes `sc7a20`.
- `[ls_para]`: bus 1, address `0x23`, interrupt PB07; the detector list
  includes `ltr_501als`. Its `ls_used` flag is `0`.
- Android's `sensors.exdroid.so` recognizes `sc7a20 detect Accelerometer`
  and a LTR light sensor; `lights.astar.so` controls panel backlight through
  `/dev/disp`.
- The original `/vendor/modules/ltr_501als.ko` identifies itself as an
  LTR-558ALS driver and says it requires `ls_used = 1`.

The LTR read-only probe used the standard `PART_ID` (`0x86`),
`MANUFAC_ID` (`0x87`) and status (`0x8c`) registers at I2C address `0x23`.
All three reads failed, so no driver node is enabled in the Linux image.

The accelerometer test returned `x = -1037`, `y = 65`, `z = 265` at its
observed resting position with the 2g scale selected. These values prove the
IIO data path; they are not yet an axis map for automatic rotation.

The detailed private analysis is intentionally ignored by `.gitignore`.
