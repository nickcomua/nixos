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
  libsecret,
  mesa,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "tradingview";
  version = "3.4.1";

  src = fetchurl {
    url = "https://tvd-packages.tradingview.com/ubuntu/stable/latest/jammy/tradingview_amd64.deb";
    hash = "sha256-7DgfQjnbF34fPZvtFRpjXE7Fa1w3gOvRsYpjZXgGyGg=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeBinaryWrapper
  ];

  buildInputs = [
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
    libsecret
    mesa
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    systemd
    wayland
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share $out/bin
    cp -r opt/TradingView $out/share/tradingview
    chmod -R u+w $out/share/tradingview
    rm -f $out/share/tradingview/chrome-sandbox

    substituteInPlace usr/share/applications/tradingview.desktop \
      --replace-fail /opt/TradingView/tradingview tradingview
    install -Dm644 usr/share/applications/tradingview.desktop -t $out/share/applications
    install -Dm644 usr/share/icons/hicolor/512x512/apps/tradingview.png \
      $out/share/icons/hicolor/512x512/apps/tradingview.png

    makeWrapper $out/share/tradingview/tradingview $out/bin/tradingview \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath finalAttrs.buildInputs} \
      --set-default LIBGL_DRIVERS_PATH "${mesa}/lib/dri" \
      --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
      --add-flags "--no-sandbox" \
      --add-flags "--disable-gpu-sandbox" \
      --add-flags "--ozone-platform-hint=auto"

    runHook postInstall
  '';

  preFixup = ''
    patchelf --add-needed libGL.so.1 $out/share/tradingview/tradingview
  '';

  meta = {
    description = "Charting platform for traders and investors";
    homepage = "https://www.tradingview.com/desktop/";
    license = lib.licenses.unfree;
    platforms = ["x86_64-linux"];
    mainProgram = "tradingview";
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
  };
})
