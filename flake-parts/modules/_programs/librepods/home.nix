# LibrePods home-manager module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.librepods;
in {
  options.programs.librepods = {
    enable = mkEnableOption "LibrePods home-manager config";
  };

  config = mkIf cfg.enable {
    xdg.desktopEntries."librepods" = {
      name = "LibrePods";
      genericName = "Podcast Client";
      exec = "${pkgs.writeShellScript "librepods-launcher" ''
        pkill .librepods-wrap | sleep 0.1 && librepods
      ''}";
      icon = "podcast";
      terminal = false;
      categories = [
        "Audio"
        "AudioVideo"
        "Network"
      ];
    };
  };
}
