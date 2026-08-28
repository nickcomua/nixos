# The exported native selection files are NixOS modules. Keeping their original
# directory structure also preserves relative imports of draft packages.
let
  selection = ./flake-parts/hosts/nixos/desktop + "/files/.config/nixarchy";
  names = ["apps.nix" "services.nix" "advanced.nix"];
in {
  imports =
    map (name: selection + "/${name}")
    (builtins.filter (name: builtins.pathExists (selection + "/${name}")) names);
}
