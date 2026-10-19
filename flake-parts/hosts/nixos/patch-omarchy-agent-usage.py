"""Teach omarchy-agent-usage-update to find profile-installed collectors.

Upstream only globs $OMARCHY_PATH/bin/omarchy-agent-usage-*, which is the
read-only Nix store: a collector installed into the user's profile (the
declarative way to add one on NixOS) is never discovered. Widen the glob
to the per-user profile bins and run each agent id at most once, so the
built-in collectors are not collected twice when they also appear on PATH.
"""

from pathlib import Path

TARGET = "bin/omarchy-agent-usage-update"

OLD = '''for collector in "$OMARCHY_PATH"/bin/omarchy-agent-usage-*; do
  [[ -x $collector ]] || continue
  agent="${collector##*/omarchy-agent-usage-}"
  [[ $agent == "update" ]] && continue
'''

NEW = '''declare -A _seen_agents=()
for collector in "$OMARCHY_PATH"/bin/omarchy-agent-usage-* /etc/profiles/per-user/"${USER:-$(id -un)}"/bin/omarchy-agent-usage-* "$HOME/.nix-profile/bin"/omarchy-agent-usage-*; do
  [[ -x $collector ]] || continue
  agent="${collector##*/omarchy-agent-usage-}"
  [[ $agent == "update" ]] && continue
  [[ -n ${_seen_agents[$agent]:-} ]] && continue
  _seen_agents[$agent]=1
'''


def patch_update(text: str) -> str:
    if NEW.splitlines()[0] in text:
        return text
    if OLD not in text:
        raise SystemExit(f"patch-omarchy-agent-usage: collector loop not found in {TARGET}")
    return text.replace(OLD, NEW, 1)


def main() -> None:
    path = Path(TARGET)
    path.write_text(patch_update(path.read_text()))


if __name__ == "__main__":
    main()
