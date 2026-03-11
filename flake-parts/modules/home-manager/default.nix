# --- flake-parts/modules/home-manager/default.nix
{
  lib,
  inputs,
  self,
  ...
}: let
  inherit (inputs.flake-parts.lib) importApply;
  localFlake = self;
in {
  options.flake.homeModules = lib.mkOption {
    type = with lib.types; lazyAttrsOf unspecified;
    default = {};
  };

  config.flake.homeModules = {
    # Shared modules (all systems)
    shared = ./shared;
    shared-zsh = ./shared/zsh.nix;
    shared-packages = ./shared/packages.nix;

    # Platform-specific
    darwin-common = ./darwin/common.nix;
    linux-common = ./linux/common.nix;

    # Programs - home-manager parts (from _programs, excluded from auto-load)
    horse-browser = ../_programs/horse-browser/home.nix;
    librepods = ../_programs/librepods/home.nix;

    # Existing modules
    wayland = importApply ./wayland {inherit localFlake inputs;};
    activitywatch = importApply ./services/activitywatch {inherit localFlake inputs;};
  };
}
