#!/bin/sh
# TBD considering separate run scripts for local vs prod
# Dont want to gen anytingin prod, just pull prebuilt images/nginx conf
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

if [ -f megalisk.local.yml ]; then
    CONFIG_FILE=megalisk.local.yml
else
    CONFIG_FILE=megalisk.yml
fi
export CONFIG_FILE

if [ ! -f nginx/data/certs/localhost.crt ]; then
    echo "[Megalisk] Generating self-signed SSL certificate..."
    mkdir -p nginx/data/certs
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout nginx/data/certs/localhost.key \
        -out nginx/data/certs/localhost.crt \
        -subj "/CN=localhost" -quiet
fi

echo "[Megalisk] Generating docker compose override..."
sh .megalisk/scripts/generate-compose.sh

echo "[Megalisk] Generating nginx configs..."
sh .megalisk/scripts/generate-nginx.sh

echo "[Megalisk] Starting services..."
docker compose up -d

# Trigger immediate nginx reload (container also reloads every 6h)
docker exec nginx-webserver nginx -s reload 2>/dev/null || true

echo "[Megalisk] Running."
