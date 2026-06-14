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

static_volumes_tmp=$(mktemp)

echo "$modules" | while read -r name; do
    module_type=$(yq e ".modules[\"${name}\"].type" "$CONFIG_FILE")
    git_source=$(yq e ".modules[\"${name}\"].git_source" "$CONFIG_FILE")
    if [ -z "$module_type" ] || [ "$module_type" = "null" ]; then
        if [ "$git_source" != "null" ] && [ -n "$git_source" ] && [ -f "${git_source}/obelisk.yml" ]; then
            module_type=$(yq e ".type // \"module\"" "${git_source}/obelisk.yml")
        else
            module_type="module"
        fi
    fi
    image=$(yq e ".modules[\"${name}\"].image" "$CONFIG_FILE")
    port=""
    if [ -f "${LOCK_FILE:-obelisk.lock.yml}" ]; then
        port=$(yq e ".ports[\"${name}\"] // \"\"" "${LOCK_FILE:-obelisk.lock.yml}")
    fi
    if [ -z "$port" ] || [ "$port" = "null" ]; then
        port=$(yq e ".modules[\"${name}\"].port // 8080" "$CONFIG_FILE")
    fi
    replicas=$(yq e ".modules[\"${name}\"].replicas // 1" "$CONFIG_FILE")

    if [ "$module_type" = "static" ]; then
        # Static modules are served directly by nginx — mount their dist into the nginx container.
        if [ "$git_source" != "null" ] && [ -n "$git_source" ]; then
            dist=$(yq e ".modules[\"${name}\"].dist" "$CONFIG_FILE")
            if [ -z "$dist" ] || [ "$dist" = "null" ]; then
                if [ -f "${git_source}/obelisk.yml" ]; then
                    dist=$(yq e ".dist // \"dist\"" "${git_source}/obelisk.yml")
                else
                    dist="dist"
                fi
            fi
            echo "      - ${git_source}/${dist}:/obelisk/static/${name}/${dist}:ro" >> "$static_volumes_tmp"
        fi
        continue
    fi

    if [ "$image" != "null" ] && [ -n "$image" ]; then
        if [ "${OBELISK_MODE:-}" = "swarm" ]; then
            cat >> docker-compose.override.yml << YAML
  ${name}:
    image: ${image}
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

if [ -s "$static_volumes_tmp" ]; then
    cat >> docker-compose.override.yml << 'YAML'
  nginx-webserver:
    volumes:
YAML
    cat "$static_volumes_tmp" >> docker-compose.override.yml
fi
rm -f "$static_volumes_tmp"

# If no services were written, the file has only "services:" which is invalid YAML
if ! grep -q '^\s' docker-compose.override.yml; then
    printf 'services: {}\n' > docker-compose.override.yml
    if [ "${OBELISK_MODE:-}" = "swarm" ]; then
        echo "[Obelisk] warning: no deployable services found — swarm mode requires 'image:' fields on modules; 'git_source' modules are dev-only" >&2
    fi
fi

echo "[Obelisk] Generated docker-compose.override.yml"
