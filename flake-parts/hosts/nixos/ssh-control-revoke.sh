# Revoke only this user's managed SSH masters, never unrelated agent sockets.
set -euo pipefail
runtime="${XDG_RUNTIME_DIR:?Missing user runtime directory}"
status=0
for control in "$runtime"/ssh-session-* "$runtime"/ssh-github-*; do
  [[ -S "$control" && ! -L "$control" && -O "$control" ]] || continue
  if timeout 3 ssh -F /dev/null -S "$control" -O exit unused; then
    printf 'Closed SSH master: %s\n' "$control"
  else
    printf 'Unable to close SSH master: %s\n' "$control" >&2
    status=1
  fi
done
exit "$status"
