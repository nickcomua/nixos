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
  };

  # Disable Horse Browser as default, use Google Chrome instead
  # programs.horse-browser.setAsDefault = false;

  # Omarchy owns mutable application defaults and Hyprland Lua settings.
  services.nixi.enable = false;
}
