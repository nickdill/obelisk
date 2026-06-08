#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if [ -f megalisk.local.yml ]; then
    CONFIG_FILE=megalisk.local.yml
else
    CONFIG_FILE=megalisk.yml
fi
export CONFIG_FILE

echo "[Megalisk] Generating docker compose override..."
sh scripts/generate-compose.sh

echo "[Megalisk] Generating nginx configs..."
sh scripts/generate-nginx.sh

echo "[Megalisk] Starting services..."
docker compose up -d

# Trigger immediate nginx reload (container also reloads every 6h)
docker exec nginx-webserver nginx -s reload 2>/dev/null || true

echo "[Megalisk] Running."
