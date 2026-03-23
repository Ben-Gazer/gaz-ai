#!/usr/bin/env bash
#
# Merge security overlay into openclaw.json
# Run as root (or sudo) after 03-harden-openclaw.sh
#
# This uses Python (available on Ubuntu 24.04) to do a proper
# deep merge of the security overlay into the existing config.
#
set -euo pipefail

OPENCLAW_DATA="/docker/openclaw-rcen/data/.openclaw"
CONFIG="$OPENCLAW_DATA/openclaw.json"
OVERLAY="$OPENCLAW_DATA/security-overlay.json"
BACKUP="$OPENCLAW_DATA/openclaw.json.pre-hardening"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found."
  exit 1
fi

if [[ ! -f "$OVERLAY" ]]; then
  echo "ERROR: $OVERLAY not found. Run 03-harden-openclaw.sh first."
  exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  Merging Security Settings into OpenClaw     ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Back up current config
cp "$CONFIG" "$BACKUP"
echo "Backed up current config to:"
echo "  $BACKUP"
echo ""

# Deep merge using Python
python3 << PYEOF
import json, copy, sys

def deep_merge(base, overlay):
    """Recursively merge overlay into base. Overlay wins on conflicts."""
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result

with open("$CONFIG", "r") as f:
    config = json.load(f)

with open("$OVERLAY", "r") as f:
    overlay = json.load(f)

merged = deep_merge(config, overlay)

with open("$CONFIG", "w") as f:
    json.dump(merged, f, indent=2)

added_keys = [k for k in overlay.keys() if k not in config]
updated_keys = [k for k in overlay.keys() if k in config]

print("Merge complete!")
print()
if added_keys:
    print(f"  Added sections:   {', '.join(added_keys)}")
if updated_keys:
    print(f"  Updated sections: {', '.join(updated_keys)}")
print()
PYEOF

echo "Changes applied to: $CONFIG"
echo ""
echo "Review the merged config:"
echo "  sudo cat $CONFIG | python3 -m json.tool"
echo ""
echo "If something looks wrong, restore the backup:"
echo "  sudo cp $BACKUP $CONFIG"
echo ""
echo "Then restart OpenClaw:"
echo "  sudo docker restart openclaw-rcen-openclaw-1"
