# --- flake-parts/devenv/default.nix
{
  inputs,
  lib,
  ...
}: {
  imports = with inputs; [devenv.flakeModule];

  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: let
    # Evaluate the shell config once to avoid duplicate evaluation issues
    devShellConfig = import ./dev.nix {
      inherit pkgs system;
      inherit (inputs) devenv-root;
      treefmt-wrapper =
        if (lib.hasAttr "treefmt" config)
        then config.treefmt.build.wrapper
        else null;
    };
  in {
    devenv.shells = {
      dev = devShellConfig;
      # Use the same evaluated config for default to avoid secretspec conflicts
      default = devShellConfig;
    };
  };
}
