#!/bin/sh
set -e

cd "$(dirname "$0")/../.."

CONFIG_FILE="${CONFIG_FILE:-megalisk.yml}"
OUTFILE="docker-compose.override.yml"

LOCAL=false
[ "$CONFIG_FILE" = "megalisk.local.yml" ] && LOCAL=true

SERVICES_TMP=$(mktemp)
NGINX_VOLS_TMP=$(mktemp)
trap "rm -f $SERVICES_TMP $NGINX_VOLS_TMP" EXIT

yq '.modules | to_entries | .[] | select(.value.type != "static") | .key + " " + (.value.port | tostring)' "$CONFIG_FILE" \
    | awk 'BEGIN{port=4000} {print port, $0; port++}' \
    | while IFS=' ' read -r host_port name container_port; do
        git_source=$(yq ".modules.$name.git_source" "$CONFIG_FILE" 2>/dev/null)
        case "$git_source" in
            ./*|../*|/*) source_path="$git_source" ;;
            *)           source_path="./modules/$name" ;;
        esac
        module_yml="$source_path/megalisk.yml"
        if [ -f "$module_yml" ]; then
            module_type=$(yq '.type' "$module_yml" 2>/dev/null)
            [ "$module_type" = "static" ] && continue
        fi
        cat >> "$SERVICES_TMP" << EOF
  $name:
    container_name: $name
    build:
      context: $source_path
    restart: unless-stopped
    networks:
      - megalisk
    ports:
      - "$host_port:$container_port"
EOF

        env_count=$(yq '.modules.'"$name"'.env | length' "$CONFIG_FILE" 2>/dev/null)
        env_count="${env_count:-0}"
        if [ "$env_count" -gt 0 ] 2>/dev/null; then
            printf "    environment:\n" >> "$SERVICES_TMP"
            yq '.modules.'"$name"'.env | to_entries | .[] | "      - " + .key + "=" + .value' "$CONFIG_FILE" >> "$SERVICES_TMP"
        fi

        printf "\n" >> "$SERVICES_TMP"
    done

# Collect static module volume mounts for nginx (local only)
if [ "$LOCAL" = "true" ]; then
    yq '.modules | to_entries | .[] | .key' "$CONFIG_FILE" \
        | while read -r name; do
            git_source=$(yq ".modules.$name.git_source" "$CONFIG_FILE" 2>/dev/null)
            case "$git_source" in
                ./*|../*|/*) source_path="$git_source" ;;
                *)           source_path="./modules/$name" ;;
            esac
            module_yml="$source_path/megalisk.yml"
            if [ -f "$module_yml" ]; then
                module_type=$(yq '.type' "$module_yml" 2>/dev/null)
                if [ "$module_type" = "static" ]; then
                    printf "      - %s:/usr/share/nginx/modules/%s:ro\n" "$source_path" "$name" >> "$NGINX_VOLS_TMP"
                fi
            fi
        done
fi

if [ -s "$SERVICES_TMP" ] || [ "$LOCAL" = "true" ]; then
    printf "services:\n" > "$OUTFILE"
    cat "$SERVICES_TMP" >> "$OUTFILE"
    if [ "$LOCAL" = "true" ]; then
        printf "  certbot:\n    entrypoint: [\"/bin/sh\", \"-c\", \"exit 0\"]\n    restart: \"no\"\n" >> "$OUTFILE"
        printf "  nginx-webserver:\n    volumes:\n" >> "$OUTFILE"
        printf "      - ./nginx/data/nginx:/etc/nginx/conf.d\n" >> "$OUTFILE"
        printf "      - ./nginx/conf/default.conf:/etc/nginx/conf.d/00-default.conf:ro\n" >> "$OUTFILE"
        printf "      - ./nginx/html:/usr/share/nginx/html:ro\n" >> "$OUTFILE"
        printf "      - ./nginx/data/certs:/etc/nginx/certs:ro\n" >> "$OUTFILE"
        cat "$NGINX_VOLS_TMP" >> "$OUTFILE"
    fi
else
    : > "$OUTFILE"
fi

printf "networks:\n  megalisk:\n" >> "$OUTFILE"

echo "[generate-compose] Wrote $OUTFILE"
