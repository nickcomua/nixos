#!/usr/bin/env bash
set -euo pipefail

# Git, jj and desktop clients must share the system-managed agent/key stubs.
export GNUPGHOME="$HOME/.gnupg"
for arg in "$@"; do
  case "$arg" in
    -bsau|-bs|-s|-b|--sign|--detach-sign|--clearsign)
      # Both YubiKeys carry the same signing key but have different serials.
      # Refresh the card stub before signing instead of requesting the last key.
      result=$(gpg-connect-agent 'SCD SERIALNO' 'LEARN --force' /bye)
      if [[ "$result" == *ERR* ]]; then
        printf '%s\n' 'Signing stopped: cannot access the OpenPGP YubiKey. Insert one signing key and retry.' >&2
        exit 1
      fi
      break
      ;;
  esac
done
exec gpg --pinentry-mode ask "$@"
