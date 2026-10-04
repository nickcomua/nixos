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
        assert !host.programs.gnupg.agent.enableSSHSupport;
        assert host.systemd.user.services.gcr-ssh-agent.wantedBy == ["graphical-session.target"];
        assert builtins.elem "wayland-session-waitenv.service" host.systemd.user.services.gcr-ssh-agent.after;
        assert host.systemd.user.services.gcr-ssh-agent.environment.SSH_ASKPASS_REQUIRE == "force";
        assert host.systemd.user.sockets.gcr-ssh-agent.wantedBy == ["graphical-session.target"];
        assert !(files ? "mimeapps.list");
        assert !(files ? "hypr/hyprland.conf");
        assert host.programs.hyprland.package.stdenv.cc.libc.outPath == host.hardware.graphics.package.stdenv.cc.libc.outPath;
        assert host.security.pam.services.polkit-1.u2f.enable;
        assert !host.systemd.services."polkit-agent-helper@".serviceConfig.PrivateDevices;
        assert host.systemd.services."polkit-agent-helper@".serviceConfig.ProtectHome == "tmpfs";
        assert builtins.elem "char-hidraw rw" host.systemd.services."polkit-agent-helper@".serviceConfig.DeviceAllow;
        assert builtins.elem "/dev/urandom r" host.systemd.services."polkit-agent-helper@".serviceConfig.DeviceAllow;
        assert builtins.elem "/home/nick/.config/Yubico/u2f_keys" host.systemd.services."polkit-agent-helper@".serviceConfig.BindReadOnlyPaths;
        assert host.security.pam.services.omarchy-lock-u2f.u2f.enable;
        assert !host.security.pam.services.omarchy-lock-u2f.unixAuth;
        assert host.home-manager.users.nick.systemd.user.services.omarchy-logind-lock.Service.Restart == "on-failure";
          pkgs.runCommand "desktop-runtime-check" {nativeBuildInputs = [pkgs.qt6.qtdeclarative];} ''
            test -x ${host.system.build.toplevel}/sw/bin/qs
            test -x ${host.system.build.toplevel}/sw/bin/omarchy-launch-shell
            test -x ${host.system.build.toplevel}/sw/bin/nixarchy
            for plugin in lock/Service.qml lock/LockView.qml polkit/PolkitAgent.qml; do
              qmlformat ${host.programs.nixarchy.package}/share/omarchy/shell/plugins/"$plugin" >/dev/null
            done
            grep -q 'auth required .*pam_deny.so' ${host.system.build.toplevel}/etc/pam.d/omarchy-lock-u2f
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
          python3 -B -m unittest discover -s tests -p 'test_ssh_askpass.py'
          OMARCHY_SOURCE=${inputs.nixarchy.inputs.omarchy} python3 -B -m unittest discover -s tests -p 'test_omarchy_auth.py'
          OMARCHY_SOURCE=${inputs.nixarchy.inputs.omarchy} lua tests/nixarchy-bindings.lua
            touch "$out"
        '';
      # Upstream's VM loads two real, pinned community plugins, exercises their
      # enable/disable lifecycle, and checks the desktop responds over IPC.
      desktop-plugins = inputs.nixarchy.checks.${system}.plugin;
    };
  };
}
