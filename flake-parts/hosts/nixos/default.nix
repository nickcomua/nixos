# NixOS host configuration
{
  config,
  pkgs,
  inputs,
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
    ../../modules/_programs/horse-browser
    ../../modules/_programs/librepods
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
  boot.loader.grub = {
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

  networking = {
    hostName = "nixos";
    networkmanager.enable = true;
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
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    displayManager.sddm = {
      enable = true;
      wayland.enable = true;
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

    minio = {
      enable = true;
      rootCredentialsFile = "/home/nick/.secrets/minio-root-credentials";
      dataDir = ["/var/lib/minio/data"];
      consoleAddress = "0.0.0.0:9001";
      listenAddress = "0.0.0.0:9000";
    };

    desktopManager.gnome.enable = true;
    printing.enable = true;

    tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      };
    };

    power-profiles-daemon.enable = false;
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
    '';
  };

  # Hardware configuration
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        DeviceID = "bluetooth:004C:0000:0000";
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

    lenovo-conservation-mode = {
      description = "Set Lenovo IdeaPad battery conservation mode";
      wantedBy = ["sysinit.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # 0 = charge to 100%, 1 = conservation mode (~60%)
        echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
      '';
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

  # Security settings
  security = {
    rtkit.enable = true;
    pam.services = {
      hyprlock = {};
      gdm-password.enableGnomeKeyring = true;
    };
    polkit.enable = true;
  };

  # Programs configuration
  programs = {
    horse-browser.enable = true;
    librepods.enable = true;
    whisper-transcribe.enable = true;
    nix-ld.enable = true;
    hyprland = {
      enable = true;
      xwayland.enable = true;
    };
    kdeconnect.enable = true;
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
    ssh.askPassword = "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";
    zsh.enable = true;
    firefox.enable = true;
    seahorse.enable = true;
  };

  # Create i2c group if it doesn't exist
  users.groups.i2c = {};

  # Define a user account
  users.users.nick = {
    isNormalUser = true;
    description = "Nick";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
      "i2c"
      "docker"
    ];
    packages = with pkgs; [];
  };

  # Enable home-manager for user
  home-manager = {
    backupFileExtension = "bak";
    users.nick = import ./nick.nix;
  };

  virtualisation.docker.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Environment configuration
  environment = {
    variables.XDG_RUNTIME_DIR = "/run/user/$UID";
    systemPackages = with pkgs; [
      vscode
      google-chrome
      ghostty
      direnv
      fnm
      uv
      zellij
      git
      jujutsu
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
      activitywatch
      discord
      bluez
      bluetui
      pavucontrol
      kdePackages.krdp
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
  ];

  system.stateVersion = "25.11";
}
