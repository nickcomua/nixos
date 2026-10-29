{
  lib,
  pkgs,
  ...
}: let
  # Headless upstream release: avoid Electron and npm downloads at service startup.
  t3 = pkgs.stdenv.mkDerivation rec {
    pname = "t3code-cli";
    version = "0.1.5";
    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-arm64.tar.gz";
      sha256 = "389362e2a349ea62b38d9bc708f4fca2381936cccb2d326b5fc5d074b072aef1";
    };
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.stdenv.cc.cc.lib pkgs.libsecret];
    dontBuild = true;
    # The executable contains its JS payload; stripping can corrupt it.
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/t3code $out/bin
      cp -a . $out/lib/t3code/
      ln -s $out/lib/t3code/t3 $out/bin/t3
      runHook postInstall
    '';
    meta = {
      description = "T3 Code headless server";
      homepage = "https://github.com/pingdotgg/t3code";
      license = lib.licenses.mit;
      platforms = ["aarch64-linux"];
      mainProgram = "t3";
    };
  };
in {
  environment.systemPackages = [t3];

  # Use the existing unprivileged account: projects, provider logins and T3's
  # identity/database all stay in /home/alta, also when invoked over SSH.
  users.users.alta.linger = true;
  systemd.user.services.t3code = {
    description = "T3 Code headless coding environment";
    wantedBy = ["default.target"];
    unitConfig.ConditionUser = "alta";
    path = [pkgs.git pkgs.jujutsu pkgs.openssh pkgs.nodejs pkgs.curl pkgs.bash];
    environment = {
      HOME = "/home/alta";
      T3CODE_HOME = "/home/alta/.t3";
      PATH = lib.mkForce "/home/alta/.local/bin:/home/alta/.nix-profile/bin:/run/current-system/sw/bin:${lib.makeBinPath [pkgs.git pkgs.jujutsu pkgs.openssh pkgs.nodejs pkgs.curl pkgs.bash pkgs.coreutils]}";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/home/alta";
      ExecStart = "${lib.getExe t3} serve --host 0.0.0.0 --port 3773";
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      # Deliberately allow project/home writes and JIT/subprocess execution.
      # T3 is an agent host, not a read-only web server. Never run it as root.
      NoNewPrivileges = true;
    };
  };
}
