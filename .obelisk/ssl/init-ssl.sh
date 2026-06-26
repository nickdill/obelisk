#!/bin/sh
set -e

SCALED_DOWN=""
cleanup() {
    docker stop obelisk-ssl-bootstrap 2>/dev/null || true
    if [ -n "$SCALED_DOWN" ]; then
        docker service scale obelisk_nginx-webserver=1 --detach=false || true
    fi
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

[ -f .env ] && . ./.env

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
else
    CONFIG_FILE=obelisk.yml
fi

OBELISK_ENV="${OBELISK_ENV:-local}"
RSA_KEY_SIZE=4096
CERTBOT_DIR=".obelisk/certbot"
STAGING="${OBELISK_SSL_STAGING:-0}"
EMAIL="${OBELISK_SSL_EMAIL:-}"

echo "[Obelisk] Initializing SSL certificates..."

mkdir -p "$CERTBOT_DIR/conf" "$CERTBOT_DIR/www"

# Fix ownership on certbot dirs that may be root-owned from previous Docker runs
fix_certbot_permissions() {
    docker run --rm \
        -v "${SCRIPT_DIR}/${CERTBOT_DIR}/conf:/etc/letsencrypt" \
        alpine:3.20 chown -R "$(id -u):$(id -g)" /etc/letsencrypt 2>/dev/null || true
}
fix_certbot_permissions

# Generate self-signed default cert for the catch-all 443 block
if [ ! -f "$CERTBOT_DIR/conf/live/default/fullchain.pem" ]; then
    echo "[Obelisk] Creating default self-signed certificate..."
    mkdir -p "$CERTBOT_DIR/conf/live/default"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$CERTBOT_DIR/conf/live/default/privkey.pem" \
        -out "$CERTBOT_DIR/conf/live/default/fullchain.pem" \
        -subj '/CN=localhost'
fi

# Collect domains that need new certificates
pending_file="$CERTBOT_DIR/.pending_domains"
rm -f "$pending_file"

# Server-level domain
server_domain=$(yq e ".domains[\"${OBELISK_ENV}\"] // \"\"" "$CONFIG_FILE")
if [ -n "$server_domain" ]; then
    if [ -f "$CERTBOT_DIR/conf/live/${server_domain}/fullchain.pem" ] && \
       [ -f "$CERTBOT_DIR/conf/live/${server_domain}/privkey.pem" ]; then
        echo "[Obelisk] Certificate for ${server_domain} already exists, skipping."
    else
        echo "[Obelisk] Creating dummy certificate for ${server_domain}..."
        mkdir -p "$CERTBOT_DIR/conf/live/${server_domain}"
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout "$CERTBOT_DIR/conf/live/${server_domain}/privkey.pem" \
            -out "$CERTBOT_DIR/conf/live/${server_domain}/fullchain.pem" \
            -subj "/CN=${server_domain}"
        echo "${server_domain}" >> "$pending_file"
    fi
fi

# Module domains are fronted by CloudFront with an HTTP-only origin, so nginx
# serves them over plain HTTP and they need no cert here. HTTP-01 challenges
# can't reach them anyway (they CNAME to CloudFront), so we don't request any.

if [ ! -f "$pending_file" ]; then
    echo "[Obelisk] All certificates up to date."
    exit 0
fi

# Stop existing nginx so ports 80/443 are free for the bootstrap container.
if docker service inspect obelisk_nginx-webserver >/dev/null 2>&1; then
    echo "[Obelisk] Scaling down swarm nginx to free ports..."
    docker service scale obelisk_nginx-webserver=0 --detach=false || true
    SCALED_DOWN=1
fi

# Start a temporary nginx container to serve ACME challenges.
# Uses docker run directly so it works before stack deploy (swarm mode).
echo "[Obelisk] Starting temporary nginx for ACME challenges..."
docker run -d --rm \
    --name obelisk-ssl-bootstrap \
    -p "${OBELISK_HTTP_PORT:-80}:80" \
    -p "${OBELISK_HTTPS_PORT:-443}:443" \
    -v "${SCRIPT_DIR}/.obelisk/nginx:/etc/nginx/conf.d:ro" \
    -v "${SCRIPT_DIR}/${CERTBOT_DIR}/conf:/etc/letsencrypt:ro" \
    -v "${SCRIPT_DIR}/${CERTBOT_DIR}/www:/var/www/certbot:ro" \
    nginx:1.27-alpine
sleep 2

# Request real certificates for pending domains
while IFS= read -r domain; do
    [ -z "$domain" ] && continue

    echo "[Obelisk] Deleting dummy certificate for ${domain}..."
    # These paths were created by the certbot container as root, so delete them
    # from inside a root container too — a host-side rm hits "Permission denied".
    docker run --rm \
        -v "${SCRIPT_DIR}/${CERTBOT_DIR}/conf:/etc/letsencrypt" \
        alpine:3.20 rm -rf \
        "/etc/letsencrypt/live/${domain}" \
        "/etc/letsencrypt/archive/${domain}" \
        "/etc/letsencrypt/renewal/${domain}.conf"

    echo "[Obelisk] Requesting Let's Encrypt certificate for ${domain}..."

    staging_arg=""
    if [ "$STAGING" != "0" ]; then
        staging_arg="--staging"
    fi

    email_arg="--register-unsafely-without-email"
    if [ -n "$EMAIL" ]; then
        email_arg="--email $EMAIL"
    fi

    docker run --rm \
        -v "${SCRIPT_DIR}/${CERTBOT_DIR}/conf:/etc/letsencrypt" \
        -v "${SCRIPT_DIR}/${CERTBOT_DIR}/www:/var/www/certbot" \
        certbot/certbot certonly --webroot \
        -w /var/www/certbot \
        $staging_arg \
        $email_arg \
        -d "$domain" \
        --rsa-key-size "$RSA_KEY_SIZE" \
        --agree-tos \
        --non-interactive \
        --force-renewal || {
        echo "[Obelisk] WARNING: Failed to obtain certificate for ${domain}, restoring dummy..."
        fix_certbot_permissions
        mkdir -p "$CERTBOT_DIR/conf/live/${domain}"
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout "$CERTBOT_DIR/conf/live/${domain}/privkey.pem" \
            -out "$CERTBOT_DIR/conf/live/${domain}/fullchain.pem" \
            -subj "/CN=${domain}"
    }

done < "$pending_file"
rm -f "$pending_file"

echo "[Obelisk] SSL initialization complete."
