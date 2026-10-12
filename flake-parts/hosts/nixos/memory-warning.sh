#!/usr/bin/env bash
set -euo pipefail

# Run from a user timer, independently of terminals and editor sessions.
mem_total=0 mem_available=0 swap_total=0 swap_free=0
while read -r key value _; do
  case "$key" in
    MemTotal:) mem_total=$value ;;
    MemAvailable:) mem_available=$value ;;
    SwapTotal:) swap_total=$value ;;
    SwapFree:) swap_free=$value ;;
  esac
done < "${1:-/proc/meminfo}"
(( mem_total > 0 )) || exit 1
state="$XDG_RUNTIME_DIR/desktop-memory-warning.last"
now=$(date +%s)
if (( mem_available * 100 < mem_total * 15 || (swap_total > 0 && (swap_total - swap_free) * 100 > swap_total * 80) )); then
  last=0
  if [[ -r "$state" ]]; then read -r last < "$state"; fi
  if (( now - last >= 300 )); then
    @notify@ --urgency=critical --app-name='Memory monitor' \
      'Memory pressure — applications may be killed' \
      "Available RAM: $((mem_available / 1024)) MiB. Swap used: $(((swap_total - swap_free) / 1024)) MiB. Pause heavy jobs or check btop before the OOM killer intervenes."
    printf '%s\n' "$now" > "$state"
  fi
else
  rm -f "$state"
fi
