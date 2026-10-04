{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeBinaryWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libXScrnSaver,
  libxshmfence,
  libxtst,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  xdg-utils,
}: let
  runtimeLibs = [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libGL
    libglvnd
    libnotify
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libXScrnSaver
    libxshmfence
    libxtst
    mesa
    nspr
    nss
    pango
    systemd
    wayland
  ];
in
  stdenv.mkDerivation {
    pname = "grok-bot";
    version = "0.62.0";

    # Pinned stable build. Bump version, url, and hash together.
    src = fetchurl {
      url = "https://downloads.cursor.com/grokbot/stable/a67f2c3899679c9eb027dc51987b449e0268bd8f/linux/x64/grok-bot_0.62.0_amd64.deb";
      hash = "sha256-yrxLrFCTgpTKSjt8m2HG5HaeK4PT9V1k69vyfCL3+Xk=";
    };

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
      makeBinaryWrapper
    ];

    buildInputs = runtimeLibs;

    # Prebuilt Electron binary; stripping breaks it.
    dontStrip = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share $out/bin
      # Vendor path contains a space, which breaks Electron's SUID sandbox helper.
      cp -r "opt/Grok Bot" $out/share/grok-bot
      chmod -R u+w $out/share/grok-bot
      rm -f $out/share/grok-bot/chrome-sandbox

      substituteInPlace usr/share/applications/grok-bot.desktop \
        --replace-fail "Exec=grok-bot %U" "Exec=$out/bin/grok-bot %U"
      install -Dm644 usr/share/applications/grok-bot.desktop -t $out/share/applications

      for size in 16 24 32 48 64 128 256 512; do
        install -Dm644 "usr/share/icons/hicolor/''${size}x''${size}/apps/grok-bot.png" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/grok-bot.png"
      done

      makeWrapper $out/share/grok-bot/grok-bot $out/bin/grok-bot \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
        --prefix PATH : ${lib.makeBinPath [xdg-utils]} \
        --set-default LIBGL_DRIVERS_PATH "${mesa}/lib/dri" \
        --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
        --add-flags "--no-sandbox" \
        --add-flags "--disable-gpu-sandbox" \
        --add-flags "--ozone-platform-hint=auto"

      runHook postInstall
    '';

    meta = {
      description = "Grok Bot desktop agent";
      homepage = "https://cursor.com";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "grok-bot";
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
