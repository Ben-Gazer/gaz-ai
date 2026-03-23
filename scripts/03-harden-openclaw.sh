#!/usr/bin/env bash
#
# OpenClaw Application-Level Security Hardening
# Run as root (or sudo) after 02-harden-docker.sh
#
# This script configures OpenClaw's own security settings:
#   - Sandbox mode enforcement
#   - DM policy restrictions
#   - Blocked dangerous commands
#   - Audit logging
#   - Credential file permissions
#
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║  OpenClaw Application Hardening              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────
# Detect OpenClaw data directory
# ──────────────────────────────────────────────
# Hostinger template typically mounts data at one of these locations
OPENCLAW_DATA=""

# Find the OpenClaw container (name varies by deployment method)
OC_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || echo "")
DOCKER_MOUNT=""
if [[ -n "$OC_CONTAINER" ]]; then
  DOCKER_MOUNT=$(docker inspect "$OC_CONTAINER" 2>/dev/null | grep -oP '"Source":\s*"\K[^"]+' | head -1 || echo "")
fi

CANDIDATES=(
  "/docker/openclaw-rcen/data/.openclaw"
  "/docker/openclaw/data/.openclaw"
)

# Prepend Docker-detected mount if found
if [[ -n "$DOCKER_MOUNT" ]]; then
  CANDIDATES=("$DOCKER_MOUNT/.openclaw" "$DOCKER_MOUNT" "${CANDIDATES[@]}")
fi

# Also check standard paths
CANDIDATES+=(
  "/home/openclaw/.openclaw"
  "/root/.openclaw"
  "/opt/openclaw"
)

for dir in "${CANDIDATES[@]}"; do
  if [[ -d "$dir" ]]; then
    OPENCLAW_DATA="$dir"
    break
  fi
done

if [[ -z "$OPENCLAW_DATA" ]]; then
  echo "ERROR: Could not find OpenClaw data directory."
  echo "       Checked: ${CANDIDATES[*]}"
  echo "       Try: docker inspect openclaw | grep -A5 Mounts"
  exit 1
fi

echo "Found OpenClaw data at: $OPENCLAW_DATA"
CONFIG_FILE="$OPENCLAW_DATA/openclaw.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "WARNING: $CONFIG_FILE not found. Creating security config overlay."
fi

# ──────────────────────────────────────────────
# 1. Create/merge security settings
# ──────────────────────────────────────────────
echo ""
echo "[1/4] Applying OpenClaw security configuration..."

# Write security overlay that will be merged into the config
SECURITY_OVERLAY="$OPENCLAW_DATA/security-overlay.json"
cat > "$SECURITY_OVERLAY" << 'SECEOF'
{
  "sandbox": {
    "enabled": true,
    "permissions": {
      "network": false,
      "filesystem": "read-only",
      "shell": false,
      "docker": false
    },
    "timeoutMs": 30000,
    "memoryLimitMb": 512
  },
  "security": {
    "dm": {
      "policy": "explicit-allow",
      "allowedUsers": [],
      "blockUnknownSenders": true
    },
    "blockedCommands": [
      "rm -rf /",
      "rm -rf /*",
      "mkfs",
      "dd if=",
      ":(){:|:&};:",
      "chmod -R 777",
      "git push --force",
      "git push -f",
      "curl | sh",
      "curl | bash",
      "wget | sh",
      "wget | bash",
      "shutdown",
      "reboot",
      "halt",
      "poweroff",
      "init 0",
      "init 6"
    ],
    "blockedPatterns": [
      "\\|\\s*(bash|sh|zsh)",
      "eval\\s*\\(",
      "exec\\s*\\(",
      ">\\s*/etc/",
      ">\\s*/dev/"
    ],
    "rateLimiting": {
      "enabled": true,
      "maxRequestsPerMinute": 30,
      "maxRequestsPerHour": 300
    },
    "promptInjection": {
      "wrapUntrustedContent": true,
      "blockDirectExecution": true
    }
  },
  "logging": {
    "level": "info",
    "auditEnabled": true,
    "auditEvents": [
      "command.execute",
      "tool.invoke",
      "channel.message",
      "auth.login",
      "auth.fail",
      "config.change",
      "skill.install",
      "skill.execute"
    ],
    "logFile": "logs/openclaw-audit.log",
    "rotateSize": "50M",
    "rotateKeep": 10
  }
}
SECEOF

echo "  Security overlay written to $SECURITY_OVERLAY"
echo ""
echo "  To apply, merge into your openclaw.json using one of:"
echo "    a) Manually copy the relevant sections into openclaw.json"
echo "    b) Use the OpenClaw CLI: openclaw config merge $SECURITY_OVERLAY"
echo ""

# ──────────────────────────────────────────────
# 2. Lock down file permissions
# ──────────────────────────────────────────────
echo "[2/4] Securing file permissions..."

# Config files should be readable only by the owner
find "$OPENCLAW_DATA" -name "*.json" -exec chmod 600 {} \;
find "$OPENCLAW_DATA" -name "*.env" -exec chmod 600 {} \;
find "$OPENCLAW_DATA" -name "*.key" -exec chmod 600 {} \;
find "$OPENCLAW_DATA" -name "*.pem" -exec chmod 600 {} \;

# Credentials directory
if [[ -d "$OPENCLAW_DATA/credentials" ]]; then
  chmod 700 "$OPENCLAW_DATA/credentials"
  find "$OPENCLAW_DATA/credentials" -type f -exec chmod 600 {} \;
  echo "  Credentials directory locked to owner-only."
fi

echo "  Config and credential files set to 600 (owner read/write only)."

# ──────────────────────────────────────────────
# 3. Set up audit log directory
# ──────────────────────────────────────────────
echo "[3/4] Setting up audit logging..."
mkdir -p "$OPENCLAW_DATA/logs"
touch "$OPENCLAW_DATA/logs/openclaw-audit.log"
chmod 700 "$OPENCLAW_DATA/logs"
chmod 600 "$OPENCLAW_DATA/logs/openclaw-audit.log"
echo "  Audit log directory created at $OPENCLAW_DATA/logs/"

# ──────────────────────────────────────────────
# 4. Create logrotate config for OpenClaw logs
# ──────────────────────────────────────────────
echo "[4/4] Configuring log rotation..."
cat > /etc/logrotate.d/openclaw << LREOF
$OPENCLAW_DATA/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 600 root root
    copytruncate
}
LREOF
echo "  Log rotation configured (daily, keep 14 days, compressed)."

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  OpenClaw hardening complete!                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Applied:"
echo "  • Security overlay created (sandbox, DM policy, blocked cmds, logging)"
echo "  • Config & credential files locked to owner-only (600)"
echo "  • Audit logging directory created"
echo "  • Log rotation configured (14-day retention)"
echo ""
echo "IMPORTANT — Manual steps required:"
echo ""
echo "  1. Edit $CONFIG_FILE and add your allowed DM users:"
echo '     "dm": { "allowedUsers": ["your-whatsapp-id", "your-telegram-id"] }'
echo ""
echo "  2. Review and merge the security overlay:"
echo "     $SECURITY_OVERLAY"
echo ""
echo "  3. Restart the OpenClaw container:"
echo "     docker restart ${OC_CONTAINER:-openclaw}"
echo ""
echo "  4. Verify sandbox mode is active in the OpenClaw web UI"
