{pkgs, ...}: let
  releases = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-/hoATKngUMq/4ViuM8agdg2J5NutqnNaCWYEKoy9D/c=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-see8lnoDaXvXmUFOzsyg3+CgIy42K5OXkYr+4YZVeEA=";
    };
  };
  release = releases.${pkgs.stdenv.hostPlatform.system};
  awl = pkgs.stdenvNoCC.mkDerivation {
    pname = "awl";
    version = "0.20.0";
    src = pkgs.fetchurl {
      url = "https://github.com/anywherelan/awl/releases/download/v0.20.0/awl-linux-${release.arch}-v0.20.0.tar.gz";
      inherit (release) hash;
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
      platforms = builtins.attrNames releases;
      mainProgram = "awl";
    };
  };
in {
  environment.systemPackages = [awl];
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
