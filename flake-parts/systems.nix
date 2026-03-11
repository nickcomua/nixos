# --- flake-parts/systems.nix
{inputs, ...}: {
  # All systems we support
  systems = [
    "x86_64-linux" # Main PC
    "aarch64-linux" # Alta (Raspberry Pi)
    "aarch64-darwin" # MacBook Pro
  ];
}
