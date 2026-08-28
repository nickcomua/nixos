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
    includes = ["~/.ssh/config.local"];
    settings = {
      "cyrus.kaminazuma.com" = {
        HostName = "cyrus.kaminazuma.com";
        User = "ubuntu";
        ForwardX11 = true;
        ForwardX11Trusted = true;
      };
      "kaminazuma.com" = {
        HostName = "167.71.67.207";
        User = "root";
      };
      "alta.local" = {
        HostName = "alta.local";
        User = "root";
      };
      "alta" = {
        HostName = "kaminazuma.com";
        User = "root";
      };
    };
  };

  # Force overwrite the existing manually managed ~/.ssh/config
  home.file.".ssh/config".force = true;
}
