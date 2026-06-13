#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${CONFIG_FILE:-obelisk.yml}"

modules=$(yq e '.modules // {} | keys | .[]' "$CONFIG_FILE")

if [ -z "$modules" ]; then
    printf 'services: {}\n' > docker-compose.override.yml
    echo "[Obelisk] Generated docker-compose.override.yml"
    exit 0
fi

cat > docker-compose.override.yml << 'YAML'
services:
YAML

echo "$modules" | while read -r name; do
    module_type=$(yq e ".modules[\"${name}\"].type // \"module\"" "$CONFIG_FILE")
    image=$(yq e ".modules[\"${name}\"].image" "$CONFIG_FILE")
    git_source=$(yq e ".modules[\"${name}\"].git_source" "$CONFIG_FILE")
    port=$(yq e ".modules[\"${name}\"].port // 8080" "$CONFIG_FILE")
    replicas=$(yq e ".modules[\"${name}\"].replicas // 1" "$CONFIG_FILE")

    if [ "$module_type" = "static" ]; then
        # Static modules are served directly by nginx — no Docker service needed.
        continue
    fi

    if [ "$image" != "null" ] && [ -n "$image" ]; then
        if [ "${OBELISK_MODE:-}" = "swarm" ]; then
            cat >> docker-compose.override.yml << YAML
  ${name}:
    image: ${image}
    expose:
      - "${port}"
    environment:
      PORT: "${port}"
    networks:
      - obelisk
    deploy:
      replicas: ${replicas}
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
YAML
        else
            cat >> docker-compose.override.yml << YAML
  ${name}:
    image: ${image}
    expose:
      - "${port}"
    environment:
      PORT: "${port}"
    networks:
      - obelisk
YAML
        fi
    elif [ "$git_source" != "null" ] && [ -n "$git_source" ]; then
        if [ "${OBELISK_MODE:-}" = "swarm" ]; then
            echo "[Obelisk] warning: module '${name}' uses git_source which is not supported in Swarm mode — skipping" >&2
        else
            cat >> docker-compose.override.yml << YAML
  ${name}:
    build:
      context: ${git_source}
    expose:
      - "${port}"
    environment:
      PORT: "${port}"
    networks:
      - obelisk
YAML
        fi
    else
        echo "[Obelisk] warning: module '${name}' has no image or git_source — skipping" >&2
    fi
done

echo "[Obelisk] Generated docker-compose.override.yml"
