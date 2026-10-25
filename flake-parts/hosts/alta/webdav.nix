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

    if [[ ! -f /var/lib/webdav-tls/key.pem ]]; then
      ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
        -subj /CN=alta.local \
        -addext 'subjectAltName=DNS:alta.local,DNS:alta,DNS:alta.home,IP:192.168.1.96,IP:192.168.7.2' \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -keyout /var/lib/webdav-tls/key.pem.new \
        -out /var/lib/webdav-tls/cert.pem.new
      chown webdav:webdav /var/lib/webdav-tls/*.new
      chmod 0400 /var/lib/webdav-tls/key.pem.new
      chmod 0444 /var/lib/webdav-tls/cert.pem.new
      mv /var/lib/webdav-tls/cert.pem.new /var/lib/webdav-tls/cert.pem
      mv /var/lib/webdav-tls/key.pem.new /var/lib/webdav-tls/key.pem
    fi
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
    description = "Authenticated HTTPS WebDAV storage";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "sops-nix.service" "srv-webdav.mount"];
    requires = ["srv-webdav.mount"];
    bindsTo = ["srv-webdav.mount"];
    serviceConfig = {
      User = "webdav";
      Group = "webdav";
      StateDirectory = "webdav-tls";
      ReadWritePaths = ["/srv/webdav"];
      StateDirectoryMode = "0700";
      RuntimeDirectory = "webdav";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      ExecStartPre = "+${prepare}";
      ExecStart = "${pkgs.rclone}/bin/rclone serve webdav /srv/webdav/files --addr :8443 --htpasswd /run/webdav/htpasswd --cert /var/lib/webdav-tls/cert.pem --key /var/lib/webdav-tls/key.pem --config /dev/null";
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
  networking.firewall.interfaces.end0.allowedTCPPorts = [8443];
}
