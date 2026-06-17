#!/bin/sh

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
elif [ -f obelisk.yml ]; then
    CONFIG_FILE=obelisk.yml
else
    exit 0
fi

HTTP_PORT="${OBELISK_HTTP_PORT:-80}"
HTTPS_PORT="${OBELISK_HTTPS_PORT:-443}"
OBELISK_ENV="${OBELISK_ENV:-local}"
SSL="${OBELISK_SSL:-false}"

if [ "$SSL" = "true" ]; then
    SCHEME="https"
    PORT="$HTTPS_PORT"
    DEFAULT_PORT=443
else
    SCHEME="http"
    PORT="$HTTP_PORT"
    DEFAULT_PORT=80
fi

if [ "$PORT" = "$DEFAULT_PORT" ]; then
    PORT_SUFFIX=""
else
    PORT_SUFFIX=":${PORT}"
fi

server_domain=$(yq e ".domains[\"${OBELISK_ENV}\"] // \"\"" "$CONFIG_FILE")

echo ""
echo "[Obelisk] Access your services:"
if [ -n "$server_domain" ] && [ "$server_domain" != "null" ]; then
    printf "  %-12s %s\n" "server:" "${SCHEME}://${server_domain}${PORT_SUFFIX}"
fi

yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" | while read -r name; do
    domain=$(yq e ".modules[\"${name}\"].domains[\"${OBELISK_ENV}\"] // \"\"" "$CONFIG_FILE")
    if [ -n "$domain" ] && [ "$domain" != "null" ]; then
        printf "  %-12s %s\n" "${name}:" "${SCHEME}://${domain}${PORT_SUFFIX}"
    fi
done
echo ""
