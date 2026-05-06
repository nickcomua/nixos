# Pulse Secure VPN client package
# Wrapped from the official .deb installer (ps-pulse-linux-9.1r14.0-b13525-64bit-installer.deb)
#
# Uses buildFHSEnv because the proprietary binaries expect:
# - FHS filesystem layout (/opt/pulsesecure, /usr/lib, etc.)
# - Root daemon with systemd service
# - D-Bus system service
# - CEF runtime downloaded at runtime
# - NSS certificate database access
#
# Note: `pkgs` MUST be the older nixpkgs pin (nixos-24.11) — see the comment
# in default.nix for why. Using current nixpkgs glib (2.86+) causes the
# daemon to SEGV inside g_object_unref, and webkitgtk_4_0 was removed from
# current nixpkgs entirely.
{
  pkgs,
  lib,
}: let
  pulsesecure-unwrapped = pkgs.stdenv.mkDerivation rec {
    pname = "pulsesecure-unwrapped";
    version = "9.1r14.0";

    # The .deb installer lives next to this file in the repo so it can be
    # copied into the nix store under pure evaluation (no impure paths).
    src = ./ps-pulse-linux-9.1r14.0-b13525-64bit-installer.deb;

    nativeBuildInputs = with pkgs; [dpkg];

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r opt $out/
      cp -r usr $out/
      cp -r var $out/
      cp -r lib $out/
      # Fix broken symlink: dbus config points to /opt/pulsesecure which doesn't
      # exist in the nix store. Replace with copy from the actual JUNS directory.
      rm -f $out/usr/share/dbus-1/system.d/net.psecure.pulse.conf
      cp $out/opt/pulsesecure/lib/JUNS/net.psecure.pulse.conf $out/usr/share/dbus-1/system.d/
      runHook postInstall
    '';
  };

  # Required libraries that the Pulse Secure binaries link against
  requiredLibs = with pkgs; [
    glib
    gtk3
    gtkmm3
    # GTKmm/GLibmm/etc. C++ bindings — Pulse Secure UI is a C++ GTK app
    # built against the legacy 1.6/2.4/1.4/1.0 ABIs of the *mm libraries.
    # glibmm provides both libglibmm-2.4 AND libgiomm-2.4.
    atkmm
    glibmm
    pangomm
    cairomm
    libsigcxx
    # The real webkitgtk 4.0 (libsoup2-based) from an older nixpkgs pin —
    # necessary because the Pulse login WebView is hard-linked against
    # libwebkit2gtk-4.0.so.37 AND libsoup-2.4.so.1 in the same process, and
    # webkitgtk_4_1 uses libsoup 3 which crashes at load time with
    # "libsoup2 symbols detected. Using libsoup2 and libsoup3 in the same
    # process is not supported."
    webkitgtk_4_0
    # libsoup 2.4 is needed by webkit2gtk-4.0 and the Pulse login WebView.
    # It is marked insecure in nixpkgs (CVE-2024-52530 etc.) — the host
    # config opts in via nixpkgs.config.permittedInsecurePackages.
    # In nixos-24.11 this attribute is just `libsoup`; it got renamed to
    # `libsoup_2_4` when `libsoup_3` was added as the new default later.
    libsoup
    curl
    nss
    nspr
    libbsd
    util-linux
    openssl
    libuuid
    stdenv.cc.cc.lib
    cairo
    pango
    atk
    at-spi2-atk
    gdk-pixbuf
    # librsvg provides the GDK-pixbuf SVG loader. Without it the Pulse UI
    # emits `Gtk-WARNING: Could not load image 'plus.svg': Couldn't recognize
    # the image file format` for every SVG in its toolbar (+, edit, delete).
    librsvg
    harfbuzz
    libxml2
    sqlite
    # X11 libs live under `pkgs.xorg.*` in nixos-24.11 (they were promoted
    # to top-level attrs later); use the namespaced names so this package
    # builds against the older pin.
    xorg.libpthreadstubs
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libXfixes
    xorg.libXdamage
    xorg.libXcomposite
    xorg.libXrandr
    xorg.libXtst
    libxkbcommon
    mesa
    vulkan-loader
    # Used by the upstream startup.sh helper script
    procps
    util-linux
    coreutils
    # CRITICAL: Pulse Secure's TunnelManager (dsTMService.so) shells out to
    # `/sbin/ip` (iproute2) to configure the TUN/TAP virtual adapter — set
    # tunnel IP, MTU, route table, etc. Without iproute2 in the FHS bubble,
    # every connection attempt dies at the adapter setup stage with the
    # log message
    #     'TM' /sbin/ip failed set tunnel ip with error 32512
    #     'session' tunnel setup failed 105
    # which the UI surfaces as "failed to setup virtual adapter".
    # 32512 is `127 << 8` from waitpid() — i.e. `/sbin/ip: command not found`.
    iproute2
  ];
in
  pkgs.buildFHSEnv {
    name = "pulsesecure";

    targetPkgs = _pkgs: requiredLibs;

    runScript = "bash";

    # Bind-mount the unwrapped Pulse Secure tree under /opt/pulsesecure inside
    # the FHS bubble. The binaries and convenience wrapper scripts hard-code
    # `/opt/pulsesecure/bin/...` paths, so the tree must actually be present
    # at that location at runtime — adding it to $PATH alone is not enough.
    #
    # We also override read-only /etc/resolv.conf and /etc/pulse-resolv.conf
    # paths inside the bubble with writable backing files. By default the FHS env
    # sets /etc as a tmpfs populated with symlinks into /.host-etc/... which is a
    # read-only bind mount of the host's /etc. Pulse Secure's dsTMService.so
    # opens /etc/resolv.conf with O_WRONLY to install the VPN's DNS servers and
    # /etc/pulse-resolv.conf to back up the original. Both writes get EROFS
    # (errno 30) against the read-only bind, producing:
    #     DNSSystemUtils: Failed to create /etc/resolv.conf with error 30
    #     TM: Failed to setup DNS. Setting jamStatus to JAMSTATUS_VIRTUAL_ADAPTER_FAILD
    #     session: tunnel setup failed 105
    # which the UI surfaces as "failed to setup virtual adapter".
    #
    # Solution: use bwrap's `--tmp-overlay` to mount an overlayfs at /.host-etc
    # with the host's /etc as the source layer and an invisible tmpfs as the
    # writable upper layer. The symlinks at /etc/<name> → /.host-etc/<name>
    # then resolve to writable files inside the overlay; Pulse can truncate and
    # rewrite /etc/resolv.conf normally, and writes are isolated to the bubble
    # (the host's real /etc/resolv.conf is untouched).
    #
    # We can't simply --bind a writable file at /etc/resolv.conf because:
    # 1. buildFHSEnv hardcodes the symlink in its `symlinks` array, which is
    #    expanded BEFORE our extraBwrapArgs.
    # 2. bwrap's --bind on a symlink follows the symlink and tries to create
    #    the bind mount at /.host-etc/resolv.conf, which is read-only.
    # 3. Trying to bind onto /.host-etc/resolv.conf directly fails with
    #    EROFS in this systemd-spawned context (mount propagation differs
    #    from interactive bwrap invocations).
    #
    # Caveat: with --tmp-overlay, writes to /etc/resolv.conf inside the bubble
    # are NOT visible to host processes outside the bubble. The VPN tunnel
    # itself (kernel routes via /sbin/ip) is set up at host level and works
    # system-wide, but to resolve internal hostnames from host processes you
    # would need a separate DNS bridge (e.g., systemd-resolved with split-DNS
    # or a sidecar that exports the bubble's resolv.conf to the host's resolver).
    # For "just connect to the VPN", this is sufficient.
    extraBwrapArgs = [
      "--ro-bind ${pulsesecure-unwrapped}/opt/pulsesecure /opt/pulsesecure"
      "--overlay-src /etc"
      "--tmp-overlay /.host-etc"
    ];

    # Stage Pulse Secure's bundled OpenSSL 1.1.1g compiled-in default trust
    # store path inside the FHS rootfs at build time. The bundled libcrypto
    # has OPENSSLDIR=/usr/local/ssl compiled in, so `SSL_CTX_set_default_verify_paths`
    # looks for /usr/local/ssl/cert.pem (CAfile) and /usr/local/ssl/certs/ (CApath).
    # We can't bwrap-bind these at runtime because the FHS rootfs is read-only
    # and bwrap can't mkdir the missing parent dirs. Creating the directory and
    # copying the cert bundle into the rootfs at build time is the reliable
    # solution.
    #
    # We use `cacert.unbundled` / `ca-no-trust-rules-bundle.crt`, NOT
    # `ca-bundle.crt`. The default `ca-bundle.crt` from `pkgs.cacert` is a
    # p11-kit-extracted bundle that contains BOTH `BEGIN CERTIFICATE` and
    # `BEGIN TRUSTED CERTIFICATE` PEM blocks (the latter carry p11-kit trust
    # assertions / per-cert usage policies). Pulse Secure's bundled libcrypto
    # 1.1.1g uses `X509_STORE_load_locations` → `PEM_read_bio_X509`, which
    # rejects `BEGIN TRUSTED CERTIFICATE` blocks (it only handles them via
    # `PEM_read_bio_X509_AUX`). The whole bundle load aborts → `verifyTrust`
    # fails → user gets the "Untrusted server certificate" prompt for every
    # connect attempt. `ca-no-trust-rules-bundle.crt` is the same set of CAs
    # in plain `BEGIN CERTIFICATE` format with no trust assertions, which
    # OpenSSL 1.1.1g parses cleanly.
    #
    # We also expose the bundle at the alternate paths Pulse's binaries probe
    # so that any cert-loading code path lands on a working file. Pulse's
    # binaries scan, in order:
    #   /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt   (RHEL/Fedora)
    #   /etc/pki/ca-trust/source/anchors/                         (RHEL/Fedora)
    #   /etc/ssl/certs/ca-certificates.crt                        (Debian/Ubuntu)
    # We populate the first one (single-file CAfile) at build time, and the
    # third one is already provided by NixOS's /etc symlink farm into the
    # FHS bubble — but we replace it with our parser-friendly bundle to avoid
    # the same `BEGIN TRUSTED CERTIFICATE` parsing problem.
    extraBuildCommands = ''
      mkdir -p $out/usr/local/ssl/certs
      cp ${pkgs.cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt $out/usr/local/ssl/cert.pem

      mkdir -p $out/etc/pki/ca-trust/extracted/openssl
      cp ${pkgs.cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt \
         $out/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt

      mkdir -p $out/etc/pki/ca-trust/source/anchors
    '';

    profile = ''
      export PATH="/opt/pulsesecure/bin:$PATH"
      # Point gdk-pixbuf at librsvg's loaders.cache so SVG icons actually
      # render. librsvg's cache already contains all the standard pixbuf
      # loaders plus the SVG loader, and references them by /nix/store
      # absolute paths which are visible inside the FHS bubble.
      export GDK_PIXBUF_MODULE_FILE="${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
      # Point Pulse Secure's bundled OpenSSL 1.1.1g at the parser-friendly CA
      # bundle staged at /usr/local/ssl/cert.pem (see extraBuildCommands above).
      # Cannot use NixOS's /etc/ssl/certs/ca-certificates.crt directly because
      # that file contains `BEGIN TRUSTED CERTIFICATE` blocks which Pulse's
      # OpenSSL refuses to parse via X509_STORE_load_locations.
      export SSL_CERT_FILE=/usr/local/ssl/cert.pem
      export SSL_CERT_DIR=/usr/local/ssl/certs
    '';

    extraInstallCommands = ''
      # Desktop entry — point Exec at our wrapper so that clicking PulseUI in
      # the launcher always goes through the FHS env, not bare PATH lookup.
      mkdir -p $out/share/applications
      cat > $out/share/applications/pulse.desktop << EOF
      [Desktop Entry]
      Version=1.0
      Name=PulseUI
      Comment=Pulse Secure VPN Client
      Exec=$out/bin/pulseUI
      Icon=${pulsesecure-unwrapped}/opt/pulsesecure/resource/pulse.png
      Terminal=false
      Type=Application
      Categories=Network;VPN;
      StartupWMClass=pulseUI
      EOF

      # Convenience wrapper scripts.
      #
      # IMPORTANT: every wrapper must use a nix-store bash shebang (NOT
      # `#!/bin/bash` — that path doesn't exist on NixOS and silently breaks
      # everything launched from the desktop entry / dbus / systemd) and must
      # invoke the FHS env entry by *absolute* path ($out/bin/pulsesecure)
      # rather than relying on $PATH, so wrappers keep working when launched
      # from sandboxed contexts that don't inherit the user's PATH.
      #
      # The FHS env wrapper internally does `exec bash "$@"`, i.e. it runs
      # bash with whatever arguments we pass. If we just pass a binary path
      # (e.g. `/opt/pulsesecure/bin/pulseUI`), the inner bash treats it as a
      # script and fails with "cannot execute binary file". We therefore wrap
      # every command in `-c 'exec /path/to/cmd "$@"' --` so the inner bash
      # actually runs the binary, with `--` becoming $0 and our forwarded
      # args becoming $1..$N.
      mkdir -p $out/bin

      # Direct UI launcher
      cat > $out/bin/pulseUI << SCRIPT
      #!${pkgs.bash}/bin/bash
      exec $out/bin/pulsesecure -c 'exec /opt/pulsesecure/bin/pulseUI "\$@"' -- "\$@"
      SCRIPT
      chmod +x $out/bin/pulseUI

      # Service control script (used by the systemd unit and for manual control)
      cat > $out/bin/pulsesecure-service << SCRIPT
      #!${pkgs.bash}/bin/bash
      case "\$1" in
        start|stop|restart)
          exec $out/bin/pulsesecure -c 'exec /opt/pulsesecure/bin/startup.sh "\$@"' -- "\$1"
          ;;
        *)
          echo "Usage: pulsesecure-service {start|stop|restart}"
          exit 1
          ;;
      esac
      SCRIPT
      chmod +x $out/bin/pulsesecure-service

      # CEF setup script (one-time, downloads ~1.1 GB Chromium Embedded Framework)
      cat > $out/bin/pulsesecure-setup-cef << SCRIPT
      #!${pkgs.bash}/bin/bash
      exec $out/bin/pulsesecure -c 'exec /opt/pulsesecure/bin/setup_cef.sh "\$@"' -- "\$@"
      SCRIPT
      chmod +x $out/bin/pulsesecure-setup-cef

      # Certificate management
      cat > $out/bin/pulsesecure-cert << SCRIPT
      #!${pkgs.bash}/bin/bash
      exec $out/bin/pulsesecure -c 'exec /opt/pulsesecure/bin/certificate_installer.sh "\$@"' -- "\$@"
      SCRIPT
      chmod +x $out/bin/pulsesecure-cert

      # jamCommand (CLI for connection management)
      cat > $out/bin/jamCommand << SCRIPT
      #!${pkgs.bash}/bin/bash
      exec $out/bin/pulsesecure -c 'exec /opt/pulsesecure/bin/jamCommand "\$@"' -- "\$@"
      SCRIPT
      chmod +x $out/bin/jamCommand

      # Install dbus config
      mkdir -p $out/share/dbus-1/system.d
      cp ${pulsesecure-unwrapped}/opt/pulsesecure/lib/JUNS/net.psecure.pulse.conf $out/share/dbus-1/system.d/

      # Install man page
      mkdir -p $out/share/man/man1
      cp ${pulsesecure-unwrapped}/usr/share/man/man1/pulse.1.gz $out/share/man/man1/
    '';

    meta = with lib; {
      description = "Pulse Secure VPN client";
      homepage = "https://www.pulsesecure.net/";
      license = licenses.unfree;
      platforms = ["x86_64-linux"];
    };
  }
