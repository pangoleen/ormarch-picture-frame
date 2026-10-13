-- Hyprland alone, with the look that Omarchy 4 ships: no blur, no shadows, no rounding, animations on.
hl.config({ debug = { disable_logs = false, enable_stdout_logs = true } })
hl.monitor({ output = "", mode = "1280x800", position = "0x0", scale = 1 })
hl.config({
  general = { gaps_in = 5, gaps_out = 10, border_size = 2,
              col = { active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }, inactive_border = "rgba(595959aa)" } },
  decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
  animations = { enabled = true },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, background_color = "rgb(203040)" },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
