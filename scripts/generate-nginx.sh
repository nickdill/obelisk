#!/bin/sh
set -e

cd "$(dirname "$0")/.."

CONFIG_FILE="${CONFIG_FILE:-megalisk.yml}"
CONF_DIR="nginx/data/nginx"
TEMPLATE="nginx/templates/module.conf.tmpl"

mkdir -p "$CONF_DIR"

# Remove previously generated configs (identified by comment marker)
grep -rl "# megalisk-generated" "$CONF_DIR" 2>/dev/null | xargs rm -f 2>/dev/null || true

yq '.modules | to_entries | .[] | .key + " " + .value.domain + " " + (.value.port | tostring)' "$CONFIG_FILE" \
    | while IFS=' ' read -r name domain container_port; do
        outfile="$CONF_DIR/$name.conf"
        sed \
            -e "s|{{MODULE_NAME}}|$name|g" \
            -e "s|{{DOMAIN}}|$domain|g" \
            -e "s|{{CONTAINER_PORT}}|$container_port|g" \
            "$TEMPLATE" > "$outfile"
        echo "[generate-nginx] Generated $outfile"
    done
