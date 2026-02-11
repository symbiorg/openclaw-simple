#!/bin/bash
# Example deployment with all options

# Step 1: Set your credentials
export HETZNER_TOKEN="YOUR_HETZNER_TOKEN_HERE"
export TAILSCALE_KEY="tskey-auth-YOUR_TAILSCALE_KEY_HERE"
export ANTHROPIC_KEY="sk-ant-YOUR_ANTHROPIC_KEY_HERE"

# Step 2 (Optional): Enable Slack
export SLACK_APP_TOKEN="xapp-YOUR_APP_TOKEN_HERE"
export SLACK_BOT_TOKEN="xoxb-YOUR_BOT_TOKEN_HERE"

# Step 3 (Optional): Enable AWS CLI
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"  # Optional, defaults to us-east-1

# Step 4 (Optional): Enable GitHub CLI
export GITHUB_TOKEN="ghp_..."  # Personal Access Token or github_pat_...

# Step 5: Choose a name for your agent
AGENT_NAME="openclaw-01"

# Step 6: Deploy
./deploy.sh "$AGENT_NAME"
