#!/bin/bash
# Verify credentials before deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║   OpenClaw Credential Verification   ║"
echo "╚═══════════════════════════════════════╝"
echo ""

# Check environment variables
log "Checking environment variables..."

if [[ -z "${HETZNER_TOKEN:-}" ]]; then
  error "HETZNER_TOKEN not set"
fi
success "HETZNER_TOKEN is set"

if [[ -z "${TAILSCALE_KEY:-}" ]]; then
  error "TAILSCALE_KEY not set"
fi
success "TAILSCALE_KEY is set"

if [[ -z "${ANTHROPIC_KEY:-}" ]]; then
  error "ANTHROPIC_KEY not set"
fi
success "ANTHROPIC_KEY is set"

# Validate Hetzner API access
log "Testing Hetzner API..."
if ! curl -sf -H "Authorization: Bearer $HETZNER_TOKEN" \
  https://api.hetzner.cloud/v1/servers?per_page=1 >/dev/null; then
  error "Invalid Hetzner token or API unreachable"
fi
success "Hetzner API accessible"

# Check required tools
log "Checking required tools..."
for tool in curl jq ssh git; do
  if ! command -v "$tool" &>/dev/null; then
    error "Required tool not found: $tool"
  fi
  success "$tool found"
done

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     All Checks Passed! ✅            ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "You're ready to deploy:"
echo "  ./deploy.sh my-agent-name"
echo ""
