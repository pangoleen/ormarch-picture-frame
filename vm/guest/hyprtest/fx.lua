-- Hyprland alone, with every effect on: blur, shadows, rounding, see-through windows, animations.
hl.config({ debug = { disable_logs = false, enable_stdout_logs = true } })
hl.monitor({ output = "", mode = "1280x800", position = "0x0", scale = 1 })
hl.config({
  general = { gaps_in = 8, gaps_out = 16, border_size = 3,
              col = { active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }, inactive_border = "rgba(595959aa)" } },
  decoration = { rounding = 14, active_opacity = 0.80, inactive_opacity = 0.70,
                 shadow = { enabled = true, range = 20, render_power = 3 },
                 blur = { enabled = true, size = 6, passes = 2, noise = 0.02, vibrancy = 0.2 } },
  animations = { enabled = true },
  misc = { disable_hyprland_logo = false, disable_splash_rendering = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
