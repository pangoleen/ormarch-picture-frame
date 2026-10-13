#!/usr/bin/env python3
"""Apply the PF1007L's low-overhead Hyprland display settings.

The 800x1280 panel is mounted rotated.  A 1.6 compositor scale and 2x GTK
scale leave a 500x800 logical desktop, which is needlessly large for this
owner's use.  This keeps the measured transform and uses 1.25x / 1x instead.
Animations are disabled to reduce compositor work on the Mali-400.
"""

from pathlib import Path


home = Path.home()
monitors = home / ".config/hypr/monitors.lua"
look = home / ".config/hypr/looknfeel.lua"


def replace_once(path: Path, old: str, new: str, backup_suffix: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"expected setting not found in {path}: {old!r}")
    backup = path.with_name(path.name + backup_suffix)
    if not backup.exists():
        backup.write_text(text)
    path.write_text(text.replace(old, new, 1))


replace_once(monitors, "local omarchy_monitor_scale = 1.6", "local omarchy_monitor_scale = 1.25", ".before-frame-performance")
replace_once(monitors, "local omarchy_gdk_scale = 2", "local omarchy_gdk_scale = 1", ".before-frame-performance")

marker = "-- PF1007L low-overhead rendering"
look_text = look.read_text()
if marker not in look_text:
    backup = look.with_name(look.name + ".before-frame-performance")
    if not backup.exists():
        backup.write_text(look_text)
    look.write_text(
        look_text
        + "\n"
        + marker
        + "\nhl.config({\n  animations = { enabled = false },\n  decoration = { blur = { enabled = false }, shadow = { enabled = false } },\n})\n"
    )

tear_marker = "-- PF1007L tear fix test"
look_text = look.read_text()
if tear_marker not in look_text:
    look.write_text(
        look_text
        + "\n"
        + tear_marker
        + " (E057): full repaint each frame; rotation already composites.\n"
        + "hl.config({\n  debug = { damage_tracking = 0 },\n})\n"
    )
