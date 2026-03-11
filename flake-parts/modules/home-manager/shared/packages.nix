# Shared packages for all systems
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    # Core tools
    git
    jujutsu
    ripgrep
    fd
    fzf
    tree
    btop
    dua
    eza
    bat

    # Development
    gh
    nixd
    alejandra

    # Network/utils
    rsync
    wget
    curl
    jq

    # Modern replacements
    rip2
    tlrc

    # Kubernetes (optional, usually wanted everywhere)
    kubectl
    k9s
  ];

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings.user.name = lib.mkDefault "Mykola Korniichuk";
    settings.user.email = lib.mkDefault "mykola.korniichuk.ua@gmail.com";
  };
}
