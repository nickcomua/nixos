# Contributing Guidelines

## Pre-Push Checklist

**IMPORTANT:** Always run these checks before pushing:

```bash
# 1. Check flake validity
nix flake check --accept-flake-config

# 2. Format code
nix fmt

# 3. Verify formatting
nix fmt -- --check .
```

## Why This Matters

- CI runs `nix flake check` and will fail if there are errors
- Formatting must pass or CI will reject the push
- Catching errors locally saves time and CI resources

## Quick Fix for Failed CI

If CI fails after you push:

```bash
# Check what's wrong
nix flake check --accept-flake-config

# Format if needed  
nix fmt

# Commit and push fix
git add -A
git commit -m "Fix CI errors"
git push
```

## Module Development

When creating new modules in `flake-parts/modules/`:
- Test with `nix flake check` after each change
- Ensure paths in module exports are correct
- Verify both NixOS and home-manager modules load properly
