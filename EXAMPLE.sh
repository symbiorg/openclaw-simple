#!/bin/bash
# Example deployment script
# Copy this file, fill in your credentials, and run it

# Step 1: Set your credentials
export HETZNER_TOKEN="YOUR_HETZNER_TOKEN_HERE"
export TAILSCALE_KEY="tskey-auth-YOUR_TAILSCALE_KEY_HERE"
export ANTHROPIC_KEY="sk-ant-YOUR_ANTHROPIC_KEY_HERE"

# Step 2: Choose a name for your agent
AGENT_NAME="my-openclaw-agent"

# Step 3: Deploy!
./deploy.sh "$AGENT_NAME"

# After deployment completes, you can access your agent:
# tailscale ssh my-openclaw-agent
#
# Check status:
# ssh root@<public-ip> 'systemctl status openclaw'
# ssh root@<public-ip> 'journalctl -u openclaw -f'
#
# Test the gateway:
# curl http://<tailscale-ip>:18789/health
