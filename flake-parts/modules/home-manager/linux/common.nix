# Linux-specific home-manager config (extends shared)
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../shared
  ];

  # Linux-specific packages can be added here
  home.packages = with pkgs; [
    # Linux specific tools
  ];
}
