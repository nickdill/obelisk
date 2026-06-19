#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${CONFIG_FILE:-obelisk.yml}"
SSL_ENABLED="${OBELISK_SSL:-false}"

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
        if [ "$git_source" != "null" ] && [ -n "$git_source" ]; then
            dist=$(yq e ".modules[\"${name}\"].dist" "$CONFIG_FILE")
            if [ -z "$dist" ] || [ "$dist" = "null" ]; then
                if [ -f "${git_source}/obelisk.yml" ]; then
                    dist=$(yq e ".dist // \".\"" "${git_source}/obelisk.yml")
                else
                    dist="."
                fi
            fi
            abs_source=$(cd "$git_source" && pwd)
            if [ "$dist" = "." ]; then
                echo "      - ${abs_source}:/obelisk/static/${name}:ro" >> "$static_volumes_tmp"
            else
                echo "      - ${abs_source}/${dist}:/obelisk/static/${name}/${dist}:ro" >> "$static_volumes_tmp"
            fi
        fi
        continue
    fi

    env_block="      PORT: \"${port}\""
    env_keys=$(yq e ".modules[\"${name}\"].environment // {} | keys | .[]" "$CONFIG_FILE" 2>/dev/null || true)
    if [ -n "$env_keys" ]; then
        extra=$(echo "$env_keys" | while read -r key; do
            [ "$key" = "PORT" ] && continue
            val=$(yq e ".modules[\"${name}\"].environment[\"${key}\"]" "$CONFIG_FILE")
            printf '      %s: "%s"\n' "$key" "$val"
        done)
        if [ -n "$extra" ]; then
            env_block="${env_block}
${extra}"
        fi
    fi

    vol_block=""
    vol_entries=$(yq e ".modules[\"${name}\"].volumes // [] | .[]" "$CONFIG_FILE" 2>/dev/null || true)
    if [ -n "$vol_entries" ]; then
        vol_block="    volumes:"
        vol_block="${vol_block}
$(echo "$vol_entries" | while read -r v; do printf '      - %s\n' "$v"; done)"
    fi

    if [ "$image" != "null" ] && [ -n "$image" ]; then
        if [ "${OBELISK_MODE:-}" = "swarm" ]; then
            cat >> docker-compose.override.yml << YAML
  ${name}:
    image: ${image}
    environment:
${env_block}
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
            if [ -n "$vol_block" ]; then
                echo "$vol_block" >> docker-compose.override.yml
            fi
        else
            cat >> docker-compose.override.yml << YAML
  ${name}:
    image: ${image}
    profiles: ["local"]
    expose:
      - "${port}"
    environment:
${env_block}
    networks:
      - obelisk
YAML
            if [ -n "$vol_block" ]; then
                echo "$vol_block" >> docker-compose.override.yml
            fi
        fi
    elif [ "$git_source" != "null" ] && [ -n "$git_source" ]; then
        if [ "${OBELISK_MODE:-}" = "swarm" ]; then
            echo "[Obelisk] warning: module '${name}' uses git_source which is not supported in Swarm mode — skipping" >&2
        else
            cat >> docker-compose.override.yml << YAML
  ${name}:
    build:
      context: ${git_source}
    profiles: ["local"]
    expose:
      - "${port}"
    environment:
${env_block}
    networks:
      - obelisk
YAML
            if [ -n "$vol_block" ]; then
                echo "$vol_block" >> docker-compose.override.yml
            fi
        fi
    else
        echo "[Obelisk] warning: module '${name}' has no image or git_source — skipping" >&2
    fi
done

# Nginx overrides: static module volumes + SSL volumes/command
nginx_needs_override=false
ssl_volumes=""
ssl_command=""

if [ "$SSL_ENABLED" = "true" ]; then
    nginx_needs_override=true
    ssl_volumes="      - ./.obelisk/certbot/conf:/etc/letsencrypt:ro
      - ./.obelisk/certbot/www:/var/www/certbot:ro"
    ssl_command='    command: "/bin/sh -c '"'"'while :; do sleep 6h & wait $${!}; nginx -s reload; done & nginx -g \"daemon off;\"'"'"'"'
fi

has_static=false
if [ -s "$static_volumes_tmp" ]; then
    nginx_needs_override=true
    has_static=true
fi

if [ "$nginx_needs_override" = "true" ]; then
    cat >> docker-compose.override.yml << 'YAML'
  nginx-webserver:
YAML
    if [ -n "$ssl_command" ]; then
        echo "$ssl_command" >> docker-compose.override.yml
    fi
    echo "    volumes:" >> docker-compose.override.yml
    if [ -s "$static_volumes_tmp" ]; then
        cat "$static_volumes_tmp" >> docker-compose.override.yml
    fi
    if [ -n "$ssl_volumes" ]; then
        echo "$ssl_volumes" >> docker-compose.override.yml
    fi
fi
rm -f "$static_volumes_tmp"

# Certbot renewal service
if [ "$SSL_ENABLED" = "true" ]; then
    if [ "${OBELISK_MODE:-}" = "swarm" ]; then
        cat >> docker-compose.override.yml << 'YAML'
  certbot:
    image: certbot/certbot
    volumes:
      - ./.obelisk/certbot/conf:/etc/letsencrypt
      - ./.obelisk/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    networks:
      - obelisk
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
YAML
    else
        cat >> docker-compose.override.yml << 'YAML'
  certbot:
    image: certbot/certbot
    volumes:
      - ./.obelisk/certbot/conf:/etc/letsencrypt
      - ./.obelisk/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    networks:
      - obelisk
YAML
    fi
fi

# If no services were written, the file has only "services:" which is invalid YAML
if ! grep -q '^\s' docker-compose.override.yml; then
    printf 'services: {}\n' > docker-compose.override.yml
    if [ "${OBELISK_MODE:-}" = "swarm" ] && [ "$has_static" = "false" ]; then
        echo "[Obelisk] warning: no deployable services found — swarm mode requires 'image:' fields on modules; 'git_source' modules are dev-only" >&2
    fi
fi

echo "[Obelisk] Generated docker-compose.override.yml"
