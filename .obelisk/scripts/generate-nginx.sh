#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${CONFIG_FILE:-obelisk.yml}"

mkdir -p .obelisk/nginx
rm -f .obelisk/nginx/*.conf

yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" | while read -r name; do
    module_type=$(yq e ".modules[\"${name}\"].type // \"module\"" "$CONFIG_FILE")
    domain=$(yq e ".modules[\"${name}\"].domain" "$CONFIG_FILE")

    if [ "$module_type" = "static" ]; then
        dist=$(yq e ".modules[\"${name}\"].dist // \"dist\"" "$CONFIG_FILE")
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
        port=$(yq e ".modules[\"${name}\"].port // 8080" "$CONFIG_FILE")
        cat > ".obelisk/nginx/${name}.conf" << NGINX
server {
    listen 80;
    server_name ${domain};

    location / {
        proxy_pass http://${name}:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX
    fi
done

echo "[Obelisk] Generated nginx configs."
