# NixOS host configuration
{
  pkgs,
  inputs,
  config,
  ...
}: let
  sharedNix = import ../../modules/_shared-nix.nix;
in {
  imports = [
    ./hardware-configuration.nix
    ./apfs.nix
    # Determinate Nix for consistent nix daemon management
    inputs.determinate.nixosModules.default
    # Sops for secrets management
    inputs.sops-nix.nixosModules.sops
    # Import program modules directly (prefixed with _ to exclude from auto-load)
    ../../modules/_programs/whisper-transcribe
  ];

  # Sops secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets.yaml;
    age.keyFile = "/home/nick/.config/sops/age/keys.txt";
    secrets = {
      "openclaw-hooks-token" = {};
      "gmail-push-token" = {};
      "telegram-bot-token" = {};
      "BWS_ACCESS_TOKEN" = {
        owner = "nick"; # Changes file owner to your user
        mode = "0400"; # Gives read-only access exclusively to the owner
      };
    };
  };

  # Nix settings - caches and experimental features
  nix.settings = {
    inherit (sharedNix.caches) substituters;
    trusted-public-keys = sharedNix.caches.trustedPublicKeys;
    experimental-features = sharedNix.experimentalFeatures;
    trusted-users = [
      "root"
      "nick"
    ];
  };

  # Bootloader
  boot = {
    extraModprobeConfig = ''
      options iwlmvm power_scheme=1
    '';
    binfmt.emulatedSystems = ["aarch64-linux"];

    loader.grub = {
      enable = true;
      devices = ["nodev"];
      efiInstallAsRemovable = true;
      efiSupport = true;
      useOSProber = true;
      theme = pkgs.stdenv.mkDerivation {
        pname = "distro-grub-themes";
        version = "3.1";
        src = pkgs.fetchFromGitHub {
          owner = "AdisonCavani";
          repo = "distro-grub-themes";
          rev = "v3.1";
          hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
        };
        installPhase = "cp -r customize/nixos $out";
      };
    };
  };

  networking = {
    hostName = "nixos";
    networkmanager = {
      enable = true;
      settings.connection."wifi.powersave" = 2;
    };
    firewall.allowedTCPPorts = [
      9000
      9001
    ];
  };

  # Set your time zone
  time.timeZone = "Europe/Amsterdam";

  # Select internationalisation properties
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "nl_NL.UTF-8";
      LC_IDENTIFICATION = "nl_NL.UTF-8";
      LC_MEASUREMENT = "nl_NL.UTF-8";
      LC_MONETARY = "nl_NL.UTF-8";
      LC_NAME = "nl_NL.UTF-8";
      LC_NUMERIC = "nl_NL.UTF-8";
      LC_PAPER = "nl_NL.UTF-8";
      LC_TELEPHONE = "nl_NL.UTF-8";
      LC_TIME = "nl_NL.UTF-8";
    };
  };

  # Services configuration
  services = {
    flatpak.enable = true;
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    displayManager.ly = {
      enable = true;
      # wayland.enable = true;
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        userServices = true;
        addresses = true;
      };
    };

    # minio = {
    #   enable = true;
    #   rootCredentialsFile = "/home/nick/.secrets/minio-root-credentials";
    #   dataDir = ["/var/lib/minio/data"];
    #   consoleAddress = "0.0.0.0:9001";
    #   listenAddress = "0.0.0.0:9000";
    # };

    desktopManager.gnome.enable = true;
    printing.enable = true;

    # power-profiles-daemon is required by Noctalia for power profile controls
    # https://docs.noctalia.dev/getting-started/nixos/
    power-profiles-daemon.enable = true;

    # upower is required by Noctalia for battery status
    upower.enable = true;
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    tailscale.enable = true;
    seatd.enable = true;
    gnome.gnome-keyring.enable = true;

    udev.extraRules = ''
      # Allow i2c group to access I2C devices for DDC/CI monitor control
      SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0666"
      KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0666"

      # Noctalia ideapad-battery-health plugin: grant battery_ctl group
      # write access to conservation_mode for BAT0
      SUBSYSTEM=="power_supply", KERNEL=="BAT0", RUN+="${pkgs.coreutils}/bin/chgrp battery_ctl /sys%p/extensions/ideapad_laptop/conservation_mode", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/extensions/ideapad_laptop/conservation_mode"
    '';
  };

  # Hardware configuration
  hardware = {
    graphics.enable32Bit = true;
    openrazer.enable = true;
    bluetooth = {
      enable = true;
      powerOnBoot = true; # unblock rfkill so Noctalia can manage bluetooth
      settings = {
        General = {
          DeviceID = "bluetooth:004C:0000:0000";
        };
      };
    };
  };

  # Systemd services
  systemd.services = {
    voice-to-text-bot = {
      description = "Voice-to-Text Telegram Bot using Whisper";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "nick";
        Group = "users";
        WorkingDirectory = "/home/nick/projects/voice-to-text-rs";
        Restart = "on-failure";
        RestartSec = "10s";
        EnvironmentFile = "/home/nick/.secrets/voice-to-text-bot.env";
        ExecStart = "${pkgs.nix}/bin/nix run /home/nick/projects/voice-to-text-rs";
      };
    };

    fix-i2c-permissions = {
      description = "Fix I2C device permissions for ddcutil";
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "oneshot";
      script = ''
        chmod 666 /dev/i2c-* 2>/dev/null || true
        chgrp i2c /dev/i2c-* 2>/dev/null || true
      '';
    };
  };

  systemd.tmpfiles.rules = [
    # Steam's FHS wrapper treats /.host-etc as a nested-wrapper marker.
    # A stale empty directory here prevents it from exposing the real /etc.
    "r! /.host-etc - - - - -"
  ];

  # Security settings
  security = {
    rtkit.enable = true;
    pam.services = {
      hyprlock = {};
      gdm-password.enableGnomeKeyring = true;
    };
    polkit.enable = true;
  };

  # 2. Let NixOS inject the system's CA certificate bundle
  security.pki.certificateFiles = [];

  # Programs configuration
  programs = {
    # horse-browser.enable = true;
    # librepods.enable = true;
    whisper-transcribe.enable = true;
    nix-ld.enable = true;
    hyprland = {
      enable = true;
      xwayland.enable = true;
    };
    kdeconnect.enable = true;
    steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv = {
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          SSL_CERT_DIR = "/etc/ssl/certs";
          CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };
        extraProfile = ''
          rm -rf /etc/ssl/certs /etc/pki
          mkdir -p /etc/ssl/certs /etc/pki/tls/certs
          ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
          ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
          ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt
        '';
      };
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
    zsh.enable = true;
    firefox.enable = true;
    seahorse.enable = true;
  };

  users = {
    # Create i2c group if it doesn't exist
    groups.i2c = {};
    # Battery conservation mode control (Noctalia ideapad-battery-health plugin)
    groups.battery_ctl = {};

    # Define a user account
    users.nick = {
      isNormalUser = true;
      description = "Nick";
      shell = pkgs.zsh;
      extraGroups = [
        "networkmanager"
        "wheel"
        "i2c"
        "docker"
        "battery_ctl"
        "openrazer"
      ];
      # packages = with pkgs; [];
    };
  };

  # Enable home-manager for user
  home-manager = {
    users.nick = import ./nick.nix;
  };

  virtualisation.docker.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Environment configuration
  environment = {
    localBinInPath = true;
    variables = {
      XDG_RUNTIME_DIR = "/run/user/$UID";
      BROWSER = "floorp";
      BWS_ACCESS_TOKEN = "$(cat ${config.sops.secrets."BWS_ACCESS_TOKEN".path})";
      BWS_SERVER_URL = "https://vault.bitwarden.eu";
    };
    etc."inputrc".text = ''
      $include /etc/inputrc.default
      set enable-bracketed-paste off
    '';
    systemPackages = with pkgs; [
      vscode
      google-chrome
      floorp-bin
      ghostty
      direnv
      bubblewrap
      fnm
      uv
      zellij
      git
      jujutsu
      iw # Inspect Wi-Fi link, BSSID, bitrate, and power state.
      fzf
      pkg-config
      llvmPackages.bintools
      glibc.dev
      glib.dev
      openssl
      gg-jj
      libsecret
      telegram-desktop
      google-cloud-sdk
      gcc
      tldr
      super-productivity
      # activitywatch
      discord
      bluez
      bluetui
      pavucontrol
      qt6.qtwebsockets
      kdePackages.krdp
      kdePackages.ark
      kdePackages.partitionmanager
      bitwarden-desktop
      bitwarden-cli

      openrazer-daemon
      polychromatic
      zed-editor

      sops
      age
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
  ];

  system.stateVersion = "25.11";
}
