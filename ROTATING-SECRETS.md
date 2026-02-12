# Rotating Secrets — OpenClaw Credential Runbook

Self-service guide for rotating every credential the system uses. Follow the per-credential procedure for routine rotation, or jump to [Emergency: Rotate Everything](#emergency--rotate-everything-at-once) if you suspect a full compromise.

---

## Quick Reference Table

| Credential | Generate at | Server location | Restart needed? |
|---|---|---|---|
| `ANTHROPIC_KEY` | console.anthropic.com | `/opt/openclaw/.openclaw/.env` | Yes (`systemctl restart openclaw`) |
| `SLACK_APP_TOKEN` | api.slack.com/apps | `/opt/openclaw/.openclaw/.env` | Yes (`systemctl restart openclaw`) |
| `SLACK_BOT_TOKEN` | api.slack.com/apps | `/opt/openclaw/.openclaw/.env` | Yes (`systemctl restart openclaw`) |
| `GITHUB_TOKEN` | github.com/settings/tokens | `/opt/openclaw/.openclaw/.env` + `gh` auth + dcf-vault remote | Yes (`systemctl restart openclaw`) + `gh auth login` |
| `OPENAI_API_KEY` | platform.openai.com/api-keys | `/opt/openclaw/.openclaw/.env` | Yes (`systemctl restart openclaw`) |
| `AWS_ACCESS_KEY_ID` | AWS IAM console | `/opt/openclaw/.aws/credentials` + `/opt/openclaw/.openclaw/.env` | No (read per-call) |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM console | `/opt/openclaw/.aws/credentials` + `/opt/openclaw/.openclaw/.env` | No (read per-call) |
| `HETZNER_TOKEN` | console.hetzner.cloud | Local env only (not on server) | No (deploy-time only) |
| `TAILSCALE_KEY` | login.tailscale.com/admin/settings/keys | Local env only (consumed at boot) | No (already joined) |
| SSH keys (`~/.ssh/hetzner`) | `ssh-keygen` locally | `~/.ssh/` local + server `authorized_keys` + Hetzner console | No |

---

## Per-Credential Rotation Procedures

### Anthropic API Key

**What it does:** Authenticates all Claude API calls — the core LLM behind OpenClaw.

1. **Generate new key:** Go to https://console.anthropic.com/settings/keys and create a new API key. Copy it immediately (you won't see it again).

2. **Update on server:**
   ```bash
   ssh root@<SERVER_IP>
   su - openclaw
   # Edit the .env file — replace the ANTHROPIC_API_KEY line
   nano /opt/openclaw/.openclaw/.env
   # Change: ANTHROPIC_API_KEY=sk-ant-OLD...
   # To:     ANTHROPIC_API_KEY=sk-ant-NEW...
   ```

3. **Restart the service:**
   ```bash
   exit  # back to root
   systemctl restart openclaw
   systemctl status openclaw  # confirm it's running
   ```

4. **Verify:** Check the journal for successful startup (no auth errors):
   ```bash
   journalctl -u openclaw --since "1 min ago" --no-pager
   ```

5. **Revoke old key:** Go back to https://console.anthropic.com/settings/keys and delete the old key.

6. **Update local env:** Update your local shell exports or `.env` file so future deploys use the new key:
   ```bash
   export ANTHROPIC_KEY="sk-ant-NEW..."
   ```

---

### Slack Tokens (App Token + Bot Token)

**What they do:** `SLACK_APP_TOKEN` (starts with `xapp-`) opens the Socket Mode connection. `SLACK_BOT_TOKEN` (starts with `xoxb-`) authenticates API calls. These must be rotated together.

1. **Generate new tokens:** Go to https://api.slack.com/apps, select your app.
   - **App Token:** Settings > Basic Information > App-Level Tokens. Generate a new token with `connections:write` scope.
   - **Bot Token:** OAuth & Permissions > Bot User OAuth Token. Reinstall the app to your workspace to get a new `xoxb-` token.

2. **Update on server:**
   ```bash
   ssh root@<SERVER_IP>
   su - openclaw
   nano /opt/openclaw/.openclaw/.env
   # Replace both lines:
   #   SLACK_APP_TOKEN=xapp-NEW...
   #   SLACK_BOT_TOKEN=xoxb-NEW...
   ```

3. **Restart the service:**
   ```bash
   exit  # back to root
   systemctl restart openclaw
   ```

4. **Verify:** Watch the journal for a successful Slack socket connection:
   ```bash
   journalctl -u openclaw -f --no-pager
   # Look for: Slack channel connected / socket open
   ```

5. **Revoke old tokens:** In the Slack app settings, delete the old App-Level Token. The old Bot Token is automatically invalidated when you reinstall the app.

6. **Update local env:**
   ```bash
   export SLACK_APP_TOKEN="xapp-NEW..."
   export SLACK_BOT_TOKEN="xoxb-NEW..."
   ```

---

### GitHub Token

**What it does:** Authenticates `gh` CLI, git clone/push for private repos (including `dcf-vault`), and is passed to the OpenClaw process.

1. **Generate new token:** Go to https://github.com/settings/tokens (or Fine-grained tokens). Create a new token with the same scopes as the old one (typically `repo`, `read:org`).

2. **Update on server — four places:**
   ```bash
   ssh root@<SERVER_IP>
   su - openclaw

   # (a) Update .env
   nano /opt/openclaw/.openclaw/.env
   # Change: GITHUB_TOKEN=ghp_OLD...
   # To:     GITHUB_TOKEN=ghp_NEW...

   # (b) Re-authenticate gh CLI
   echo 'ghp_NEW...' | gh auth login --with-token
   gh auth status  # confirm

   # (c) Update dcf-vault git remote (token is embedded in the clone URL)
   cd /opt/openclaw/knowledge/dcf-vault
   git remote set-url origin https://ghp_NEW...@github.com/symbiorgco/dcf-setup.git
   git fetch  # confirm it works

   # (d) Update gh CLI config (should already be handled by step b, but verify)
   cat ~/.config/gh/hosts.yml
   ```

3. **Restart the service:**
   ```bash
   exit  # back to root
   systemctl restart openclaw
   ```

4. **Verify:**
   ```bash
   su - openclaw -c "gh auth status"
   su - openclaw -c "cd /opt/openclaw/knowledge/dcf-vault && git pull"
   ```

5. **Revoke old token:** Go to https://github.com/settings/tokens and delete the old token.

6. **Update local env:**
   ```bash
   export GITHUB_TOKEN="ghp_NEW..."
   ```

---

### OpenAI API Key

**What it does:** Enables OpenAI/Codex as an additional AI provider (optional).

1. **Generate new key:** Go to https://platform.openai.com/api-keys and create a new secret key.

2. **Update on server:**
   ```bash
   ssh root@<SERVER_IP>
   su - openclaw
   nano /opt/openclaw/.openclaw/.env
   # Change: OPENAI_API_KEY=sk-OLD...
   # To:     OPENAI_API_KEY=sk-NEW...
   ```

3. **Restart the service:**
   ```bash
   exit  # back to root
   systemctl restart openclaw
   ```

4. **Verify:** Check the journal for no OpenAI auth errors:
   ```bash
   journalctl -u openclaw --since "1 min ago" --no-pager
   ```

5. **Revoke old key:** Go to https://platform.openai.com/api-keys and delete the old key.

6. **Update local env:**
   ```bash
   export OPENAI_API_KEY="sk-NEW..."
   ```

---

### AWS Credentials (Access Key + Secret Key)

**What they do:** Authenticate the AWS CLI for S3, STS, and other AWS services. Read per-call — no restart required.

1. **Generate new credentials:** Go to AWS IAM Console > Users > your user > Security credentials > Create access key.

2. **Update on server — two files:**
   ```bash
   ssh root@<SERVER_IP>
   su - openclaw

   # (a) Update AWS credentials file
   nano /opt/openclaw/.aws/credentials
   # Replace:
   #   [default]
   #   aws_access_key_id = AKIANEW...
   #   aws_secret_access_key = NEW_SECRET...

   # (b) Update .env (OpenClaw also reads these)
   nano /opt/openclaw/.openclaw/.env
   # Change both lines:
   #   AWS_ACCESS_KEY_ID=AKIANEW...
   #   AWS_SECRET_ACCESS_KEY=NEW_SECRET...
   ```

3. **Restart:** Not needed — AWS CLI reads credentials per-call. But if you want OpenClaw processes to pick up the .env changes immediately:
   ```bash
   exit  # back to root
   systemctl restart openclaw  # optional, for .env changes
   ```

4. **Verify:**
   ```bash
   su - openclaw -c "aws sts get-caller-identity"
   ```

5. **Deactivate old key:** Go to AWS IAM Console > Users > your user > Security credentials. Deactivate (then delete) the old access key.

6. **Update local env:**
   ```bash
   export AWS_ACCESS_KEY_ID="AKIANEW..."
   export AWS_SECRET_ACCESS_KEY="NEW_SECRET..."
   ```

---

### Hetzner API Token

**What it does:** Creates and manages Hetzner Cloud servers. Only used locally by `deploy.sh` — never stored on the server.

1. **Generate new token:** Go to https://console.hetzner.cloud > your project > Security > API Tokens. Create a new Read & Write token.

2. **Update locally:** Just update your shell environment before the next deploy:
   ```bash
   export HETZNER_TOKEN="NEW_TOKEN..."
   ```

3. **Restart:** Not needed — this token is only used at deploy time.

4. **Verify:**
   ```bash
   curl -s -H "Authorization: Bearer $HETZNER_TOKEN" \
     https://api.hetzner.cloud/v1/servers?per_page=1 | jq .
   # Or run: ./verify.sh
   ```

5. **Revoke old token:** Go to https://console.hetzner.cloud > your project > Security > API Tokens. Delete the old token.

---

### Tailscale Auth Key

**What it does:** Joins the server to your Tailscale network at boot time. Only used locally by `deploy.sh` and consumed once during cloud-init. Already-running servers don't need it.

1. **Generate new key:** Go to https://login.tailscale.com/admin/settings/keys. Create a new auth key (reusable if you deploy multiple servers).

2. **Update locally:**
   ```bash
   export TAILSCALE_KEY="tskey-auth-NEW..."
   ```

3. **Restart:** Not needed for existing servers — they're already joined. Only needed for new deploys.

4. **If a server loses Tailscale auth** (rare — e.g., key expired on a pre-auth node):
   ```bash
   ssh root@<SERVER_IP>  # use public IP since Tailscale is down
   tailscale up --authkey=tskey-auth-NEW...
   ```

5. **Revoke old key:** Go to https://login.tailscale.com/admin/settings/keys and delete the old key. This does NOT disconnect servers already using it.

---

### SSH Keys

**What they do:** Authenticate SSH connections to Hetzner servers. The deploy scripts use `~/.ssh/hetzner` as the identity file.

1. **Generate new keypair:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/hetzner-new -C "openclaw-deploy"
   ```

2. **Add new public key to Hetzner console:** Go to https://console.hetzner.cloud > your project > Security > SSH Keys. Add the contents of `~/.ssh/hetzner-new.pub`.

3. **Add new public key to existing server(s):**
   ```bash
   # Use the OLD key to connect, then add the new one
   ssh -i ~/.ssh/hetzner root@<SERVER_IP> \
     "cat >> /root/.ssh/authorized_keys" < ~/.ssh/hetzner-new.pub
   ```

4. **Test the new key:**
   ```bash
   ssh -i ~/.ssh/hetzner-new root@<SERVER_IP> "echo works"
   ```

5. **Remove old public key from server(s):**
   ```bash
   ssh -i ~/.ssh/hetzner-new root@<SERVER_IP>
   nano /root/.ssh/authorized_keys
   # Delete the line containing the old key
   ```

6. **Remove old key from Hetzner console:** Delete the old SSH key entry (so new servers won't get it).

7. **Swap locally:**
   ```bash
   mv ~/.ssh/hetzner ~/.ssh/hetzner-old
   mv ~/.ssh/hetzner-new ~/.ssh/hetzner
   mv ~/.ssh/hetzner-new.pub ~/.ssh/hetzner.pub
   ```

8. **Update `~/.ssh/config`** if you have host entries referencing the key:
   ```
   Host openclaw-*
     IdentityFile ~/.ssh/hetzner
     User root
   ```

---

## Emergency — Rotate Everything at Once

If you suspect all credentials are compromised, work through this checklist in order. The order is by blast radius — revoke infrastructure access first, then API keys, then SSH.

### Phase 1: Revoke infrastructure access (prevent new resource creation)

- [ ] **Hetzner token:** Delete the old token at console.hetzner.cloud immediately. This prevents anyone from creating/deleting servers.
- [ ] **Tailscale key:** Delete the old auth key at login.tailscale.com/admin/settings/keys. This prevents new devices from joining your network.

### Phase 2: Rotate API keys (stop unauthorized API usage)

- [ ] **Anthropic key:** Generate new key, update server `.env`, restart service, delete old key.
- [ ] **OpenAI key:** Generate new key, update server `.env`, restart service, delete old key.
- [ ] **GitHub token:** Generate new token, update server `.env`, re-auth `gh`, update dcf-vault remote, restart service, delete old token.
- [ ] **Slack tokens:** Generate new App + Bot tokens, update server `.env`, restart service, delete old tokens.
- [ ] **AWS credentials:** Generate new access key, update server `.aws/credentials` + `.env`, deactivate old key.

### Phase 3: Rotate SSH keys (lock out unauthorized shell access)

- [ ] Generate new SSH keypair.
- [ ] Add new public key to server `authorized_keys` and Hetzner console.
- [ ] Remove old public key from server `authorized_keys` and Hetzner console.
- [ ] Test access with new key.

### Phase 4: Verify

- [ ] `systemctl status openclaw` — service running
- [ ] `journalctl -u openclaw --since "5 min ago"` — no auth errors
- [ ] `su - openclaw -c "gh auth status"` — GitHub connected
- [ ] `su - openclaw -c "aws sts get-caller-identity"` — AWS connected
- [ ] `su - openclaw -c "cd /opt/openclaw/knowledge/dcf-vault && git pull"` — dcf-vault accessible
- [ ] `curl -s http://localhost:18789/health` — gateway responds (from server)

---

## Where Credentials Live (Reference)

### On the server

| File | Contains | Owner | Perms |
|---|---|---|---|
| `/opt/openclaw/.openclaw/.env` | `ANTHROPIC_API_KEY`, `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `openclaw:openclaw` | `0600` |
| `/opt/openclaw/.aws/credentials` | `aws_access_key_id`, `aws_secret_access_key`, `region` | `openclaw:openclaw` | `0600` |
| `/opt/openclaw/.config/gh/hosts.yml` | GitHub CLI auth (oauth_token) | `openclaw:openclaw` | `0600` |
| `/opt/openclaw/knowledge/dcf-vault/.git/config` | GitHub token embedded in remote URL | `openclaw:openclaw` | — |

### On your local machine

| Location | Contains |
|---|---|
| Shell env vars (`export ...`) | `HETZNER_TOKEN`, `TAILSCALE_KEY`, `ANTHROPIC_KEY`, `SLACK_APP_TOKEN`, `SLACK_BOT_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `~/.ssh/hetzner` / `~/.ssh/hetzner.pub` | SSH keypair for Hetzner server access |

### Easy to miss

- **dcf-vault git remote:** The GitHub token is embedded in the clone URL at `/opt/openclaw/knowledge/dcf-vault/.git/config`. If you rotate the GitHub token but forget this, `git pull` and `git push` in dcf-vault will break. Fix with:
  ```bash
  su - openclaw -c "cd /opt/openclaw/knowledge/dcf-vault && git remote set-url origin https://NEW_TOKEN@github.com/symbiorgco/dcf-setup.git"
  ```

- **`gh` CLI auth:** Stored in `/opt/openclaw/.config/gh/hosts.yml`. Re-run `echo 'NEW_TOKEN' | gh auth login --with-token` as the `openclaw` user.

---

## Safety Notes

- **Never commit tokens to git.** The `.env` file is on the server only and is not (and should never be) tracked in this repo.
- **After rotating, verify the old token is revoked** — not just replaced. An unused-but-active old token is still a risk.
- **The Hetzner token and Tailscale key shared during the initial deployment chat session should be rotated immediately.** They were transmitted in plaintext.
- **Test after every rotation.** A replaced-but-wrong token will break the service just as badly as a revoked one.
- **Keep the service `.env` file at `0600` permissions** (`chmod 600 /opt/openclaw/.openclaw/.env`). Cloud-init sets this, but verify after manual edits.
