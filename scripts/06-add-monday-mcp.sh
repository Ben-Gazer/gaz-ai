#!/usr/bin/env bash
#
# Add Monday.com MCP server to OpenClaw config
#
# Uses the hosted MCP at https://mcp.monday.com/mcp (no local npx required).
# Docs: https://github.com/mondaycom/mcp
#
# Prerequisites:
#   1. Get your Monday.com API token:
#      - monday.com → Profile (top right) → Developers → API token → Show
#      - Or: Administration → Connections → Personal API token
#   2. Add to .env: MONDAY_API_TOKEN=your_token_here
#   3. Ensure docker-compose passes MONDAY_API_TOKEN to the container
#
# Usage:
#   sudo MONDAY_API_TOKEN=xxx bash scripts/06-add-monday-mcp.sh
#   # or export MONDAY_API_TOKEN first, then run
#
set -euo pipefail

OPENCLAW_DATA="${OPENCLAW_DATA:-/docker/openclaw-rcen/data/.openclaw}"
CONFIG="$OPENCLAW_DATA/openclaw.json"
BACKUP="$OPENCLAW_DATA/openclaw.json.pre-monday-mcp"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found."
  exit 1
fi

USE_ENV=false
if [[ -n "${MONDAY_API_TOKEN:-}" ]]; then
  USE_ENV=true
  echo "Using MONDAY_API_TOKEN from environment (recommended)"
elif [[ -f "${OPENCLAW_DATA%/openclaw.json}/../.env" ]] || [[ -f "/docker/openclaw-rcen/.env" ]]; then
  # Try to source .env for token
  for envfile in "/docker/openclaw-rcen/.env" "$(dirname "$CONFIG")/../.env" 2>/dev/null; do
    if [[ -f "$envfile" ]] && grep -q MONDAY_API_TOKEN "$envfile" 2>/dev/null; then
      set -a
      source "$envfile" 2>/dev/null || true
      set +a
      if [[ -n "${MONDAY_API_TOKEN:-}" ]]; then
        USE_ENV=true
        echo "Using MONDAY_API_TOKEN from $envfile"
        break
      fi
    fi
  done
fi

if [[ "$USE_ENV" != "true" ]]; then
  echo "ERROR: MONDAY_API_TOKEN not set."
  echo "  Get token: monday.com → Profile → Developers → API token"
  echo "  Add to .env: MONDAY_API_TOKEN=your_token"
  echo "  Or run: MONDAY_API_TOKEN=your_token $0"
  exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  Adding Monday.com MCP to OpenClaw            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

cp "$CONFIG" "$BACKUP"
echo "Backed up config to: $BACKUP"
echo ""

export CONFIG_PATH="$CONFIG"
export USE_ENV="$USE_ENV"
export MONDAY_API_TOKEN
python3 << 'PYEOF'
import json
import os

config_path = os.environ["CONFIG_PATH"]
use_env = os.environ.get("USE_ENV") == "true"
token = os.environ.get("MONDAY_API_TOKEN", "")

with open(config_path, "r") as f:
    config = json.load(f)

if "mcpServers" not in config:
    config["mcpServers"] = {}

if use_env:
    config["mcpServers"]["monday-api-mcp"] = {
        "url": "https://mcp.monday.com/mcp",
        "headers": {
            "MONDAY_TOKEN": "${MONDAY_API_TOKEN}"
        }
    }
    print("Added mcpServers.monday-api-mcp (hosted: mcp.monday.com, token from env)")
else:
    config["mcpServers"]["monday-api-mcp"] = {
        "url": "https://mcp.monday.com/mcp",
        "headers": {
            "MONDAY_TOKEN": token
        }
    }
    print("Added mcpServers.monday-api-mcp (hosted: mcp.monday.com, token embedded)")

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

echo ""
echo "Next steps:"
echo "  1. Add MONDAY_API_TOKEN to /docker/openclaw-rcen/.env"
echo "  2. Add MONDAY_API_TOKEN to docker-compose env (if not already passed)"
echo "  3. Restart: sudo docker restart openclaw-rcen-openclaw-1"
echo "  4. Verify: sudo docker exec openclaw-rcen-openclaw-1 openclaw mcp list"
echo ""
