#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
else
    CONFIG_FILE=obelisk.yml
fi
export CONFIG_FILE

echo "[Obelisk] Generating docker-compose override..."
sh .obelisk/scripts/generate-compose.sh

echo "[Obelisk] Generating nginx configs..."
sh .obelisk/scripts/generate-nginx.sh

echo "[Obelisk] Starting services (dev mode)..."
docker compose up
