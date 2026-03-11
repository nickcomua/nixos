{inputs, ...}: {
  imports = [
    inputs.catppuccin-nix.homeModules.catppuccin
    inputs.vicinae.homeManagerModules.default
    ./options.nix
    ./hyprland
    ./hyprpanel
    ./hyprlock
    ./hypridle
    ./hyprpaper
    ./satty
    ./vicinae
  ];

  # Configure catppuccin with sensible defaults
  catppuccin = {
    flavor = "mocha";
    accent = "blue";
    enable = true;
  };

  # Cursor theme must be enabled explicitly (not included in catppuccin.enable)
  catppuccin.cursors.enable = true;

  # Set cursor size to match wayland option
  home.pointerCursor.size = 24;

  # Configure catppuccin for hyprland
  catppuccin.hyprland = {
    enable = true;
    flavor = "mocha";
    accent = "blue";
  };
}
