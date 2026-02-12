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
  - mkdir -p /opt/openclaw/app /opt/openclaw/knowledge /opt/openclaw/workspace /opt/openclaw/config /opt/openclaw/logs /opt/openclaw/scripts /opt/openclaw/safety/hooks /opt/openclaw/.openclaw/skills/compound-engineering
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

  - path: /opt/openclaw/safety/SAFETY.md
    permissions: '0444'
    owner: root:root
    content: |
      # Safety Constraints — IMMUTABLE
      # Owner: root:root | Permissions: 0444 | Flag: chattr +i
      # To update: SSH as root, chattr -i, edit, chattr +i

      ## Invariants
      1. Never expose credentials (no logging tokens, no committing .env files)
      2. Never open firewall ports to the public
      3. Never delete data — archive instead. Show plan before bulk changes.
      4. Never push code to main without human review (always branch + PR for code repos)
      5. Never weaken security to improve availability
      6. Never modify safety constraints (this file, git hooks, safety/ directory)

      ## Namespace Ownership
      - Agent MAY write to: memory/, agent-context/, workspace/, LEARNINGS.md
      - Agent may NOT write to: SAFETY.md, safety/ directory
      - Agent may update CLAUDE.md for navigation/knowledge but NOT safety rules

      ## Cross-Tier Rules
      - This vault -> Tier 3 (Google): Allowed
      - This vault -> Tier 1 (Personal): NEVER

  - path: /opt/openclaw/safety/hooks/pre-commit
    permissions: '0555'
    owner: root:root
    content: |
      #!/bin/bash
      # Safety constraint enforcement hook (root-owned, immutable)

      STAGED_FILES=\$(git diff --cached --name-only --diff-filter=ACDMR 2>/dev/null)

      for file in \$STAGED_FILES; do
          if [[ "\$(basename "\$file")" == "SAFETY.md" || "\$(basename "\$file")" == "SAFETY-HOOKS.md" ]]; then
              echo "BLOCKED: Cannot commit changes to protected file: \$file"
              echo "\$(date -u +%Y-%m-%dT%H:%M:%SZ) BLOCKED commit to \$file by \$(whoami)" \
                  >> /opt/openclaw/safety/audit.log 2>/dev/null || true
              exit 1
          fi
      done

      # Chain to repo-local hooks (core.hooksPath replaces .git/hooks/, so we call them explicitly)
      GIT_DIR="\$(git rev-parse --git-dir 2>/dev/null)"
      REPO_ROOT="\$(git rev-parse --show-toplevel 2>/dev/null)"

      for hook in "\$GIT_DIR/hooks/pre-commit" "\$REPO_ROOT/.husky/pre-commit"; do
          if [ -f "\$hook" ] && [ -x "\$hook" ]; then
              "\$hook" "\$@" || exit \$?
          fi
      done

      exit 0

  - path: /opt/openclaw/safety/SAFETY-HOOKS.md
    permissions: '0444'
    owner: root:root
    content: |
      # Safety Hooks — Documentation

      ## What's Enforced
      - A global pre-commit hook at /opt/openclaw/safety/hooks/pre-commit
        blocks any commit that stages changes to SAFETY.md or SAFETY-HOOKS.md.
      - The hook is set via system-level git config (core.hooksPath in /etc/gitconfig).
      - All safety files are root-owned with chattr +i (immutable flag).
      - The systemd service uses ReadOnlyPaths=/opt/openclaw/safety.

      ## How to Update Safety Constraints (Human Operator)
      1. SSH as root to the server
      2. chattr -i /opt/openclaw/safety/SAFETY.md
      3. Edit the file
      4. chattr +i /opt/openclaw/safety/SAFETY.md
      5. If the file is also in dcf-vault, repeat for that copy

      ## Hook Chaining
      The safety pre-commit hook runs first, then chains to:
      - .git/hooks/pre-commit (repo-local hooks)
      - .husky/pre-commit (husky-managed hooks)
      This ensures repo-specific linting/formatting still runs.

  - path: /opt/openclaw/workspace/TOOLS.md
    permissions: '0644'
    owner: openclaw:openclaw
    content: |
      # TOOLS.md - What You Have Access To

      ## DCF Knowledge Vault

      Company knowledge base at \`/opt/openclaw/knowledge/dcf-vault/\`.
      Read \`CLAUDE.md\` there for the full manifest. Key areas:
      - \`Company/\` — Brand, operations, team, rewards, links
      - \`Codebase/\` — Technical systems, smart contracts, reference
      - \`Finance/\` — Payout process, scripts
      - \`Projects/Active/\` — Dune, Discord, Support, Affiliate
      - \`memory/\` — Agent-writable daily learnings
      - \`agent-context/\` — Agent-generated summaries

      ### Writing rules
      - MAY write to: \`memory/\`, \`agent-context/\`
      - Do NOT write to: \`Company/\`, \`Projects/\`, \`Finance/\`, \`Codebase/\`
      - Those are human-owned and sync from GitHub

      ### Sync
      - Repo: \`symbiorgco/dcf-setup\` (GitHub, cloned with token)
      - Pull: automatic | Push: \`cd /opt/openclaw/knowledge/dcf-vault && git add -A && git commit -m "Agent: <desc>" && git push\`

      ## GitHub CLI (\`gh\`)

      Authenticated as \`bit-ship-it\`. Available globally.

      ### Common operations
      - \`gh repo list symbiorgco\` — list org repos
      - \`gh pr list --repo symbiorgco/REPO\` — list PRs
      - \`gh pr create --title "..." --body "..."\` — create PR
      - \`gh issue list --repo symbiorgco/REPO\` — list issues
      - \`gh repo clone symbiorgco/REPO /opt/openclaw/workspace/REPO\` — clone a repo

      ### Safety
      - Always branch + PR for code changes (never push to main directly)
      - Use \`bit-ship-it\` as commit author (already configured in git config)

      ## AWS CLI

      Credentials configured at \`/opt/openclaw/.aws/credentials\`. Available globally.

      ### Common operations
      - \`aws s3 ls\` — list S3 buckets
      - \`aws s3 cp <local> s3://bucket/key\` — upload to S3
      - \`aws sts get-caller-identity\` — verify credentials

      ## Antfarm (Multi-Agent Workflows)

      Installed at \`/opt/openclaw/app/antfarm/\`, npm-linked globally.

      Antfarm is a multi-agent workflow orchestrator. It runs teams of specialized AI agents through defined workflows (feature development, bug fixes, security audits).

      ### Available workflows
      - \`feature-dev\` — Plan → setup → implement → verify → test → PR → review
      - \`bug-fix\` — Investigate → fix → verify → test → PR
      - \`security-audit\` — Scan → analyze → patch → verify

      ### Usage
      - \`antfarm run --workflow feature-dev --repo <path> --task "<description>"\`
      - \`antfarm status\` — check running workflows
      - Docs: \`/opt/openclaw/app/antfarm/README.md\`

      ## Compound Engineering (Nightly Knowledge Compounding)

      One cron job runs nightly:

      - **compound-engineering** (22:30 UTC) — Gathers data from all sources,
        extracts insights, writes a daily compound report, updates LEARNINGS.md

      Skill definition: \`skills/compound-engineering/SKILL.md\`

      ### Workspace layout
      \`\`\`
      workspace/compound/
      ├── learnings/      — Daily reports (YYYY-MM-DD.md) + LEARNINGS.md
      ├── slack/          — Slack thread extracts
      ├── github/         — GitHub activity
      ├── logs/           — Execution logs
      └── reports/        — Prioritized work items
      \`\`\`

      ### How to use
      - **Primary:** Read \`dcf-vault/agent-context/compound-learnings.md\` (auto-loaded in context)
      - **Archive:** Check \`workspace/compound/learnings/YYYY-MM-DD.md\` for full daily reports
      - **Full log:** Check \`workspace/compound/learnings/LEARNINGS.md\` for the raw rolling log
      - Trigger manually: \`openclaw cron run <id>\`

  - path: /opt/openclaw/.openclaw/skills/compound-engineering/SKILL.md
    permissions: '0644'
    owner: openclaw:openclaw
    content: |
      # Compound Engineering — Nightly Knowledge Compounding

      This skill defines a nightly batch cycle that compounds knowledge from
      everything the system did in the last 24 hours. Run it by following
      all four phases in order.

      ---

      ## Phase 1 — Gather

      Scan every data source below. For each, run the listed command and
      note what happened in the last 24 hours.

      | Source | Command | What to extract |
      |--------|---------|-----------------|
      | Slack sessions | \`openclaw sessions --json\` | Active sessions, topics discussed, decisions made, questions asked |
      | Cron job history | \`openclaw cron list --json\` | Run results — success/failure, errors, duration trends |
      | Git activity (PRs) | \`gh pr list --state all --limit 20 --json title,state,createdAt,mergedAt,url\` | PRs created/merged/closed in last 24h |
      | Git activity (Issues) | \`gh issue list --state all --limit 20 --json title,state,createdAt,url\` | Issues opened/closed |
      | Git commits | \`git -C /opt/openclaw/knowledge/dcf-vault log --since="24 hours ago" --oneline\` | Recent commits to knowledge vault |
      | Antfarm | \`antfarm status 2>/dev/null\` | Workflow runs, agent results (if antfarm ran anything) |
      | Workspace changes | \`find workspace/ -name "*.md" -mtime -1\` | Files modified today |
      | Agent memory | Read \`workspace/memory/\$(date +%Y-%m-%d).md\` if it exists | Today's memory log |
      | System health | \`openclaw status --json 2>/dev/null\` | Gateway health, channel status, errors |
      | Previous learnings | Read \`workspace/compound/learnings/LEARNINGS.md\` | Existing knowledge base for context |

      ---

      ## Phase 2 — Extract

      For each source that returned data, answer:
      1. **What happened?** (facts only)
      2. **What was learned?** (non-obvious insights)
      3. **What patterns connect across sources?** (cross-cutting themes)

      If a source returned empty or errored, note that — do NOT hallucinate data.

      ---

      ## Phase 3 — Synthesize

      ### Daily report
      Write \`workspace/compound/learnings/YYYY-MM-DD.md\` using this template:

      \`\`\`markdown
      # Compound Report — YYYY-MM-DD

      ## Summary
      (2-3 sentence overview of the day)

      ## Slack Activity
      (key conversations, decisions, unresolved questions)

      ## Development Activity
      (PRs, issues, commits, code changes)

      ## System Health
      (cron results, errors, uptime)

      ## Learnings
      (non-obvious insights, patterns, things that should be remembered)

      ## Action Items
      (things that need human attention or follow-up)

      ## Discovery
      (new data sources, files, or patterns found that weren't in Phase 1)
      \`\`\`

      ### Rolling knowledge base
      Append key learnings to \`workspace/compound/learnings/LEARNINGS.md\`.
      Keep entries concise — one line per learning, prefixed with the date.

      ### Context bridge (workspace → agent context)
      Copy the rolling knowledge into the agent's context path so every
      future session sees it automatically:

      1. Read \`workspace/compound/learnings/LEARNINGS.md\` (the file you just updated).
      2. Write its full contents to
         \`/opt/openclaw/knowledge/dcf-vault/agent-context/compound-learnings.md\`,
         replacing whatever was there before. Prefix the file with:
         \`\`\`
         # Compound Engineering — Rolling Learnings
         *Auto-generated by compound-engineering nightly. Do not edit manually.*
         *Source: workspace/compound/learnings/LEARNINGS.md*
         \`\`\`
      3. This file is in the agent's context load path — every new session reads it.

      ### CLAUDE.md updates
      If new navigation or lookup info was discovered (file paths, sheet IDs,
      quick references), update the dcf-vault \`CLAUDE.md\` at
      \`/opt/openclaw/knowledge/dcf-vault/CLAUDE.md\`.
      **NEVER modify safety rules or Core Guardrails sections.**

      ### Commit & push
      Stage all changed files in **both** repos and push:
      1. \`cd /opt/openclaw/workspace && git add -A && git commit -m "compound: nightly report YYYY-MM-DD" && git push\`
      2. \`cd /opt/openclaw/knowledge/dcf-vault && git add -A && git commit -m "compound: update learnings YYYY-MM-DD" && git push\`

      ---

      ## Phase 4 — Discover

      Self-improvement pass — look for things not listed in Phase 1:
      - Scan for new directories, new file types, new tools
      - Check if any new OpenClaw plugins or channels were added
      - If new data sources are found, document them under \`## Discovery\`
        in the daily report so this skill can be updated

      ---

      ## Critical Rules

      - **Always produce a reply** summarizing what you compounded.
        This is required so \`--announce\` delivers results to Slack.
      - On quiet days with little activity, still reply:
        "Quiet day — no significant activity to compound."
      - **Never modify SAFETY.md files** — they are root-owned and immutable.
        If you hit a permission error, skip the file and continue.
      - **Don't hallucinate learnings** from empty data.
        If a source returned nothing, say so.

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
      ReadOnlyPaths=/opt/openclaw/safety

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

  # Install AWS CLI v2 (if credentials provided)
  - |
    if [ -n "${AWS_ACCESS_KEY_ID}" ] && [ -n "${AWS_SECRET_ACCESS_KEY}" ]; then
      apt-get install -y unzip
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      cd /tmp && unzip -qo awscliv2.zip && ./aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip
      mkdir -p /opt/openclaw/.aws
      mv /opt/openclaw/.aws-credentials /opt/openclaw/.aws/credentials
      chown -R openclaw:openclaw /opt/openclaw/.aws
      echo "AWS CLI v2 installed and configured" >> /var/log/openclaw-deploy.log
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
      su - openclaw -c "git config --global user.name 'bit-ship-it'"
      su - openclaw -c "git config --global user.email 'bit-ship-it@users.noreply.github.com'"
      echo "GitHub CLI installed and authenticated" >> /var/log/openclaw-deploy.log
    fi

  # Clone dcf-vault context (private repo)
  - |
    if [ -n "${GITHUB_TOKEN}" ]; then
      su - openclaw -c "cd /opt/openclaw/knowledge && git clone https://${GITHUB_TOKEN}@github.com/symbiorgco/dcf-setup.git dcf-vault"
    fi

  # Install Antfarm
  - su - openclaw -c "cd /opt/openclaw && git clone https://github.com/snarktank/antfarm.git app/antfarm"
  - su - openclaw -c "cd /opt/openclaw/app/antfarm && npm install && npm run build"
  - cd /opt/openclaw/app/antfarm && npm link

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

  # Configure Slack (enable + mention-gated with thread auto-follow)
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.enabled true" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set plugins.entries.slack.enabled true" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.groupPolicy open" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.dm.allowFrom '[\"*\"]'" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.dm.policy open" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set messages.ackReactionScope all" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.replyToMode all" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.replyToModeByChatType --json '{\"channel\":\"all\",\"direct\":\"all\",\"group\":\"all\"}'" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.requireMention true" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.thread.inheritParent true" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.channels.workspace.requireMention false" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.channels.workbase.requireMention false" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.channels.workbase.systemPrompt 'When replying in a thread, always continue in that same thread. Never break out to the main channel.'" || true
  - su - openclaw -c "cd /opt/openclaw && openclaw config set channels.slack.channels.workspace.systemPrompt 'When replying in a thread, always continue in that same thread. Never break out to the main channel.'" || true

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
  - su - openclaw -c "cd /opt/openclaw && antfarm install"

  # Safety hardening — make safety files immutable to agents
  - |
    # Copy SAFETY.md into dcf-vault for agent context loading
    cp /opt/openclaw/safety/SAFETY.md /opt/openclaw/knowledge/dcf-vault/SAFETY.md
    chown root:root /opt/openclaw/knowledge/dcf-vault/SAFETY.md
    chmod 0444 /opt/openclaw/knowledge/dcf-vault/SAFETY.md

    # Set immutable flags on safety files
    chattr +i /opt/openclaw/safety/SAFETY.md
    chattr +i /opt/openclaw/safety/SAFETY-HOOKS.md
    chattr +i /opt/openclaw/safety/hooks/pre-commit
    chattr +i /opt/openclaw/knowledge/dcf-vault/SAFETY.md

    # Set core.hooksPath in SYSTEM-LEVEL git config (not user .gitconfig)
    git config --system core.hooksPath /opt/openclaw/safety/hooks
    # /etc/gitconfig is already root-owned; make it immutable
    chattr +i /etc/gitconfig

    # Create audit log (root-owned, openclaw can append)
    touch /opt/openclaw/safety/audit.log
    chown root:openclaw /opt/openclaw/safety/audit.log
    chmod 0664 /opt/openclaw/safety/audit.log

    # Add SAFETY.md to dcf-vault .gitignore
    echo "SAFETY.md" >> /opt/openclaw/knowledge/dcf-vault/.gitignore

    # Ensure learnings directories exist
    mkdir -p /opt/openclaw/workspace/compound/learnings
    touch /opt/openclaw/workspace/compound/learnings/LEARNINGS.md
    chown -R openclaw:openclaw /opt/openclaw/workspace/compound/learnings

  # Seed compound-learnings.md placeholder in dcf-vault
  - |
    mkdir -p /opt/openclaw/knowledge/dcf-vault/agent-context
    cat > /opt/openclaw/knowledge/dcf-vault/agent-context/compound-learnings.md <<'SEEDEOF'
    # Compound Engineering — Rolling Learnings
    *Auto-generated by compound-engineering nightly. Do not edit manually.*
    *Source: workspace/compound/learnings/LEARNINGS.md*

    No learnings yet — the first nightly compound-engineering run will populate this file.
    SEEDEOF
    chown openclaw:openclaw /opt/openclaw/knowledge/dcf-vault/agent-context/compound-learnings.md

  # Inject "Compound Engineering Context" section into dcf-vault CLAUDE.md
  - |
    DCF_CLAUDE="/opt/openclaw/knowledge/dcf-vault/CLAUDE.md"
    if [ -f "\$DCF_CLAUDE" ] && ! grep -q "Compound Engineering Context" "\$DCF_CLAUDE"; then
      cat >> "\$DCF_CLAUDE" <<'CLEOF'

    ## Compound Engineering Context

    The compound-engineering nightly skill (22:30 UTC) gathers data from all
    sources, extracts insights, and writes a daily compound report.

    | What | Path | Notes |
    |------|------|-------|
    | **Accumulated learnings** | `agent-context/compound-learnings.md` | Primary — auto-loaded every session |
    | **Daily reports (archive)** | `workspace/compound/learnings/YYYY-MM-DD.md` | One file per day |
    | **Raw rolling log** | `workspace/compound/learnings/LEARNINGS.md` | Append-only log |
    | **Skill definition** | `skills/compound-engineering/SKILL.md` | Full nightly procedure |
    CLEOF
      chown openclaw:openclaw "\$DCF_CLAUDE"
    fi

  # Compound Engineering — 22:30 nightly (knowledge compounding)
  - |
    su - openclaw -c "HOME=/opt/openclaw OPENCLAW_HOME=/opt/openclaw \
      openclaw cron add \
        --name 'compound-engineering' \
        --cron '30 22 * * *' \
        --message 'Read and follow the compound-engineering skill at skills/compound-engineering/SKILL.md. Execute the full nightly compounding cycle: Gather data from all sources, Extract insights, Synthesize into a daily report, and run the Discovery pass. Write the report to workspace/compound/learnings/. Commit and push changes. Always reply with a summary of what you compounded, even if it was a quiet day.' \
        --announce \
        --channel slack \
        --timeout-seconds 900" || echo "cron add skipped"

  # Success marker
  - echo "Deployment completed at \$(date)" > /var/log/openclaw-deploy.log
EOF
}
