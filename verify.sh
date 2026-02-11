#!/bin/bash
# Verify credentials before deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║   OpenClaw + Antfarm Credential Verification ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# Check required environment variables
log "Checking required credentials..."

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

# Check optional Slack credentials
echo ""
log "Checking optional Slack credentials..."

if [[ -n "${SLACK_APP_TOKEN:-}" ]] || [[ -n "${SLACK_BOT_TOKEN:-}" ]]; then
  if [[ -z "${SLACK_APP_TOKEN:-}" ]]; then
    log "WARNING: SLACK_BOT_TOKEN set but SLACK_APP_TOKEN missing"
  elif [[ ! "$SLACK_APP_TOKEN" =~ ^xapp- ]]; then
    log "WARNING: SLACK_APP_TOKEN should start with 'xapp-'"
  else
    success "SLACK_APP_TOKEN format valid"
  fi

  if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
    log "WARNING: SLACK_APP_TOKEN set but SLACK_BOT_TOKEN missing"
  elif [[ ! "$SLACK_BOT_TOKEN" =~ ^xoxb- ]]; then
    log "WARNING: SLACK_BOT_TOKEN should start with 'xoxb-'"
  else
    success "SLACK_BOT_TOKEN format valid"
  fi

  echo ""
  log "✓ Slack integration will be enabled"
else
  log "Slack not configured (optional - deploy will use CLI-only mode)"
fi

# Check optional AWS credentials
echo ""
log "Checking optional AWS credentials..."

if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    log "WARNING: AWS_SECRET_ACCESS_KEY set but AWS_ACCESS_KEY_ID missing"
  elif [[ ! "$AWS_ACCESS_KEY_ID" =~ ^AKIA[0-9A-Z]{16}$ ]]; then
    log "WARNING: AWS_ACCESS_KEY_ID format looks unusual (should be AKIA...)"
  else
    success "AWS_ACCESS_KEY_ID format valid"
  fi

  if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    log "WARNING: AWS_ACCESS_KEY_ID set but AWS_SECRET_ACCESS_KEY missing"
  elif [[ ${#AWS_SECRET_ACCESS_KEY} -ne 40 ]]; then
    log "WARNING: AWS_SECRET_ACCESS_KEY length unusual (should be 40 chars)"
  else
    success "AWS_SECRET_ACCESS_KEY format valid"
  fi

  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo ""
    log "✓ AWS CLI will be enabled"
  fi
else
  log "AWS not configured (optional - for debugging/monitoring)"
fi

# Check optional OpenAI credentials
echo ""
log "Checking optional OpenAI credentials..."

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  if [[ ! "$OPENAI_API_KEY" =~ ^sk- ]]; then
    log "WARNING: OPENAI_API_KEY should start with 'sk-'"
  else
    success "OPENAI_API_KEY format valid"
  fi

  echo ""
  log "OpenAI/Codex will be enabled"
else
  log "OpenAI not configured (optional - for multi-provider AI)"
fi

# Check optional GitHub credentials
echo ""
log "Checking optional GitHub credentials..."

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  if [[ ! "$GITHUB_TOKEN" =~ ^(ghp_|github_pat_)[a-zA-Z0-9]{36,}$ ]]; then
    log "WARNING: GITHUB_TOKEN format looks unusual (should be ghp_... or github_pat_...)"
  else
    success "GITHUB_TOKEN format valid"
  fi

  echo ""
  log "✓ GitHub CLI will be enabled"
else
  log "GitHub not configured (optional - for code reviews/PRs)"
fi

# Validate Hetzner API access
echo ""
log "Testing Hetzner API..."
if ! curl -sf -H "Authorization: Bearer $HETZNER_TOKEN" \
  https://api.hetzner.cloud/v1/servers?per_page=1 >/dev/null; then
  error "Invalid Hetzner token or API unreachable"
fi
success "Hetzner API accessible"

# Check required tools
echo ""
log "Checking required tools..."
for tool in curl jq ssh git; do
  if ! command -v "$tool" &>/dev/null; then
    error "Required tool not found: $tool"
  fi
  success "$tool found"
done

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║        All Checks Passed! ✅                 ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "You're ready to deploy:"
ENABLED_FEATURES=""
[[ -n "${SLACK_APP_TOKEN:-}" ]] && [[ -n "${SLACK_BOT_TOKEN:-}" ]] && ENABLED_FEATURES+="Slack "
[[ -n "${OPENAI_API_KEY:-}" ]] && ENABLED_FEATURES+="OpenAI "
[[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]] && ENABLED_FEATURES+="AWS "
[[ -n "${GITHUB_TOKEN:-}" ]] && ENABLED_FEATURES+="GitHub "
ENABLED_FEATURES+="Compound "

if [[ -n "$ENABLED_FEATURES" ]]; then
  echo "  ./deploy.sh my-agent  # With: $ENABLED_FEATURES"
else
  echo "  ./deploy.sh my-agent  # CLI-only mode"
fi
echo ""
