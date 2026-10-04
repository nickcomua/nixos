# Shared SSH client configuration for all systems
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Alta's SSH entries log in as root (UID 0). %i expands to the local UID.
  localGpgExtraSocket =
    if pkgs.stdenv.hostPlatform.isLinux then
      "/run/user/%i/gnupg/S.gpg-agent.extra"
    else
      "%d/.gnupg/S.gpg-agent.extra";
  gpgRemoteForward = "/run/user/0/gnupg/S.gpg-agent ${localGpgExtraSocket}";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # Include an editable local file for ad-hoc host entries.
    # Create ~/.ssh/config.local and add any Host blocks there;
    # they will be picked up automatically without rebuilding.
    includes = [ "~/.ssh/config.local" ];
    settings = {
      "alta.local" = {
        hostname = "alta.local";
        user = "root";
        forwardAgent = true;
        forwardX11 = true;
        forwardX11Trusted = true;
        RemoteForward = gpgRemoteForward;
      };
      "alta" = {
        hostname = "ssh.kaminazuma.com";
        user = "root";
        proxyCommand = "${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h";
        forwardAgent = true;
        forwardX11 = true;
        forwardX11Trusted = true;
        RemoteForward = gpgRemoteForward;
      };
    };
  };

  # Force overwrite the existing manually managed ~/.ssh/config
  home.file.".ssh/config".force = true;
}
