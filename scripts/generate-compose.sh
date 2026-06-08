#!/bin/sh
set -e

cd "$(dirname "$0")/.."

CONFIG_FILE="${CONFIG_FILE:-megalisk.yml}"
OUTFILE="docker-compose.override.yml"

printf "services:\n" > "$OUTFILE"

yq '.modules | to_entries | .[] | .key + " " + .value.image + " " + (.value.port | tostring)' "$CONFIG_FILE" \
    | awk 'BEGIN{port=4000} {print port, $0; port++}' \
    | while IFS=' ' read -r host_port name image container_port; do
        cat >> "$OUTFILE" << EOF
  $name:
    image: $image
    container_name: $name
    restart: unless-stopped
    networks:
      - monolith
    ports:
      - "$host_port:$container_port"
EOF

        env_count=$(yq '.modules.'"$name"'.env | length' "$CONFIG_FILE" 2>/dev/null)
        env_count="${env_count:-0}"
        if [ "$env_count" -gt 0 ] 2>/dev/null; then
            printf "    environment:\n" >> "$OUTFILE"
            yq '.modules.'"$name"'.env | to_entries | .[] | "      - " + .key + "=" + .value' "$CONFIG_FILE" >> "$OUTFILE"
        fi

        printf "\n" >> "$OUTFILE"
    done

echo "[generate-compose] Wrote $OUTFILE"
