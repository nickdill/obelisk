#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
else
    CONFIG_FILE=obelisk.yml
fi
export CONFIG_FILE

LOCK_FILE="obelisk.lock.yml"
export LOCK_FILE

BASE_PORT="${OBELISK_BASE_PORT:-9000}"

# Initialize lockfile if it doesn't exist
if [ ! -f "$LOCK_FILE" ]; then
    printf 'ports: {}\n' > "$LOCK_FILE"
fi

# Compute next_port = one above the highest port currently in the lockfile
max_port=$((BASE_PORT - 1))
ports_tmp=$(mktemp)
yq e '.ports // {} | to_entries[] | .value' "$LOCK_FILE" > "$ports_tmp" 2>/dev/null || true
while IFS= read -r p; do
    [ -n "$p" ] && [ "$p" -gt "$max_port" ] && max_port=$p
done < "$ports_tmp"
rm -f "$ports_tmp"
next_port=$((max_port + 1))
if [ "$next_port" -lt "$BASE_PORT" ]; then
    next_port=$BASE_PORT
fi

# Resolve ports for all modules and write to lockfile
modules_tmp=$(mktemp)
yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" > "$modules_tmp" 2>/dev/null || true
while IFS= read -r name; do
    [ -z "$name" ] && continue

    yml_port=$(yq e ".modules[\"${name}\"].port" "$CONFIG_FILE")
    if [ -n "$yml_port" ] && [ "$yml_port" != "null" ]; then
        yq e -i ".ports[\"${name}\"] = ${yml_port}" "$LOCK_FILE"
    else
        lock_port=$(yq e ".ports[\"${name}\"] // \"\"" "$LOCK_FILE")
        if [ -z "$lock_port" ] || [ "$lock_port" = "null" ]; then
            yq e -i ".ports[\"${name}\"] = ${next_port}" "$LOCK_FILE"
            next_port=$((next_port + 1))
        fi
    fi
done < "$modules_tmp"
rm -f "$modules_tmp"

echo "[Obelisk] Generating stack override..."
sh .obelisk/scripts/generate-compose.sh

echo "[Obelisk] Generating nginx configs..."
sh .obelisk/scripts/generate-nginx.sh
