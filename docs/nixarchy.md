# Nixarchy desktop

The `nixos` host uses the pinned Nixarchy/Omarchy desktop, SDDM greeter, Hyprland
Lua configuration, and Codex integration. macOS and Alta share the updated
package inputs from Determinate's `nixpkgs-weekly/0.1` feed but do not import the
desktop modules. Determinate still manages Nix on the hosts that used it before.
The obsolete desktop and auxiliary inputs have been removed.

## Daily use

- `Super+Space`: Omarchy menu; `Super+Alt+Space`: apps.
- `Super+Q`: close window; `Super+W`: deliberately unbound.
- `Super+Return`: Ghostty; `Super+E`: Yazi; `Super+B`: Obsidian daily note.
- `Super+S`: scratchpad; `Super+Alt+S`: move a window into it.
- `Super+L`: layout; `Super+Ctrl+L`: lock; `Super+Tab`: next workspace.
- `Super+V`: paste; `Super+Ctrl+V`: clipboard history.
- `Super+Escape`: system menu; `Super+Ctrl+T`: btop.
- `Print`: Omarchy capture; old Shift/Ctrl+Shift Print overrides are removed.
- Hold/release `Ctrl+grave`: existing Whisper dictation.
- `Super+K`: show the complete active bindings.

Ghostty and Floorp remain defaults. Omarchy's preinstalled applications are
included alongside existing applications. Optional Windows/Android environments,
containers and remote desktop are not activated by this migration.

Codex is the initial agent. Existing account credentials are reused; this change
does not sign in, modify credentials, or purchase API access. The desktop help
integration is installed, but authenticated responses require a working account.

## Saving changes

Use **My configuration** in the Omarchy menu, or:

```sh
nixarchy-config status
nixarchy-config export
jj diff
```

Export saves a versioned snapshot under `flake-parts/hosts/nixos/desktop`.
It never commits, pushes or switches the system. It captures:

- `~/.config/hypr/*.lua`;
- Omarchy shell settings, defaults, extensions, branding and hooks;
- theme choice, rendered current theme, toggles and the selected wallpaper;
- plugins/themes: revision and hash for clean HTTPS Git sources; local files
  for modified/custom sources, without repository metadata or caches;
- `mimeapps.list`, `xdg-terminals.list`, and native Nixarchy app/service/draft
  package selections.

The manifest and file hashes are generated together. Do not edit snapshot files
in isolation: make the change live and export it. The snapshot is the source for
fresh installations; existing homes retain live edits on rebuild. Run `status`
after pulling a changed snapshot and explicitly restore it if desired.

```sh
nixarchy-config restore
```

Restore first writes a dated backup under `~/.local/state/nixarchy-config/backups`,
then reinstates saved settings and plugin/theme sources. Log out and back in to
load the complete restored desktop. For a backup created by this tool, use
`nixarchy-config restore --snapshot /path/to/backup` (provided it contains valid
configuration). The first activation also preserves old Hyprland/Noctalia/Satty
configuration under `~/.local/state/nixarchy-config/legacy-desktop`.

Only the documented desktop paths are exported. Browser profiles, shell/editor
configuration, account credentials and application data are outside this scope.
Unusual plugin dependencies still need packaging in Nix; source capture does not
convert Arch installation scripts into NixOS modules. Unsafe external source
symlinks and credential fields in settings are rejected. Custom wallpapers and
locally changed code become repository assets and should be reviewed in `jj diff`.

## Installing applications

Pick applications through Omarchy's Install menu, then choose **Apply changes**.
The repository's `nixarchy-apply` adapter validates and copies only the native
Nix selections into the snapshot, snapshots the working copy with Jujutsu,
evaluates the `nixos` configuration and runs `nh os switch --hostname nixos`
with `/run/wrappers/bin/pkexec` as its privilege elevation program.
It does not export unrelated live desktop edits. Prior selections are backed up
under `~/.local/state/nixarchy-config/apply-backups`.

`nixarchy-apps.nix` imports the exported selections. The root `nixarchy` symlink
lets upstream menus inspect those same selections. There is no Git staging or
automatic commit. Saving the whole desktop also saves app selections, but does
not install them until the next rebuild.

## Feature and verification checklist

| Capability | Implementation / verification |
| --- | --- |
| Desktop, menus, themes, login | Native Nixarchy modules; runtime GPU/login checks still required |
| Omarchy plugins | Runtime installation plus exportable sources/state; upstream VM check tests two real plugins |
| AI help and troubleshooting | Codex default with NixOS-aware upstream integration; authenticated interaction requires the user's session |
| Existing application defaults | Mutable Ghostty/Floorp defaults; existing personal application data retained |
| Live customization | Explicit export, status and backed-up restore; tested in isolated homes |
| App management | Native selections imported by this flake; Jujutsu-aware Apply adapter |
| Optional services | Available through Nixarchy; enabled only on demand |
| Hardware integration | Existing display layout/input settings and screen-sharing exclusions retained; verify on the laptop |

CI builds all three hosts, tests export/restore, and runs Nixarchy's plugin VM.
A successful build is not a hardware test. After switching and starting a fresh
Nixarchy session, check both displays/scaling, audio, brightness, clipboard,
screenshots, sharing exclusions, dictation, suspend/resume and lock/unlock.

Keep the previous boot generation until these checks pass. Select it at boot
or use `pkexec nixos-rebuild switch --rollback` to return to the previous system.
Desktop runtime data has its own backups above; a system-generation rollback
alone does not undo mutable desktop settings.
