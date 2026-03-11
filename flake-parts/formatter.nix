# --- flake-parts/formatter.nix
{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    # Use alejandra as the default formatter
    formatter = pkgs.alejandra;
  };
}
