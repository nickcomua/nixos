# --- flake.nix
{
  description = "Unified Nix configurations for all machines";

  inputs = {
    # --- BASE DEPENDENCIES ---
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    # Older nixpkgs pin used *only* to pull `webkitgtk_4_0` for the Pulse
    # Secure VPN package. webkitgtk_4_0 was removed from current nixpkgs on
    # 2025-10-08 (port to libsoup_3 + webkitgtk_4_1), but Pulse Secure's
    # proprietary GTK/WebView binaries are hard-linked against the 4.0 ABI
    # and the webkitgtk_4_1 libraries are wire-incompatible with libsoup 2,
    # which the rest of the Pulse binary requires. The clean fix is to ship
    # an actual 4.0 build from a nixpkgs revision that still had it.
    nixpkgs-webkit4.url = "github:NixOS/nixpkgs/nixos-24.11";
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
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-dokploy = {
      url = "github:el-kurto/nix-dokploy";
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
    nix-openclaw = {
      url = "github:nickcomua/nix-openclaw";
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
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # zed.url = "github:zed-industries/zed";
    librepods = {
      url = "github:kavishdevar/librepods/linux/rust";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # aw-watcher-window-hyprland = {
    #   url = "github:bobvanderlinden/aw-watcher-window-hyprland";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    prismlauncher-cracked = {
      url = "github:Diegiwg/PrismLauncher-Cracked";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Caches are configured via shared-nix.nix and Determinate Nix on each host
  # This nixConfig is for users who don't have Determinate Nix installed yet
  # Note: Must be static values (can't use let/import at flake top-level)
  nixConfig = {
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
      "nickcomua.cachix.org-1:stcsazuAJ0uhVu6i4yXinhDenHEwKngOtystEXf++so="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://zed.cachix.org"
      "https://nickcomua.cachix.org"
      "https://noctalia.cachix.org"
    ];
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
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
