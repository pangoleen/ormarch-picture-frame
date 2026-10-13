# PF1007L build F, A/B test: the same as ums-diag.cmd, but CTRL+C from the console is NOT ignored.
# If ums ends here after some minutes and the watchdog brings FEL back, console noise is the cause.
setenv ums_ignore_eject 1
mw.l 0x01c20cb4 1
mw.l 0x01c20cb8 0xb1
ums 0 mmc 0,1 || ums 0 mmc 1 || ums 0 mmc 0
