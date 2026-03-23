#!/usr/bin/env bash
#
# OpenClaw VPS Health Check
# Quick overview of system and OpenClaw status.
#
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║  OpenClaw VPS Status Report                  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# System info
echo "── System ────────────────────────────────────"
echo "  Hostname : $(hostname)"
echo "  OS       : $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "  Kernel   : $(uname -r)"
echo "  Uptime   : $(uptime -p)"
echo "  Load     : $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo ""

# Memory
echo "── Memory ────────────────────────────────────"
free -h | awk 'NR==2{printf "  Used: %s / %s (%.1f%%)\n", $3, $2, $3/$2*100}'
echo ""

# Disk
echo "── Disk ──────────────────────────────────────"
df -h / | awk 'NR==2{printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
echo ""

# Docker
echo "── Docker ────────────────────────────────────"
if command -v docker &>/dev/null; then
  echo "  Version : $(docker --version | awk '{print $3}' | tr -d ',')"
  echo "  Running : $(docker ps -q | wc -l | tr -d ' ') containers"
  echo ""
  docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  (cannot read docker status)"
else
  echo "  Docker not installed"
fi
echo ""

# OpenClaw
echo "── OpenClaw ──────────────────────────────────"
OC_CONTAINER="openclaw-rcen-openclaw-1"
OC_STATUS=$(docker inspect -f '{{.State.Status}}' "$OC_CONTAINER" 2>/dev/null || echo "not found")
echo "  Container : $OC_STATUS ($OC_CONTAINER)"
if [[ "$OC_STATUS" == "running" ]]; then
  OC_UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$OC_CONTAINER" 2>/dev/null)
  echo "  Started   : $OC_UPTIME"
  OC_MEM=$(docker stats "$OC_CONTAINER" --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
  echo "  Memory    : $OC_MEM"
  OC_PORT=$(docker port "$OC_CONTAINER" 2>/dev/null || echo "N/A")
  echo "  Port      : $OC_PORT"
  echo "  HTTPS     : https://openclaw-rcen.srv1502801.hstgr.cloud"
fi
echo ""

# Firewall
echo "── Firewall ──────────────────────────────────"
if command -v ufw &>/dev/null; then
  UFW_STATUS=$(ufw status | head -1)
  echo "  $UFW_STATUS"
  ufw status | grep -E "^\d|ALLOW|DENY" | while read -r line; do
    echo "  $line"
  done
else
  echo "  UFW not installed"
fi
echo ""

# fail2ban
echo "── fail2ban ──────────────────────────────────"
if command -v fail2ban-client &>/dev/null; then
  F2B_STATUS=$(systemctl is-active fail2ban 2>/dev/null || echo "inactive")
  echo "  Status  : $F2B_STATUS"
  if [[ "$F2B_STATUS" == "active" ]]; then
    BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    echo "  Banned IPs (SSH): ${BANNED:-0}"
  fi
else
  echo "  fail2ban not installed"
fi
echo ""

# Security updates
echo "── Updates ───────────────────────────────────"
SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
echo "  Pending security updates: $SECURITY_UPDATES"
echo ""

# Backups
echo "── Backups ───────────────────────────────────"
BACKUP_DIR="/opt/backups/openclaw"
if [[ -d "$BACKUP_DIR" ]]; then
  LATEST=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
  if [[ -n "$LATEST" ]]; then
    echo "  Latest : $(basename "$LATEST") ($(du -h "$LATEST" | cut -f1))"
    echo "  Count  : $(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
  else
    echo "  No backups found"
  fi
else
  echo "  Backup directory not configured"
fi
echo ""
