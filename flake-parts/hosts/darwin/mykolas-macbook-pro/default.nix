{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  sharedNix = import ../../../modules/_shared-nix.nix;
in {
  imports = [
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.determinate.darwinModules.default
  ];

  # Determinate Nix - manages nix configuration
  nix.enable = false;
  determinateNix.customSettings = {
    eval-cores = 0;
    extra-experimental-features = sharedNix.advancedExperimentalFeatures;
    extra-substituters = sharedNix.caches.substituters;
    extra-trusted-public-keys = sharedNix.caches.trustedPublicKeys;
  };

  # Homebrew
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = "nick";
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "gromgit/homebrew-fuse" = inputs.homebrew-fuse;
      "openhue/homebrew-cli" = inputs.homebrew-openhue;
    };
    mutableTaps = false;
  };

  programs.direnv.enable = true;
  programs.zsh.enableCompletion = false;

  homebrew = {
    enable = true;
    taps = [
      "homebrew/cask"
      "openhue/cli"
    ];
    brews = [
      "gemini-cli"
      "postgresql@16"
      "iproute2mac"
      "gromgit/fuse/s3fs-mac"
      "helm"
      "openhue-cli"
    ];
    casks = [
      "balenaetcher"
      "macfuse"
      "background-music"
      "openinterminal"
      "hiddenbar"
      "raycast"
      "orbstack"
      "betterdisplay"
      "mac-mouse-fix@2"
      "steam"
      "blender"
      "qgis"
      "ghostty"
      "activitywatch"
    ];
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    primaryUser = "nick";
    defaults = {
      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "clmv";
        ShowPathbar = true;
      };
      dock = {
        persistent-others = [
          "/Users/nick/Documents/repos"
          "/Users/nick/Downloads"
        ];
      };
    };
    stateVersion = 5;
  };

  users.users = {
    nick = {
      name = "nick";
      home = "/Users/nick";
      uid = 501;
    };
    nickp = {
      name = "nickp";
      home = "/Users/nickp";
      uid = 502;
    };
  };

  # Home Manager is configured via darwin.nix flake-parts module
}
