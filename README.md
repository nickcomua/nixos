# NixOS Configuration

Multi-system Nix configuration managing NixOS, macOS (nix-darwin), and Raspberry Pi deployments from a single flake.

## Systems

| Host | Platform | Description |
|------|----------|-------------|
| `nixos` | x86_64-linux | Main development machine with Hyprland |
| `mykolas-macbook-pro` | aarch64-darwin | MacBook Pro with nix-darwin |
| `alta` | aarch64-linux | Raspberry Pi deployment server |

## Quick Start

```bash
# NixOS - rebuild and switch
sudo nixos-rebuild switch --flake ~/.config/nixos/#nixos

# macOS - rebuild and switch
darwin-rebuild switch --flake ~/.config/nixos/#Mykolas-MacBook-Pro

# Build without applying (test for errors)
nixos-rebuild build --flake ~/.config/nixos/#nixos

# Check flake syntax
nix flake check

# Update all inputs
nix flake update

# Update specific input
nix flake update <input-name>
```

## Version Control

This repository uses **Jujutsu (jj)** instead of git:

```bash
jj status              # Check status
jj commit -m "msg"     # Create commit
jj git push            # Push to remote
```

## Directory Structure

```
flake-parts/
├── _bootstrap.nix           # Module loader (files with _ prefix excluded)
├── formatter.nix            # Alejandra formatter
├── systems.nix              # Supported systems
├── devenv/                  # Development environment
├── hosts/
│   ├── default.nix          # mkHost/mkDarwinHost functions
│   ├── nixos/               # Main NixOS host (x86_64-linux)
│   ├── alta/                # Raspberry Pi (aarch64-linux)
│   └── darwin/
│       └── mykolas-macbook-pro/  # macOS host (aarch64-darwin)
└── modules/
    ├── home-manager/
    │   ├── shared/          # Cross-platform (zsh, packages, openclaw)
    │   ├── linux/           # Linux-specific modules
    │   ├── darwin/          # macOS-specific modules
    │   ├── wayland/         # Hyprland ecosystem
    │   └── services/        # User services (activitywatch)
    ├── nixos/               # System-level NixOS modules
    └── _programs/           # Program modules (excluded from auto-load)
```

## Module System

The configuration uses a custom recursive module loader (`_bootstrap.nix`):

- Files/directories starting with `_` are **excluded** from auto-loading
- If `dir/default.nix` exists, only that file is loaded (no recursion)
- All other `.nix` files are automatically imported

Home-manager modules are registered in `modules/home-manager/default.nix` and loaded via `sharedModules` for all users.

## Key Features

### Wayland/Hyprland
- Comprehensive Hyprland configuration with multi-monitor support
- Adaptive brightness control (laptop + external DDC/CI monitors)
- Hyprpanel, Hyprlock, Hypridle, Hyprpaper integration
- Vicinae app launcher with clipboard history
- Satty screenshot annotation

### Cross-Platform
- Shared zsh configuration with platform-specific extensions
- Common packages across all systems
- Clawdbot Telegram integration (macOS + NixOS)

### Hardware Support
- Lenovo IdeaPad battery conservation mode
- I2C/DDC-CI for external monitor control
- Bluetooth with Apple DeviceID for AirPods

### Services
- ActivityWatch time tracking
- MinIO object storage
- Steam with remote play
- Docker virtualization

## Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) using age encryption:

```bash
# Edit secrets (decrypts, opens editor, re-encrypts)
sops secrets.yaml

# Initial setup on new machine
age-keygen -o ~/.config/sops/age/keys.txt
# Add public key to .sops.yaml, then:
sops updatekeys secrets.yaml
```

Files:
- `secrets.yaml` - Encrypted secrets (safe to commit)
- `.sops.yaml` - Sops config with public keys
- `~/.config/sops/age/keys.txt` - Private key (never commit)

## CI/CD

GitHub Actions builds all configurations on push/PR:

| Job | Platform | Description |
|-----|----------|-------------|
| check | ubuntu | Format + statix lint |
| build-nixos | x86_64-linux | Main NixOS build |
| build-alta | aarch64-linux | Raspberry Pi via QEMU |
| build-macos | aarch64-darwin | macOS build |

Successful main branch builds promote to `stable-nixos`, `stable-alta`, `stable-darwin` branches.

**Required GitHub Secret:** `CACHIX_AUTH_TOKEN` for binary cache.

## Development

```bash
# Enter dev shell
nix develop

# Format all nix files
nix fmt

# Lint
nix run nixpkgs#statix -- check .
```

Pre-commit hooks are configured for: treefmt, nil, markdownlint, editorconfig-checker.

## Adding a New Home-Manager Module

1. Create `flake-parts/modules/home-manager/my-feature/default.nix`
2. Use two-layer function signature for `importApply`:
   ```nix
   { localFlake, inputs, ... }:
   { config, lib, pkgs, ... }:
   {
     # Module content
   }
   ```
3. Register in `modules/home-manager/default.nix`:
   ```nix
   my-feature = importApply ./my-feature { inherit localFlake inputs; };
   ```

## References

- Built using [tsandrini/flake-parts-builder](https://github.com/tsandrini/flake-parts-builder/)
- [flake-parts documentation](https://flake.parts/)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [Hyprland wiki](https://wiki.hyprland.org/)
