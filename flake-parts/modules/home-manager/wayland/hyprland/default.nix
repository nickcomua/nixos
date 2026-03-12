{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.wayland;
  mkAutostartEntry = {
    program,
    workspace,
  }: "[workspace ${workspace} silent] ${program}";
  mkAutostartList = entries: (map mkAutostartEntry entries);

  brightnessUp = pkgs.writeShellScript "brightness-up" ''
    ACTIVE_MONITOR=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | .name')
    # For laptop displays (eDP-*), use brightnessctl
    if echo "$ACTIVE_MONITOR" | ${pkgs.gnugrep}/bin/grep -qE '^eDP'; then
      ${pkgs.brightnessctl}/bin/brightnessctl set 10%+
    else
      # For external monitors, use DDC/CI
      # Based on ddcutil detect, Display 1 is the Samsung monitor (HDMI-A-1)
      # Try Display 1 first, then fallback to trying all displays
      ${pkgs.ddcutil}/bin/ddcutil -d 1 setvcp 10 + 10 2>/dev/null || \
      # If Display 1 fails, try other displays
      for DISPLAY_NUM in 2 3 4; do
        ${pkgs.ddcutil}/bin/ddcutil -d "$DISPLAY_NUM" setvcp 10 + 10 2>/dev/null && break
      done
    fi
  '';

  brightnessDown = pkgs.writeShellScript "brightness-down" ''
    ACTIVE_MONITOR=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused == true) | .name')
    # For laptop displays (eDP-*), use brightnessctl
    if echo "$ACTIVE_MONITOR" | ${pkgs.gnugrep}/bin/grep -qE '^eDP'; then
      ${pkgs.brightnessctl}/bin/brightnessctl set 10%-
    else
      # For external monitors, use DDC/CI
      # Based on ddcutil detect, Display 1 is the Samsung monitor (HDMI-A-1)
      # Try Display 1 first, then fallback to trying all displays
      ${pkgs.ddcutil}/bin/ddcutil -d 1 setvcp 10 - 10 2>/dev/null || \
      # If Display 1 fails, try other displays
      for DISPLAY_NUM in 2 3 4; do
        ${pkgs.ddcutil}/bin/ddcutil -d "$DISPLAY_NUM" setvcp 10 - 10 2>/dev/null && break
      done
    fi
  '';
in {
  home = {
    packages = with pkgs; [
      hyprcursor
      wl-clip-persist # clipboard persistence for Wayland
      wtype # Type text via Wayland
      yazi # Terminal file manager
      obsidian # Note-taking app
      ddcutil # DDC/CI control for external monitors
      btop # System monitor
    ];
    sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "wayland"; # helps with electron apps like 1password
    };
  };

  services = {
    hyprpolkitagent.enable = true;
  };

  xdg.configFile."electron-flags.conf" = {
    text = ''
      --enable-features=UseOzonePlatform
      --ozone-platform=wayland
    '';
  };

  wayland.windowManager.hyprland = {
    enable = true;

    # package and portportalPackage are set to null
    # because they are installed via NixOS instead of Home Manager
    # https://wiki.hyprland.org/Nix/Hyprland-on-Home-Manager/#using-the-home-manager-module-with-nixos
    package = null;
    portalPackage = null;

    plugins = [
      # inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system}.hyprexpo
    ];
    systemd.variables = ["--all"];
    settings = {
      # Configure multiple monitors
      # Format: "NAME,RESOLUTION@REFRESH,POSITION,SCALE"
      # Set via wayland.hyprland.monitor in host config
      inherit (cfg.hyprland) monitor;
      cursor = {
        # needed for nvidia
        no_hardware_cursors = true;
      };
      input = {
        kb_layout = "us";
        kb_variant = ",";
        kb_options = "grp:alt_shift_toggle";

        sensitivity = 0; # for mouse cursor

        # must click on window to move focus
        # follow_mouse=2

        touchpad = {
          natural_scroll = "yes";
          scroll_factor = 0.7;
        };
      };

      device = {
        name = "razer-razer-deathadder-v2-1";
        sensitivity = -1;
      };

      gestures = {
        workspace_swipe_touch = "yes";
      };

      general = {
        resize_on_border = true;
        gaps_in = 3;
        gaps_out = 3;
        border_size = 2;
        # rotating gradeint border!
        "col.active_border" = "rgba(88c0d0ff) rgba(b48eadff) rgba(ebcb8bff) rgba(a3be8cff) 45deg";
        "col.inactive_border" = "0xff434c5e";
      };
      decoration = {
        shadow = {
          enabled = true;
          range = 20;
          render_power = 3;
          color = "0xee1a1a1a";
          color_inactive = "0xee1a1a1a";
        };
        rounding = 10;

        blur = {
          enabled = true;
          size = 5; # minimum 1
          passes = 3; # minimum 1, more passes = more resource intensive.
          # Your blur "amount" is blur_size * blur_passes, but high blur_size (over around 5-ish) will produce artifacts.
          # if you want heavy blur, you need to up the blur_passes.
          # the more passes, the more you can up the blur_size without noticing artifacts.
          noise = 0.05;
          xray = false;
        };
      };
      group = {
        "col.border_inactive" = "0xff89dceb";
        "col.border_active" = "rgba(88c0d0ff) rgba(b48eadff) rgba(ebcb8bff) rgba(a3be8cff) 45deg";
      };
      misc = {
        enable_swallow = true;
        animate_manual_resizes = true;
        animate_mouse_windowdragging = true;
        disable_hyprland_logo = true;
        # this should spawn a window right on top of the terminal
        # but I couldn't get it working yet
        swallow_regex = "^(Alacritty|kitty|ghostty)$";
      };
      animations = {
        enabled = 1;

        bezier = [
          "easeOutQuint,0.22, 1, 0.36, 1" # https://easings.net/#easeOutQuint
          "easeOutSine,0.61, 1, 0.88, 1" # https://easings.net/#easeOutSine
        ];

        animation = [
          "windows,1,2,easeOutQuint,popin"
          "border,1,20,easeOutQuint"
          "fade,1,10,easeOutQuint"
          "workspaces,1,6,easeOutQuint,slide"
          # gradient disco party borders!
          "borderangle, 1, 30, easeOutSine, loop"
        ];
      };
      layerrule = [
        # eww
        "blur on, match:namespace gtk-layer-shell"
        "ignore_alpha 0, match:namespace gtk-layer-shell" # remove blurred surface around borders

        # use `hyprctl layers` to get layer namespaces
        "blur on, match:namespace notifications"
        "ignore_alpha 0, match:namespace notifications" # remove blurred surface around borders

        # vicinae
        "blur on, match:namespace (vicinae)"
        "dim_around on, match:namespace vicinae"
        "ignore_alpha 0, match:namespace (vicinae)"
      ];
      env = [
        "WLR_NO_HARDWARE_CURSORS,1"
        "XDG_SESSION_TYPE,wayland"
        "XCURSOR_THEME,catppuccin-mocha-blue-cursors"
        "XCURSOR_SIZE,${toString cfg.cursor.size}"
        "HYPRCURSOR_THEME,catppuccin-mocha-blue-cursors"
        "HYPRCURSOR_SIZE,${toString cfg.cursor.size}"
      ];

      # list of commands to run during Hyprland startup
      exec-once =
        [
          # import env vars set with home.sessionVariables
          "systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP ELECTRON_OZONE_PLATFORM_HINT"
          "wl-clip-persist --clipboard regular"
        ]
        ++ mkAutostartList cfg.hyprland.autostart;

      windowrule = [
        "float on, match:title ^(Open Folder)$" # File Chooser
        "float on, match:class xarchiver"
        "float on, match:title ^(Enter .*)$" # chrome login in English
        "float on, match:title ^*(Media viewer)$" # Telegram media viewer
        "float on, match:initial_class ^*(qimgv)$" # image viewer
        "float on, match:initial_class ^(chrome-.*)$"
        "stay_focused on, match:class ^(pinentry-.*)$"
        "pin on, match:class ^(pinentry-.*)$" # pin == show on all workspaces

        # persist window size between launches
        "persistent_size on, match:title ^*(Media viewer)$"
        "float on, match:initial_class ^*(qimgv)$" # image viewer

        # automatically open applications at specific workspaces
        "workspace 2, match:class org.telegram.desktop"

        # forbid screensharing for sensitive apps
        "no_screen_share on, match:class org.telegram.desktop"
        "no_screen_share on, match:class Slack"
        "no_screen_share on, match:class discord"
        "no_screen_share on, match:class Bitwarden"
        "no_screen_share on, match:class 1Password"
      ];

      bind = [
        # Whisper dictation - hold CTRL+` to record, release to transcribe + paste
        "CTRL,grave,exec,whisper-dictate-start"

        # starting applications
        "SUPER,RETURN,exec,${pkgs.ghostty}/bin/ghostty"
        "SUPER,E,exec,${pkgs.ghostty}/bin/ghostty -e ${pkgs.yazi}/bin/yazi"
        # application launcher
        "SUPER,space,exec,${pkgs.vicinae}/bin/vicinae toggle"
        "SUPER,v,exec,${pkgs.vicinae}/bin/vicinae deeplink vicinae://extensions/vicinae/clipboard/history"
        # open obsidian daily note
        "SUPER,B,exec, [float; minsize 500 500] ${pkgs.obsidian}/bin/obsidian obsidian://daily?vault=The%20Well"

        # window management
        "SUPER,Q,killactive"
        #"SUPER_SHIFT,M,exit"
        "SUPER,S,togglefloating"
        "SUPER,F,fullscreen"
        # move the active window to the next position
        "SUPER,N,swapnext"
        # make the active window the main
        "SUPER,A,togglesplit"
        # toggle pseudo tiling mode for a window
        "SUPER,P,pseudo,"
        # start hyprexpo - an overview of all workspaces
        # "SUPER, grave, hyprexpo:expo, toggle" # can be: toggle, off/disable or on/enable

        # screenshots
        ",Print,exec,${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
        ''SHIFT,Print,exec,${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy''
        "CTRL_SHIFT,Print,exec,${pkgs.grim}/bin/grim - | ${pkgs.satty}/bin/satty --filename -"

        # brightness control (active screen)
        ", XF86MonBrightnessUp,     exec, ${brightnessUp}"
        ", XF86MonBrightnessDown,   exec, ${brightnessDown}"

        # volume control (for pipewire / wireplumber)
        ", XF86AudioMute, exec, ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioRaiseVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%+"
        ", XF86AudioLowerVolume, exec, ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-"

        # disable notifications
        # TODO: find how to do it with hyprpanel
        # "SHIFT_SUPER,N,exec,makoctl mode -t do-not-disturb"

        # screen locking
        "SUPER,L,exec,hyprlock"
        # hyprland management
        "SUPER,R,exec,${pkgs.hyprland}/bin/hyprctl reload"

        # system monitor
        "CTRL_SHIFT,escape,exec,${pkgs.ghostty}/bin/ghostty -e ${pkgs.btop}/bin/btop"
      ];

      # move and resize windows with the mouse cursor
      bindm = [
        "SUPER,mouse:272,movewindow"
        "SHIFT_SUPER,mouse:272,resizewindow"
        "SUPER,mouse:273,resizewindow"
      ];

      dwindle = {
        pseudotile = 1; # enable pseudotiling on dwindle
        force_split = 0;
      };

      master = {};

      plugin = [];
    };

    extraConfig = ''
      debug:disable_logs = false

      # Whisper dictation - release CTRL+` to stop recording and transcribe
      bindr=CTRL,grave,exec,whisper-dictate-stop

      # special workspace
      bind=CTRL_SUPER,W,exec,${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspace special
      bind=SUPER,W,workspace,special
      bind=SHIFT_SUPER,W,exec, ${pkgs.hyprland}/bin/hyprctl dispatch togglespecialworkspace ""

      # navigation between windows
      bind=SUPER,left,movefocus,l
      bind=SUPER,right,movefocus,r
      bind=SUPER,up,movefocus,u
      bind=SUPER,down,movefocus,d

      # workspace selection
      bind=SUPER,1,workspace,1
      bind=SUPER,2,workspace,2
      bind=SUPER,3,workspace,3
      bind=SUPER,4,workspace,4
      bind=SUPER,5,workspace,5
      bind=SUPER,6,workspace,6
      bind=SUPER,7,workspace,7
      bind=SUPER,8,workspace,8
      bind=SUPER,9,workspace,9
      bind=SUPER,0,workspace,10

      # move window to workspace
      bind=SHIFT_SUPER,1,movetoworkspace,1
      bind=SHIFT_SUPER,2,movetoworkspace,2
      bind=SHIFT_SUPER,3,movetoworkspace,3
      bind=SHIFT_SUPER,4,movetoworkspace,4
      bind=SHIFT_SUPER,5,movetoworkspace,5
      bind=SHIFT_SUPER,6,movetoworkspace,6
      bind=SHIFT_SUPER,7,movetoworkspace,7
      bind=SHIFT_SUPER,8,movetoworkspace,8
      bind=SHIFT_SUPER,9,movetoworkspace,9
      bind=SHIFT_SUPER,0,movetoworkspace,10

      bind=SUPER,mouse_down,workspace,e+1
      bind=SUPER,mouse_up,workspace,e-1

      bind=SUPER,g,togglegroup
      bind=SUPER,tab,changegroupactive
    '';
  };
}
