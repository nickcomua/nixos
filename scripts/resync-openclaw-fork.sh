#!/usr/bin/env bash
# Resync nickcomua/nix-openclaw fork with upstream
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

UPSTREAM="openclaw/nix-openclaw"  
FORK="nickcomua/nix-openclaw"

echo "🔄 Resyncing OpenClaw fork with upstream..."

# Method 1: GitHub CLI (recommended)
if command -v gh >/dev/null 2>&1; then
    log "Using GitHub CLI to sync fork"
    
    # Check if we have a local clone
    if [ ! -d ~/repos/nix-openclaw ]; then
        log "Cloning fork locally"
        mkdir -p ~/repos
        cd ~/repos
        gh repo clone "$FORK"
        cd nix-openclaw
    else
        log "Using existing local clone"
        cd ~/repos/nix-openclaw
    fi
    
    log "Fetching upstream and syncing"
    git remote add upstream "https://github.com/$UPSTREAM.git" 2>/dev/null || true
    git fetch upstream
    git checkout main
    git merge upstream/main
    git push origin main
    
    log "Fork synced successfully"
    
elif [ "$1" = "--web" ]; then
    warn "Manual sync needed - opening GitHub web interface"
    warn "Go to: https://github.com/$FORK"
    warn "Click 'Sync fork' button, then 'Update branch'"
    
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "https://github.com/$FORK"
    fi
else
    warn "GitHub CLI not available. Options:"
    echo "  1. Install gh: nix-shell -p github-cli"
    echo "  2. Use web interface: $0 --web"
    echo "  3. Manual git commands:"
    echo "     git clone https://github.com/$FORK.git"
    echo "     cd nix-openclaw"
    echo "     git remote add upstream https://github.com/$UPSTREAM.git"
    echo "     git fetch upstream && git merge upstream/main && git push"
    exit 1
fi

warn "After fork sync, update flake input:"
echo "  cd ~/.config/nixos"
echo "  nix flake update nix-openclaw"
echo "  jj commit -m 'feat: update OpenClaw to latest version'"
echo "  jj git push"