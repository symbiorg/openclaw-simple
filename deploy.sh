#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/hetzner.sh"
source "$SCRIPT_DIR/lib/cloud-init.sh"

# Parse args
INSTANCE_NAME="${1:-openclaw-$(date +%s)}"

# Get required credentials
HETZNER_TOKEN="${HETZNER_TOKEN:-}"
TAILSCALE_KEY="${TAILSCALE_KEY:-}"
ANTHROPIC_KEY="${ANTHROPIC_KEY:-}"

# Get optional OpenAI/Codex credentials
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# Determine OpenAI enabled state
OPENAI_ENABLED="false"
if [[ -n "$OPENAI_API_KEY" ]]; then
  OPENAI_ENABLED="true"
  log "OpenAI/Codex will be enabled"
else
  log "OpenAI not configured (optional)"
fi

# Get optional Slack credentials
SLACK_APP_TOKEN="${SLACK_APP_TOKEN:-}"
SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"

# Determine Slack enabled state
SLACK_ENABLED="false"
if [[ -n "$SLACK_APP_TOKEN" && -n "$SLACK_BOT_TOKEN" ]]; then
  SLACK_ENABLED="true"
  log "Slack integration will be enabled"
else
  log "Deploying without Slack (CLI-only mode)"
fi

# Get optional AWS credentials
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Determine AWS enabled state
AWS_ENABLED="false"
if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
  AWS_ENABLED="true"
  log "AWS CLI will be enabled"
else
  log "AWS CLI not configured (optional)"
fi

# Get optional GitHub credentials
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Determine GitHub enabled state
GITHUB_ENABLED="false"
if [[ -n "$GITHUB_TOKEN" ]]; then
  GITHUB_ENABLED="true"
  log "GitHub CLI will be enabled"
else
  log "GitHub CLI not configured (optional)"
fi

# Banner
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  OpenClaw + Antfarm + Compound Engineering → Hetzner ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
log "Instance name: $INSTANCE_NAME"
log "Slack:   $SLACK_ENABLED"
log "OpenAI:  $OPENAI_ENABLED"
log "GitHub:  $GITHUB_ENABLED"
log "AWS:     $AWS_ENABLED"
echo ""

# Validate credentials
validate

# Generate cloud-init
export TAILSCALE_KEY ANTHROPIC_KEY \
       SLACK_APP_TOKEN SLACK_BOT_TOKEN SLACK_ENABLED \
       AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION AWS_ENABLED \
       GITHUB_TOKEN GITHUB_ENABLED \
       OPENAI_API_KEY OPENAI_ENABLED \
       INSTANCE_NAME
CLOUD_INIT=$(generate_cloud_init)

# Create server
SERVER_ID=$(hetzner_create_server "$INSTANCE_NAME" "$CLOUD_INIT")
SERVER_IP=$(hetzner_get_ip "$SERVER_ID")

# Wait for ready
hetzner_wait_ready "$SERVER_IP"

# Get Tailscale IP
log "Getting Tailscale IP..."
sleep 10
TAILSCALE_IP=$(ssh -o StrictHostKeyChecking=no "root@$SERVER_IP" \
  "tailscale ip -4" 2>/dev/null | tr -d '\r\n' || echo "pending")

# Summary
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║            Deployment Complete!                      ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Name:        $INSTANCE_NAME"
echo "  Server ID:   $SERVER_ID"
echo "  Public IP:   $SERVER_IP"
echo "  Tailscale:   $TAILSCALE_IP"
echo ""
echo "Integrations:"
echo "  Slack:     $SLACK_ENABLED"
echo "  OpenAI:    $OPENAI_ENABLED"
echo "  GitHub:    $GITHUB_ENABLED"
echo "  AWS:       $AWS_ENABLED"
echo "  Compound:  enabled (22:30 review, 23:00 auto-compound)"
echo ""
echo "Access:"
echo "  tailscale ssh $INSTANCE_NAME"
if [[ "$TAILSCALE_IP" != "pending" ]]; then
  echo "  Gateway: http://$TAILSCALE_IP:18789"
fi
echo ""
if [[ "$SLACK_ENABLED" == "true" ]]; then
  echo "Slack: DM or @mention the bot in any channel (open policy)"
fi
echo ""
echo "Compound Engineering:"
echo "  ssh root@$SERVER_IP \"su - openclaw -c 'openclaw cron list'\""
echo "  ssh root@$SERVER_IP \"su - openclaw -c 'openclaw cron run compound-review'\""
echo ""
echo "Diagnostics:"
echo "  ssh root@$SERVER_IP 'systemctl status openclaw'"
echo "  ssh root@$SERVER_IP 'journalctl -u openclaw -f'"
echo "  ssh root@$SERVER_IP 'node --version'  # Should be v22.x"
echo ""
