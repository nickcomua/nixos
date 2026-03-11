# Darwin-specific home-manager config (extends shared)
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../shared
  ];

  # Darwin-specific packages
  home.packages = with pkgs; [
    # macOS specific tools
    bruno
    xxh
    mkcert
    fnm
    tree-sitter
    openssl_3
    ffmpeg-full
  ];
}
