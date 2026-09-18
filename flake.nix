# --- flake.nix
{
  description = "Unified Nix configurations for all machines";

  inputs = {
    # --- BASE DEPENDENCIES ---
    nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1";
    flake-parts = {
      url = "https://flakehub.com/f/hercules-ci/flake-parts/0";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # --- DARWIN ---
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-fuse = {
      url = "github:gromgit/homebrew-fuse";
      flake = false;
    };
    homebrew-openhue = {
      url = "github:openhue/homebrew-cli";
      flake = false;
    };

    # --- ALTA (ARM Linux) ---
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
      # Keep upstream dependencies to reuse Determinate's binary cache.
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
    };
    ssd-doda-bot = {
      url = "github:nickcomua/ssd-doda-bot";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- SHARED ---
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "https://flakehub.com/f/Mic92/sops-nix/0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --- MAIN PC SPECIFIC ---
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };
    nixarchy = {
      url = "github:olafkfreund/nixarchy";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
        sops-nix.follows = "sops-nix";
      };
    };
    nixi = {
      url = "github:olafkfreund/nixi-nixarchy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarchy.inputs.nixi.follows = "nixi";
    # aw-watcher-window-hyprland = {
    #   url = "github:bobvanderlinden/aw-watcher-window-hyprland";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    prismlauncher-cracked = {
      url = "github:Diegiwg/PrismLauncher-Cracked";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}: let
    inherit (inputs.nixpkgs) lib;
    inherit (import ./flake-parts/_bootstrap.nix {inherit lib;}) loadParts;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      debug = true;
      imports = loadParts ./flake-parts;
    };
}
