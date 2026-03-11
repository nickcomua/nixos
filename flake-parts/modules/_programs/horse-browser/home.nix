# Horse Browser home-manager module
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
    enable = mkEnableOption "Horse Browser home-manager config";

    setAsDefault = mkOption {
      type = types.bool;
      default = true;
      description = "Set Horse Browser as the default web browser";
    };
  };

  config = mkIf cfg.enable {
    xdg.desktopEntries."horse-browser" = {
      name = "Horse Browser";
      exec = "horse-browser";
      icon = "web-browser";
      terminal = false;
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeType = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "application/xml"
        "application/vnd.mozilla.xul+xml"
        "application/rss+xml"
        "application/rdf+xml"
        "image/svg+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
    };

    xdg.mimeApps = mkIf cfg.setAsDefault {
      enable = true;
      defaultApplications = {
        "text/html" = "horse-browser.desktop";
        "text/xml" = "horse-browser.desktop";
        "application/xhtml+xml" = "horse-browser.desktop";
        "application/xml" = "horse-browser.desktop";
        "application/vnd.mozilla.xul+xml" = "horse-browser.desktop";
        "application/rss+xml" = "horse-browser.desktop";
        "application/rdf+xml" = "horse-browser.desktop";
        "x-scheme-handler/http" = "horse-browser.desktop";
        "x-scheme-handler/https" = "horse-browser.desktop";
        "x-scheme-handler/unknown" = "horse-browser.desktop";
      };
    };
  };
}
