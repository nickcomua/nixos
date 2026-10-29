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
    packages = let
      keyring = import ./bitwarden-keyring.nix {inherit lib pkgs;};
    in [
      pkgs.brave
      pkgs.kubo
      (import ./ipfs-desktop.nix {inherit pkgs;})
      keyring.bw
      keyring.bws
      keyring.secretspec
    ];
  };

  # Desktop user defaults. Project aliases in a repo win over this file.
  # The bws alias reads the machine token from the login keyring so nix develop
  # and other stock secretspec binaries do not need BWS_ACCESS_TOKEN in the environment.
  xdg.configFile."secretspec/config.toml".text = ''
    #:schema https://secretspec.dev/schema/config.schema.json

    [defaults]
    profile = "nixos"

    [defaults.providers.bws]
    uri = "bws://vault.bitwarden.eu@2c5e48e2-fca9-43de-a82f-b4b300e34a75"

    [defaults.providers.bws.credentials]
    access_token = { provider = "keyring", ref = { item = "bitwarden", field = "BWS_ACCESS_TOKEN" } }
  '';

  home.sessionVariables.BROWSER = "helium";
  xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".text = ''
    [preferred]
    default=hyprland;gtk
    org.freedesktop.impl.portal.FileChooser=gnome
    org.freedesktop.impl.portal.Secret=gnome-keyring
    org.freedesktop.impl.portal.RemoteDesktop=luminous
  '';
  # GNOME's portal disables file dialogs when a forced GDK backend fails.
  xdg.configFile."systemd/user/xdg-desktop-portal-gnome.service.d/file-picker.conf".text = ''
    [Service]
    UnsetEnvironment=GDK_BACKEND
  '';

  # Omarchy owns mutable application defaults and Hyprland Lua settings.
  services.nixi.enable = false;
}
