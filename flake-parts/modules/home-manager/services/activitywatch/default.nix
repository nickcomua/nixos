{
  localFlake,
  inputs,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  # Install aw-watcher-window-hyprland from the flake input
  home.packages = [
    inputs.aw-watcher-window-hyprland.defaultPackage.${pkgs.system}
  ];

  # ActivityWatch systemd service
  systemd.user.services.activitywatch = {
    Unit = {
      Description = "ActivityWatch - Automated time tracker";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.activitywatch}/bin/aw-qt --no-gui";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # aw-watcher-window-hyprland systemd service
  systemd.user.services.aw-watcher-window-hyprland = {
    Unit = {
      Description = "ActivityWatch Hyprland Window Watcher";
      After = [
        "graphical-session.target"
        "activitywatch.service"
      ];
      PartOf = ["graphical-session.target"];
      Requires = ["activitywatch.service"];
    };

    Service = {
      ExecStart = "${
        inputs.aw-watcher-window-hyprland.defaultPackage.${pkgs.system}
      }/bin/aw-watcher-window-hyprland";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
