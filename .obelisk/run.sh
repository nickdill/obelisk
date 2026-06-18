#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

existing_driver=$(docker network inspect obelisk --format '{{.Driver}}' 2>/dev/null || echo "")
if [ "$existing_driver" = "bridge" ]; then
    echo "[Obelisk] Bringing down compose stack to free bridge network..."
    docker compose down 2>/dev/null || true
fi

swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "unknown")
if [ "$swarm_state" != "active" ]; then
    if [ "$swarm_state" != "inactive" ] && [ "$swarm_state" != "unknown" ]; then
        echo "[Obelisk] Swarm in bad state (${swarm_state}), leaving..."
        docker swarm leave --force 2>/dev/null || true
    fi
    echo "[Obelisk] Initializing Docker Swarm..."
    [ -f .env ] && set -a && . ./.env && set +a
    if [ -n "${OBELISK_ADVERTISE_ADDR:-}" ]; then
        LISTEN_ADDR="${OBELISK_LISTEN_ADDR:-0.0.0.0:2377}"
        docker swarm init --advertise-addr "$OBELISK_ADVERTISE_ADDR" --listen-addr "$LISTEN_ADDR"
    else
        docker swarm init
    fi
fi

[ -f .env ] && set -a && . ./.env && set +a

if [ -n "${REGISTRY_HOST:-}" ]; then
    echo "[Obelisk] Logging in to ${REGISTRY_HOST}..."
    echo "${REGISTRY_TOKEN}" | docker login "${REGISTRY_HOST}" \
        --username "${REGISTRY_USER}" --password-stdin
elif [ -n "${AWS_REGION:-}" ]; then
    echo "[Obelisk] Logging in to ECR..."
    aws ecr get-login-password --region "${AWS_REGION}" \
      | docker login --username AWS --password-stdin \
        "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

echo "[Obelisk] Generating stack config..."
OBELISK_MODE=swarm sh .obelisk/scripts/generate.sh

if [ "${OBELISK_SSL:-false}" = "true" ]; then
    echo "[Obelisk] Bootstrapping SSL certificates..."
    sh .obelisk/ssl/init-ssl.sh
fi

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

sh .obelisk/scripts/print-urls.sh
echo "[Obelisk] Running."
