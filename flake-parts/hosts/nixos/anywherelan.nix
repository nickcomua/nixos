{pkgs, ...}: let
  awl = pkgs.stdenvNoCC.mkDerivation {
    pname = "awl";
    version = "0.20.0";
    src = pkgs.fetchurl {
      url = "https://github.com/anywherelan/awl/releases/download/v0.20.0/awl-linux-amd64-v0.20.0.tar.gz";
      hash = "sha256-/hoATKngUMq/4ViuM8agdg2J5NutqnNaCWYEKoy9D/c=";
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 awl "$out/bin/awl"
      runHook postInstall
    '';
    meta = {
      description = "Decentralized peer-to-peer mesh VPN";
      homepage = "https://github.com/anywherelan/awl";
      license = pkgs.lib.licenses.mpl20;
      platforms = ["x86_64-linux"];
      mainProgram = "awl";
    };
  };
  desktop = pkgs.makeDesktopItem {
    name = "anywherelan";
    desktopName = "Anywherelan";
    comment = "Manage the Anywherelan mesh VPN";
    exec = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:8639";
    icon = "network-vpn";
    categories = ["Network"];
  };
in {
  environment.systemPackages = [awl desktop];
  boot.kernelModules = ["tun"];

  # Allow paired awl peers to reach all services listening on the VPN interface.
  networking.firewall.trustedInterfaces = ["awl0"];

  systemd.services.awl = {
    description = "Anywherelan peer-to-peer mesh VPN";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    environment.AWL_DATA_DIR = "/var/lib/anywherelan";
    path = [pkgs.iproute2 pkgs.iptables pkgs.systemd pkgs.openresolv];
    serviceConfig = {
      ExecStart = "${awl}/bin/awl";
      StateDirectory = "anywherelan";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/anywherelan";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
