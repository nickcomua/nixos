{pkgs, ...}: let
  desktop = pkgs.makeDesktopItem {
    name = "anywherelan";
    desktopName = "Anywherelan";
    comment = "Manage the Anywherelan mesh VPN";
    exec = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:8639";
    icon = "network-vpn";
    categories = ["Network"];
  };
in {
  imports = [../../modules/nixos/anywherelan.nix];
  environment.systemPackages = [desktop];
}
