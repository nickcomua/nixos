# NixOS home-manager config for user nick
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # Note: shared and Nixarchy modules are loaded automatically via sharedModules
  # in hosts/default.nix - don't import them here to avoid duplicate declarations

  home = {
    stateVersion = "24.05";
    username = "nick";
    homeDirectory = "/home/nick";
    packages = [pkgs.brave (import ./ipfs-desktop.nix {inherit pkgs;})];
  };

  home.sessionVariables.BROWSER = "helium";

  # Omarchy owns mutable application defaults and Hyprland Lua settings.
  services.nixi.enable = false;
}
