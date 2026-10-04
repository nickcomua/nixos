# Shared packages for all systems
{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # Core tools
    git
    jujutsu
    ripgrep
    fd
    fzf
    tree
    dua
    eza
    bat

    # Development
    gh
    nixd
    nil
    alejandra

    # Network/utils
    rsync
    rclone
    wget
    curl
    jq

    # Calculator
    libqalculate

    # Modern replacements
    rip2
    tlrc
    lsd

    # Kubernetes (optional, usually wanted everywhere)
    kubectl
    k9s

    bws
  ];

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings.user.name = lib.mkDefault "Mykola Korniichuk";
    settings.user.email = lib.mkDefault "mykola.korniichuk.ua@gmail.com";

    signing = {
      key = "DA16D6435985D05EE87223C7DB5C5C04C419C4C6!";
      signByDefault = true;
      format = "openpgp";
      signer = "${pkgs.gnupg}/bin/gpg";
    };
    settings.tag.gpgSign = true;
  };
}
