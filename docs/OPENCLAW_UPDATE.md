# OpenClaw Self-Update Workflow

> **Updated**: 2026-03-18 - GitHub Actions had 8+ hour queue issues

Since we're using a **fork** of nix-openclaw (`nickcomua/nix-openclaw`), updating requires resyncing with upstream first.

## Quick Update

```bash
# 1. Resync fork with upstream
cd ~/.config/nixos
./scripts/resync-openclaw-fork.sh

# 2. Update flake input  
nix flake update nix-openclaw

# 3. Commit and deploy
jj commit -m "feat: update OpenClaw to latest version"
jj bookmark set main -r @-
jj git push

# 4. Wait for CI and system rebuild
gh run watch
```

## Manual Steps

### 1. Resync Fork
**Option A: GitHub CLI**
```bash
cd ~/repos
gh repo clone nickcomua/nix-openclaw
cd nix-openclaw
git remote add upstream https://github.com/openclaw/nix-openclaw.git
git fetch upstream
git checkout main  
git merge upstream/main
git push origin main
```

**Option B: GitHub Web UI**
1. Go to https://github.com/nickcomua/nix-openclaw
2. Click "Sync fork" button
3. Click "Update branch"

### 2. Update NixOS Flake
```bash
cd ~/.config/nixos
nix flake update nix-openclaw  # Updates to latest fork commit
```

### 3. Deploy
```bash
jj commit -m "feat: update OpenClaw to $(nix eval --raw .#inputs.nix-openclaw.rev | cut -c1-7)"
jj bookmark set main -r @-
jj git push
```

### 4. Verify Update
After CI completes and system rebuilds:
```bash
systemctl --user status openclaw-gateway
openclaw --version
```

## Fork Info
- **Upstream**: `openclaw/nix-openclaw`  
- **Fork**: `nickcomua/nix-openclaw`
- **Flake input**: `github:nickcomua/nix-openclaw`

## Automation Ideas
- GitHub Action to auto-sync fork daily
- Cron job to check for updates and notify
- Webhook to trigger updates when upstream releases