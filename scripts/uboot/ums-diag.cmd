# PF1007L build F: read-only USB disks + diagnostics from wesbos/photo-frame-dashboard issue #24.
# The console log goes to SRAM A2 (0x48000, 16 KiB) and survives a reset: read it over FEL.
setenv ums_ignore_ctrlc 1
setenv ums_ignore_eject 1
# Arm the A33 hardware watchdog: 16 s, whole-system reset. Only the ums wait loop feeds it.
# If ums ends or U-Boot hangs, the SoC resets and the stub card gives FEL again. A power loss gives nothing.
mw.l 0x01c20cb4 1
mw.l 0x01c20cb8 0xb1
ums 0 mmc 0,1 || ums 0 mmc 1 || ums 0 mmc 0
