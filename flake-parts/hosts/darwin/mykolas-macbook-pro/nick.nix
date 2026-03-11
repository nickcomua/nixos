{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../../modules/home-manager/darwin/common.nix
  ];

  home = {
    stateVersion = "24.05";
    username = "nick";
    homeDirectory = "/Users/nick";
    sessionPath = [
      "/Users/nick/.local/bin"
      "/Users/nick/.bun/bin"
      "/Users/nick/.deno/bin"
    ];
  };
}
