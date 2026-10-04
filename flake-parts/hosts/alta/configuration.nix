# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).
{
  config,
  pkgs,
  ...
}:
let
  bwsServerUrl = "https://vault.bitwarden.eu";

  bwsCli = pkgs.writeShellScriptBin "bws" ''
    set -euo pipefail
    export BWS_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.BWS_ACCESS_TOKEN.path})"
    export BWS_SERVER_URL="${bwsServerUrl}"
    exec ${pkgs.bws}/bin/bws "$@"
  '';
in
{
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

    actual = {
      enable = true;
      settings = {
        hostname = "127.0.0.1";
        port = 5006;
      };
    };

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
        # Allow GUI applications on this headless host over SSH; NixOS also
        # supplies the matching xauth store path to sshd.
        X11Forwarding = true;
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "yes";
      };
    };
  };

  systemd.services = {
    cloudflared-services = {
      description = "Cloudflare Tunnel for hosted services";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/tunnel-token";
        LoadCredential = "tunnel-token:/var/lib/cloudflared/vaultwarden.token";
        Restart = "on-failure";
        RestartSec = "5s";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
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
    bwsCli
    git
    jujutsu
    gg-jj
    dnsmasq
    iptables
    nftables
  ];

  # The remaining Home Assistant YAML is intentionally user-managed.
  environment.etc."home-assistant/http.yaml".text = ''
    use_x_forwarded_for: true
    trusted_proxies:
      - 127.0.0.1
      - "::1"
  '';

  programs = {
    direnv.enable = true;
    nix-ld.enable = true;
  };

  users = {
    groups.bws = { };
    users.alta = {
      isNormalUser = true;
      extraGroups = [
        "bws"
        "wheel"
      ];
      password = "     ";
    };
    extraUsers = {
      alta.openssh.authorizedKeys.keys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEuxsuGRgSwuYMG6qnRfp6PtKJeqiodnoBZfWjr60cVrAAAACnNzaDpiYWNrdXA= mykola.korniichuk.ua@gmail.com"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDc5+1k9yIiEF0ri0vkNuKhh/bIqXiQI3Ew1uCY12gprAAAACHNzaDptYWlu mykola.korniichuk.ua@gmail.com"
      ];
      root.openssh.authorizedKeys.keys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEuxsuGRgSwuYMG6qnRfp6PtKJeqiodnoBZfWjr60cVrAAAACnNzaDpiYWNrdXA= mykola.korniichuk.ua@gmail.com"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIDc5+1k9yIiEF0ri0vkNuKhh/bIqXiQI3Ew1uCY12gprAAAACHNzaDptYWlu mykola.korniichuk.ua@gmail.com"
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
