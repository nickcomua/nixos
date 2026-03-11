# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a multi-system Nix configuration built using the flake-parts architecture pattern from [tsandrini/flake-parts-builder](https://github.com/tsandrini/flake-parts-builder/). It manages NixOS (with Hyprland), macOS (nix-darwin), and Raspberry Pi deployments with comprehensive home-manager integration.

## Essential Commands

### System Management
```bash
# Rebuild and switch to new configuration (requires sudo password)
sudo nixos-rebuild switch --flake ~/.config/nixos/#nixos

# Build without applying (test for errors)
nixos-rebuild build --flake ~/.config/nixos/#nixos

# Update all flake inputs
nix flake update

# Update a specific input
nix flake update <input-name>

# Show flake outputs
nix flake show
```

### Development
```bash
# Enter devenv shell (if defined in flake-parts/devenv)
nix develop

# Check flake syntax
nix flake check
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
├── hosts/                   # Host configurations
│   ├── default.nix         # mkHost/mkDarwinHost functions and configurations
│   ├── nixos/              # Main NixOS host (x86_64-linux)
│   │   ├── default.nix     # Host-level NixOS config
│   │   ├── nick.nix        # User home-manager config
│   │   ├── hardware-configuration.nix
│   │   └── apfs.nix        # APFS filesystem support
│   ├── alta/               # Raspberry Pi (aarch64-linux)
│   │   └── default.nix
│   └── darwin/             # macOS hosts
│       └── mykolas-macbook-pro/
│           ├── default.nix
│           ├── nick.nix
│           └── nickp.nix
├── homes/                   # Home-manager standalone configs (currently unused)
├── modules/
│   ├── home-manager/       # Home-manager modules
│   │   ├── default.nix     # Exports homeModules via importApply
│   │   ├── shared/         # Cross-platform (zsh, packages, openclaw)
│   │   ├── linux/          # Linux-specific modules
│   │   ├── darwin/         # macOS-specific modules
│   │   ├── wayland/        # Wayland/Hyprland ecosystem
│   │   │   ├── hyprland/
│   │   │   ├── hyprpanel/
│   │   │   ├── hyprlock/
│   │   │   ├── hypridle/
│   │   │   └── ...
│   │   └── services/       # User services (systemd --user)
│   │       └── activitywatch/
│   ├── nixos/              # System-level NixOS modules
│   └── _programs/          # Program modules (excluded from auto-load)
│       ├── horse-browser/
│       ├── librepods/
│       └── whisper-transcribe/
└── devenv/                 # Development environment config
```

### Home-Manager Integration

This configuration uses **NixOS integration mode** for home-manager (not standalone):

1. `hosts/default.nix` includes `home-manager.nixosModules.home-manager` when `withHomeManager = true`
2. All modules in `flake.homeModules` are loaded via `sharedModules = lib.attrValues config.flake.homeModules`
3. Host-specific home-manager config is in `hosts/nixos/default.nix` under the `home-manager.users.nick` section

### Module Function Signatures

**Home-manager modules** must use this two-layer function pattern to work with `importApply`:

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

**NixOS modules** follow standard NixOS module structure.

### Wayland Configuration System

The `wayland` option namespace (defined in `modules/home-manager/wayland/options.nix`) provides centralized configuration:

- `wayland.hyprland.monitor` - Monitor layouts (set per-host)
- `wayland.hyprland.autostart` - Programs to launch on startup
- `wayland.hypridle.listener` - Idle timeout actions
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
2. Create `default.nix` with two-layer function signature
3. Register in `flake-parts/modules/home-manager/default.nix`:
```nix
config.flake.homeModules = {
  # ... existing modules
  my-feature = importApply ./my-feature { inherit localFlake inputs; };
};
```

The module will be automatically loaded for all home-manager users.

### Adding Systemd User Services

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

# Add a new secret (edit the file and add a new key)
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

GitHub Actions runs on every push and PR:

### Jobs
1. **check** - Format check (`nix fmt`) and linting (`statix`)
2. **build-nixos** - Build x86_64-linux NixOS configuration
3. **build-alta** - Build aarch64-linux (Raspberry Pi) configuration via QEMU
4. **build-macos** - Build aarch64-darwin macOS configuration
5. **promote-*** - On main branch, push to stable branches after successful builds

### Stable Branches
- `stable-nixos` - Last known good NixOS build
- `stable-alta` - Last known good Alta (ARM) build
- `stable-darwin` - Last known good macOS build

### Required GitHub Secrets
- `CACHIX_AUTH_TOKEN` - Auth token for cachix.org binary cache (nickcomua)

## Important Notes

- **This repository uses Jujutsu (jj) for version control**, not git commands
- **Three hosts are defined**: `nixos` (x86_64-linux), `alta` (aarch64-linux), `Mykolas-MacBook-Pro` (aarch64-darwin)
- **activitywatch is installed system-wide** in `environment.systemPackages`, but services are user-level
- **Hyprland is installed via NixOS** (`programs.hyprland.enable = true`), so home-manager's `wayland.windowManager.hyprland.package = null`
- **All homeModules are automatically loaded** via the `sharedModules` mechanism in `hosts/default.nix`
- **Files starting with `_` are ignored** by the module loader - use this for helper files or utilities
- **Secrets are encrypted with sops-nix** - the private age key must be present at `~/.config/sops/age/keys.txt` for activation to succeed
