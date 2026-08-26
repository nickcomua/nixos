# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  ...
}: let
  holesail = pkgs.stdenv.mkDerivation {
    pname = "holesail";
    version = "2.4.1";

    src = pkgs.fetchurl {
      url = "https://github.com/holesail/holesail/releases/download/2.4.1/linux-arm64.zip";
      hash = "sha256-NMWZdPFM3agA6bx8v0oe5oc+U4r1qLtafEh1hJbFqN4=";
    };

    nativeBuildInputs = [pkgs.unzip];
    dontUnpack = true;

    installPhase = ''
      unzip "$src" -d release
      install -Dm755 "$(find release -type f -name holesail -print -quit)" "$out/bin/holesail"
    '';
  };
in {
  imports = [
    ./hardware-configuration.nix
  ];

  # The Raspberry Pi 4 USB-C power connector also supports USB 2 gadget mode.
  # Present it as an Ethernet adapter whenever Alta is powered over USB-C.
  boot = {
    kernelModules = [
      "dwc2"
      "g_ether"
    ];
    extraModprobeConfig = ''
      options g_ether dev_addr=02:00:00:00:07:02 host_addr=02:00:00:00:07:01
    '';
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  services = {
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
    resolved.enable = true;

    # Assign the USB host 192.168.7.1 so Alta is always reachable at
    # 192.168.7.2 without relying on Ethernet, mDNS, or internet access.
    dnsmasq = {
      enable = true;
      settings = {
        interface = "usb0";
        bind-dynamic = true;
        dhcp-range = "192.168.7.1,192.168.7.1,255.255.255.0,1h";
        dhcp-option = "option:router";
      };
    };

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "yes";
      };
    };
  };

  systemd.services.holesail-ssh = {
    description = "Expose Alta SSH through Holesail";
    after = [
      "network-online.target"
      "sshd.service"
    ];
    wants = ["network-online.target"];
    requires = ["sshd.service"];
    wantedBy = ["multi-user.target"];

    preStart = ''
      umask 077
      export BWS_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.BWS_ACCESS_TOKEN.path})"
      export BWS_SERVER_URL="https://vault.bitwarden.eu"

      ${pkgs.bws}/bin/bws secret get \
        f197f4ae-b8ae-4f9a-998d-b4b00156fb3a \
        --output json \
        | ${pkgs.jq}/bin/jq --exit-status --raw-output '.value | select(length > 0)' \
        > /run/holesail-ssh/connection-key
    '';

    script = ''
      exec ${holesail}/bin/holesail \
        --live 22 \
        --host 127.0.0.1 \
        --key "$(${pkgs.coreutils}/bin/cat /run/holesail-ssh/connection-key)"
    '';

    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "holesail-ssh";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "null";

      # Holesail needs outbound networking only; SSH stays bound to localhost.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  systemd.services.home-assistant-holesail = {
    description = "Expose Home Assistant through Holesail";
    after = [
      "network-online.target"
      "home-assistant.service"
    ];
    wants = ["network-online.target"];
    requires = ["home-assistant.service"];
    wantedBy = ["multi-user.target"];

    preStart = ''
      ${pkgs.coreutils}/bin/install \
        --mode 0600 \
        ${config.sops.secrets.home-assistant-holesail-key.path} \
        /run/home-assistant-holesail/connection-key
    '';

    script = ''
      exec ${holesail}/bin/holesail \
        --live 8123 \
        --host 127.0.0.1 \
        --key "$(${pkgs.coreutils}/bin/cat /run/home-assistant-holesail/connection-key)" \
        --log
    '';

    serviceConfig = {
      Type = "simple";
      RuntimeDirectory = "home-assistant-holesail";
      RuntimeDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "null";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };

  networking = {
    hostName = "alta";
    interfaces = {
      end0.useDHCP = true;
      usb0 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "192.168.7.2";
            prefixLength = 24;
          }
        ];
      };
    };
    nameservers = [
      "127.0.0.53"
      "8.8.8.8"
      "8.8.4.4"
    ];
    firewall = {
      enable = true;
      allowedTCPPortRanges = [
        {
          from = 0;
          to = 65535;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 0;
          to = 65535;
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    git
    jujutsu
    gg-jj
    dnsmasq
    iptables
    nftables
  ];

  programs = {
    direnv.enable = true;
    nix-ld.enable = true;
  };

  users = {
    users.alta = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
      password = "     ";
    };
    extraUsers = {
      alta.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu6go/Gdfcvom2fGVsGnZ8lVUYgeg0ujHCi8HCikU3o mykola.korniichuk.ua@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaEFydTkBViXJm0/JFThRvRthUm4j4RfZ3SL8GYoWDi mykola.korniichuk.ua@gmail.com"
      ];
      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu6go/Gdfcvom2fGVsGnZ8lVUYgeg0ujHCi8HCikU3o mykola.korniichuk.ua@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaEFydTkBViXJm0/JFThRvRthUm4j4RfZ3SL8GYoWDi mykola.korniichuk.ua@gmail.com"
      ];
    };
  };

  time.timeZone = "Europe/Amsterdam";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
