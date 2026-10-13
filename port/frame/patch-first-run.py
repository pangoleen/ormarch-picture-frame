#!/usr/bin/env python3
"""Disable Omarchy's package-only first-run task in the source-backed port."""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "default/hypr/autostart.lua"
original = path.read_text()
before = '  hl.exec_cmd("omarchy-provision-first-run")'
after = '''  -- PF1007L source-backed setup: the upstream first-run command assumes
  -- package-owned user services that are intentionally not present here.
  -- Frame-specific services are enabled by port/frame/apply.sh instead.'''

if after not in original:
    if original.count(before) != 1:
        raise SystemExit("Omarchy first-run autostart changed upstream; review it before patching")
    backup = path.with_name(path.name + ".before-frame-port")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text(original.replace(before, after))
