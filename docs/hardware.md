# PF1007L hardware status

This page separates hardware confirmed in the preserved Android firmware from
what the SD Linux image currently exposes. It is not an instruction to enable
unfinished device-tree nodes on a daily-use frame.

| Feature | Hardware evidence | Linux status | Next safe step |
| --- | --- | --- | --- |
| Speaker | Android plays through the A33 codec. The vendor `[audio0]` configuration sets the speaker-amp enable to PH09. | **Working (E062).** Label `full-audio`. The mixer switch `AIF1 Slot 0 Digital DAC Playback Switch` must be on, or playback fails with an I/O error. `pf-speaker-amp.service` drives PH09 while audio plays. | Tune the volume range. Hide the unused capture device in the desktop. |
| Accelerometer | Vendor config puts it on I2C1 at `0x19`, interrupt PB06. Android names it `sc7a20 detect Accelerometer`. | **Working (E062).** `pf-autorotate` (user service) rotates the output and the touch panel. Upright landscape reads x ≈ −1000 (monitor transform 3, touch 6). | Confirm the upside-down and the two portrait rows by hand; the portrait direction is a guess. |
| Ambient light | Behind the front hole. It is an analog part on the A33 key-voltage converter (LRADC0); the vendor module `sunxi-keyboard.ko` reports it as the input device `lightsensor`. The `[ls_para]` I2C keys in the vendor config are unused template text. | **Working (E064).** Raw value 0–2 with the hole covered, 60–62 in a lit room. `pf-auto-brightness.service` reads it and sets the backlight. The mainline key driver for that pin must stay off (`pf1007l-lradc.conf`, `pf1007l-light-sensor.dtso`): it reads darkness as a held volume key and floods the desktop with volume scripts. | Record values in daylight and tune the level table. |
| Touch | Silead GSL at I2C0 `0x40`. | Working. | None. |
| Thermal | A33 thermal block. | Working through Linux thermal/IIO. | None. |
| Buttons | AXP power key and LRADC input. | Present. | Map only after identifying desired actions. |
| Internal Wi-Fi | AIC8800 SDIO radio. | Working at 2.4 GHz. | None. |
| Microphone | The vendor config has microphone volume keys, but the stock firmware does not declare the microphone feature. | None found: MIC1, MIC2 and Line In recorded only noise at maximum gain while the speaker played a 1 kHz tone (E062). | None. |
| Camera | Vendor config lists a `gc2035` on I2C2 with `vip_used = 0`; every camera driver line in the stock init script is commented out. | Not tested under Linux. | Look into the front hole: a lens is visible as dark glass. |
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
