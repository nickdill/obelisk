#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

existing_driver=$(docker network inspect obelisk --format '{{.Driver}}' 2>/dev/null || echo "")
if [ "$existing_driver" = "bridge" ]; then
    echo "[Obelisk] Bringing down compose stack to free bridge network..."
    docker compose down 2>/dev/null || true
fi

echo "[Obelisk] Generating stack config..."
OBELISK_MODE=swarm sh .obelisk/scripts/generate.sh

echo "[Obelisk] Deploying stack..."
docker stack deploy --with-registry-auth \
    -c docker-compose.yml \
    -c docker-compose.override.yml \
    -c docker-compose.swarm.yml \
    obelisk

echo "[Obelisk] Reloading nginx..."
NGINX_CONTAINER=$(docker ps --filter "name=obelisk_nginx-webserver" --format "{{.ID}}" | head -1)
if [ -n "$NGINX_CONTAINER" ]; then
    docker exec "$NGINX_CONTAINER" nginx -s reload 2>/dev/null || true
fi

echo "[Obelisk] Running."
