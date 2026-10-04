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
      "alta.local" = {
        hostname = "alta.local";
        user = "root";
      };
      "alta" = {
        hostname = "ssh.kaminazuma.com";
        user = "root";
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
      };
    };
  };

  # Force overwrite the existing manually managed ~/.ssh/config
  home.file.".ssh/config".force = true;
}
