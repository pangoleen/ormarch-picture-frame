#!/usr/bin/env python3
"""Make the build-L source edits in a U-Boot tree (v2025.10 + Wes Bos's patch).

Used one time to generate 0002-pf1007l-linux-boot.patch. build.sh applies the
patch, not this script. Each edit must match exactly one place, or the script stops.
"""
import sys, pathlib
root = pathlib.Path(sys.argv[1]); here = pathlib.Path(__file__).parent

def edit(path, old, new):
    p = root / path; s = p.read_text()
    if s.count(old) != 1:
        sys.exit(f"STOP: {path}: expected 1 match, found {s.count(old)}")
    p.write_text(s.replace(old, new))

# 1. A Kconfig switch: do not connect the console UART to any pin.
edit("arch/arm/mach-sunxi/Kconfig", "config UART0_PORT_F\n",
"""config SUNXI_CONSOLE_NO_PINMUX
	bool "Do not set a pin mux for the console UART"
	select SYS_CONSOLE_IS_IN_ENV
	select SYS_DEVICE_NULLDEV
	---help---
	The SPL normally switches two pins to the console UART selected by
	CONFIG_CONS_INDEX. With this option it leaves every pin as it is.
	The UART still runs, but its output reaches no pin. Use this on a
	board where each possible console pin has another function (PF1007L:
	PL2 = Wi-Fi chip enable, PB0/PB1 = keys, PG6/PG7 = Bluetooth UART,
	PF2/PF4 = SD card). The device tree must not give the console UART a
	pinctrl property either.
	With no pins there is no console input: the default environment sets
	stdin=nulldev, so that nothing on a UART can stop autoboot, a script
	or the ums command.

config UART0_PORT_F
""")
edit("arch/arm/mach-sunxi/board.c",
"""	__maybe_unused uint val;
#if CONFIG_CONS_INDEX == 1 && defined(CONFIG_UART0_PORT_F)
""",
"""	__maybe_unused uint val;
#if defined(CONFIG_SUNXI_CONSOLE_NO_PINMUX)
	/* PF1007L build L: the console UART gets no pins, on purpose. */
#elif CONFIG_CONS_INDEX == 1 && defined(CONFIG_UART0_PORT_F)
""")
# 1b. No console pins -> no console input: stdin is the null device from the start.
edit("include/configs/sunxi-common.h",
"""#ifdef CONFIG_USB_KEYBOARD
#define CONSOLE_STDIN_SETTINGS \\
	"stdin=serial,usbkbd\\0"
#else
""",
"""#if defined(CONFIG_SUNXI_CONSOLE_NO_PINMUX)
/* PF1007L build L: the console UART has no pins, so it gives no input. */
#define CONSOLE_STDIN_SETTINGS \\
	"stdin=nulldev\\0"
#elif defined(CONFIG_USB_KEYBOARD)
#define CONSOLE_STDIN_SETTINGS \\
	"stdin=serial,usbkbd\\0"
#else
""")

# 1c. ums: do not stop on a console CTRL+C or on a host eject.
# Same protection as the diagnostic patch of wesbos/photo-frame-dashboard issue #24
# (project copy: scripts/uboot/wesbos-issue24-ums-diag.diff), which ran 30+ minutes on
# this frame after two runs without it stopped at about 7 minutes. Here it is a build
# option, not an environment variable.
edit("cmd/Kconfig", "config CMD_UMS_ABORT_KEYED\n",
"""config CMD_UMS_NO_ABORT
	bool "UMS: do not stop on console CTRL+C or on host eject"
	depends on CMD_USB_MASS_STORAGE
	help
	  The ums command normally ends when the console receives CTRL+C or
	  when the host sends START STOP UNIT (eject). On a board with a
	  floating console RX pin, noise can look like CTRL+C. With this
	  option ums ends only when the USB cable check fails or on an I/O
	  error.

config CMD_UMS_ABORT_KEYED
""")
edit("drivers/usb/gadget/f_mass_storage.c",
"""			/* Handle START-STOP UNIT */
			if (common->eject)
				return -EPIPE;

			/* Handle CTRL+C */
			if (ctrlc())
				return -EPIPE;
""",
"""			if (!IS_ENABLED(CONFIG_CMD_UMS_NO_ABORT)) {
				/* Handle START-STOP UNIT */
				if (common->eject)
					return -EPIPE;

				/* Handle CTRL+C */
				if (ctrlc())
					return -EPIPE;
			}
""")
edit("drivers/usb/gadget/f_mass_storage.c",
"""		curlun->sense_data = SS_INVALID_COMMAND;
		return -EINVAL;
	}

	common->eject = 1;
""",
"""		curlun->sense_data = SS_INVALID_COMMAND;
		return -EINVAL;
	}

	/* The host's eject is accepted but does not end the ums command. */
	if (IS_ENABLED(CONFIG_CMD_UMS_NO_ABORT))
		return 0;

	common->eject = 1;
""")
edit("cmd/usb_mass_storage.c",
"""			if (ctrlc()) {
				puts("\\rCTRL+C - Operation aborted.\\n");
""",
"""			if (!IS_ENABLED(CONFIG_CMD_UMS_NO_ABORT) && ctrlc()) {
				puts("\\rCTRL+C - Operation aborted.\\n");
""")

# 2. Device tree + configs
edit("arch/arm/dts/Makefile", "\tsun8i-a33-pf1007l-backup.dtb \\\n",
     "\tsun8i-a33-pf1007l-backup.dtb \\\n\tsun8i-a33-pf1007l-linux.dtb \\\n")
(root / "arch/arm/dts/sun8i-a33-pf1007l-linux.dts").write_text((here / "sun8i-a33-pf1007l-linux.dts").read_text())
for c in ("pf1007l_linux_defconfig", "pf1007l_qemu_opipc_defconfig"):
    (root / "configs" / c).write_text((here / c).read_text())
