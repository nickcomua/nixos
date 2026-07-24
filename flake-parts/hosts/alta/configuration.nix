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
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "yes";
      };
    };
  };

  systemd = {
    services = {
      holesail = {
        description = "Holesail tunnel for the local service";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${holesail}/bin/holesail --connect hs://s000ojG5RcxT7gDFcUckzG1S5c2GUBZcmIkA --host 127.0.0.1 --port 8080";
          Restart = "always";
          RestartSec = "10s";
        };
      };

      holesail-local-post = {
        description = "POST to the service exposed through Holesail";
        after = ["holesail.service"];
        requires = ["holesail.service"];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 20 --request POST http://127.0.0.1:8080/";
        };
      };
    };

    timers.holesail-local-post = {
      description = "POST to the local Holesail service every minute";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "1min";
        Persistent = true;
      };
    };
  };

  networking = {
    hostName = "alta";
    interfaces.end0.useDHCP = true;
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

  environment = {
    etc."systemd/resolved.conf.d/custom.conf".text = ''
      [Resolve]
      MulticastDNS=yes
      DNSStubListener=yes
      DNSStubListenerExtra=172.17.0.1
    '';
    systemPackages = with pkgs; [
      git
      dnsmasq
      iptables
      nftables
      dive
      podman-tui
      docker-compose
    ];
  };

  programs = {
    direnv.enable = true;
    nix-ld.enable = true;
  };

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  users = {
    users.alta = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "docker"
      ];
      password = "     ";
    };
    extraUsers = {
      alta.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaEFydTkBViXJm0/JFThRvRthUm4j4RfZ3SL8GYoWDi mykola.korniichuk.ua@gmail.com"
      ];
      root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMaEFydTkBViXJm0/JFThRvRthUm4j4RfZ3SL8GYoWDi mykola.korniichuk.ua@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBQnJ1mXvCd8Q4i6Hg2kA6AzDSpbwBI4aEB9SN5v6hVF dokploy"
      ];
    };
  };

  time.timeZone = "Europe/Amsterdam";

  virtualisation = {
    containers.enable = true;
    docker = {
      enable = true;
      daemon.settings = {
        live-restore = false;
        dns = [
          "172.17.0.1"
          "8.8.8.8"
          "8.8.4.4"
        ];
      };
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.05";
}
