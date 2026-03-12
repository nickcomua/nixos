# Shared Nix configuration values for all hosts
# Used by both NixOS and Darwin determinate configurations
{
  # All binary caches and their public keys
  caches = {
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://devenv.cachix.org"
      "https://cache.garnix.io"
      "https://nickcomua.cachix.org"
    ];

    trustedPublicKeys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "nickcomua.cachix.org-1:stcsazuAJ0uhVu6i4yXinhDenHEwKngOtystEXf++so="
    ];
  };

  # Extra experimental features beyond the defaults
  experimentalFeatures = [
    "nix-command"
    "flakes"
  ];

  # Advanced experimental features (for determinate)
  advancedExperimentalFeatures = [
    "build-time-fetch-tree"
    "parallel-eval"
    "external-builders"
  ];
}
