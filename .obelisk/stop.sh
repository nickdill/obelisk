#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

stopped=false

# Swarm stack? (docker stack ls is authoritative — don't guess from network names,
# since the stack's overlay network is named obelisk_obelisk, not obelisk)
if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx obelisk; then
    echo "[Obelisk] Removing swarm stack..."
    docker stack rm obelisk
    retries=0
    while docker network inspect obelisk_obelisk >/dev/null 2>&1; do
        retries=$((retries + 1))
        [ $retries -gt 20 ] && { docker network rm obelisk_obelisk 2>/dev/null || true; break; }
        sleep 1
    done
    stopped=true
fi

# Compose stack (local dev)?
if [ -n "$(docker compose ps -q 2>/dev/null)" ]; then
    echo "[Obelisk] Stopping compose stack..."
    docker compose down
    stopped=true
fi

if [ "$stopped" = true ]; then
    echo "[Obelisk] Stopped."
else
    echo "[Obelisk] Nothing running."
fi
