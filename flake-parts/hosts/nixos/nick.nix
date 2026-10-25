# NixOS home-manager config for user nick
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  # Note: shared and Nixarchy modules are loaded automatically via sharedModules
  # in hosts/default.nix - don't import them here to avoid duplicate declarations

  home = {
    stateVersion = "24.05";
    username = "nick";
    homeDirectory = "/home/nick";
    packages = [pkgs.brave pkgs.kubo (import ./ipfs-desktop.nix {inherit pkgs;})];
  };

  home.sessionVariables.BROWSER = "helium";
  xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".text = ''
    [preferred]
    default=hyprland;gtk
    org.freedesktop.impl.portal.FileChooser=gnome
    org.freedesktop.impl.portal.Secret=gnome-keyring
  '';
  # GNOME's portal disables file dialogs when a forced GDK backend fails.
  xdg.configFile."systemd/user/xdg-desktop-portal-gnome.service.d/file-picker.conf".text = ''
    [Service]
    UnsetEnvironment=GDK_BACKEND
  '';

  # Omarchy owns mutable application defaults and Hyprland Lua settings.
  services.nixi.enable = false;
}
