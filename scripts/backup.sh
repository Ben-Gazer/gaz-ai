#!/usr/bin/env bash
#
# OpenClaw Automated Backup Script
# Backs up OpenClaw config, credentials, and Docker volumes.
#
# Usage:
#   sudo bash backup.sh              # One-time backup
#   sudo bash backup.sh --install    # Install as daily cron job
#
set -euo pipefail

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
BACKUP_DIR="/opt/backups/openclaw"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openclaw-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

# Hostinger OpenClaw paths
OPENCLAW_PROJECT="/docker/openclaw-rcen"
OPENCLAW_DATA="$OPENCLAW_PROJECT/data/.openclaw"
CONTAINER_NAME="openclaw-rcen-openclaw-1"

# ──────────────────────────────────────────────
# Install cron job
# ──────────────────────────────────────────────
if [[ "${1:-}" == "--install" ]]; then
  SCRIPT_PATH=$(realpath "$0")
  CRON_LINE="0 3 * * * $SCRIPT_PATH >> /var/log/openclaw-backup.log 2>&1"

  if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH"; then
    echo "Cron job already installed."
  else
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "Backup cron job installed: daily at 3:00 AM"
  fi
  exit 0
fi

# ──────────────────────────────────────────────
# Preflight
# ──────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root or with sudo."
  exit 1
fi

if [[ ! -d "$OPENCLAW_DATA" ]]; then
  echo "ERROR: OpenClaw data directory not found at $OPENCLAW_DATA"
  exit 1
fi

echo "[$TIMESTAMP] Starting OpenClaw backup..."
echo "  Source: $OPENCLAW_DATA"
echo "  Target: $BACKUP_PATH"

mkdir -p "$BACKUP_PATH"

# ──────────────────────────────────────────────
# 1. Backup OpenClaw data directory
# ──────────────────────────────────────────────
echo "  [1/4] Backing up OpenClaw data..."
rsync -a --exclude='logs/*' "$OPENCLAW_DATA/" "$BACKUP_PATH/data/"

# ──────────────────────────────────────────────
# 2. Backup Docker container config
# ──────────────────────────────────────────────
echo "  [2/4] Saving Docker and project configuration..."
docker inspect "$CONTAINER_NAME" > "$BACKUP_PATH/container-inspect.json" 2>/dev/null || true
cp "$OPENCLAW_PROJECT/docker-compose.yml" "$BACKUP_PATH/" 2>/dev/null || true
cp "$OPENCLAW_PROJECT/.env" "$BACKUP_PATH/env.backup" 2>/dev/null || true

# ──────────────────────────────────────────────
# 3. Backup system configs
# ──────────────────────────────────────────────
echo "  [3/4] Backing up system security configs..."
mkdir -p "$BACKUP_PATH/system"
cp /etc/ssh/sshd_config.d/hardened.conf "$BACKUP_PATH/system/" 2>/dev/null || true
cp /etc/fail2ban/jail.local "$BACKUP_PATH/system/" 2>/dev/null || true
cp /etc/docker/daemon.json "$BACKUP_PATH/system/" 2>/dev/null || true
ufw status verbose > "$BACKUP_PATH/system/ufw-rules.txt" 2>/dev/null || true
crontab -l > "$BACKUP_PATH/system/crontab.txt" 2>/dev/null || true

# ──────────────────────────────────────────────
# 4. Compress
# ──────────────────────────────────────────────
echo "  [4/4] Compressing backup..."
tar -czf "${BACKUP_PATH}.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

BACKUP_SIZE=$(du -h "${BACKUP_PATH}.tar.gz" | cut -f1)
echo "  Backup complete: ${BACKUP_PATH}.tar.gz ($BACKUP_SIZE)"

# ──────────────────────────────────────────────
# Cleanup old backups
# ──────────────────────────────────────────────
echo "  Cleaning backups older than ${RETENTION_DAYS} days..."
DELETED=$(find "$BACKUP_DIR" -name "openclaw-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "  Removed $DELETED old backup(s)."

echo "[$TIMESTAMP] Backup finished successfully."
