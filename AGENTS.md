# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Repository Overview

This is a multi-system Nix configuration built using the flake-parts architecture pattern from [tsandrini/flake-parts-builder](https://github.com/tsandrini/flake-parts-builder/). It manages NixOS (with Hyprland), macOS (nix-darwin), and Raspberry Pi deployments with comprehensive home-manager integration.

## Essential Commands

### System Management

```bash
# --- NixOS (x86_64-linux) ---
# Rebuild and switch to new configuration
sudo nixos-rebuild switch --flake ~/.config/nixos/#nixos

# Build without applying (test for errors)
nixos-rebuild build --flake ~/.config/nixos/#nixos

# --- macOS / nix-darwin (aarch64-darwin) ---
# Rebuild and switch to new configuration
darwin-rebuild switch --flake ~/.config/nixos/#Mykolas-MacBook-Pro

# Build without applying
darwin-rebuild build --flake ~/.config/nixos/#Mykolas-MacBook-Pro

# --- Flake management ---
# Update all flake inputs
nix flake update

# Update a specific input
nix flake update <input-name>

# Show flake outputs
nix flake show

# Check flake syntax and linting
nix flake check

# Format nix files
nix fmt
```

### Development
```bash
# Enter devenv shell (defined in flake-parts/devenv)
nix develop
```

### Version Control

**This repository uses Jujutsu (jj) instead of git.** Jujutsu is a Git-compatible VCS that provides a better user experience.

```bash
# Check status
jj status

# Create a new commit
jj commit -m "Description of changes"

# Push changes to remote
jj git push

# Typical workflow after making changes
jj commit -m "Add feature X"
jj git push
```

## Architecture

### Flake-Parts Module Loading System

The repository uses a custom recursive module loader (`flake-parts/_bootstrap.nix`) that automatically discovers and imports all `.nix` files in `flake-parts/`. Key behaviors:

1. **Files/directories starting with `_` or `.git` are ignored**
2. **If `myDir/default.nix` exists, only that file is loaded (children are not recursed)**
3. **All other `.nix` files are automatically imported**

This means you can organize modules arbitrarily and they'll be discovered automatically - no need to manually add imports to a central file.

### Directory Structure

```
flake-parts/
├── _bootstrap.nix           # Module loading system (not auto-imported due to _ prefix)
├── systems.nix              # Supported systems: x86_64-linux, aarch64-linux, aarch64-darwin
├── formatter.nix            # nix fmt configuration
├── devenv/                  # Development environment config
│   ├── default.nix
│   └── dev.nix
├── hosts/                   # Host configurations
│   ├── default.nix         # mkHost/mkDarwinHost functions and configurations
│   ├── nixos/              # Main NixOS host (x86_64-linux)
│   │   ├── default.nix     # Host-level NixOS config
│   │   ├── nick.nix        # User home-manager config (imported directly)
│   │   ├── hardware-configuration.nix
│   │   └── apfs.nix        # APFS filesystem support
│   ├── alta/               # Raspberry Pi (aarch64-linux)
│   │   ├── default.nix
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── darwin/             # macOS hosts
│       └── mykolas-macbook-pro/
│           ├── default.nix  # Darwin system config (Homebrew, system defaults, users)
│           ├── nick.nix     # nick user home-manager config
│           └── nickp.nix   # nickp user home-manager config
├── homes/                   # Home-manager standalone configs (currently unused)
└── modules/
    ├── _shared-nix.nix      # Shared Nix cache/substituter settings (excluded from auto-load)
    ├── _programs/           # Program modules (excluded from auto-load)
    │   ├── horse-browser/
    │   ├── librepods/
    │   └── whisper-transcribe/
    ├── darwin/              # Darwin system-level modules (imported directly by darwin hosts)
    │   ├── default.nix      # Stops auto-loader recursion
    │   └── monitoring.nix
    ├── nixos/               # System-level NixOS modules
    │   ├── default.nix
    │   └── monitoring.nix
    └── home-manager/
        ├── default.nix      # Exports homeModules via importApply
        ├── shared/          # Cross-platform (zsh, packages, clawdbot)
        │   ├── default.nix
        │   ├── zsh.nix
        │   ├── packages.nix
        │   └── clawdbot.nix
        ├── linux/           # Linux-specific modules
        │   └── common.nix
        ├── darwin/          # macOS-specific modules
        │   └── common.nix
        ├── wayland/         # Wayland/Hyprland ecosystem
        │   ├── default.nix
        │   ├── options.nix  # Centralized wayland option definitions
        │   ├── hyprland/
        │   ├── hyprpanel/
        │   ├── hyprlock/
        │   ├── hypridle/
        │   ├── hyprpaper/
        │   ├── ags/
        │   ├── anyrun/
        │   ├── satty/
        │   └── vicinae/
        └── services/        # User services (systemd --user)
            └── activitywatch/
```

### Home-Manager Integration

#### NixOS (nixos host)

Uses **NixOS integration mode** (not standalone):

1. `hosts/default.nix` includes `home-manager.nixosModules.home-manager` when `withHomeManager = true`
2. **All** modules in `flake.homeModules` are loaded via `sharedModules = lib.attrValues config.flake.homeModules`
3. sops home-manager module is also added to `sharedModules`
4. Host-specific home-manager config is in `hosts/nixos/default.nix` under `home-manager.users.nick = import ./nick.nix`

#### macOS (darwin host)

Uses **nix-darwin integration mode**:

1. `hosts/default.nix` includes `home-manager.darwinModules.home-manager` (always, no `withHomeManager` flag)
2. `sharedModules` only includes `inputs.sops-nix.homeManagerModules.sops` — **homeModules are NOT auto-loaded on darwin**
3. Each user's home-manager config is loaded individually via the `users` parameter in `mkDarwinHost`:
   ```nix
   home-manager.users.${user} = import ./darwin/${hostName}/${user}.nix
   ```

#### Alta (Raspberry Pi)

Uses `withHomeManager = false` — no home-manager is configured for alta.

### Module Function Signatures

**Home-manager modules using `importApply`** (wayland, activitywatch) must use this two-layer function pattern:

```nix
{ localFlake, inputs, ... }:  # First layer: flake-level args
{
  config,
  lib,
  pkgs,
  ...
}:  # Second layer: module-level args
{
  # Module content here
}
```

**Home-manager modules NOT using `importApply`** (shared, linux-common, darwin-common, horse-browser, librepods) use standard single-layer module structure:

```nix
{ config, lib, pkgs, ... }:
{
  # Module content here
}
```

**NixOS modules** follow standard NixOS module structure.

### Determinate Nix

All hosts use [Determinate Nix](https://docs.determinate.systems/) for consistent nix daemon management:

- **NixOS**: `inputs.determinate.nixosModules.default` imported in `hosts/nixos/default.nix`
- **macOS**: `inputs.determinate.darwinModules.default` imported in `hosts/darwin/mykolas-macbook-pro/default.nix`; `nix.enable = false` disables the built-in nix-darwin nix management
- **Alta**: Determinate commented out pending upstream CI fix

Shared cache/substituter settings live in `modules/_shared-nix.nix` and are imported by all hosts.

### Wayland Configuration System

The `wayland` option namespace (defined in `modules/home-manager/wayland/options.nix`) provides centralized configuration:

- `wayland.hyprland.monitor` - Monitor layouts (set per-host)
- `wayland.hyprland.autostart` - Programs to launch on startup
- `wayland.hypridle.listener` - Idle timeout actions
- `wayland.hyprlock.monitor` / `wayland.hyprlock.auth.*` - Lock screen settings
- `wayland.hyprpanel.modules.right` - Panel module ordering
- `wayland.cursor.size`, `wayland.font.text.size` - UI sizing

This allows host-specific overrides in `hosts/nixos/default.nix` under `home-manager.users.nick`.

## Common Patterns

### Adding a New Flake Input

1. Add to `flake.nix` inputs section:
```nix
my-package = {
  url = "github:owner/repo";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

2. Access in modules via `inputs.my-package`

3. Update the lock file:
```bash
nix flake update my-package
```

### Creating a New Home-Manager Module

1. Create directory: `flake-parts/modules/home-manager/my-feature/`
2. Create `default.nix` with appropriate function signature (see above)
3. Register in `flake-parts/modules/home-manager/default.nix`:
```nix
config.flake.homeModules = {
  # ... existing modules
  # If the module needs flake context (self/inputs), use importApply:
  my-feature = importApply ./my-feature { inherit localFlake inputs; };
  # Otherwise, use a direct path:
  my-feature = ./my-feature;
};
```

The module will be automatically loaded for all NixOS home-manager users. For darwin users, it must be explicitly imported in the user's home config file.

### Adding Systemd User Services (NixOS only)

Create service modules in `flake-parts/modules/home-manager/services/`. Example:

```nix
{ localFlake, inputs, ... }:
{ config, lib, pkgs, ... }:
{
  systemd.user.services.my-service = {
    Unit = {
      Description = "My Service";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.my-package}/bin/my-command";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
```

### Host-Specific Configuration

Edit `flake-parts/hosts/nixos/default.nix`. For home-manager settings:

```nix
home-manager.users.nick = {
  wayland.hyprland.monitor = [
    "eDP-1,1920x1080@165,0x0,1"
  ];
};
```

## Secrets Management (sops-nix)

This repository uses [sops-nix](https://github.com/Mic92/sops-nix) for secrets management with age encryption. Secrets are stored encrypted in the repo and decrypted at NixOS activation time.

### File Locations

- `secrets.yaml` - Encrypted secrets file (safe to commit publicly)
- `.sops.yaml` - Sops configuration with age public keys
- `~/.config/sops/age/keys.txt` - Private age key (NEVER commit, back up securely)

### Commands

```bash
# Edit secrets (decrypts, opens editor, re-encrypts on save)
sops secrets.yaml

# Rotate keys or re-encrypt
sops updatekeys secrets.yaml
```

### Adding New Secrets

1. Add the secret to `secrets.yaml`:
```bash
sops secrets.yaml
# Add: my-new-secret: "secret-value"
```

2. Reference in NixOS config (`flake-parts/hosts/nixos/default.nix`):
```nix
sops.secrets."my-new-secret" = {};
```

3. Use in services via `config.sops.secrets."my-new-secret".path`

### Build-Time vs Runtime Secrets

- **Runtime secrets**: Use `config.sops.secrets."name".path` for services that read from files
- **Build-time config values**: Use placeholder pattern with activation script substitution (see `clawdbot.nix` for example)

### Initial Setup on New Machine

1. Generate age key: `age-keygen -o ~/.config/sops/age/keys.txt`
2. Add public key to `.sops.yaml`
3. Re-encrypt secrets: `sops updatekeys secrets.yaml`

## CI/CD Pipeline

GitHub Actions runs on every push and PR (`.github/workflows/ci.yml`):

### Jobs

1. **check** - Format check (`nix fmt -- --check .`) and linting (`statix`)
2. **build-nixos** - Build x86_64-linux NixOS configuration
3. **build-alta** - Build aarch64-linux (Raspberry Pi) configuration via QEMU on an 8-core runner (3h timeout)
4. **build-macos** - Build aarch64-darwin macOS configuration
5. **promote-nixos / promote-alta / promote-darwin** - On main branch, push to stable branches after successful builds
6. **notify** - Sends webhook notification after all builds complete (success or failure); requires `CI_WEBHOOK_URL` and `CI_WEBHOOK_TOKEN` secrets

### Stable Branches

- `stable-nixos` - Last known good NixOS build
- `stable-alta` - Last known good Alta (ARM) build
- `stable-darwin` - Last known good macOS build

### Required GitHub Secrets

- `CACHIX_AUTH_TOKEN` - Auth token for cachix.org binary cache (nickcomua)
- `CI_WEBHOOK_URL` - (Optional) Webhook URL for build notifications
- `CI_WEBHOOK_TOKEN` - (Optional) Bearer token for webhook auth

## Important Notes

- **This repository uses Jujutsu (jj) for version control**, not git commands
- **Three hosts are defined**: `nixos` (x86_64-linux), `alta` (aarch64-linux), `Mykolas-MacBook-Pro` (aarch64-darwin)
- **Darwin uses Determinate Nix** with `nix.enable = false` — do not re-enable nix-darwin's built-in nix management
- **Darwin home-manager modules are NOT auto-loaded** — unlike NixOS, darwin `sharedModules` only includes sops; modules must be explicitly imported per user
- **Darwin home-manager users** are declared via the `users` list in `mkDarwinHost` and loaded from `hosts/darwin/<host>/<user>.nix`
- **activitywatch is installed system-wide** in `environment.systemPackages` on NixOS, but services are user-level; on macOS it's installed via Homebrew cask
- **Hyprland is installed via NixOS** (`programs.hyprland.enable = true`), so home-manager's `wayland.windowManager.hyprland.package = null`
- **All homeModules are automatically loaded for NixOS** via the `sharedModules` mechanism in `hosts/default.nix`
- **Files starting with `_` are ignored** by the module loader — use this for helper files or utilities
- **Secrets are encrypted with sops-nix** — the private age key must be present at `~/.config/sops/age/keys.txt` for activation to succeed
- **`modules/_shared-nix.nix`** centralizes Nix cache/substituter settings shared across all hosts — edit this file to add new binary caches
- **Alta (Raspberry Pi) does not use home-manager** (`withHomeManager = false`) and has Determinate Nix commented out pending upstream CI fix
