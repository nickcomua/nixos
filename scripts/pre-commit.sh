#!/usr/bin/env bash
# Pre-commit checks for nixos flake
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

cd "$(git rev-parse --show-toplevel 2>/dev/null || jj root)"

echo "🔍 Running pre-commit checks..."

# 1. Format check
log "Checking formatting..."
if ! nix fmt -- --check . >/dev/null 2>&1; then
    warn "Files need formatting, auto-fixing..."
    nix fmt
    log "Formatting applied"
else
    log "Formatting OK"
fi

# 2. Basic flake evaluation check
log "Checking core system evaluation..."
if nix eval .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath >/dev/null 2>&1; then
    log "NixOS system evaluation OK"
else
    error "NixOS system evaluation failed! This will break builds."
fi

# 3. Build check (optional, faster)
if [[ "${1:-}" == "--build" ]]; then
    log "Testing build (this may take a while)..."
    nix build .#nixosConfigurations.nixos.config.system.build.toplevel --dry-run
    log "Build check OK"
fi

echo
log "✨ All pre-commit checks passed!"
echo -e "${GREEN}Safe to commit and push!${NC}"