#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

CONFIG_FILE="${CONFIG_FILE:-obelisk.yml}"
SSL_ENABLED="${OBELISK_SSL:-false}"
OBELISK_ENV="${OBELISK_ENV:-local}"

mkdir -p .obelisk/nginx
find .obelisk/nginx -maxdepth 1 -name '*.conf' ! -name 'default.conf' -delete

server_domain=$(yq e ".domains[\"${OBELISK_ENV}\"] // \"\"" "$CONFIG_FILE")

if [ "$SSL_ENABLED" = "true" ]; then
    if [ -n "$server_domain" ]; then
        cat > ".obelisk/nginx/default.conf" << NGINX
server {
    listen 80;
    server_name ${server_domain};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}

server {
    listen 443 ssl;
    server_name ${server_domain};

    ssl_certificate /etc/letsencrypt/live/${server_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${server_domain}/privkey.pem;

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}

server {
    listen 80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/default/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/default/privkey.pem;

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}
NGINX
    else
        cat > ".obelisk/nginx/default.conf" << 'NGINX'
server {
    listen 80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/default/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/default/privkey.pem;

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}
NGINX
    fi
else
    cat > ".obelisk/nginx/default.conf" << 'NGINX'
server {
    listen 80 default_server;
    server_name _;

    location / {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>obelisk</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:system-ui,sans-serif}.c{text-align:center}h1{font-size:2rem;font-weight:300;letter-spacing:.1em;margin-bottom:.5rem}p{color:#666;font-size:.85rem}</style>
</head><body><div class="c"><h1>obelisk</h1><p>server is running</p></div></body></html>';
    }
}
NGINX
fi

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
    domain=$(yq e ".modules[\"${name}\"].domains[\"${OBELISK_ENV}\"] // \"\"" "$CONFIG_FILE")

    if [ -z "$domain" ] || [ "$domain" = "null" ]; then
        continue
    fi

    if [ "$module_type" = "static" ]; then
        # The served path is always /obelisk/static/${name}/ regardless of the
        # module's `dist` setting: in local dev the dist dir is bind-mounted
        # there, and in production sync-static.sh extracts the dist contents
        # there. `dist` is purely a build/extract concern now, not a serve path.
        static_root="/obelisk/static/${name}/"

        # Module domains are fronted by CloudFront (HTTP-only origin), so nginx
        # serves them over plain HTTP — no per-domain TLS cert needed here.
        cat > ".obelisk/nginx/${name}.conf" << NGINX
server {
    listen 80;
    server_name ${domain};

    root ${static_root};
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

        # Module domains are fronted by CloudFront (HTTP-only origin), so nginx
        # proxies them over plain HTTP — no per-domain TLS cert needed here.
        # X-Forwarded-Proto is taken from CloudFront's header so upstreams still
        # see the original https scheme.
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
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINX
    fi
done

echo "[Obelisk] Generated nginx configs."
