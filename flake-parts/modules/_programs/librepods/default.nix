# LibrePods NixOS module
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
  cfg = config.programs.librepods;
in {
  options.programs.librepods = {
    enable = mkEnableOption "LibrePods podcast client";

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "LibrePods package (uses input if null)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (
        if cfg.package != null
        then cfg.package
        else inputs.librepods.packages.x86_64-linux.default
      )
    ];
  };
}
