{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
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
