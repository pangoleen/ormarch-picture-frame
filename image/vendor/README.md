# Required touch-firmware input

The PF1007L image requires the Silead touch firmware from the **same model's
original Android card or firmware backup**. It is proprietary vendor data, so
this repository does not distribute it.

For the tested PF1007L, extract it from the original `gslX680new.ko` module:

```sh
python3 -I image/vendor/extract_gsl_fw.py /path/to/gslX680new.ko --out /tmp/pf1007l-touch
export PF1007L_TOUCH_FIRMWARE=/tmp/pf1007l-touch/gsl_m86_hd.fw
image/build.sh
```

The build verifies the expected SHA-256 before it creates an image. A mismatch
means the donor firmware is not the version tested by this project. Do not add
the extracted `.fw` file to Git.

`extract_gsl_fw.py` reads the ARM ELF module and writes only the selected
`gsl_m86_hd` table in the format used by Linux's Silead driver.
