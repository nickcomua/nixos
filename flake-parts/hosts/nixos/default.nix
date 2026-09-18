# NixOS host configuration
{
  pkgs,
  lib,
  inputs,
  config,
  ...
}: let
  sharedNix = import ../../modules/_shared-nix.nix;
  applyDesktop = lib.hiPrio (pkgs.writeShellScriptBin "nixarchy-apply" ''
    exec /etc/profiles/per-user/nick/bin/nixarchy-config apply "$@"
  '');
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
    inputs.nixarchy.nixosModules.nixarchy
    ../../../nixarchy-apps.nix
  ];

  programs.nixarchy = {
    enable = true;
    user = "nick";
    flake = "/home/nick/.config/nixos";
    defaultAgent = "codex";
    preinstalls = true;
    displayManager = true;
    bootSplash = "force";
    shellIntegration = false;
    bashIntegration = false;
    binaryCaches = false; # Centralized in _shared-nix.nix.
    package = (pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace default/sddm/omarchy/Main.qml \
              --replace-fail 'Keys.onPressed: {' 'Keys.onPressed: function(event) {'
        '';
    });
    menu.extraEntries = {
      "personal".label = "My configuration";
      "personal.export" = {
        label = "Save desktop to Nix";
        action = "omarchy-launch-floating-terminal-with-presentation nixarchy-config export";
      };
      "personal.status" = {
        label = "Unsaved desktop changes";
        action = "omarchy-launch-floating-terminal-with-presentation nixarchy-config status";
      };
      "personal.restore" = {
        label = "Restore saved desktop";
        action = "omarchy-launch-floating-terminal-with-presentation nixarchy-config restore";
      };
    };
  };

  # Sops secrets configuration
  sops = {
    defaultSopsFile = ../../../secrets.yaml;
    age.keyFile = "/home/nick/.config/sops/age/keys.txt";
    secrets = {
      "gmail-push-token" = {};
      "telegram-bot-token" = {};
      "BWS_ACCESS_TOKEN" = {
        owner = "nick"; # Changes file owner to your user
        mode = "0400"; # Gives read-only access exclusively to the owner
      };
    };
  };

  nix = {
    settings = {
      extra-substituters = sharedNix.caches.substituters;
      trusted-public-keys = sharedNix.caches.trustedPublicKeys;
      experimental-features = sharedNix.experimentalFeatures;
      trusted-users = [
        "root"
        "nick"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    optimise = {
      automatic = true;
      dates = ["weekly"];
    };
  };

  # Bootloader
  boot = {
    kernelPackages = pkgs.linuxPackages_6_18;
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
      configurationLimit = 14;
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
      wifi.backend = "iwd";
      settings = {
        # dnscrypt-proxy owns DNS configuration for this host.
        main.dns = "none";
        connection."wifi.powersave" = 2;

        # Let NetworkManager—not iwd—control autoconnection.
        device."wifi.iwd.autoconnect" = false;
      };
    };
    firewall = {
      checkReversePath = false;
      allowedTCPPorts = [
        9000
        9001
      ];
    };
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
    suwayomi-server = {
      enable = true;
      settings.server = {
        kcefEnabled = false;
        initialOpenInBrowserEnabled = false;
      };
    };
    dnscrypt-proxy = {
      enable = true;
      settings = {
        # Quad9 Secure: DNSSEC validation and malicious-domain blocking over DoH.
        server_names = [
          "quad9-doh-ip4-port443-filter-pri"
          "quad9-doh-ip6-port443-filter-pri"
        ];
        listen_addresses = [
          "127.0.0.1:53"
          "[::1]:53"
        ];
        bootstrap_resolvers = [
          "9.9.9.9:53"
          "149.112.112.112:53"
          "[2620:fe::fe]:53"
          "[2620:fe::9]:53"
        ];
        require_dnssec = true;
        require_nolog = true;
        require_nofilter = false;
      };
    };

    flatpak.enable = true;
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    displayManager = {
      defaultSession = "omarchy";
      ly.enable = false;
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

    desktopManager.gnome.enable = false;
    printing.enable = true;

    # Desktop power and battery controls.
    power-profiles-daemon.enable = true;

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
      powerOnBoot = true;
      settings = {
        General = {
          DeviceID = "bluetooth:004C:0000:0000";
        };
      };
    };
  };

  # Systemd services
  systemd = {
    services = {
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
      # Flatpak's remote setup needs the resolver after networking restarts on switch.
      flatpak-managed-install = {
        wants = ["network-online.target"];
        after = ["network-online.target" "dnscrypt-proxy.service"];
      };
    };
    tmpfiles.rules = [
      # Steam's FHS wrapper treats /.host-etc as a nested-wrapper marker.
      # A stale empty directory here prevents it from exposing the real /etc.
      "r! /.host-etc - - - - -"
    ];
  };

  # Security settings
  security = {
    rtkit.enable = true;
    polkit.enable = true;
    polkit.enablePkexecWrapper = true;
  };

  # 2. Let NixOS inject the system's CA certificate bundle
  security.pki.certificateFiles = [];

  # Programs configuration
  programs = {
    # horse-browser.enable = true;
    nm-applet.enable = false;
    whisper-transcribe.enable = true;
    nix-ld = {
      enable = true;
      # Runtime dependencies for downloaded Electron apps (including Hermes Desktop).
      libraries = with pkgs; [
        dbus
        atk
        at-spi2-atk
        at-spi2-core
        cups
        cairo
        gtk3
        pango
        libXcomposite
        libXdamage
        libXfixes
        libgbm
        expat
      ];
    };
    kdeconnect.enable = true;
    zsh.enable = true;
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
    pathsToLink = ["/share/omarchy"];
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
    # Applications without a Nixarchy catalog entry.
    systemPackages = with pkgs; [
      applyDesktop
      floorp-bin
      direnv
      bubblewrap
      fnm
      zellij
      iw # Inspect Wi-Fi link, BSSID, bitrate, and power state.
      pkg-config
      llvmPackages.bintools
      glibc.dev
      glib.dev
      openssl
      gg-jj
      libsecret
      telegram-desktop
      google-cloud-sdk
      tldr
      super-productivity
      discord
      bluetui
      pavucontrol
      qt6.qtwebsockets
      kdePackages.krdp
      kdePackages.ark
      kdePackages.partitionmanager
      openrazer-daemon
      polychromatic
      age
      yazi
      bitwarden-cli
      wireguard-tools
      proton-vpn
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.droid-sans-mono
    nerd-fonts.jetbrains-mono
  ];

  system.stateVersion = "25.11";
}
