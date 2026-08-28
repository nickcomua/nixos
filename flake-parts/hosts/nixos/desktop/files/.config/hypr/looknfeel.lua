-- Keep privacy rules while taking appearance and tiling defaults from Omarchy.
for _, class in ipairs({ "org.telegram.desktop", "Slack", "discord", "Bitwarden", "1Password" }) do
  o.window(class, { no_screen_share = true })
end
