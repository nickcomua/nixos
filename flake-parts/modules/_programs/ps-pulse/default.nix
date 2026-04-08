# Pulse Secure VPN client NixOS module
{
  config,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:
with lib; let
  cfg = config.programs.ps-pulse;
  # Use an older nixpkgs pin (nixos-24.11, glib 2.82) for the *entire* FHS
  # env runtime. Reason: the Pulse Secure proprietary daemon (9.1r14) was
  # built against glib ~2.70 and SEGVs inside g_object_unref when loaded
  # against glib 2.86 from current nixpkgs (the GObject type-system layout
  # changed in a way that's not backward-compatible for the heap paths the
  # daemon's glib main loop exercises). 2.82 is new enough to still be ABI
  # compatible with the binary but old enough to avoid the crash.
  #
  # This also gives us a coherent GNOME stack (gtk3, webkitgtk_4_0, glib,
  # gdk-pixbuf, librsvg) that was built together, avoiding subtle ABI
  # mismatches between individual libs coming from different nixpkgs
  # generations.
  oldPkgs = import inputs.nixpkgs-webkit4 {
    inherit system;
    config.allowUnfree = true;
    config.permittedInsecurePackages = [
      "libsoup-2.74.3"
    ];
  };
  pulsesecure = import ./package.nix {
    pkgs = oldPkgs;
    inherit lib;
  };
in {
  options.programs.ps-pulse = {
    enable = mkEnableOption "Pulse Secure VPN client";

    package = mkOption {
      type = types.package;
      default = pulsesecure;
      description = "Pulse Secure VPN client package";
    };

    enableService = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the pulsesecure system service that runs the
        background daemon required by the Pulse Secure UI client.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # D-Bus system configuration so the daemon can talk on the system bus
    services.dbus.packages = [cfg.package];

    # The Pulse Secure daemon runs as root and is required by the UI client.
    # We declare the unit here so it picks up the package's nix-store paths
    # rather than relying on the unit file shipped inside the .deb (which
    # references /opt/pulsesecure paths that don't exist outside the FHS env).
    systemd.services.pulsesecure = mkIf cfg.enableService {
      description = "Pulse Secure VPN service Daemon";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "forking";
        Restart = "always";
        RestartSec = 1;
        User = "root";
        ExecStart = "${cfg.package}/bin/pulsesecure-service start";
        ExecStop = "${cfg.package}/bin/pulsesecure-service stop";
      };
    };

    # Pre-create the runtime state directory used by the daemon for the
    # connection store, device id and config backups.
    systemd.tmpfiles.rules = [
      "d /var/lib/pulsesecure 0755 root root -"
      "d /var/lib/pulsesecure/pulse 0755 root root -"
    ];
  };
}
