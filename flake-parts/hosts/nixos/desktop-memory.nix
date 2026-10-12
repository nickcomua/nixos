# Keep memory warnings alive even if a terminal's entire process group dies.
{ lib, pkgs, ... }:
let
  warning = pkgs.writeShellScript "desktop-memory-warning" (
    builtins.replaceStrings [ "@notify@" ] [ "${pkgs.libnotify}/bin/notify-send" ] (
      builtins.readFile ./memory-warning.sh
    )
  );
in
{
  home-manager.users.nick = {
    systemd.user.services.desktop-memory-warning = {
      Unit.Description = "Warn before desktop memory exhaustion";
      Service = {
        Type = "oneshot";
        ExecStart = warning;
        Environment = "PATH=${lib.makeBinPath [ pkgs.coreutils ]}";
      };
    };
    systemd.user.timers.desktop-memory-warning = {
      Unit.Description = "Check desktop memory every 15 seconds";
      Timer = {
        OnStartupSec = "30s";
        OnUnitActiveSec = "15s";
        AccuracySec = "1s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
    # Zed otherwise inherits the terminal scope, even after it daemonizes.
    programs.zsh.initContent = lib.mkAfter ''
      zeditor() {
        command ${pkgs.systemd}/bin/systemd-run --user --scope --collect \
          --quiet --same-dir -- ${pkgs.zed-editor}/bin/zeditor "$@"
      }
    '';
  };
}
