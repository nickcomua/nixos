# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  lib,
  pkgs,
  ...
}: {
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
