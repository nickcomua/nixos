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
    # Linux specific tools
  ];
}
