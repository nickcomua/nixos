# Noctalia shell - desktop shell for Wayland compositors
# https://docs.noctalia.dev/getting-started/nixos/
{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;
    # Settings exported via: noctalia-shell ipc call state all | jq .settings
    # Or: Open Settings Panel -> General -> Copy Settings
    settings = builtins.fromJSON (builtins.readFile ./settings.json);
    # Plugins config: sources, states (enabled plugins), version
    plugins = builtins.fromJSON (builtins.readFile ./plugins.json);
  };
}
