# OpenClaw Simple - One-Click Deployment

Deploy OpenClaw agents to Hetzner with full context access in one command.

## Quick Start

```bash
# 1. Set credentials
export HETZNER_TOKEN="your-hetzner-token"
export TAILSCALE_KEY="tskey-auth-..."
export ANTHROPIC_KEY="sk-ant-..."

# 2. Deploy
./deploy.sh my-agent

# 3. Access
tailscale ssh my-agent
```

## What You Get

- ✅ Bare metal systemd (no Docker)
- ✅ Antfarm AI framework pre-installed
- ✅ DCF company context loaded
- ✅ Tailscale secure access
- ✅ Auto-updates enabled
- ✅ Resource limits (4GB RAM, 2 CPU)

## Context Access

Your agent has direct access to:
- `/opt/openclaw/context/dcf-vault/` - Company knowledge
- `/opt/openclaw/context/antfarm/` - Antfarm framework

No symlinks, no Docker mounts, no permission issues. Just works.

## Architecture

```
/opt/openclaw/
├── app/              # Node.js app (antfarm by default)
├── context/          # Context files (direct access)
│   ├── dcf-vault/    # Company knowledge (git submodule)
│   └── antfarm/      # Antfarm framework (git submodule)
├── workspace/        # Agent workspace
├── config/           # .env, config.json
└── scripts/          # Minimal scripts
```

## Requirements

- Hetzner Cloud account ([get one](https://hetzner.cloud))
- Tailscale account ([get one](https://tailscale.com))
- Anthropic API key ([get one](https://console.anthropic.com))

## How It Works

1. **Validates** your credentials
2. **Generates** optimized cloud-init configuration
3. **Creates** Hetzner CX22 server (Ubuntu 24.04)
4. **Installs** Tailscale, Node.js, security tools
5. **Clones** antfarm app and dcf-vault context
6. **Configures** systemd service with resource limits
7. **Starts** OpenClaw agent automatically

Total deployment time: ~3-5 minutes

## Security Features

- **Tailscale-only access** - No public exposure
- **UFW firewall** - Allow Tailscale interface only
- **Fail2ban** - Brute-force protection
- **Resource limits** - 4GB RAM, 200% CPU max
- **Systemd hardening** - NoNewPrivileges, PrivateTmp

## Troubleshooting

### Check service status
```bash
tailscale ssh my-agent
systemctl status openclaw
journalctl -u openclaw -n 50
```

### Verify context loading
```bash
ls -la /opt/openclaw/context/dcf-vault/
cat /var/log/openclaw-deploy.log
```

### Test connectivity
```bash
curl http://localhost:18789/health
```

## 80-20 Principle

This tool focuses on the essential 80% of use cases:
- ✅ Hetzner only (can add providers later)
- ✅ Single server (HA adds complexity)
- ✅ Tailscale security (simplest and best)
- ✅ Direct file access (no symlinks/mounts)

**Result:** 5 files, ~600 lines, bulletproof deployment.

## License

MIT
