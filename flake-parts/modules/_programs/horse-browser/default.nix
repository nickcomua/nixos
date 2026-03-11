# Horse Browser NixOS module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.horse-browser;
in {
  options.programs.horse-browser = {
    enable = mkEnableOption "Horse Browser";

    package = mkOption {
      type = types.package;
      default = pkgs.appimageTools.wrapType2 {
        pname = "horse-browser";
        version = "0.74.1";
        src = pkgs.fetchurl {
          url = "https://carrots.browser.horse/download/appimage-x64";
          hash = "sha256-5I2pg+7NqTj2dHkLW/SSrN83zMeOa4aCjVBierXB0+w=";
        };
        extraPkgs = pkgs: with pkgs; [];
      };
      description = "Horse Browser package";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
  };
}
