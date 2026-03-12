{
  inputs = {
    nixos.url = "path:..";
    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixos/nixpkgs";
    };
  };
  outputs = {
    nixos,
    comin,
    ...
  }: {
    nixosConfigurations.nixos = nixos.nixosConfigurations.nixos.extendModules {
      modules = [
        comin.nixosModules.comin
        {
          services.comin = {
            enable = true;
            repositorySubdir = "comin";
            remotes = [
              {
                name = "origin";
                url = "https://github.com/nickcomua/nixos.git";
                branches.main.name = "stable-nixos";
              }
            ];
          };
        }
      ];
    };

    nixosConfigurations.alta = nixos.nixosConfigurations.alta.extendModules {
      modules = [
        comin.nixosModules.comin
        {
          services.comin = {
            enable = true;
            repositorySubdir = "comin";
            remotes = [
              {
                name = "origin";
                url = "https://github.com/nickcomua/nixos.git";
                branches.main.name = "stable-alta";
              }
            ];
          };
        }
      ];
    };

    darwinConfigurations."Mykolas-MacBook-Pro" = nixos.darwinConfigurations."Mykolas-MacBook-Pro".extendModules {
      modules = [
        comin.darwinModules.comin
        ({lib, ...}: {
          services.comin = {
            enable = true;
            hostname = "Mykolas-MacBook-Pro";
            repositorySubdir = "comin";
            remotes = [
              {
                name = "origin";
                url = "https://github.com/nickcomua/nixos.git";
                branches.main.name = "stable-darwin";
              }
            ];
          };
          # comin's darwin module accesses nix.package even when nix.enable = false
          # (Determinate Nix case). Override the launchd daemon PATH manually.
          launchd.daemons.comin.serviceConfig.EnvironmentVariables = lib.mkForce {
            NIX_REMOTE = "daemon";
            PATH = "/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          };
        })
      ];
    };
  };
}
