# Linux-specific home-manager config (extends shared)
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../shared
  ];

  # Linux-specific packages can be added here
  home.packages = [
    # inputs.zed.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Linux specific tools
  ];
}
