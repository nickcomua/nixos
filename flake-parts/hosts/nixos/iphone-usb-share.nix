{
  config,
  lib,
  pkgs,
  ...
}: let
  share = pkgs.writeShellApplication {
    name = "iphone-usb-share";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.networkmanager
    ];
    text = builtins.readFile ./iphone-usb-share.sh;
  };
  installIpa = pkgs.writeShellApplication {
    name = "iphone-install-ipa";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.openssh
    ];
    excludeShellChecks = ["SC2029"];
    text = builtins.readFile ./iphone-install-ipa.sh;
  };
in {
  services.usbmuxd.enable = true;

  # Mode 3: CDC-NCM + mux (USB configuration 5). -p skips lockdownd preflight
  # so a jailbroken phone still enumerates.
  systemd.services.usbmuxd = {
    environment.USBMUXD_DEFAULT_DEVICE_MODE = "3";
    serviceConfig.ExecStart = lib.mkForce "${config.services.usbmuxd.package}/bin/usbmuxd -U ${config.services.usbmuxd.user} -v -p -f";
  };

  # Stable name for Apple CDC-NCM so firewall and NM can bind to it.
  services.udev.extraRules = ''
    SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="05ac", ENV{ID_NET_DRIVER}=="cdc_ncm", NAME="iphoneusb"
  '';

  networking.firewall.trustedInterfaces = ["iphoneusb"];
  networking.firewall.extraCommands = ''
    iptables -w -C nixos-fw -i iphoneusb -p udp --dport 67 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i iphoneusb -p udp --dport 67 -j nixos-fw-accept
    iptables -w -C nixos-fw -i iphoneusb -p udp --dport 53 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i iphoneusb -p udp --dport 53 -j nixos-fw-accept
    iptables -w -C nixos-fw -i iphoneusb -p tcp --dport 53 -j nixos-fw-accept 2>/dev/null || iptables -w -I nixos-fw 1 -i iphoneusb -p tcp --dport 53 -j nixos-fw-accept
  '';
  networking.firewall.extraStopCommands = ''
    iptables -w -D nixos-fw -i iphoneusb -p udp --dport 67 -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -i iphoneusb -p udp --dport 53 -j nixos-fw-accept 2>/dev/null || true
    iptables -w -D nixos-fw -i iphoneusb -p tcp --dport 53 -j nixos-fw-accept 2>/dev/null || true
  '';

  systemd.services.iphone-iproxy = {
    description = "Loopback SSH forward to the USB iPhone";
    after = ["usbmuxd.service"];
    wants = ["usbmuxd.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "nick";
      Restart = "on-failure";
      RestartSec = 3;
      ExecStart = "${pkgs.libusbmuxd}/bin/iproxy -s 127.0.0.1 2222:22";
    };
  };

  systemd.services.iphone-usb-share = {
    description = "Share this PC's internet to the iPhone over USB NCM";
    bindsTo = ["sys-subsystem-net-devices-iphoneusb.device"];
    after = [
      "sys-subsystem-net-devices-iphoneusb.device"
      "NetworkManager.service"
      "usbmuxd.service"
      "iphone-iproxy.service"
    ];
    wants = [
      "NetworkManager.service"
      "usbmuxd.service"
      "iphone-iproxy.service"
    ];
    wantedBy = ["sys-subsystem-net-devices-iphoneusb.device"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe share} up";
      ExecStop = "${lib.getExe share} down";
    };
  };

  users.users.nick.extraGroups = ["usbmux"];

  environment.systemPackages = [
    share
    installIpa
    pkgs.libimobiledevice
    pkgs.libusbmuxd
  ];
}
