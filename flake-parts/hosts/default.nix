# --- flake-parts/hosts/default.nix
{
  lib,
  inputs,
  withSystem,
  config,
  ...
}: let
  mkHost = args: hostName: {
    extraSpecialArgs ? {},
    extraModules ? [],
    extraOverlays ? [],
    withHomeManager ? false,
    ...
  }: let
    baseSpecialArgs =
      {
        inherit (args) system;
        inherit inputs hostName;
      }
      // extraSpecialArgs;
  in
    inputs.nixpkgs.lib.nixosSystem {
      inherit (args) system;
      specialArgs =
        baseSpecialArgs
        // {
          inherit lib hostName;
          host.hostName = hostName;
        };
      modules =
        [
          {
            nixpkgs = {
              overlays = extraOverlays;
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [
                  "electron-37.10.3"
                ];
              };
            };
            networking.hostName = hostName;
          }
          ./${hostName}
        ]
        ++ extraModules
        ++ (
          if (withHomeManager && (lib.hasAttr "home-manager" inputs))
          then [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = baseSpecialArgs;
                sharedModules =
                  lib.attrValues config.flake.homeModules
                  ++ [inputs.sops-nix.homeManagerModules.sops];
              };
            }
          ]
          else []
        );
    };

  mkDarwinHost = args: hostName: {
    extraSpecialArgs ? {},
    extraModules ? [],
    extraOverlays ? [],
    users ? [],
    ...
  }: let
    baseSpecialArgs =
      {
        inherit (args) system;
        inherit inputs hostName;
      }
      // extraSpecialArgs;
  in
    inputs.nix-darwin.lib.darwinSystem {
      inherit (args) system;
      specialArgs =
        baseSpecialArgs
        // {
          inherit lib hostName;
          host.hostName = hostName;
        };
      modules =
        [
          {
            nixpkgs.overlays = extraOverlays;
            nixpkgs.config.allowUnfree = true;
          }
          ./darwin/${hostName}
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = baseSpecialArgs;
            };
          }
        ]
        ++ extraModules
        ++ (map (user: {
            home-manager.users.${user} = import ./darwin/${hostName}/${user}.nix;
          })
          users);
    };
in {
  flake.nixosConfigurations = {
    # Main PC (x86_64)
    nixos = withSystem "x86_64-linux" (
      args:
        mkHost args "nixos" {
          withHomeManager = true;
          extraOverlays = [];
          extraModules = lib.attrValues config.flake.nixosModules;
        }
    );

    # Alta - Raspberry Pi (aarch64)
    alta = withSystem "aarch64-linux" (
      args:
        mkHost args "alta" {
          withHomeManager = false;
          extraOverlays = [];
        }
    );
  };

  flake.darwinConfigurations = {
    "Mykolas-MacBook-Pro" = withSystem "aarch64-darwin" (
      args:
        mkDarwinHost args "mykolas-macbook-pro" {
          users = [
            "nick"
            "nickp"
          ];
          extraOverlays = [];
        }
    );
  };
}
