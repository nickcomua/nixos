#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'usage: iphone-install-ipa <file.ipa>\n' >&2
  exit 2
fi

ipa=$(realpath "$1")
if [[ ! -f "$ipa" ]]; then
  printf 'iphone-install-ipa: not a file: %s\n' "$1" >&2
  exit 1
fi
case "$ipa" in
  *.ipa | *.IPA) ;;
  *)
    printf 'iphone-install-ipa: expected an .ipa\n' >&2
    exit 1
    ;;
esac

identity="${IPHONE_SSH_IDENTITY:-/home/nick/.ssh/id_ed25519_sk_main}"
known="${IPHONE_SSH_KNOWN_HOSTS:-/home/nick/.hermes/cache/scratch/iphone-ssh-hostkey}"
port="${IPHONE_SSH_PORT:-2222}"
user="${IPHONE_SSH_USER:-mobile}"
base=$(basename "$ipa")
remote="/var/tmp/${base}"

ssh_opts=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o IdentitiesOnly=yes
  -i "$identity"
  -o StrictHostKeyChecking=yes
)
if [[ -f "$known" ]]; then
  ssh_opts+=(-o "UserKnownHostsFile=$known")
fi

ssh "${ssh_opts[@]}" -p "$port" "${user}@127.0.0.1" 'true'

sum=$(sha256sum -- "$ipa" | awk '{print $1}')
scp -q "${ssh_opts[@]}" -P "$port" -- "$ipa" "${user}@127.0.0.1:${remote}"
ssh "${ssh_opts[@]}" -p "$port" "${user}@127.0.0.1" "printf '%s  %s\n' '$sum' '$remote' | sha256sum -c -"

helper=$(
  ssh "${ssh_opts[@]}" -p "$port" "${user}@127.0.0.1" 'sh -s' <<'REMOTE'
set -e
if test -x /var/jb/usr/bin/trollstorehelper; then
  echo /var/jb/usr/bin/trollstorehelper
  exit 0
fi
for d in /var/containers/Bundle/Application/*/TrollStore.app /Applications/TrollStore.app /var/jb/Applications/TrollStore.app; do
  if test -x "$d/trollstorehelper"; then
    echo "$d/trollstorehelper"
    exit 0
  fi
done
exit 1
REMOTE
)

if [[ -z "$helper" ]]; then
  printf 'iphone-install-ipa: trollstorehelper not found on the phone\n' >&2
  exit 1
fi

quoted_helper=$(printf '%q' "$helper")
quoted_remote=$(printf '%q' "$remote")
ssh "${ssh_opts[@]}" -p "$port" "${user}@127.0.0.1" "sudo -n ${quoted_helper} install ${quoted_remote}"
ssh "${ssh_opts[@]}" -p "$port" "${user}@127.0.0.1" "rm -f ${quoted_remote}"
printf 'iphone-install-ipa: installed %s\n' "$base"
