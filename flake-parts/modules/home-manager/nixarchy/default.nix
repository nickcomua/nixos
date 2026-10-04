{
  config,
  lib,
  pkgs,
  inputs,
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
    # Seed the default agent once; subsequent UI changes belong to the user.
    activation.nixarchyDefaultAgent = lib.mkForce (lib.hm.dag.entryAfter ["writeBoundary"] "");
  };
  # The repository is already managed with jj; upstream's Git setup wizard
  # must not offer to initialize or commit it on login.
  xdg.configFile."omarchy/hooks/post-boot.d/config-repo".enable = false;
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
