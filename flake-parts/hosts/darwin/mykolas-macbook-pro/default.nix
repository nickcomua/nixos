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
    ../../../modules/darwin/monitoring.nix
  ];

  # Determinate Nix - manages nix configuration
  nix.enable = false;
  determinateNix.customSettings = {
    trusted-users = ["root" "nick" "nickp"];
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

      "automake"
      {
        name = "cliproxyapi";
        start_service = true;
        restart_service = true;
      }
      "dbus"
      "gdal"
      "pdal"
      "cmake"
      "bat"
      "git-delta"
      "glow"

      "scrcpy"
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

      # Wine/MT5 support (Whisky bundles its own Wine)
      "whisky"

      "android-platform-tools"
    ];
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  networking = {
    hostName = "Mykolas-MacBook-Pro";
    localHostName = "Mykolas-MacBook-Pro";
    computerName = "Mykola's MacBook Pro";
  };

  launchd.agents."set-dbus-session-bus-address" = {
    serviceConfig = {
      Label = "set-dbus-session-bus-address";
      ProgramArguments = [
        "/bin/bash"
        "-c"
        ''
          # Ensure dbus session is running
          launchctl kickstart -k gui/$(id -u)/org.freedesktop.dbus-session 2>/dev/null || true
          # Wait for the socket to appear (launchctl print gives the real path)
          for i in $(seq 1 20); do
            SOCKET=$(launchctl print gui/$(id -u)/org.freedesktop.dbus-session 2>/dev/null \
              | awk '/path = \/private\/tmp/{print $3}')
            if [ -n "$SOCKET" ] && [ -S "$SOCKET" ]; then
              launchctl setenv DBUS_LAUNCHD_SESSION_BUS_SOCKET "$SOCKET"
              launchctl setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$SOCKET"
              exit 0
            fi
            sleep 1
          done
        ''
      ];
      RunAtLoad = true;
    };
  };

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
