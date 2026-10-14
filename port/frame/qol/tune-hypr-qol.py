#!/usr/bin/env python3
"""PF1007L: Hyprland settings of the quality-of-life round (E071). Appends one marked block to
~/.config/hypr/looknfeel.lua (backup: looknfeel.lua.before-frame-qol). Run again: no change."""
from pathlib import Path

look = Path.home() / ".config/hypr/looknfeel.lua"
marker = "-- PF1007L quality of life (E071)"
marker2 = "damage_tracking = 2"
text = look.read_text()
if marker not in text:
    backup = look.with_name(look.name + ".before-frame-qol")
    if not backup.exists():
        backup.write_text(text)
    look.write_text(text + f'''
{marker}
hl.config({{
  misc = {{
    -- A slow app start (Firefox needs up to 2 min) must not raise the "not responding" dialog.
    enable_anr_dialog = false,
  }},
  render = {{
    -- Triple buffering; the Hyprland wiki names it for weak hardware.
    new_render_scheduling = true,
  }},
  debug = {{
    -- E076: partial repaint again. Full repaint (E057) costs much more memory bandwidth; the
    -- vertical lines stayed with it, and memory traffic can starve the display.
    damage_tracking = 2,
  }},
  xwayland = {{
    -- No X11 app is in use on the frame; Xwayland held about 40 MiB. Set true if one is needed.
    enabled = false,
  }},
}})
-- GTK4 apps (Files): software drawing is the safe path on a GLES 2 GPU.
hl.env("GSK_RENDERER", "cairo")
hl.env("MOZ_ENABLE_WAYLAND", "1")
''')
