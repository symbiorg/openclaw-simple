#!/bin/bash

generate_cloud_init() {
  cat <<EOF
#cloud-config

package_update: true
package_upgrade: true

apt:
  conf: |
    APT::Get::Assume-Yes "true";
    DPkg::Options:: "--force-confold";
    Dpkg::Options:: "--force-confdef";

packages:
  - curl
  - git
  - jq
  - ufw
  - fail2ban
  - sqlite3

bootcmd:
  - useradd -r -m -d /opt/openclaw -s /bin/bash openclaw || true
  - mkdir -p /opt/openclaw/app /opt/openclaw/knowledge /opt/openclaw/workspace /opt/openclaw/config /opt/openclaw/logs /opt/openclaw/scripts
  - mkdir -p /opt/openclaw/workspace/compound/slack /opt/openclaw/workspace/compound/github /opt/openclaw/workspace/compound/logs /opt/openclaw/workspace/compound/reports /opt/openclaw/workspace/compound/prds /opt/openclaw/workspace/compound/implementation /opt/openclaw/workspace/compound/learnings
  - chown -R openclaw:openclaw /opt/openclaw

write_files:
  - path: /opt/openclaw/.aws-credentials
    permissions: '0600'
    owner: openclaw:openclaw
    content: |
      ${AWS_ACCESS_KEY_ID:+[default]}
      ${AWS_ACCESS_KEY_ID:+aws_access_key_id = ${AWS_ACCESS_KEY_ID}}
      ${AWS_SECRET_ACCESS_KEY:+aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}}
      ${AWS_DEFAULT_REGION:+region = ${AWS_DEFAULT_REGION}}

  - path: /etc/systemd/system/openclaw.service
    permissions: '0644'
    content: |
      [Unit]
      Description=OpenClaw AI Agent Platform
      After=network-online.target tailscaled.service
      Wants=network-online.target

      [Service]
      Type=simple
      User=openclaw
      Group=openclaw
      WorkingDirectory=/opt/openclaw
      Environment="NODE_ENV=production"
      Environment="HOME=/opt/openclaw"
      Environment="OPENCLAW_HOME=/opt/openclaw"
      EnvironmentFile=/opt/openclaw/.openclaw/.env
      ExecStart=/usr/bin/openclaw gateway --port 18789 --allow-unconfigured
      Restart=always
      RestartSec=10
      StandardOutput=journal
      StandardError=journal

      NoNewPrivileges=true
      PrivateTmp=true
      MemoryMax=4G
      CPUQuota=200%

      [Install]
      WantedBy=multi-user.target

runcmd:
  - export DEBIAN_FRONTEND=noninteractive

  # Install Tailscale
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${TAILSCALE_KEY} --ssh --hostname=${INSTANCE_NAME}

  # Firewall: Tailscale + SSH (SSH needed for deploy script health checks)
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow in on tailscale0
  - ufw --force enable

  # Install Node.js 22 (remove system nodejs first, use NodeSource)
  - apt-get remove -y nodejs libnode-dev libnode109 || true
  - |
    DEBIAN_FRONTEND=noninteractive curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

  # Install OpenClaw globally (npm package)
  - npm install -g openclaw

  # Install AWS CLI (if credentials provided)
  - |
    if [ -n "${AWS_ACCESS_KEY_ID}" ] && [ -n "${AWS_SECRET_ACCESS_KEY}" ]; then
      apt-get install -y awscli
      mkdir -p /opt/openclaw/.aws
      mv /opt/openclaw/.aws-credentials /opt/openclaw/.aws/credentials
      chown -R openclaw:openclaw /opt/openclaw/.aws
      echo "AWS CLI installed and configured" >> /var/log/openclaw-deploy.log
    else
      rm -f /opt/openclaw/.aws-credentials
    fi

  # Install GitHub CLI (if token provided)
  - |
    if [ -n "${GITHUB_TOKEN}" ]; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      apt-get update
      apt-get install -y gh
      su - openclaw -c "echo '${GITHUB_TOKEN}' | gh auth login --with-token"
      echo "GitHub CLI installed and authenticated" >> /var/log/openclaw-deploy.log
    fi

  # Clone dcf-vault context (private repo)
  - |
    if [ -n "${GITHUB_TOKEN}" ]; then
      su - openclaw -c "cd /opt/openclaw/knowledge && git clone https://${GITHUB_TOKEN}@github.com/symbiorgco/dcf-setup.git dcf-vault"
    fi

  # Install Antfarm
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/snarktank/antfarm.git app/antfarm"
  - su - openclaw -c "cd /opt/openclaw/app/antfarm && npm install && npm run build && npm link"

  # Run openclaw onboard (native setup — creates config, .env, systemd service)
  - |
    su - openclaw -c "cd /opt/openclaw && \
      openclaw onboard --non-interactive \
        --accept-risk \
        --anthropic-api-key '${ANTHROPIC_KEY}' \
        ${OPENAI_API_KEY:+--openai-api-key '${OPENAI_API_KEY}'} \
        ${SLACK_APP_TOKEN:+--skip-channels} \
        --gateway-bind loopback \
        --gateway-port 18789 \
        --install-daemon \
        --workspace /opt/openclaw/workspace"

  # Write env tokens that onboard doesn't handle
  - |
    mkdir -p /opt/openclaw/.openclaw
    cat > /opt/openclaw/.openclaw/.env <<ENVEOF
    ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
    OPENCLAW_DISABLE_BONJOUR=1
    OPENCLAW_BIND_HOST=127.0.0.1
    OPENCLAW_GATEWAY_TOKEN=local
    ${SLACK_APP_TOKEN:+SLACK_APP_TOKEN=${SLACK_APP_TOKEN}}
    ${SLACK_BOT_TOKEN:+SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}}
    ${GITHUB_TOKEN:+GITHUB_TOKEN=${GITHUB_TOKEN}}
    ${OPENAI_API_KEY:+OPENAI_API_KEY=${OPENAI_API_KEY}}
    ${AWS_ACCESS_KEY_ID:+AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}}
    ${AWS_SECRET_ACCESS_KEY:+AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}}
    ENVEOF
    chown openclaw:openclaw /opt/openclaw/.openclaw/.env
    chmod 600 /opt/openclaw/.openclaw/.env

  # Configure Slack (open policy — respond in any channel/DM)
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.groupPolicy open" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.dm.allowFrom '[\"*\"]'" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.dm.policy open" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set messages.ackReactionScope all" || true

  # Start/restart service (onboard --install-daemon may have created it)
  - systemctl daemon-reload
  - systemctl enable openclaw || true
  - systemctl restart openclaw || systemctl start openclaw

  # Wait for service to be ready
  - |
    echo "Waiting for OpenClaw service to start..."
    for i in \$(seq 1 30); do
      if systemctl is-active --quiet openclaw; then
        echo "OpenClaw service is running"
        break
      fi
      sleep 2
    done

  # Install Antfarm into OpenClaw
  - su - openclaw -c "cd /opt/openclaw && antfarm install || true"

  # Compound Review — 22:30 nightly (extract learnings, update CLAUDE.md)
  - |
    su - openclaw -c "HOME=/opt/openclaw OPENCLAW_HOME=/opt/openclaw \
      openclaw cron add \
        --name 'compound-review' \
        --cron '30 22 * * *' \
        --message 'Load the compound-engineering skill. Review all threads from the last 24 hours. For any thread where we did not compound learnings, do so now — extract key learnings and update the relevant CLAUDE.md files. Commit and push to main.' \
        --announce \
        --timeout-seconds 600" || echo "cron add skipped"

  # Auto-Compound — 23:00 nightly (fetch reports, implement, create draft PRs)
  - |
    su - openclaw -c "HOME=/opt/openclaw OPENCLAW_HOME=/opt/openclaw \
      openclaw cron add \
        --name 'auto-compound' \
        --cron '0 23 * * *' \
        --message 'Pull latest from main. Check workspace/compound/reports/ for prioritized work items. If found, pick the top priority, create a feature branch, generate a PRD, implement it, and create a draft PR. If no reports, check GitHub issues labeled auto-compound.' \
        --announce \
        --timeout-seconds 1800" || echo "cron add skipped"

  # Success marker
  - echo "Deployment completed at \$(date)" > /var/log/openclaw-deploy.log
EOF
}
