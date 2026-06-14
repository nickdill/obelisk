#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

existing_driver=$(docker network inspect obelisk --format '{{.Driver}}' 2>/dev/null || echo "")

if [ "$existing_driver" = "overlay" ]; then
    echo "[Obelisk] Removing swarm stack..."
    docker stack rm obelisk
    retries=0
    while docker network inspect obelisk >/dev/null 2>&1; do
        retries=$((retries + 1))
        [ $retries -gt 20 ] && { docker network rm obelisk 2>/dev/null || true; break; }
        sleep 1
    done
elif [ "$existing_driver" = "bridge" ]; then
    echo "[Obelisk] Stopping compose stack..."
    docker compose down
else
    echo "[Obelisk] Nothing running."
fi

echo "[Obelisk] Stopped."
