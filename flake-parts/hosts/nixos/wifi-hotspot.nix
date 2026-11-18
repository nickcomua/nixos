{
  lib,
  pkgs,
  ...
}: let
  ethernet = "enp5s0";
  wifi = "wlp6s0";
  connection = "ethernet-hotspot";
  subnet = "10.42.0.0/24";
  gateway = "10.42.0.1/24";
  pskFile = "/var/lib/wifi-hotspot/psk.env";

  hotspot = pkgs.writeShellApplication {
    name = "ethernet-hotspot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.networkmanager
    ];
    text = ''
      ethernet_up() {
        local state
        [[ -r /sys/class/net/${ethernet}/carrier ]] || return 1
        [[ "$(cat /sys/class/net/${ethernet}/carrier)" == "1" ]] || return 1
        state="$(nmcli -g GENERAL.STATE device show ${ethernet} 2>/dev/null || true)"
        [[ "$state" == 100* ]]
      }

      hotspot_active() {
        [[ "$(nmcli -g GENERAL.CONNECTION device show ${wifi} 2>/dev/null || true)" == "${connection}" ]]
      }

      up() {
        local attempt=0
        if ! ethernet_up; then
          return 0
        fi
        if hotspot_active; then
          return 0
        fi
        while (( attempt < 8 )); do
          attempt=$((attempt + 1))
          if nmcli -t -f NAME connection show | grep -Fxq ${connection}; then
            if nmcli connection up ${connection} ifname ${wifi}; then
              return 0
            fi
          fi
          sleep 1
        done
        printf 'ethernet-hotspot: could not start the hotspot\n' >&2
        return 1
      }

      down() {
        if ! hotspot_active; then
          return 0
        fi
        nmcli connection down ${connection} >/dev/null 2>&1 || true
        nmcli device connect ${wifi} >/dev/null 2>&1 || true
      }

      case "''${1:-sync}" in
        up) up ;;
        down) down ;;
        sync)
          if ethernet_up; then
            up
          elif hotspot_active; then
            down
          fi
          ;;
        *)
          printf 'usage: ethernet-hotspot up|down|sync\n' >&2
          exit 2
          ;;
      esac
    '';
  };
in {
  # Share the built-in Ethernet port over Wi-Fi. The passphrase is generated
  # once into pskFile and substituted at activation, so it never enters the
  # world-readable Nix store. autoconnect stays off: the radio is an access
  # point only while enp5s0 is connected, then returns to the saved client.
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [pskFile];
    profiles.${connection} = {
      connection = {
        id = connection;
        type = "wifi";
        uuid = "7c49b02f-a687-4a1b-8d33-5c8244aea9f1";
        interface-name = wifi;
        autoconnect = false;
        autoconnect-priority = -999;
      };
      wifi = {
        mode = "ap";
        ssid = "nixos-hotspot";
        band = "bg";
        cloned-mac-address = "permanent";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_HOTSPOT_PSK";
      };
      ipv4 = {
        method = "shared";
        addresses = gateway;
        never-default = true;
      };
      ipv6.method = "disabled";
    };
  };

  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "ethernet-hotspot-dispatcher" ''
        if [[ "$1" != "${ethernet}" ]]; then
          exit 0
        fi
        case "$2" in
          up|dhcp4-change)
            ${lib.getExe hotspot} up
            ;;
          down)
            ${lib.getExe hotspot} down
            ;;
        esac
      '';
    }
  ];

  # NAT only the hotspot subnet out of Ethernet. Wi-Fi client traffic on
  # 192.168.1.0/24 is not rewritten.
  networking.nat = {
    enable = true;
    externalInterface = ethernet;
    internalIPs = [subnet];
  };

  networking.firewall.extraCommands = ''
    iptables -w -C nixos-fw -i ${wifi} -p udp --dport 67 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i ${wifi} -p udp --dport 67 -j nixos-fw-accept
    iptables -w -C nixos-fw -i ${wifi} -s ${subnet} -p udp --dport 53 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i ${wifi} -s ${subnet} -p udp --dport 53 -j nixos-fw-accept
    iptables -w -C nixos-fw -i ${wifi} -s ${subnet} -p tcp --dport 53 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i ${wifi} -s ${subnet} -p tcp --dport 53 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D nixos-fw -i ${wifi} -p udp --dport 67 -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -i ${wifi} -s ${subnet} -p udp --dport 53 -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -i ${wifi} -s ${subnet} -p tcp --dport 53 -j nixos-fw-accept 2>/dev/null || true
  '';

  systemd.services.wifi-hotspot-psk = {
    description = "Create the Wi-Fi hotspot passphrase if it is missing";
    wantedBy = ["multi-user.target"];
    before = ["NetworkManager-ensure-profiles.service"];
    path = [
      pkgs.coreutils
      pkgs.openssl
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0700 /var/lib/wifi-hotspot
      if [[ ! -s ${pskFile} ]]; then
        umask 077
        printf 'WIFI_HOTSPOT_PSK=%s\n' "$(openssl rand -hex 16)" > ${pskFile}
        chmod 0400 ${pskFile}
      fi
    '';
  };

  systemd.services.NetworkManager-ensure-profiles = {
    after = ["wifi-hotspot-psk.service"];
    wants = ["wifi-hotspot-psk.service"];
  };

  systemd.services.ethernet-hotspot = {
    description = "Start the Wi-Fi hotspot when ${ethernet} is connected";
    wantedBy = ["multi-user.target"];
    after = [
      "NetworkManager.service"
      "NetworkManager-ensure-profiles.service"
      "wifi-hotspot-psk.service"
    ];
    wants = [
      "NetworkManager-ensure-profiles.service"
      "wifi-hotspot-psk.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe hotspot} sync";
    };
  };

  environment.systemPackages = [hotspot];
}
