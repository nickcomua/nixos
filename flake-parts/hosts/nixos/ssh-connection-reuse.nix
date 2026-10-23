{lib, pkgs, ...}: let
  revoke = pkgs.writeShellApplication {
    name = "ssh-control-revoke";
    runtimeInputs = [pkgs.openssh pkgs.coreutils];
    text = builtins.readFile ./ssh-control-revoke.sh;
  };
in {
  # User/host-specific SSH settings can still override these system defaults.
  programs.ssh.extraConfig = lib.mkBefore ''
    Host *
      ControlMaster auto
      ControlPath /run/user/%i/ssh-session-%C
      ControlPersist yes
    Match all
  '';
  environment.systemPackages = [revoke];
  # Omarchy runs the same revoker when its Wayland session lock becomes secure.
  # Also clean up on logout; no remote authentication is needed to close masters.
  systemd.user.services.ssh-control-session = {
    description = "Revoke shared SSH connections when the graphical session ends";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = lib.getExe revoke;
    };
  };
}
