# gaz-ai — OpenClaw VPS

Claude Code is part of this stack. Read this before starting any session.

## Stack

| Component | Role |
|-----------|------|
| **OpenClaw** | Always-on agency AI on Hostinger VPS — handles Telegram, Gmail, WhatsApp, Monday.com |
| **Claude Code** | Interactive dev/config sessions (you are here) |
| **gaz-memory** | Shared memory vault — `github.com/gazer-tech/gaz-memory` |

## Connect

```bash
ssh openclaw-vps          # openclaw@187.77.130.204:22
```

## Key Paths on VPS

| Path | Description |
|------|-------------|
| `/docker/openclaw-rcen/` | Project root |
| `/docker/openclaw-rcen/.env` | API keys |
| `/docker/openclaw-rcen/data/.openclaw/openclaw.json` | Main config |
| `/docker/openclaw-rcen/data/.openclaw/memory/` | gaz-memory git repo |
| `/root/openclaw-setup/scripts/` | These scripts (on VPS) |

## Common Commands

```bash
# Health
sudo bash /root/openclaw-setup/scripts/status.sh

# Logs
sudo docker logs openclaw-rcen-openclaw-1 --tail 50

# Restart
sudo docker restart openclaw-rcen-openclaw-1

# Edit config
sudo nano /docker/openclaw-rcen/data/.openclaw/openclaw.json

# Validate
sudo docker exec openclaw-rcen-openclaw-1 openclaw doctor

# Memory search
sudo -i qmd query "your query"
```

## Memory Architecture

- OpenClaw writes `memory/YYYY-MM-DD.md` via compaction (at 40k tokens)
- Gemini `gemini-embedding-001` → `main.sqlite` (automatic context injection)
- QMD hybrid search (BM25 + vector + reranking) on `localhost:8181`, proxied to `:8182`
- Git auto-sync: cron every 10min → `memory-sync.sh` → `gazer-tech/gaz-memory`

## Services

```bash
systemctl status qmd-mcp      # QMD MCP server
systemctl status qmd-proxy    # socat proxy (docker → QMD)
crontab -l                    # cron jobs
```

## Firewall (iptables — no UFW)

Open ports: 22, 80, 443. Docker bridges allowed to 8181/8182 (QMD).

```bash
iptables -L INPUT -n --line-numbers
iptables-save > /etc/iptables/rules.v4   # persist changes
```

## Email (Himalaya)

OpenClaw sends email via `himalaya` CLI using `gaz@gazer.agency` (Google Workspace).

| Path | Description |
|------|-------------|
| `/data/.config/himalaya/config.toml` | Himalaya IMAP/SMTP config |
| `/data/.config/himalaya/.gaz-passwd` | App password (chmod 600, not in git) |

```bash
# Test connection
sudo docker exec openclaw-rcen-openclaw-1 himalaya folder list

# Send test email
sudo docker exec openclaw-rcen-openclaw-1 himalaya message send --account gazer
```

## Composio

Composio plugin provides 1000+ third-party tool integrations to the agent.

- Consumer key stored in `openclaw.json` → `plugins.entries.composio.config.consumerKey`
- The `docker-compose.yml` entrypoint runs `chown -R root:root /data/.openclaw/extensions` on every start to satisfy OpenClaw's plugin ownership security check
- Connect new apps at **dashboard.composio.dev**

## Cron Jobs

| Job | Schedule | Description |
|-----|----------|-------------|
| Weekly Time Tracking Report | Mon 10:00 Europe/London | Queries ops.gazer.agency Metabase API, emails report to ben@gazer.agency |

```bash
# List jobs
sudo docker exec openclaw-rcen-openclaw-1 openclaw cron list

# Trigger manually
sudo docker exec openclaw-rcen-openclaw-1 openclaw cron run dd770ea7-e522-4b62-95d6-43cbf32929e4

# View run history
sudo docker exec openclaw-rcen-openclaw-1 openclaw cron runs --id dd770ea7-e522-4b62-95d6-43cbf32929e4
```

## Repo Layout

```
gaz-ai/
├── CLAUDE.md                  ← you are here
├── README.md                  ← human overview
├── docker-compose.hardened.yml
├── nginx/
├── openclaw/
│   ├── docker-compose.yml     ← live compose config (with entrypoint fix)
│   ├── himalaya-config.toml   ← email client config template
│   └── cron-jobs.json         ← cron job definitions
└── scripts/
    ├── 01-harden-vps.sh
    ├── 02-harden-docker.sh
    ├── 03-harden-openclaw.sh
    ├── 04-merge-security.sh
    ├── 05-apply-valid-security.sh
    ├── 06-add-monday-mcp.sh
    ├── 07-setup-integrations.sh
    ├── backup.sh
    └── status.sh
```
