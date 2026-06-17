#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

export OBELISK_SSL=false

existing_driver=$(docker network inspect obelisk --format '{{.Driver}}' 2>/dev/null || echo "")
if [ "$existing_driver" = "overlay" ]; then
    echo "[Obelisk] Removing stale swarm stack and overlay network..."
    docker stack rm obelisk 2>/dev/null || true
    retries=0
    while docker network inspect obelisk >/dev/null 2>&1; do
        retries=$((retries + 1))
        [ $retries -gt 20 ] && { docker network rm obelisk 2>/dev/null || true; break; }
        sleep 1
    done
fi

sh .obelisk/scripts/generate.sh

echo "[Obelisk] Starting services (dev mode)..."
docker compose up
