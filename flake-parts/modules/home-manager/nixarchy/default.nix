{
  config,
  lib,
  pkgs,
  inputs,
  osConfig,
  ...
}: let
  snapshot = ../../../hosts/nixos/desktop;
  manifest = builtins.fromJSON (builtins.readFile (snapshot + "/manifest.json"));
  sources =
    lib.mapAttrs (
      _: source:
        if source.kind == "git"
        then
          pkgs.fetchgit {
            inherit (source) url rev hash;
          }
        else snapshot + "/sources/${source.path}"
    )
    manifest.sources;
  sourceMap = pkgs.writeText "nixarchy-sources.json" (builtins.toJSON sources);
  # nixpkgs helper programs use stock Nix, which cannot parse Determinate-only
  # settings such as lazy-trees and provenance from /etc/nix/nix.conf.
  toolNixConfig = pkgs.writeTextDir "nix.conf" ''
    experimental-features = nix-command flakes
    extra-substituters = https://cache.flakehub.com https://edge.cache.flakehub.com
  '';
  configTool = pkgs.writeShellApplication {
    name = "nixarchy-config";
    runtimeInputs = [pkgs.python3 pkgs.git pkgs.nix-prefetch-git pkgs.nix pkgs.jujutsu pkgs.nh pkgs.lua pkgs.alejandra];
    text = ''
      export NIXARCHY_SNAPSHOT=${snapshot}
      export NIXARCHY_SOURCES=${sourceMap}
      export NIX_CONF_DIR=${toolNixConfig}
      exec python3 ${./config.py} "$@"
    '';
  };
  omarchyTree = osConfig.programs.nixarchy.tree or "${config.programs.nixarchy.package}/share/omarchy";
  logindLock = pkgs.writeShellApplication {
    name = "omarchy-logind-lock";
    runtimeInputs = [pkgs.dbus pkgs.systemd];
    text = ''
      # Follow only this graphical session, not another user's lock requests.
      session="''${XDG_SESSION_ID:?Missing graphical session ID}"
      session_path=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager GetSession s "$session")
      session_path="''${session_path#o \"}"
      session_path="''${session_path%\"}"
      dbus-monitor --system \
        "type='signal',sender='org.freedesktop.login1',path='$session_path',interface='org.freedesktop.login1.Session',member='Lock'" \
        | while IFS= read -r event; do
          if [[ "$event" == signal\ * && "$event" == *"interface=org.freedesktop.login1.Session; member=Lock" ]]; then
            /run/current-system/sw/bin/omarchy-shell lock lock
          fi
        done
    '';
  };
in {
  imports = [inputs.nixarchy.homeManagerModules.nixarchy];
  programs.nixarchy = {
    enable = true;
    defaultTheme = "tokyo-night";
    # Same patched Omarchy as the system package (hosts/nixos): the
    # home-manager module otherwise installs an unpatched copy in the user
    # profile. The agents panel is a user plugin clone (nick.agents in the
    # desktop snapshot), so no collector discovery patch is needed here.
    package = (pkgs.extend inputs.nixarchy.overlays.default).omarchy.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace default/sddm/omarchy/Main.qml \
            --replace-fail 'Keys.onPressed: {' 'Keys.onPressed: function(event) {'
          ${pkgs.python3}/bin/python3 ${../../../hosts/nixos/patch-omarchy-auth.py} .
        '';
      # Run after Nixarchy's own notification patches, not before their anchors.
      postInstall =
        (old.postInstall or "")
        + ''
          ${pkgs.python3}/bin/python3 ${../../../hosts/nixos/patch-omarchy-auth.py} --notifications "$out/share/omarchy"
        '';
    });
  };
  home = {
    packages = [configTool];
    sessionVariables = {
      NIXARCHY_FLAKE = "/home/nick/.config/nixos";
      NH_ELEVATION_STRATEGY = "/run/wrappers/bin/pkexec";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
    };

    # Restore the committed baseline before upstream's copy-if-absent activation.
    # Existing mutable files are never overwritten on ordinary rebuilds.
    activation.nixarchyDesktop = lib.hm.dag.entryBetween ["nixarchySeed" "linkGeneration"] ["writeBoundary"] ''
      run ${configTool}/bin/nixarchy-config seed
    '';
    # The graphical session bakes OMARCHY_PATH into the session launcher at
    # build time, so after a switch the running Hyprland/systemd session
    # still points at the previous Omarchy tree and keybinds such as
    # Super+Space spawn commands from the old tree. Point the live session
    # at this generation's tree and restart the shell onto it. Best effort:
    # never fail activation when no graphical session is running.
    activation.nixarchySessionEnv = lib.hm.dag.entryAfter ["writeBoundary"] ''
      runtimeDir="/run/user/$(id -u)"
      export XDG_RUNTIME_DIR="$runtimeDir"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtimeDir/bus"
      systemctl=${pkgs.systemd}/bin/systemctl
      currentOmarchyPath=$($systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
      if [[ "$currentOmarchyPath" != "${omarchyTree}" ]]; then
        # omarchy-restart-shell kills the config named by the *new* session
        # environment, so stop the previous tree's shell explicitly first.
        if [[ -n "$currentOmarchyPath" && -d "$currentOmarchyPath/shell" ]]; then
          while timeout 5 /run/current-system/sw/bin/quickshell kill -p "$currentOmarchyPath/shell" --any-display >/dev/null 2>&1; do :; done
        fi
        currentPath=$($systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p' | tail -n 1)
        newPath="${omarchyTree}/bin"
        IFS=: read -r -a pathParts <<< "$currentPath"
        for part in "''${pathParts[@]}"; do
          if [[ -n "$part" && "$part" != *nixarchy-omarchy-tree/bin ]]; then
            newPath="$newPath:$part"
          fi
        done
        $systemctl --user set-environment "OMARCHY_PATH=${omarchyTree}" "PATH=$newPath" || true
        hyprDir=$(find "$runtimeDir/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
        if [[ -n "$hyprDir" ]]; then
          export HYPRLAND_INSTANCE_SIGNATURE="''${hyprDir##*/}"
          /run/current-system/sw/bin/hyprctl eval "hl.env('OMARCHY_PATH', '${omarchyTree}')" >/dev/null 2>&1 || true
          /run/current-system/sw/bin/hyprctl eval "hl.env('PATH', '$newPath')" >/dev/null 2>&1 || true
          env "OMARCHY_PATH=${omarchyTree}" "PATH=$newPath" "${omarchyTree}/bin/omarchy-restart-shell" >/dev/null 2>&1 || true
        fi
      fi
    '';
    # Seed the default agent once; subsequent UI changes belong to the user.
    activation.nixarchyDefaultAgent = lib.mkForce (lib.hm.dag.entryAfter ["writeBoundary"] "");
  };
  # The repository is already managed with jj; upstream's Git setup wizard
  # must not offer to initialize or commit it on login.
  xdg.configFile."omarchy/hooks/post-boot.d/config-repo".enable = false;
  # Omarchy ships a Discord web app under a different desktop ID from the
  # native client. Mask only that shortcut, retaining the native app and data.
  xdg.desktopEntries."omarchy-Discord" = {
    name = "Discord";
    settings.Hidden = "true";
  };
  systemd.user.services.omarchy-logind-lock = {
    Unit = {
      Description = "Forward logind lock requests to the Omarchy lock screen";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${logindLock}/bin/omarchy-logind-lock";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
