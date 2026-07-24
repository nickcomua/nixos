{pkgs, ...}: {
  home.packages = [pkgs.hyprpaper];

  systemd.user.services.hyprpaper = {
    Unit = {
      Description = "hyprpaper";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.hyprpaper}/bin/hyprpaper";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = ["hyprland-session.target"];
    };
  };
}
