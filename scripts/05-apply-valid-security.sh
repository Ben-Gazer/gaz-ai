#!/usr/bin/env bash
#
# Apply OpenClaw security settings using VALID config schema keys.
# Run after restoring openclaw.json from the pre-hardening backup.
#
set -euo pipefail

CONFIG="/docker/openclaw-rcen/data/.openclaw/openclaw.json"
BACKUP="/docker/openclaw-rcen/data/.openclaw/openclaw.json.pre-security-v2"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found."
  exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  OpenClaw Security Config (Schema-Valid)     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

cp "$CONFIG" "$BACKUP"
echo "Backed up to: $BACKUP"
echo ""

python3 << 'PYEOF'
import json, copy

CONFIG = "/docker/openclaw-rcen/data/.openclaw/openclaw.json"

def deep_merge(base, overlay):
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result

with open(CONFIG, "r") as f:
    config = json.load(f)

# All keys below are verified against the official OpenClaw config schema:
# https://docs.openclaw.ai/gateway/configuration-reference

security_settings = {
    # Sandbox: run tool execution in isolated Docker containers
    "agents": {
        "defaults": {
            "sandbox": {
                "mode": "non-main",       # off | non-main | all
                "backend": "docker",
                "scope": "agent",
                "workspaceAccess": "none",
                "docker": {
                    "readOnlyRoot": True,
                    "network": "none",
                    "memoryMb": 512,
                    "cpus": 1.0,
                    "pidsLimit": 256,
                    "tmpfs": ["/tmp", "/var/tmp", "/run"]
                }
            }
        }
    },

    # DM policies: restrict who can message the bot per channel
    "channels": {
        "defaults": {
            "groupPolicy": "allowlist"
        },
        "telegram": {
            "dmPolicy": "pairing",
            "configWrites": False
        }
    },

    # Tool restrictions
    "tools": {
        "deny": [
            "exec"
        ],
        "elevated": {
            "enabled": False
        },
        "exec": {
            "allowBash": False
        },
        "web": {
            "search": {
                "enabled": False
            },
            "fetch": {
                "enabled": False
            }
        }
    },

    # Disable host shell via commands
    "commands": {
        "bash": False
    },

    # Logging with a stable file path
    "logging": {
        "level": "info",
        "file": "/data/.openclaw/logs/openclaw.log"
    },

    # Gateway auth hardening
    "gateway": {
        "auth": {
            "rateLimit": {
                "maxAttempts": 5,
                "windowMs": 60000,
                "lockoutMs": 300000,
                "exemptLoopback": True
            }
        }
    }
}

merged = deep_merge(config, security_settings)

with open(CONFIG, "w") as f:
    json.dump(merged, f, indent=2)

print("Merged settings:")
print("  agents.defaults.sandbox  → mode: non-main, docker, network: none")
print("  channels.defaults        → groupPolicy: allowlist")
print("  channels.telegram        → dmPolicy: pairing, configWrites: false")
print("  tools.deny               → [exec]")
print("  tools.elevated           → disabled")
print("  tools.exec               → allowBash: false")
print("  tools.web                → search/fetch disabled")
print("  commands.bash            → disabled")
print("  logging                  → level: info, file: /data/.openclaw/logs/openclaw.log")
print("  gateway.auth.rateLimit   → 5 attempts / 60s, 5min lockout")
PYEOF

echo ""
echo "Config updated: $CONFIG"
echo ""
echo "Validate with:   sudo docker exec openclaw-rcen-openclaw-1 openclaw doctor 2>&1 | head -20"
echo "Then restart:    sudo docker restart openclaw-rcen-openclaw-1"
echo "Restore backup:  sudo cp $BACKUP $CONFIG"
