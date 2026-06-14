#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${CONFIG_FILE:-obelisk.yml}"

mkdir -p .obelisk/nginx
find .obelisk/nginx -maxdepth 1 -name '*.conf' ! -name 'default.conf' -delete

yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" | while read -r name; do
    module_type=$(yq e ".modules[\"${name}\"].type" "$CONFIG_FILE")
    git_source=$(yq e ".modules[\"${name}\"].git_source" "$CONFIG_FILE")
    image=$(yq e ".modules[\"${name}\"].image" "$CONFIG_FILE")
    if [ -z "$module_type" ] || [ "$module_type" = "null" ]; then
        if [ "$git_source" != "null" ] && [ -n "$git_source" ] && [ -f "${git_source}/obelisk.yml" ]; then
            module_type=$(yq e ".type // \"module\"" "${git_source}/obelisk.yml")
        else
            module_type="module"
        fi
    fi
    domain=$(yq e ".modules[\"${name}\"].domain" "$CONFIG_FILE")

    if [ "$module_type" = "static" ]; then
        dist=$(yq e ".modules[\"${name}\"].dist" "$CONFIG_FILE")
        if [ -z "$dist" ] || [ "$dist" = "null" ]; then
            if [ "$git_source" != "null" ] && [ -n "$git_source" ] && [ -f "${git_source}/obelisk.yml" ]; then
                dist=$(yq e ".dist // \"dist\"" "${git_source}/obelisk.yml")
            else
                dist="dist"
            fi
        fi
        cat > ".obelisk/nginx/${name}.conf" << NGINX
server {
    listen 80;
    server_name ${domain};

    root /obelisk/static/${name}/${dist}/;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
        add_header Cache-Control "no-cache" always;
        add_header X-Content-Type-Options "nosniff" always;
    }
}
NGINX
    else
        if [ "${OBELISK_MODE:-}" = "swarm" ] && [ "$git_source" != "null" ] && [ -n "$git_source" ] && { [ -z "$image" ] || [ "$image" = "null" ]; }; then
            echo "[Obelisk] skipping nginx config for '${name}' (git_source not deployable in swarm)" >&2
            continue
        fi
        port=""
        if [ -f "${LOCK_FILE:-obelisk.lock.yml}" ]; then
            port=$(yq e ".ports[\"${name}\"] // \"\"" "${LOCK_FILE:-obelisk.lock.yml}")
        fi
        if [ -z "$port" ] || [ "$port" = "null" ]; then
            port=$(yq e ".modules[\"${name}\"].port // 8080" "$CONFIG_FILE")
        fi
        cat > ".obelisk/nginx/${name}.conf" << NGINX
server {
    listen 80;
    server_name ${domain};

    location / {
        resolver 127.0.0.11 valid=10s;
        set \$upstream http://${name}:${port};
        proxy_pass \$upstream;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
    fi
done

echo "[Obelisk] Generated nginx configs."
