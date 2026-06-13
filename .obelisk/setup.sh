#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# Install yq if not present
if ! command -v yq > /dev/null 2>&1; then
    echo "[Obelisk] Installing yq..."
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod +x /usr/local/bin/yq
fi

# Load environment
[ -f .env ] && . ./.env

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
else
    CONFIG_FILE=obelisk.yml
fi
export CONFIG_FILE

# Initialize Docker Swarm (idempotent)
if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q 'active'; then
    echo "[Obelisk] Initializing Docker Swarm..."
    docker swarm init
else
    echo "[Obelisk] Docker Swarm already active."
fi

echo "[Obelisk] Setup complete."
