# Shared zsh configuration for all systems
{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.zsh = {
    enable = true;
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      l = "ls -la";
      c = "clear";
      h = "history";
      da = "direnv allow";
      gg = "~/.cargo/bin/gg";
      rm = "echo 'Use rip to delete files'";
    };
    sessionVariables = {
      ZSH_DISABLE_COMPFIX = true;
      MAILCHECK = 30;
    };
    initContent = lib.mkMerge [
      ''
        # Common shell init
        source <(fzf --zsh)
        source <(COMPLETE=zsh jj)

        # Cargo
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

        # fnm (if available)
        command -v fnm &>/dev/null && eval "$(fnm env --use-on-cd --shell zsh)"

        # kubectl (if available)
        command -v kubectl &>/dev/null && source <(kubectl completion zsh)

        # Platform-specific reload-nix command
        reload-nix() {
          if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS - use darwin-rebuild
            darwin-rebuild switch --flake ~/.config/nix
          elif [[ -f /etc/NIXOS ]]; then
            # NixOS
            if [[ -d ~/.config/nixos ]]; then
              sudo nixos-rebuild switch --flake ~/.config/nixos
            elif [[ -d /etc/nixos ]]; then
              sudo nixos-rebuild switch --flake /etc/nixos
            else
              echo "Error: No NixOS config found in ~/.config/nixos or /etc/nixos"
              return 1
            fi
          else
            echo "Error: Unsupported platform or not a NixOS/nix-darwin system"
            return 1
          fi
        }
      ''
      (lib.mkIf pkgs.stdenv.isDarwin ''
        # macOS specific
        eval "$(uv generate-shell-completion zsh)"
        eval "$(uvx --generate-shell-completion zsh)"
        source <(determinate-nixd completion zsh)
        export PATH=$HOME/.opencode/bin:$PATH
      '')
    ];
    plugins = [
      {
        file = "p10k.zsh";
        name = "powerlevel10k-config";
        src = ./.;
      }
      {
        file = "powerlevel10k.zsh-theme";
        name = "zsh-powerlevel10k";
        src = "${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k";
      }
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "v0.8.0";
          sha256 = "1lzrn0n4fxfcgg65v0qhnj7wnybybqzs4adz7xsrkgmcsr0ii8b7";
        };
      }
    ];
    oh-my-zsh = {
      enable = true;
      plugins =
        [
          "git"
          "git-auto-fetch"
          "docker"
          "python"
          "yarn"
          "jj"
          "npm"
          "fnm"
          "bun"
          "ssh"
          "man"
          "tldr"
          "sudo"
          "fzf"
          "direnv"
          "kubectl"
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin ["macos"];
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = ["--cmd cd"];
  };
}
