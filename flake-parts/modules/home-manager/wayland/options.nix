# Wayland module options - defines all configurable settings with defaults
{lib, ...}: {
  options.wayland = {
    cursor = {
      size = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size for Wayland compositors";
      };
    };

    font = {
      text = {
        size = lib.mkOption {
          type = lib.types.int;
          default = 13;
          description = "Default font size for UI elements";
        };
      };
    };

    hyprland = {
      monitor = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Monitor configuration for Hyprland. Empty list means auto-detect.";
      };

      autostart = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              program = lib.mkOption {
                type = lib.types.str;
                description = "Program to autostart";
              };
              workspace = lib.mkOption {
                type = lib.types.str;
                description = "Workspace to start the program on";
              };
            };
          }
        );
        default = [];
        description = "List of programs to autostart with their workspaces";
      };
    };

    hyprlock = {
      monitor = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Monitor for hyprlock screenshots";
      };

      auth = {
        grace = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Grace period in seconds before requiring password";
        };
        no_fade_in = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable fade in animation";
        };
        no_fade_out = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable fade out animation";
        };
        no_input_text = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Text to show when there's no input";
        };
      };
    };

    hypridle = {
      listener = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              timeout = lib.mkOption {
                type = lib.types.int;
                description = "Timeout in seconds";
              };
              onTimeout = lib.mkOption {
                type = lib.types.str;
                description = "Command to run on timeout";
              };
              onResume = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Command to run on resume";
              };
            };
          }
        );
        default = [
          {
            timeout = 300;
            onTimeout = "hyprctl dispatch dpms off";
            onResume = "hyprctl dispatch dpms on";
          }
          {
            timeout = 900;
            onTimeout = "grim -o '' /tmp/screenshot.png && (pidof hyprlock || hyprlock)";
            onResume = "";
          }
          {
            timeout = 1800;
            onTimeout = "systemctl suspend";
            onResume = "";
          }
        ];
        description = "List of idle timeout listeners";
      };
    };

    hyprpanel = {
      modules = {
        right = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "network"
            "bluetooth"
            "battery"
            "systray"
            "clock"
            "power"
          ];
          description = "Modules to show on the right side of the panel";
        };

        config = {
          cpuTemperature = {
            sensorPath = lib.mkOption {
              type = lib.types.str;
              default = "/sys/class/thermal/thermal_zone0/temp";
              description = "Path to CPU temperature sensor";
            };
          };
        };
      };
    };
  };
}
