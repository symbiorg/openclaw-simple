#!/bin/bash

generate_cloud_init() {
  cat <<EOF
#cloud-config

package_update: true
package_upgrade: true

packages:
  - curl
  - git
  - jq
  - ufw
  - fail2ban
  - sqlite3

users:
  - name: openclaw
    system: true
    shell: /bin/bash
    home: /opt/openclaw

bootcmd:
  - mkdir -p /opt/openclaw/{app,knowledge,workspace,config,logs,antfarm,antfarm-data/workflows,scripts}
  - mkdir -p /opt/openclaw/workspace/compound/{slack,github,logs,reports,prds,implementation,learnings}
  - chown -R openclaw:openclaw /opt/openclaw

write_files:
  - path: /opt/openclaw/config/.env
    permissions: '0600'
    owner: openclaw:openclaw
    content: |
      NODE_ENV=production
      ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
      OPENCLAW_DISABLE_BONJOUR=1
      ${SLACK_APP_TOKEN:+SLACK_APP_TOKEN=${SLACK_APP_TOKEN}}
      ${SLACK_BOT_TOKEN:+SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}}
      ${AWS_ACCESS_KEY_ID:+AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}}
      ${AWS_SECRET_ACCESS_KEY:+AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}}
      ${AWS_DEFAULT_REGION:+AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}}
      ${GITHUB_TOKEN:+GITHUB_TOKEN=${GITHUB_TOKEN}}
      ${OPENAI_API_KEY:+OPENAI_API_KEY=${OPENAI_API_KEY}}

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
      Description=OpenClaw Agent with Antfarm
      After=network-online.target tailscaled.service

      [Service]
      Type=simple
      User=openclaw
      WorkingDirectory=/opt/openclaw/app
      EnvironmentFile=/opt/openclaw/config/.env
      Environment="OPENCLAW_CONFIG=/opt/openclaw/config/config.json"
      Environment="OPENCLAW_WORKSPACE=/opt/openclaw/workspace"
      Environment="HOME=/opt/openclaw"
      ExecStart=/usr/bin/node dist/index.js
      Restart=always
      RestartSec=10

      NoNewPrivileges=true
      PrivateTmp=true
      MemoryMax=4G
      CPUQuota=200%

      [Install]
      WantedBy=multi-user.target

runcmd:
  # Install Tailscale
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --authkey=${TAILSCALE_KEY} --ssh --hostname=${INSTANCE_NAME}

  # Firewall: Tailscale + SSH (SSH needed for deploy script health checks)
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow in on tailscale0
  - ufw --force enable

  # Install Node.js 22
  - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  - apt-get install -y nodejs

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

  # Clone OpenClaw
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/snarktank/openclaw.git app"
  - su - openclaw -c "cd /opt/openclaw/app && npm ci && npm run build"

  # Clone dcf-vault context
  - su - openclaw -c "cd /opt/openclaw/knowledge && git clone https://github.com/symbiorgco/dcf-setup.git dcf-vault"

  # Install Antfarm (clone, build, link, install)
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/snarktank/antfarm.git antfarm"
  - su - openclaw -c "cd /opt/openclaw/antfarm && npm install && npm run build && npm link"
  - su - openclaw -c "cd /opt/openclaw/app && antfarm install"

  # Run openclaw onboard (native setup)
  - |
    su - openclaw -c "cd /opt/openclaw/app && \
      openclaw onboard --non-interactive \
        --accept-risk \
        --anthropic-api-key '${ANTHROPIC_KEY}' \
        ${OPENAI_API_KEY:+--openai-api-key '${OPENAI_API_KEY}'} \
        ${SLACK_APP_TOKEN:+--skip-channels} \
        --gateway-bind loopback \
        --gateway-port 18789 \
        --install-daemon \
        --workspace /opt/openclaw/workspace"

  # Configure Slack (open policy — respond in any channel/DM)
  - |
    su - openclaw -c "cd /opt/openclaw/app && \
      openclaw config set channels.slack.groupPolicy open && \
      openclaw config set channels.slack.dm.policy open && \
      openclaw config set channels.slack.dm.allowFrom '[\"*\"]' && \
      openclaw config set messages.ackReactionScope all"

  # Start service
  - systemctl daemon-reload
  - systemctl enable openclaw
  - systemctl start openclaw

  # Wait for service to be ready before adding cron jobs
  - |
    echo "Waiting for OpenClaw service to start..."
    for i in \$(seq 1 30); do
      if systemctl is-active --quiet openclaw; then
        echo "OpenClaw service is running"
        break
      fi
      sleep 2
    done

  # Install compound-engineering skill via ClawHub
  - su - openclaw -c "cd /opt/openclaw/app && npm install -g clawhub && clawhub install compound-engineering || echo 'ClawHub install skipped (not yet available)'"

  # Compound Review — 22:30 nightly (extract learnings, update CLAUDE.md)
  - |
    su - openclaw -c "HOME=/opt/openclaw OPENCLAW_HOME=/opt/openclaw \
      openclaw cron add \
        --name 'compound-review' \
        --cron '30 22 * * *' \
        --message 'Load the compound-engineering skill. Review all threads from the last 24 hours. For any thread where we did not compound learnings, do so now — extract key learnings and update the relevant CLAUDE.md files. Commit and push to main.' \
        --announce \
        --timeout-seconds 600"

  # Auto-Compound — 23:00 nightly (fetch reports, implement, create draft PRs)
  - |
    su - openclaw -c "HOME=/opt/openclaw OPENCLAW_HOME=/opt/openclaw \
      openclaw cron add \
        --name 'auto-compound' \
        --cron '0 23 * * *' \
        --message 'Pull latest from main. Check workspace/compound/reports/ for prioritized work items. If found, pick the top priority, create a feature branch, generate a PRD, implement it, and create a draft PR. If no reports, check GitHub issues labeled auto-compound.' \
        --announce \
        --timeout-seconds 1800"

  # Success marker
  - echo "Deployment completed at \$(date)" > /var/log/openclaw-deploy.log
EOF
}
