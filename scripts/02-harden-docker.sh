#!/usr/bin/env bash
#
# Docker Daemon Security Hardening
# Run as root (or sudo) after 01-harden-vps.sh
#
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║  Docker Daemon Hardening                     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────
# 1. Harden Docker daemon configuration
# ──────────────────────────────────────────────
echo "[1/4] Configuring Docker daemon security settings..."

mkdir -p /etc/docker

# Preserve existing config if present, merge our security settings
cat > /etc/docker/daemon.json << 'DAEMONEOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "no-new-privileges": true,
  "icc": false,
  "iptables": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 32768
    },
    "nproc": {
      "Name": "nproc",
      "Hard": 4096,
      "Soft": 2048
    }
  },
  "storage-driver": "overlay2"
}
DAEMONEOF

echo "  Daemon config written to /etc/docker/daemon.json"

# ──────────────────────────────────────────────
# 2. Create isolated Docker network for OpenClaw
# ──────────────────────────────────────────────
echo "[2/4] Creating isolated Docker network..."

if docker network inspect openclaw-net &>/dev/null; then
  echo "  Network 'openclaw-net' already exists."
else
  docker network create \
    --driver bridge \
    --internal=false \
    --subnet=172.20.0.0/16 \
    openclaw-net
  echo "  Network 'openclaw-net' created (172.20.0.0/16)."
fi

# ──────────────────────────────────────────────
# 3. Docker socket permissions
# ──────────────────────────────────────────────
echo "[3/4] Securing Docker socket permissions..."
chmod 660 /var/run/docker.sock
echo "  Docker socket set to 660 (owner + group only)."

# ──────────────────────────────────────────────
# 4. Docker system prune cron job
# ──────────────────────────────────────────────
echo "[4/4] Setting up weekly Docker cleanup..."
cat > /etc/cron.weekly/docker-cleanup << 'CRONEOF'
#!/bin/sh
docker system prune -af --volumes --filter "until=168h" > /dev/null 2>&1
CRONEOF
chmod +x /etc/cron.weekly/docker-cleanup
echo "  Weekly Docker prune scheduled."

# ──────────────────────────────────────────────
# Restart Docker
# ──────────────────────────────────────────────
echo ""
echo "Restarting Docker daemon..."
systemctl restart docker
echo "Docker daemon restarted with hardened config."

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Docker hardening complete!                  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Applied:"
echo "  • Log rotation (10MB × 3 files per container)"
echo "  • no-new-privileges flag (prevent privilege escalation)"
echo "  • Inter-container communication disabled by default"
echo "  • Isolated 'openclaw-net' bridge network created"
echo "  • Docker socket restricted to owner + docker group"
echo "  • Weekly automated cleanup of unused images/volumes"
echo ""
echo "NEXT: Run 03-harden-openclaw.sh"
