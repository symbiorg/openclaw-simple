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

users:
  - name: openclaw
    system: true
    shell: /bin/bash
    home: /opt/openclaw

bootcmd:
  - mkdir -p /opt/openclaw/{app,context,workspace,config,scripts}
  - chown -R openclaw:openclaw /opt/openclaw

write_files:
  - path: /opt/openclaw/config/.env
    permissions: '0600'
    owner: openclaw:openclaw
    content: |
      NODE_ENV=production
      ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
      OPENCLAW_DISABLE_BONJOUR=1

  - path: /etc/systemd/system/openclaw.service
    permissions: '0644'
    content: |
      [Unit]
      Description=OpenClaw Agent
      After=network-online.target tailscaled.service

      [Service]
      Type=simple
      User=openclaw
      WorkingDirectory=/opt/openclaw/app
      EnvironmentFile=/opt/openclaw/config/.env
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

  # Firewall: Tailscale only
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow in on tailscale0
  - ufw --force enable

  # Install Node.js 20
  - curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  - apt-get install -y nodejs

  # Clone antfarm
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/snarktank/antfarm.git app"
  - su - openclaw -c "cd /opt/openclaw/app && npm ci"

  # Clone context
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/symbiorgco/dcf-setup.git context/dcf-vault"

  # Start service
  - systemctl daemon-reload
  - systemctl enable openclaw
  - systemctl start openclaw

  # Success marker
  - echo "OpenClaw deployed successfully at \$(date)" > /var/log/openclaw-deploy.log
EOF
}
