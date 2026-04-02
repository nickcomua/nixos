# Shared SSH client configuration for all systems
{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "cyrus.kaminazuma.com" = {
        hostname = "cyrus.kaminazuma.com";
        user = "ubuntu";
        forwardX11 = true;
        forwardX11Trusted = true;
      };
      "kaminazuma.com" = {
        hostname = "167.71.67.207";
        user = "root";
      };
      "alta.local" = {
        hostname = "alta.local";
        user = "root";
      };
      "alta" = {
        hostname = "kaminazuma.com";
        user = "root";
      };
    };
  };
}
