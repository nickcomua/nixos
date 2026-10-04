{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      desktop-runtime = let
        host = self.nixosConfigurations.nixos.config;
        files = host.home-manager.users.nick.xdg.configFile;
      in
        assert host.programs.nixarchy.enable;
        assert !host.services.desktopManager.gnome.enable;
        assert !(files ? "mimeapps.list");
        assert !(files ? "hypr/hyprland.conf");
        assert host.programs.hyprland.package.stdenv.cc.libc.outPath == host.hardware.graphics.package.stdenv.cc.libc.outPath;
          pkgs.runCommand "desktop-runtime-check" {} ''
            test -x ${host.system.build.toplevel}/sw/bin/qs
            test -x ${host.system.build.toplevel}/sw/bin/omarchy-launch-shell
            test -x ${host.system.build.toplevel}/sw/bin/nixarchy
            # Exercise loading the host renderer into Hyprland, not just file presence.
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            mkdir -m 700 "$XDG_RUNTIME_DIR"
            renderer=(${host.hardware.graphics.package}/lib/libgallium-*.so)
            LD_PRELOAD="''${renderer[0]}" ${host.programs.hyprland.package}/bin/.Hyprland-wrapped --version
            touch "$out"
          '';
      desktop-config =
        pkgs.runCommand "desktop-config-tests" {
          nativeBuildInputs = [pkgs.python3 pkgs.lua pkgs.nix pkgs.alejandra];
        } ''
            cp -r ${../.} source
            chmod -R u+w source
          cd source
          export NIX_STATE_DIR="$TMPDIR/nix-state"
          export NIX_REMOTE=dummy://
          python3 -B -m unittest discover -s tests -p 'test_nixarchy_config.py'
          OMARCHY_SOURCE=${inputs.nixarchy.inputs.omarchy} lua tests/nixarchy-bindings.lua
            touch "$out"
        '';
      # Upstream's VM loads two real, pinned community plugins, exercises their
      # enable/disable lifecycle, and checks the desktop responds over IPC.
      desktop-plugins = inputs.nixarchy.checks.${system}.plugin;
    };
  };
}
