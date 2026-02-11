# OpenClaw + Antfarm: One-Click Hetzner Deployment

Deploy a complete AI agent platform with multi-agent workflows to Hetzner in one command.

## What You Get

- **OpenClaw.ai** - AI agent runtime with messaging integrations
- **Antfarm** - Multi-agent workflow orchestration
- **DCF Vault** - Company context and knowledge
- **Tailscale VPN** - Secure private network access
- **Optional Slack** - Team collaboration in #workbase and #dashboards
- **Optional AWS CLI** - AWS debugging and monitoring
- **Optional GitHub CLI** - Code reviews and pull requests

## Quick Start

### 1. Set Required Credentials

```bash
export HETZNER_TOKEN="your-hetzner-api-token"
export TAILSCALE_KEY="tskey-auth-your-tailscale-key"
export ANTHROPIC_KEY="sk-ant-your-anthropic-key"
```

### 2. (Optional) Enable Slack

```bash
export SLACK_APP_TOKEN="xapp-your-app-token"
export SLACK_BOT_TOKEN="xoxb-your-bot-token"
```

**To get Slack tokens:**
1. Create app at https://api.slack.com/apps
2. Enable Socket Mode → Generate App-Level Token (xapp-)
3. Add bot scopes: `app_mentions:read`, `channels:history`, `channels:read`, `chat:write`, `users:read`
4. Install to workspace → Copy Bot User OAuth Token (xoxb-)

### 3. (Optional) Enable AWS CLI

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"  # Optional, defaults to us-east-1
```

**Use cases:**
- Check CloudWatch logs during debugging
- Access S3 buckets from workflows
- Interact with AWS services

**To get AWS credentials:**
1. Go to AWS Console → IAM → Users
2. Create user or select existing user
3. Security credentials → Create access key
4. Choose "CLI" use case
5. Copy Access Key ID and Secret Access Key

### 4. (Optional) Enable GitHub CLI

```bash
export GITHUB_TOKEN="ghp_..."  # or github_pat_...
```

**Use cases:**
- Review pull requests from workflows
- Create branches and commit code
- Open PRs automatically

**To get GitHub token:**
1. Go to https://github.com/settings/tokens
2. Generate new token (classic or fine-grained)
3. Select scopes: `repo`, `workflow`, `write:packages` (as needed)
4. Copy the token (starts with `ghp_` or `github_pat_`)

### 5. Verify and Deploy

```bash
./verify.sh          # Validate credentials
./deploy.sh my-agent # Deploy to Hetzner
```

### 4. Access Your Agent

**Via Tailscale SSH:**
```bash
tailscale ssh my-agent
```

**Via Slack (if enabled):**
```
# Invite bot to channels:
/invite @OpenClaw Agent

# In #workbase channel:
@OpenClaw Agent run feature-dev "Add user authentication"
@OpenClaw Agent status
@OpenClaw Agent help
```

**Via CLI:**
```bash
tailscale ssh my-agent
antfarm workflow list
antfarm workflow run feature-dev "Add user auth"
antfarm workflow status <run-id>
```

## Architecture

```
┌─────────────────────────────────────────┐
│           Slack #workbase               │
│         (Team Collaboration)            │
└──────────────┬──────────────────────────┘
               │ @OpenClaw Agent message
               ↓
┌─────────────────────────────────────────┐
│      OpenClaw Gateway (port 18789)      │
│   - Message routing                     │
│   - Context loading (dcf-vault)         │
│   - Platform integrations               │
└──────────────┬──────────────────────────┘
               │ Parse intent & trigger
               ↓
┌─────────────────────────────────────────┐
│         Antfarm Workflow Engine         │
│   - Multi-agent orchestration           │
│   - State management (SQLite)           │
│   - Agent cron jobs                     │
└──────────────┬──────────────────────────┘
               │ Execute workflow steps
               ↓
┌──────┬──────────┬────────┬──────────────┐
│Planner│Developer│Verifier│Tester│Reviewer│
└───────┴──────────┴────────┴──────────────┘
     Agent Team (Ralph Loop Pattern)
```

### File Structure

```
/opt/openclaw/
├── app/              # OpenClaw Node.js application
├── knowledge/
│   └── dcf-vault/    # Company context (git clone)
├── workspace/        # Agent scratch space
├── config/
│   ├── .env          # API keys and tokens
│   └── config.json   # Platform and channel config
├── .aws/             # AWS credentials (if AWS_* provided)
│   └── credentials
├── logs/
└── antfarm-data/
    ├── workflows/    # YAML workflow definitions
    ├── antfarm.db   # SQLite state
    └── events.jsonl # Event log
```

## Cost

- **Hetzner CX23:** €3.49/month (~$3.80/month)
- **Claude API:** Usage-based (typically $5-20/month)
- **Tailscale:** Free (up to 100 devices)
- **Total:** ~$10-25/month

## Configuration

All configuration in `/opt/openclaw/config/`:

**config.json** - Platform and channel settings
```json
{
  "gateway": { "port": 18789 },
  "channels": {
    "slack": {
      "enabled": true,
      "channels": {
        "#workbase": { "allow": true },
        "#dashboards": { "allow": true }
      }
    }
  },
  "context": {
    "paths": ["/opt/openclaw/knowledge/dcf-vault"]
  }
}
```

**.env** - API keys and tokens (0600 permissions)
```
ANTHROPIC_API_KEY=sk-ant-...
SLACK_APP_TOKEN=xapp-...
SLACK_BOT_TOKEN=xoxb-...
```

## Workflows

Antfarm comes with pre-configured workflows:

- **feature-dev** - Full feature development (plan → code → test → review)
- **bugfix** - Bug investigation and fix
- **refactor** - Code refactoring with safety checks
- **docs** - Documentation generation

Custom workflows: `/opt/openclaw/antfarm-data/workflows/`

## Troubleshooting

### Check service status
```bash
tailscale ssh my-agent
systemctl status openclaw
journalctl -u openclaw -n 50
```

### Test Slack connection
```bash
journalctl -u openclaw -n 100 | grep -i slack
# Should see: "Slack platform enabled", "Connected to workspace"
```

### Manual restart
```bash
systemctl restart openclaw
```

### View Antfarm state
```bash
antfarm workflow runs
sqlite3 /opt/openclaw/antfarm-data/antfarm.db "SELECT * FROM runs LIMIT 5"
```

### Verify context loading
```bash
ls -la /opt/openclaw/knowledge/dcf-vault/
cat /var/log/openclaw-deploy.log
```

### Verify AWS CLI configuration
```bash
tailscale ssh my-agent
aws --version
aws s3 ls  # Test access
```

### Verify GitHub CLI configuration
```bash
tailscale ssh my-agent
gh --version
gh auth status
gh repo list  # Test access
```

## Security

- Tailscale VPN for all access (no public ports)
- UFW firewall configured
- Fail2ban for SSH protection
- Auto-updates enabled
- Non-root user (openclaw)
- Resource limits (4GB RAM, 200% CPU)

## Advanced Usage

### Multiple Agents

Deploy multiple agents for different teams or projects:

```bash
./deploy.sh team-frontend
./deploy.sh team-backend
./deploy.sh research-agent
```

Each agent runs independently with its own context and workflows.

### Custom Workflows

Create custom Antfarm workflows:

```bash
tailscale ssh my-agent
cd /opt/openclaw/antfarm-data/workflows
vim custom-workflow.yaml
antfarm workflow validate custom-workflow.yaml
```

### Monitoring

View real-time logs and events:

```bash
# Service logs
journalctl -u openclaw -f

# Antfarm events
tail -f /opt/openclaw/antfarm-data/events.jsonl

# System resources
htop
```

## Requirements

### Accounts Needed

- **Hetzner Cloud** - [Get account](https://hetzner.cloud)
- **Tailscale** - [Get account](https://tailscale.com)
- **Anthropic API** - [Get key](https://console.anthropic.com)
- **Slack (optional)** - [Create app](https://api.slack.com/apps)

### Local Tools

- `curl`, `jq`, `ssh`, `git` - Usually pre-installed
- Run `./verify.sh` to check

## How It Works

1. **Validates** your credentials
2. **Generates** optimized cloud-init configuration
3. **Creates** Hetzner CX23 server (Ubuntu 24.04)
4. **Installs** Tailscale, Node.js, security tools
5. **Clones** OpenClaw app and dcf-vault context
6. **Initializes** Antfarm workflow engine
7. **Configures** systemd service with resource limits
8. **Starts** OpenClaw agent automatically

Total deployment time: ~4-6 minutes

## Deployment Modes

### CLI-Only (No Slack)

```bash
# Only set required credentials
export HETZNER_TOKEN="..."
export TAILSCALE_KEY="..."
export ANTHROPIC_KEY="..."

./deploy.sh cli-agent
```

Access via SSH and use `antfarm` commands directly.

### With Slack

```bash
# Set all credentials including Slack
export HETZNER_TOKEN="..."
export TAILSCALE_KEY="..."
export ANTHROPIC_KEY="..."
export SLACK_APP_TOKEN="xapp-..."
export SLACK_BOT_TOKEN="xoxb-..."

./deploy.sh slack-agent
```

Access via Slack in #workbase and #dashboards channels.

### Full Stack with All Tools

```bash
# Set all credentials
export HETZNER_TOKEN="..."
export TAILSCALE_KEY="..."
export ANTHROPIC_KEY="..."
export SLACK_APP_TOKEN="xapp-..."
export SLACK_BOT_TOKEN="xoxb-..."
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export GITHUB_TOKEN="ghp_..."

./deploy.sh full-stack-agent
```

Access via Slack, and agents can use AWS and GitHub CLIs in workflows.

## Integration with Antfarm

OpenClaw provides the platform layer (message routing, context loading, integrations), while Antfarm provides the workflow orchestration layer (multi-agent coordination, state management).

**Example workflow execution:**

1. User sends message in Slack: `@OpenClaw Agent run feature-dev "Add login page"`
2. OpenClaw receives message and loads context from dcf-vault
3. OpenClaw triggers Antfarm: `antfarm workflow run feature-dev "Add login page"`
4. Antfarm orchestrates multiple agents (planner → developer → tester → reviewer)
5. Each agent step posts updates back to Slack thread via OpenClaw
6. Final result delivered to user

## Support

- **Issues:** https://github.com/symbiorgco/openclaw-simple/issues
- **Docs:** https://docs.openclaw.ai
- **Community:** https://discord.gg/openclaw

## License

MIT
