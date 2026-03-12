{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../../modules/home-manager/darwin/common.nix
  ];

  home = {
    stateVersion = "24.05";
    username = "nickp";
    homeDirectory = "/Users/nickp";
    sessionPath = [
      "/Users/nickp/.local/bin"
      "/Users/nickp/.bun/bin"
      "/Users/nickp/.deno/bin"
    ];
  };
}
