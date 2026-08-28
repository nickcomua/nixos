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

  # Nixi shows Codex first and uses it when no per-session agent is selected.
  services.nixi.agents = lib.mkForce [
    "codex"
    "opencode"
  ];

  # Disable Horse Browser as default, use Google Chrome instead
  # programs.horse-browser.setAsDefault = false;
}
