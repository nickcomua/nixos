{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  sharedNix = import ../../modules/_shared-nix.nix;
  pyvesync_2_1_15 = pkgs.python3Packages.buildPythonPackage {
    pname = "pyvesync";
    version = "2.1.15";
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "webdjoe";
      repo = "pyvesync";
      tag = "2.1.15";
      hash = "sha256-ucPKCdx1OEsofaXoOS1DSST3yYW5x1hoBKzPDhvKHJ8=";
    };

    build-system = [pkgs.python3Packages.setuptools];
    dependencies = [pkgs.python3Packages.requests];
    pythonImportsCheck = ["pyvesync"];
  };
in {
  imports = [
    ./configuration.nix
    ./hardware-configuration.nix
    inputs.sops-nix.nixosModules.sops
    # TODO: determinate-nix tests fail in CI - re-enable when upstream fixes it
    # inputs.determinate.nixosModules.default
    inputs.vscode-server.nixosModules.default
  ];

  sops = {
    defaultSopsFile = ../../../secrets.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets = {
      BWS_ACCESS_TOKEN = {};
      home-assistant-holesail-key = {};
      ssd-doda-bot-tg-api-id = {};
      ssd-doda-bot-tg-api-hash = {};
      ssd-doda-bot-tg-bot-token = {};
    };

    templates."ssd-doda-bot.env" = {
      owner = "ssd-doda-bot";
      group = "ssd-doda-bot";
      mode = "0400";
      content = ''
        TG_API_ID=${config.sops.placeholder.ssd-doda-bot-tg-api-id}
        TG_API_HASH=${config.sops.placeholder.ssd-doda-bot-tg-api-hash}
        TG_BOT_TOKEN=${config.sops.placeholder.ssd-doda-bot-tg-bot-token}
      '';
    };
  };

  # Nix settings - caches and experimental features
  nix.settings = {
    inherit (sharedNix.caches) substituters;
    trusted-public-keys = sharedNix.caches.trustedPublicKeys;
    experimental-features = sharedNix.experimentalFeatures;
  };

  services.home-assistant = {
    enable = true;
    config = null;
    lovelaceConfig = null;
    configDir = "/var/lib/hass";
    extraComponents = [
      "androidtv_remote"
      "backup"
      "cast"
      "cloud"
      "default_config"
      "enphase_envoy"
      "esphome"
      "go2rtc"
      "google_assistant"
      "google_translate"
      "group"
      "homekit_controller"
      "homewizard"
      "homekit"
      "ipp"
      "met"
      "mobile_app"
      "radio_browser"
      "rpi_power"
      "shelly"
      "shopping_list"
      "ssdp"
      "sun"
      "upnp"
      "zeroconf"
    ];
    extraPackages = python3Packages: [
      python3Packages.aiogithubapi
      pyvesync_2_1_15
    ];
    customComponents = [pkgs.home-assistant-custom-components.localtuya];
  };

  users = {
    groups.ssd-doda-bot = {};
    users.ssd-doda-bot = {
      isSystemUser = true;
      group = "ssd-doda-bot";
    };
  };

  systemd.services.ssd-doda-bot = {
    description = "SSD DODA Telegram bot";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "simple";
      User = "ssd-doda-bot";
      Group = "ssd-doda-bot";
      EnvironmentFile = config.sops.templates."ssd-doda-bot.env".path;
      ExecStart = lib.getExe' inputs.ssd-doda-bot.packages.${pkgs.stdenv.hostPlatform.system}.default "ssd-doda-bot";
      Restart = "always";
      RestartSec = "5s";

      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
    };
  };

  services.vscode-server.enable = true;
}
