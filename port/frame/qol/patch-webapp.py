#!/usr/bin/env python3
"""Let Omarchy's web-app launcher work with Firefox on the frame.

omarchy-launch-webapp falls back to chromium.desktop for every browser that is not Chromium-based.
Chromium has no armv7h package, so every web-app entry (YouTube, ChatGPT, the Learn links ...) did
nothing. Firefox has no --app mode; the page opens in a new Firefox window.
Usage: patch-webapp.py <omarchy-tree>"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "bin/omarchy-launch-webapp"
original = path.read_text()
before = '''*) browser="chromium.desktop" ;;'''
after = '''firefox*)
  # PF1007L: no Chromium on armv7h. Open the page in a Firefox window.
  exec setsid uwsm-app -- /usr/lib/firefox/firefox --new-window "$1"
  ;;
*) browser="chromium.desktop" ;;'''
if "PF1007L: no Chromium" not in original:
    if original.count(before) != 1:
        raise SystemExit("omarchy-launch-webapp changed upstream; review it before patching")
    backup = path.with_name(path.name + ".before-frame-port")
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    path.write_text(original.replace(before, after))
