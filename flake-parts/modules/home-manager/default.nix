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
    shared = import ./shared;
    shared-zsh = import ./shared/zsh.nix;
    shared-packages = import ./shared/packages.nix;

    # Platform-specific
    darwin-common = import ./darwin/common.nix;
    linux-common = import ./linux/common.nix;

    # Programs - home-manager parts (from _programs, excluded from auto-load)
    # horse-browser = import ../_programs/horse-browser/home.nix;
    # librepods = import ../_programs/librepods/home.nix;

    # Existing modules
    wayland = importApply ./wayland {inherit localFlake inputs;};
    # activitywatch = importApply ./services/activitywatch {inherit localFlake inputs;};
  };
}
