#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/hetzner.sh"
source "$SCRIPT_DIR/lib/cloud-init.sh"

# Parse args
INSTANCE_NAME="${1:-openclaw-$(date +%s)}"

# Get credentials
HETZNER_TOKEN="${HETZNER_TOKEN:-}"
TAILSCALE_KEY="${TAILSCALE_KEY:-}"
ANTHROPIC_KEY="${ANTHROPIC_KEY:-}"

# Banner
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║     OpenClaw Simple Deployment       ║"
echo "╚═══════════════════════════════════════╝"
echo ""
log "Instance name: $INSTANCE_NAME"
echo ""

# Validate credentials
validate

# Generate cloud-init
export TAILSCALE_KEY ANTHROPIC_KEY INSTANCE_NAME
CLOUD_INIT=$(generate_cloud_init)

# Create server
SERVER_ID=$(hetzner_create_server "$INSTANCE_NAME" "$CLOUD_INIT")
SERVER_IP=$(hetzner_get_ip "$SERVER_ID")

# Wait for ready
hetzner_wait_ready "$SERVER_IP"

# Get Tailscale IP
log "Getting Tailscale IP..."
sleep 10  # Give Tailscale time to register
TAILSCALE_IP=$(ssh -o StrictHostKeyChecking=no "root@$SERVER_IP" \
  "tailscale ip -4" 2>/dev/null | tr -d '\r\n' || echo "pending")

# Summary
echo ""
echo "╔═══════════════════════════════════════╗"
echo "║      Deployment Complete! 🎉         ║"
echo "╚═══════════════════════════════════════╝"
echo ""
echo "  Name:        $INSTANCE_NAME"
echo "  Server ID:   $SERVER_ID"
echo "  Public IP:   $SERVER_IP"
echo "  Tailscale:   $TAILSCALE_IP"
echo ""
echo "Access:"
echo "  tailscale ssh $INSTANCE_NAME"
if [[ "$TAILSCALE_IP" != "pending" ]]; then
  echo "  Gateway: http://$TAILSCALE_IP:18789"
fi
echo ""
echo "Context available at:"
echo "  /opt/openclaw/context/dcf-vault/"
echo "  /opt/openclaw/context/antfarm/"
echo ""
echo "Check status:"
echo "  ssh root@$SERVER_IP 'systemctl status openclaw'"
echo "  ssh root@$SERVER_IP 'journalctl -u openclaw -f'"
echo ""
