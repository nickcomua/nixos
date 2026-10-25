{pkgs}: let
  pname = "ipfs-desktop";
  version = "0.50.1";
  src = pkgs.fetchurl {
    url = "https://github.com/ipfs/ipfs-desktop/releases/download/v${version}/ipfs-desktop-${version}-linux-x86_64.AppImage";
    hash = "sha256-4oE/Bm+uC87VqgnqCebtqY+j8yhBXDSlzKaxSvMzTFE=";
  };
  extracted = pkgs.appimageTools.extract {
    inherit pname version src;
  };
in
  pkgs.appimageTools.wrapType2 {
    inherit pname version src;
    extraInstallCommands = ''
      install -Dm644 ${extracted}/ipfs-desktop.desktop "$out/share/applications/ipfs-desktop.desktop"
      substituteInPlace "$out/share/applications/ipfs-desktop.desktop" \
        --replace-fail 'Exec=AppRun' "Exec=$out/bin/ipfs-desktop"
      cp -r ${extracted}/usr/share/icons "$out/share/"
    '';
    meta = {
      description = "Desktop application for the InterPlanetary File System";
      homepage = "https://github.com/ipfs/ipfs-desktop";
      license = pkgs.lib.licenses.mit;
      sourceProvenance = [pkgs.lib.sourceTypes.binaryNativeCode];
      platforms = ["x86_64-linux"];
      mainProgram = "ipfs-desktop";
    };
  }
