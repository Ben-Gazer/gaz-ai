#!/usr/bin/env bash
# 07-setup-integrations.sh
# Configure Himalaya email, Composio plugin, and weekly time tracking cron job
# Run on the VPS as root (or via sudo)
set -euo pipefail

CONTAINER="openclaw-rcen-openclaw-1"
DATA_DIR="/docker/openclaw-rcen/data"

echo "=== 1. Himalaya email config ==="
docker exec "$CONTAINER" mkdir -p /data/.config/himalaya

# Write config (password file must be created separately — see note below)
docker cp "$(dirname "$0")/../openclaw/himalaya-config.toml" \
  "$CONTAINER:/data/.config/himalaya/config.toml"

echo "  himalaya config deployed"
echo "  NOTE: create the app-password file manually:"
echo "    docker exec $CONTAINER bash -c 'echo -n YOUR_APP_PASSWORD > /data/.config/himalaya/.gaz-passwd && chmod 600 /data/.config/himalaya/.gaz-passwd'"

echo ""
echo "=== 2. Fix extension ownership (also handled by docker-compose entrypoint) ==="
docker exec "$CONTAINER" chown -R root:root /data/.openclaw/extensions/
echo "  done"

echo ""
echo "=== 3. Enable Composio plugin ==="
docker exec "$CONTAINER" openclaw plugins enable composio 2>&1 | grep -E 'Enabled|error' || true
echo "  Composio consumer key must already be set in openclaw.json:"
echo "    plugins.entries.composio.config.consumerKey"

echo ""
echo "=== 4. Weekly time tracking cron job ==="
echo "  Cron job is stored in /data/.openclaw/cron/jobs.json"
echo "  Schedule: Every Monday 10:00 Europe/London"
echo "  Model: openrouter/openai/gpt-4o"
echo "  Recipient: ben@gazer.agency"
echo "  To trigger manually:"
echo "    docker exec $CONTAINER openclaw cron run dd770ea7-e522-4b62-95d6-43cbf32929e4"

echo ""
echo "=== Done ==="
