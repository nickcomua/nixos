#!/usr/bin/env bash
# Setup GitHub CI webhook notifications to OpenClaw
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

WEBHOOK_TOKEN=$(openssl rand -hex 32)
OPENCLAW_HOOK_URL="http://127.0.0.1:18789/hooks/github-ci"

echo "🔗 Setting up GitHub CI webhook notifications..."

# Generate webhook token
echo "$WEBHOOK_TOKEN" > ~/.secrets/github-ci-webhook-token
chmod 600 ~/.secrets/github-ci-webhook-token

log "Generated webhook token: $WEBHOOK_TOKEN"

# Add to GitHub secrets
warn "Add these GitHub repository secrets:"
echo "  CI_WEBHOOK_URL: $OPENCLAW_HOOK_URL"  
echo "  CI_WEBHOOK_TOKEN: $WEBHOOK_TOKEN"

echo
warn "Commands to add secrets:"
echo "  gh secret set CI_WEBHOOK_URL --body '$OPENCLAW_HOOK_URL'"
echo "  gh secret set CI_WEBHOOK_TOKEN --body '$WEBHOOK_TOKEN'"

cat << 'EOF'

📋 Next Steps:

1. Set GitHub secrets (see commands above)
2. Restart OpenClaw gateway to load the new webhook endpoint
3. Push a commit to test CI notifications

The webhook will send notifications to OpenClaw when CI builds complete:
- Success: ✅ All builds passed
- Failure: ❌ Build failures with details

Messages will appear in your Telegram chat via OpenClaw.

EOF