# NixOS home-manager config for user nick
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # Note: shared and wayland modules are loaded automatically via sharedModules
  # in hosts/default.nix - don't import them here to avoid duplicate declarations

  home = {
    stateVersion = "24.05";
    username = "nick";
    homeDirectory = "/home/nick";
  };

  # Enable OpenClaw (config is in shared/clawdbot.nix)
  programs.openclaw.enable = true;

  # Disable Horse Browser as default, use Google Chrome instead
  programs.horse-browser.setAsDefault = false;

  # Set Google Chrome as the default browser
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "google-chrome.desktop";
      "text/xml" = "google-chrome.desktop";
      "application/xhtml+xml" = "google-chrome.desktop";
      "application/xml" = "google-chrome.desktop";
      "application/vnd.mozilla.xul+xml" = "google-chrome.desktop";
      "application/rss+xml" = "google-chrome.desktop";
      "application/rdf+xml" = "google-chrome.desktop";
      "x-scheme-handler/http" = "google-chrome.desktop";
      "x-scheme-handler/https" = "google-chrome.desktop";
      "x-scheme-handler/unknown" = "google-chrome.desktop";
    };
  };

  # Host-specific wayland settings
  wayland.hyprland.monitor = [
    "eDP-1,1920x1080@165,0x0,1" # Laptop display
    "HDMI-A-1,3840x2160@60,1920x0,2" # Samsung 4K monitor with scale 2
  ];
}
