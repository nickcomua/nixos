# Hypridle configuration module
{config, ...}: let
  cfg = config.wayland;
in {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "grim -o ${cfg.hyprlock.monitor} /tmp/screenshot.png && (pidof hyprlock || hyprlock)"; # avoid starting multiple hyprlock instances.
        unlock_cmd = ''notify-send "unlock-cmd"''; # same as above, but unlock
        before_sleep_cmd = "loginctl lock-session"; # lock before suspend
        after_sleep_cmd = "hyprctl dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
        ignore_dbus_inhibit = false; # whether to ignore dbus-sent idle-inhibit requests (used by e.g. firefox or steam)
        ignore_systemd_inhibit = false; # whether to ignore systemd-inhibit --what=idle inhibitors
      };
      inherit (cfg.hypridle) listener;
    };
  };
}
