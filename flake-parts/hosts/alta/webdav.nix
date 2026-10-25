{
  config,
  pkgs,
  ...
}: let
  prepare = pkgs.writeShellScript "prepare-webdav" ''
    set -euo pipefail
    umask 077
    # Never create a fallback data directory on the internal SD card.
    ${pkgs.util-linux}/bin/mountpoint -q /srv/webdav
    mkdir -p /srv/webdav/files
    export BWS_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${config.sops.secrets.BWS_ACCESS_TOKEN.path})"
    export BWS_SERVER_URL=https://vault.bitwarden.eu
    # Fetch at runtime; neither the password nor its hash enters the Nix store.
    ${pkgs.bws}/bin/bws secret get 115de79e-0fc4-4031-8e0f-b4ee01530545 --output json \
      | ${pkgs.jq}/bin/jq -er '.value | select(type == "string" and length > 0)' \
      | ${pkgs.apacheHttpd}/bin/htpasswd -niB alta > /run/webdav/htpasswd.new
    chown webdav:webdav /run/webdav/htpasswd.new
    chmod 0400 /run/webdav/htpasswd.new
    mv /run/webdav/htpasswd.new /run/webdav/htpasswd
  '';
in {
  fileSystems."/srv/webdav" = {
    device = "/dev/disk/by-uuid/69BC-736E";
    fsType = "exfat";
    options = [
      "nofail"
      "x-systemd.device-timeout=5s"
      "x-systemd.device-bound"
      "uid=988"
      "gid=982"
      "fmask=0177"
      "dmask=0077"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };
  # exFAT has no Unix ownership; keep the mount's IDs stable.
  users.groups.webdav.gid = 982;
  users.users.webdav = {
    uid = 988;
    isSystemUser = true;
    group = "webdav";
  };

  systemd.services.webdav = {
    description = "Authenticated HTTP WebDAV storage";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "sops-nix.service" "srv-webdav.mount"];
    requires = ["srv-webdav.mount"];
    bindsTo = ["srv-webdav.mount"];
    serviceConfig = {
      User = "webdav";
      Group = "webdav";
      ReadWritePaths = ["/srv/webdav"];
      RuntimeDirectory = "webdav";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      ExecStartPre = "+${prepare}";
      ExecStart = "${pkgs.rclone}/bin/rclone serve webdav /srv/webdav/files --addr :8080 --htpasswd /run/webdav/htpasswd --config /dev/null";
      Restart = "on-failure";
      RestartSec = "30s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
    };
  };
  # A newly attached drive starts WebDAV again after a missing-drive boot.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="69BC-736E", TAG+="systemd", ENV{SYSTEMD_WANTS}+="webdav.service"
  '';
  # Keep this private: no public tunnel is configured for WebDAV.
  networking.firewall.interfaces.end0.allowedTCPPorts = [8080];
}
