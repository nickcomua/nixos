# Development Workflow

## Pre-commit Checks

**Always run these commands before committing/pushing:**

```bash
# Quick: Use the pre-commit script
./scripts/pre-commit.sh

# Manual: Run checks individually  
nix fmt                    # Format all nix files
nix flake check           # Check flake syntax and evaluation
nix fmt -- --check .     # Check if formatting is needed (what CI runs)

# With build test (slower)
./scripts/pre-commit.sh --build
```

## Git Workflow

```bash
# 1. Make changes
# 2. Run pre-commit checks
nix fmt && nix flake check

# 3. Commit and push
jj commit -m "your message"
jj bookmark set main -r @-
jj git push
```

## CI Pipeline

Our CI runs these checks:
1. **Format check:** `nix fmt -- --check .`
2. **Build nixos:** x86_64-linux 
3. **Build alta:** aarch64-linux (via QEMU)
4. **Build macos:** aarch64-darwin

## Common Issues

### Formatting Errors
```bash
# Fix: Run formatter
nix fmt
```

### Flake Evaluation Errors
```bash
# Debug: Check specific host
nix build .#nixosConfigurations.nixos.config.system.build.toplevel
nix build .#darwinConfigurations.Mykolas-MacBook-Pro.system
```

### Cross-platform Eval Failures
```bash
# Avoid: nix flake check --all-systems
# Use:   nix flake check  (current system only)
```

## AI Agent Instructions

**For AI agents working with this repo:**

1. **ALWAYS run `nix fmt` before committing**
2. **ALWAYS run `nix flake check` before pushing** 
3. **Use `nix fmt -- --check .` to verify formatting**
4. **If CI fails on formatting, fix with `nix fmt` and push**
5. **If flake check fails, debug the specific build target**

### Pre-push Checklist
- [ ] `nix fmt` completed successfully
- [ ] `nix flake check` passed
- [ ] No evaluation errors in changed modules
- [ ] Commit message is descriptive

### Example Workflow
```bash
# After making changes to a .nix file:
./scripts/pre-commit.sh    # Run all checks
jj commit -m "feat: add feature xyz"
jj bookmark set main -r @-
jj git push
```

## Tools

- **Formatter:** alejandra (via `nix fmt`)
- **VCS:** jujutsu (`jj`) 
- **CI:** GitHub Actions with Cachix
- **Cache:** nickcomua.cachix.org

## Troubleshooting

### "Requires formatting" CI Error
```bash
nix run nixpkgs#alejandra -- ./path/to/file.nix
# or
nix fmt
```

### Build Failures
```bash
# Check specific system
nix build .#nixosConfigurations.nixos.config.system.build.toplevel
```

### Cross-compilation Issues
- Darwin modules can't evaluate on Linux CI
- Use system-specific builds, not `--all-systems`