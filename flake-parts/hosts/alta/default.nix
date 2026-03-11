{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  sharedNix = import ../../modules/_shared-nix.nix;
in {
  imports = [
    ./configuration.nix
    ./hardware-configuration.nix
    # TODO: determinate-nix tests fail in CI - re-enable when upstream fixes it
    # inputs.determinate.nixosModules.default
    inputs.nix-dokploy.nixosModules.default
    inputs.vscode-server.nixosModules.default
  ];

  # Nix settings - caches and experimental features
  nix.settings = {
    inherit (sharedNix.caches) substituters;
    trusted-public-keys = sharedNix.caches.trustedPublicKeys;
    experimental-features = sharedNix.experimentalFeatures;
  };

  services.dokploy = {
    enable = true;
    image = "nick395/dokploy:v0.25.11-postgresname3";
    database.useInsecureHardcodedPassword = true; # TODO: migrate to passwordFile
  };

  services.vscode-server.enable = true;
}
