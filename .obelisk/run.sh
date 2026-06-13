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
export OBELISK_MODE=swarm

echo "[Obelisk] Building static modules..."
yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" | while read -r name; do
    module_type=$(yq e ".modules[\"${name}\"].type // \"module\"" "$CONFIG_FILE")
    if [ "$module_type" != "static" ]; then
        continue
    fi
    git_source=$(yq e ".modules[\"${name}\"].git_source" "$CONFIG_FILE")
    build_cmd=$(yq e ".modules[\"${name}\"].build // \"\"" "$CONFIG_FILE")
    dest="$SCRIPT_DIR/static/${name}"
    if [ "$git_source" != "null" ] && [ -n "$git_source" ]; then
        if [ -d "${dest}/.git" ]; then
            echo "[Obelisk] Updating static module ${name}..."
            git -C "$dest" pull --ff-only
        else
            echo "[Obelisk] Cloning static module ${name}..."
            git clone "$git_source" "$dest"
        fi
    fi
    if [ -n "$build_cmd" ] && [ "$build_cmd" != "null" ] && [ -d "$dest" ]; then
        echo "[Obelisk] Building static module ${name}..."
        (cd "$dest" && sh -c "$build_cmd")
    fi
done

echo "[Obelisk] Generating stack override..."
sh .obelisk/scripts/generate-compose.sh

echo "[Obelisk] Generating nginx configs..."
sh .obelisk/scripts/generate-nginx.sh

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
