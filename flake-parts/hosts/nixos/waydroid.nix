# CloudStream on Linux: https://recloudstream.github.io/csdocs/other-devices/linux/
# The Waydroid package already wraps pyclip and wl-clipboard, which is the
# clipboard section of that guide. Shared folders still need a bind mount
# once a session has mounted Android storage.
{
  config,
  lib,
  pkgs,
  ...
}: let
  userName = "nick";
  user = config.users.users.${userName};
  home = user.home;
  group =
    if user.group == null
    then "users"
    else user.group;
  hostRoot = "${home}/Waydroid";
  hostIn = "${hostRoot}/host";
  hostOut = "${hostRoot}/droid";
  media = "${home}/.local/share/waydroid/data/media/0";
  androidIn = "${media}/Waydroid/host";
  androidOut = "${media}/Waydroid/droid";

  share = pkgs.writeShellApplication {
    name = "waydroid-share";
    runtimeInputs = [
      pkgs.acl
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      host_root=${lib.escapeShellArg hostRoot}
      host_in=${lib.escapeShellArg hostIn}
      host_out=${lib.escapeShellArg hostOut}
      media=${lib.escapeShellArg media}
      android_root=${lib.escapeShellArg "${media}/Waydroid"}
      android_in=${lib.escapeShellArg androidIn}
      android_out=${lib.escapeShellArg androidOut}

      mounted() {
        findmnt --mountpoint "$1" >/dev/null 2>&1
      }

      share_down() {
        if mounted "$android_in"; then
          umount -l "$android_in"
        fi
        if mounted "$host_out"; then
          umount -l "$host_out"
        fi
      }

      share_up() {
        install -d -o ${lib.escapeShellArg userName} -g ${lib.escapeShellArg group} -m 0755 \
          "$host_root" "$host_in" "$host_out"
        if [[ ! -d "$media" ]]; then
          echo "Waydroid session storage is not mounted ($media)." >&2
          echo "Start a session, then run: sudo waydroid-share up" >&2
          exit 1
        fi
        install -d -m 0777 "$android_root" "$android_in" "$android_out"
        # Host files show up in Android read-only, matching the guide.
        if ! mounted "$android_in"; then
          mount --bind "$host_in" "$android_in"
        fi
        mount -o remount,bind,ro "$android_in"
        # Files Android writes under /sdcard/Waydroid/droid show up on the host.
        if ! mounted "$host_out"; then
          mount --bind "$android_out" "$host_out"
        fi
        # Android writes these as mode 0660/0770, group 1023, other none.
        grant_host_user || true
      }

      # Named-user ACL so the current login can read new downloads before it
      # picks up the waydroid-media group.
      grant_host_user() {
        setfacl -R -m u:${userName}:rwX -m d:u:${userName}:rwX "$host_out"
      }

      fix_perms() {
        if ! mounted "$host_out"; then
          echo "Waydroid share is not mounted ($host_out)." >&2
          exit 1
        fi
        while mounted "$host_out"; do
          grant_host_user || true
          sleep 5
        done
      }

      if [[ "$#" -ne 1 ]]; then
        echo "usage: waydroid-share up|down|fix-perms" >&2
        exit 1
      fi
      case "$1" in
        up) share_up ;;
        down) share_down ;;
        fix-perms) fix_perms ;;
        *)
          echo "usage: waydroid-share up|down|fix-perms" >&2
          exit 1
          ;;
      esac
    '';
  };
in {
  virtualisation.waydroid.enable = true;
  # This kernel ships nf_tables and has no ip_tables.ko. The default Waydroid
  # package calls legacy iptables and then fails while bringing up waydroid0.
  virtualisation.waydroid.package = pkgs.waydroid-nftables;

  # Files Android writes under /sdcard are owned by the app and group
  # AID_MEDIA_RW (1023), mode 0660/0770. Membership makes new files readable
  # after the next login. The ACL service covers the session already running.
  users.groups.waydroid-media.gid = 1023;
  users.users.${userName}.extraGroups = ["waydroid-media"];

  environment.systemPackages = [share];

  systemd.tmpfiles.rules = [
    "d ${hostRoot} 0755 ${userName} ${group} -"
    "d ${hostIn} 0755 ${userName} ${group} -"
    "d ${hostOut} 0755 ${userName} ${group} -"
  ];

  systemd.paths.waydroid-share = {
    description = "Bind Waydroid shared folders once session storage appears";
    wantedBy = ["multi-user.target"];
    pathConfig.PathExists = media;
  };

  systemd.services.waydroid-share = {
    description = "Bind-mount Waydroid shared folders";
    after = ["waydroid-container.service"];
    partOf = ["waydroid-container.service"];
    wants = ["waydroid-share-acl.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe share} up";
      ExecStop = "${lib.getExe share} down";
    };
  };

  systemd.services.waydroid-share-acl = {
    description = "Grant the host user access to files Android writes into the shared folder";
    after = ["waydroid-share.service"];
    bindsTo = ["waydroid-share.service"];
    partOf = ["waydroid-container.service"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe share} fix-perms";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Drop the binds before the container tears down session storage.
  systemd.services.waydroid-container.preStop = ''
    ${lib.getExe share} down
  '';
}
