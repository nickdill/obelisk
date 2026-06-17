#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

[ -f .env ] && set -a && . ./.env && set +a
export OBELISK_ENV="${OBELISK_ENV:-local}"
export OBELISK_SSL=false
OBELISK_PROFILE="${OBELISK_PROFILE:-local}"

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

sh .obelisk/scripts/print-urls.sh

echo "[Obelisk] Starting services (dev mode, profile: ${OBELISK_PROFILE})..."
docker compose --profile "$OBELISK_PROFILE" up
