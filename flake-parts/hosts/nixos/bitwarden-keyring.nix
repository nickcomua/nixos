# Desktop wrappers. gnome-keyring is the Secret Service; these commands read
# Bitwarden credentials from it and pass them only to the child process.
{
  lib,
  pkgs,
}: let
  secretTool = "${pkgs.libsecret}/bin/secret-tool";
  bw = "${pkgs.bitwarden-cli}/bin/bw";
  bws = "${pkgs.bws}/bin/bws";
  secretspec = "${pkgs.secretspec}/bin/secretspec";
  bwsServer = "https://vault.bitwarden.eu";
  tokenFile = "/run/secrets/BWS_ACCESS_TOKEN";
  lookup = ''
    keyring_lookup() {
      ${secretTool} lookup service bitwarden account "$1" 2>/dev/null || true
    }
  '';
in {
  bw = lib.hiPrio (pkgs.writeShellScriptBin "bw" ''
    set -euo pipefail
    ${lookup}
    if [[ "''${1:-}" == "unlock" ]]; then
      shift
      session="$(${bw} unlock --raw "$@")"
      if [[ -z "$session" ]]; then
        echo "bw unlock did not return a session." >&2
        exit 1
      fi
      printf '%s' "$session" | ${secretTool} store --label "Bitwarden CLI session" service bitwarden account BW_SESSION
      echo "Bitwarden session stored in the login keyring."
      exit 0
    fi
    if [[ -z "''${BW_SESSION:-}" ]]; then
      session="$(keyring_lookup BW_SESSION)"
      if [[ -n "$session" ]]; then
        export BW_SESSION="$session"
      fi
    fi
    exec ${bw} "$@"
  '');

  bws = lib.hiPrio (pkgs.writeShellScriptBin "bws" ''
    set -euo pipefail
    ${lookup}
    if [[ -z "''${BWS_ACCESS_TOKEN:-}" ]]; then
      token="$(keyring_lookup BWS_ACCESS_TOKEN)"
      if [[ -z "$token" && -r ${tokenFile} ]]; then
        token="$(${pkgs.coreutils}/bin/cat ${tokenFile})"
      fi
      if [[ -n "$token" ]]; then
        export BWS_ACCESS_TOKEN="$token"
      fi
    fi
    export BWS_SERVER_URL="''${BWS_SERVER_URL:-${bwsServer}}"
    exec ${bws} "$@"
  '');

  secretspec = lib.hiPrio (pkgs.writeShellScriptBin "secretspec" ''
    set -euo pipefail
    ${lookup}
    if [[ -z "''${BW_SESSION:-}" ]]; then
      session="$(keyring_lookup BW_SESSION)"
      if [[ -n "$session" ]]; then
        export BW_SESSION="$session"
      fi
    fi
    if [[ -z "''${BWS_ACCESS_TOKEN:-}" ]]; then
      token="$(keyring_lookup BWS_ACCESS_TOKEN)"
      if [[ -z "$token" && -r ${tokenFile} ]]; then
        token="$(${pkgs.coreutils}/bin/cat ${tokenFile})"
      fi
      if [[ -n "$token" ]]; then
        export BWS_ACCESS_TOKEN="$token"
      fi
    fi
    export BWS_SERVER_URL="''${BWS_SERVER_URL:-${bwsServer}}"
    export SECRETSPEC_PROFILE="''${SECRETSPEC_PROFILE:-nixos}"
    export PATH="${pkgs.sops}/bin:${pkgs.bws}/bin:${pkgs.bitwarden-cli}/bin:${pkgs.libsecret}/bin:$PATH"
    exec ${secretspec} "$@"
  '');
}
