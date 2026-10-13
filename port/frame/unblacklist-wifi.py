#!/usr/bin/env python3
"""Remove the bring-up blacklist for the two now-tested Wi-Fi modules."""
import pathlib
import re
import sys

pattern = re.compile(r"^\s*blacklist\s+(aic8800_bsp|aic8800_fdrv)\s*(?:#.*)?$")
for path in pathlib.Path(sys.argv[1]).glob("*.conf"):
    old = path.read_text()
    lines = old.splitlines(keepends=True)
    new = "".join("# Tested on PF1007L; load at boot: " + line if pattern.match(line.rstrip()) else line for line in lines)
    if new != old:
        backup = path.with_name(path.name + ".before-frame-desktop")
        if not backup.exists():
            backup.write_bytes(path.read_bytes())
        path.write_text(new)
        print("Enabled Wi-Fi modules in", path.name)
