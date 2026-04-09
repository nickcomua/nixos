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

  ipc = "noctalia-shell ipc call";

  # Wrapper around wtype that fixes Noctalia's clipboard paste behavior.
  # Noctalia runs: cliphist decode <id> | wl-copy && wtype -M ctrl -M shift v
  # The Ctrl+Shift+V only works in terminals. This wrapper intercepts that
  # specific call and instead reads the clipboard text and types it directly
  # via wtype, which works universally in every app (terminals, browsers,
  # editors, etc.). All other wtype invocations pass through unchanged.
  wtype-wrapper = pkgs.writeShellScriptBin "wtype" ''
    real_wtype="${pkgs.wtype}/bin/wtype"

    # Detect Noctalia's broken text paste: "wtype -M ctrl -M shift v"
    if [ "$*" = "-M ctrl -M shift v" ]; then
      # Small delay for focus to return to the target window
      sleep 0.12
      # Read clipboard and type it directly -- works everywhere
      text="$(${pkgs.wl-clipboard}/bin/wl-paste --no-newline 2>/dev/null)" || true
      if [ -n "$text" ]; then
        exec "$real_wtype" -- "$text"
      fi
      exit 0
    fi

    # Everything else passes through to real wtype unchanged
    exec "$real_wtype" "$@"
  '';
in {
  home = {
    packages = with pkgs; [
      hyprcursor
      cliphist # clipboard history manager for Wayland
      wl-clipboard # wl-copy/wl-paste for Wayland clipboard
      wl-clip-persist # clipboard persistence for Wayland
      wtype-wrapper # wtype with fixed clipboard paste (wraps wtype)
      yazi # Terminal file manager
      obsidian # Note-taking app
      ddcutil # DDC/CI control for external monitors
      btop # System monitor
      hyprshot # Screenshot utility for Hyprland
    ];
    sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "wayland"; # helps with electron apps like 1password
    };
  };

  # Polkit agent is now handled by Noctalia's polkit-agent plugin
  # services.hyprpolkitagent.enable = true;

  xdg.configFile."electron-flags.conf" = {
    text = ''
      --enable-features=UseOzonePlatform
      --ozone-platform=wayland
    '';
  };

  # Force-overwrite hyprland.conf on every activation instead of refusing to
  # clobber a pre-existing file. This avoids activation failures like
  # "Existing file '/home/nick/.config/hypr/hyprland.conf' would be clobbered"
  # without leaving stale .bak files behind (which is what backupFileExtension
  # would do — and those backups would eventually collide too).
  xdg.configFile."hypr/hyprland.conf".force = true;

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
          natural_scroll = true;
          scroll_factor = 0.3;
          clickfinger_behavior = true;
        };
      };

      device = {
        name = "razer-razer-deathadder-v2-1";
        sensitivity = -1;
      };

      gestures = {
        workspace_swipe_touch = "yes";
      };

      # 3-finger left/right swipe to switch workspaces
      gesture = [
        "3, horizontal, workspace"
      ];

      general = {
        resize_on_border = true;
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        # rotating gradient border!
        "col.active_border" = "rgba(88c0d0ff) rgba(b48eadff) rgba(ebcb8bff) rgba(a3be8cff) 45deg";
        "col.inactive_border" = "0xff434c5e";
      };
      decoration = {
        rounding = 20;
        rounding_power = 2;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;
          size = 3;
          passes = 2;
          vibrancy = 0.1696;
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
        # Noctalia blur support
        # https://docs.noctalia.dev/getting-started/compositor-settings/hyprland/
        "blur true, match:namespace noctalia-background-.*$"
        "blur_popups true, match:namespace noctalia-background-.*$"
        "ignore_alpha 0.5, match:namespace noctalia-background-.*$"

        # eww
        "blur true, match:namespace gtk-layer-shell"
        "ignore_alpha 0, match:namespace gtk-layer-shell"

        # notifications
        "blur true, match:namespace notifications"
        "ignore_alpha 0, match:namespace notifications"
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
          # Clipboard watcher is handled by Noctalia (clipboardWatchTextCommand/clipboardWatchImageCommand)
          # Start Noctalia desktop shell
          "noctalia-shell"
          # KDE Connect indicator (tray icon + daemon)
          "kdeconnect-indicator"
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

        # Noctalia shell controls
        "SUPER,space,exec,${ipc} launcher toggle"
        "SUPER,V,exec,${ipc} launcher clipboard"
        "SUPER,S,exec,${ipc} controlCenter toggle"
        "SUPER,comma,exec,${ipc} settings toggle"

        # open obsidian daily note
        "SUPER,B,exec, [float; minsize 500 500] ${pkgs.obsidian}/bin/obsidian obsidian://daily?vault=The%20Well"

        # window management
        "SUPER,Q,killactive"
        #"SUPER_SHIFT,M,exit"
        "SUPER,T,togglefloating"
        "SUPER,F,fullscreen"
        # move the active window to the next position
        "SUPER,N,swapnext"
        # make the active window the main
        # "SUPER,A,togglesplit"
        # toggle pseudo tiling mode for a window
        "SUPER,P,pseudo,"
        # start hyprexpo - an overview of all workspaces
        # "SUPER, grave, hyprexpo:expo, toggle" # can be: toggle, off/disable or on/enable

        # screenshots
        ",Print,exec,${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
        ''SHIFT,Print,exec,${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.wl-clipboard}/bin/wl-copy''
        "CTRL_SHIFT,Print,exec,${pkgs.grim}/bin/grim - | ${pkgs.satty}/bin/satty --filename -"

        # screen locking
        "SUPER,L,exec,hyprlock"
        # hyprland management
        "SUPER,R,exec,${pkgs.hyprland}/bin/hyprctl reload"

        # system monitor (SUPER+Escape to avoid conflict with Noctalia clipboard
        # paste which uses wtype Ctrl+Shift+V and can trigger Ctrl+Shift keybinds)
        "SUPER,escape,exec,${pkgs.ghostty}/bin/ghostty -e ${pkgs.btop}/bin/btop"
      ];

      # Noctalia media/brightness keys (bindel/bindl for repeat/lock support)
      bindel = [
        ", XF86AudioRaiseVolume, exec, ${ipc} volume increase"
        ", XF86AudioLowerVolume, exec, ${ipc} volume decrease"
        ", XF86MonBrightnessUp, exec, ${ipc} brightness increase"
        ", XF86MonBrightnessDown, exec, ${ipc} brightness decrease"
      ];
      bindl = [
        ", XF86AudioMute, exec, ${ipc} volume muteOutput"
        ", XF86AudioMicMute, exec, ${ipc} volume muteInput"
      ];

      # move and resize windows with the mouse cursor
      bindm = [
        "SUPER,mouse:272,movewindow"
        "SHIFT_SUPER,mouse:272,resizewindow"
        "SUPER,mouse:273,resizewindow"
      ];

      dwindle = {
        # pseudotile = 1; # enable pseudotiling on dwindle
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
