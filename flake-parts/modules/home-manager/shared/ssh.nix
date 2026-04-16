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
    # Include an editable local file for ad-hoc host entries.
    # Create ~/.ssh/config.local and add any Host blocks there;
    # they will be picked up automatically without rebuilding.
    includes = [ "~/.ssh/config.local" ];
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

  # Force overwrite the existing manually managed ~/.ssh/config
  home.file.".ssh/config".force = true;
}
