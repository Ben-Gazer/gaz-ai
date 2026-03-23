# OpenClaw VPS — Hostinger Ubuntu 24.04

Production security, configuration, and agent setup for a Hostinger-hosted OpenClaw instance.

Based on the [OpenClaw Runbook](https://github.com/digitalknk/openclaw-runbook) patterns.

## Architecture

```
Internet ──▶ Traefik (ports 80/443, auto HTTPS via Let's Encrypt)
                │
                ▼
         OpenClaw container (127.0.0.1:54061)
            │
            ├── OpenRouter (GPT-5 Mini, Sonnet, Opus, etc.)
            ├── Telegram (@gazerrobot)
            ├── Gmail (OAuth2)
            └── WhatsApp (ready to pair)
```

## Key Paths

| Path | Description |
|------|-------------|
| `/docker/openclaw-rcen/` | Project root |
| `/docker/openclaw-rcen/.env` | API keys and tokens |
| `/docker/openclaw-rcen/data/.openclaw/openclaw.json` | Main config |
| `/docker/openclaw-rcen/data/.openclaw/agents/main/agent/auth-profiles.json` | Provider auth |
| `/docker/openclaw-rcen/docker-compose.yml` | Hostinger compose file |
| `/docker/traefik/` | Traefik reverse proxy |
| `/opt/backups/openclaw/` | Daily backups |

Container: `openclaw-rcen-openclaw-1`
HTTPS: `https://openclaw-rcen.srv1502801.hstgr.cloud`

## Agent Configuration

### Model Strategy (Runbook Pattern)

Cheap model as coordinator, expensive models on-demand:

| Role | Model | Route | Cost |
|------|-------|-------|------|
| Default | GPT-5 Mini | OpenRouter | ~$0.001/msg |
| Fallback 1 | Gemini 2.5 Flash | OpenRouter | ~$0.001/msg |
| Fallback 2 | GPT-5 Nano | OpenRouter | ~$0.0001/msg |
| Heartbeat | GPT-5 Nano | OpenRouter (every 2h) | ~$0.005/day |
| On-demand | GPT-5.4 | `/model GPT 5.4` | ~$0.03/msg |
| On-demand | Claude Sonnet 4.6 | `/model Sonnet` | ~$0.02/msg |
| On-demand | Claude Opus 4.6 | `/model Opus` | ~$0.10/msg |

### Switching Models (Chat Commands)

```
/model Sonnet          → Claude Sonnet 4.6 (best for conversation)
/model GPT 5.4         → GPT-5.4
/model Opus            → Claude Opus 4.6 (complex reasoning)
/model GPT Mini        → Back to cheap default
/model Flash           → Gemini 2.5 Flash
/model Haiku           → Claude Haiku 4.5 (fast + cheap)
```

### Cost Controls

- Concurrency: 4 main / 8 subagents max
- Heartbeat: cheapest model, every 2h
- Context pruning: 6h TTL, keep last 3 assistant messages
- Compaction: auto-flush to memory at 40k tokens
- Memory search: OpenAI text-embedding-3-small
- Log redaction: sensitive data redacted from tool output

**Expected cost:** $5-10/month API via OpenRouter for moderate use.

### Channels

| Channel | Status | DM Policy |
|---------|--------|-----------|
| Web UI | Active | Token auth |
| Telegram | Active (@gazerrobot) | Allowlist (ID: 8085007771) |
| Gmail | Active (OAuth2) | Via web UI config |
| WhatsApp | Ready to pair | Pairing |

### Monday.com MCP

Direct integration with Monday.com via the hosted MCP at [mcp.monday.com](https://mcp.monday.com/mcp). Uses a personal API token (no OAuth). [Configuration docs](https://github.com/mondaycom/mcp).

**Setup:**

1. Get your Monday API token: monday.com → Profile → Developers → API token → Show
2. Add to `.env`: `MONDAY_API_TOKEN=your_token`
3. Ensure `MONDAY_API_TOKEN` is passed to the OpenClaw container (add to docker-compose `environment` if needed)
4. Run the setup script:
   ```bash
   sudo bash /root/openclaw-setup/scripts/06-add-monday-mcp.sh
   ```
5. Restart: `sudo docker restart openclaw-rcen-openclaw-1`
6. Verify: `sudo docker exec openclaw-rcen-openclaw-1 openclaw mcp list`

The agent can then create items, update boards, change statuses, and manage Monday.com data via natural language.

## Security Posture

### OS Layer
- SSH: key-only, port 2222, no root, no passwords
- UFW: only ports 2222, 80, 443
- fail2ban: 24h ban after 3 SSH failures
- Automatic daily security updates
- Kernel hardening (SYN flood, IP spoofing, ASLR)

### Docker Layer
- no-new-privileges, log rotation (10MB × 3)
- Socket restricted to owner + docker group
- Weekly cleanup cron

### OpenClaw Layer
- `tools.deny`: exec blocked
- `tools.elevated`: disabled
- `commands.bash`: disabled
- Telegram: allowlist mode (your ID only)
- Gateway auth: rate limited (5 attempts/60s, 5min lockout)
- Logging: `redactSensitive: "tools"`

### Infrastructure
- HTTPS via Traefik + Let's Encrypt (auto-renewing)
- Daily backups at 3 AM (30-day retention)
- Config file permissions: 600

## Useful Commands

```bash
# Health check
sudo bash /root/openclaw-setup/scripts/status.sh

# OpenClaw logs
sudo docker logs openclaw-rcen-openclaw-1 --tail 50

# Manual backup
sudo bash /root/openclaw-setup/scripts/backup.sh

# Banned IPs
sudo fail2ban-client status sshd

# Update OpenClaw
cd /docker/openclaw-rcen && sudo docker compose pull && sudo docker compose up -d

# Restart OpenClaw
sudo docker restart openclaw-rcen-openclaw-1

# Edit config
sudo nano /docker/openclaw-rcen/data/.openclaw/openclaw.json

# Check config validity (inside container)
sudo docker exec openclaw-rcen-openclaw-1 openclaw doctor --fix

# Restart containers after crash
cd /docker/traefik && sudo docker compose up -d
cd /docker/openclaw-rcen && sudo docker compose up -d
```

## Billing

| Provider | Dashboard | What it's used for |
|----------|-----------|-------------------|
| **OpenRouter** | [openrouter.ai/settings/credits](https://openrouter.ai/settings/credits) | All model API calls |
| OpenAI | [platform.openai.com/usage](https://platform.openai.com/usage) | Memory search embeddings only |
| Anthropic | [console.anthropic.com](https://console.anthropic.com/settings/billing) | Not active (no credits) |
| Gemini | [aistudio.google.com](https://aistudio.google.com) | Free tier (rate limited) |

## Troubleshooting

**Locked out of SSH:**
Hostinger hPanel → VPS → Browser console.

**Containers gone:**
```bash
cd /docker/traefik && sudo docker compose up -d
cd /docker/openclaw-rcen && sudo docker compose up -d
```

**Config validation error:**
```bash
sudo docker exec openclaw-rcen-openclaw-1 openclaw doctor --fix
```

**API rate limit:**
Switch to a different model via `/model` or check OpenRouter credits.

**fail2ban banned your IP:**
From Hostinger console: `sudo fail2ban-client set sshd unbanip YOUR_IP`

**oxylabs plugin error:**
The Hostinger image auto-installs this plugin. Keep it in `plugins.allow` but set `enabled: false`.

## References

- [OpenClaw Runbook](https://github.com/digitalknk/openclaw-runbook) — Practical guide for stable, cost-effective OpenClaw operation
- [OpenClaw Docs](https://docs.openclaw.ai/) — Official documentation
- [Config Reference](https://docs.openclaw.ai/gateway/configuration-reference) — All valid config keys
- [Hostinger OpenClaw Guide](https://www.hostinger.com/support/how-to-install-openclaw-on-hostinger-vps/) — Hostinger-specific setup
