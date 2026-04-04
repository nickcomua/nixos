# Noctalia shell - desktop shell for Wayland compositors
# https://docs.noctalia.dev/getting-started/nixos/
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  pluginsJson = pkgs.writeText "noctalia-plugins.json"
    (builtins.toJSON (builtins.fromJSON (builtins.readFile ./plugins.json)));
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;
    # Settings exported via: noctalia-shell ipc call state all | jq .settings
    # Or: Open Settings Panel -> General -> Copy Settings
    settings = builtins.fromJSON (builtins.readFile ./settings.json);
    # NOTE: plugins is NOT set here because the noctalia module writes it as a
    # read-only symlink to the nix store. Noctalia needs to write to plugins.json
    # at runtime to manage plugin downloads from custom repos. Instead, we seed it
    # as a mutable file via the activation script below.
  };

  # Seed plugins.json as a mutable file so Noctalia can manage plugin
  # downloads/updates from custom repos at runtime. Only written if missing.
  home.activation.noctalia-plugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pluginsFile="${config.xdg.configHome}/noctalia/plugins.json"
    if [ ! -f "$pluginsFile" ] || [ -L "$pluginsFile" ]; then
      rm -f "$pluginsFile"
      mkdir -p "$(dirname "$pluginsFile")"
      cp ${pluginsJson} "$pluginsFile"
      chmod 644 "$pluginsFile"
    fi
  '';
}
