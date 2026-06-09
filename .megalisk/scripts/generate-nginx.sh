#!/bin/sh
set -e

cd "$(dirname "$0")/../.."

CONFIG_FILE="${CONFIG_FILE:-megalisk.yml}"
CONF_DIR="nginx/data/nginx"

LOCAL=false
[ "$CONFIG_FILE" = "megalisk.local.yml" ] && LOCAL=true

mkdir -p "$CONF_DIR"

# Remove previously generated configs (identified by comment marker)
grep -rl "# megalisk-generated" "$CONF_DIR" 2>/dev/null | xargs rm -f 2>/dev/null || true

yq '.modules | to_entries | .[] | .key + " " + .value.domain + " " + (.value.port | tostring)' "$CONFIG_FILE" \
    | while IFS=' ' read -r name domain container_port; do
        git_source=$(yq ".modules.$name.git_source" "$CONFIG_FILE" 2>/dev/null)
        case "$git_source" in
            ./*|../*|/*) source_path="$git_source" ;;
            *)           source_path="./modules/$name" ;;
        esac
        module_yml="$source_path/megalisk.yml"
        module_type=""
        [ -f "$module_yml" ] && module_type=$(yq '.type' "$module_yml" 2>/dev/null)

        if [ "$LOCAL" = "true" ]; then
            if [ "$module_type" = "static" ]; then
                tmpl="nginx/templates/module.local.static.conf.tmpl"
            else
                tmpl="nginx/templates/module.local.conf.tmpl"
            fi
        else
            [ "$module_type" = "static" ] && continue
            tmpl="nginx/templates/module.conf.tmpl"
        fi

        outfile="$CONF_DIR/$name.conf"
        sed \
            -e "s|{{MODULE_NAME}}|$name|g" \
            -e "s|{{DOMAIN}}|$domain|g" \
            -e "s|{{CONTAINER_PORT}}|$container_port|g" \
            "$tmpl" > "$outfile"
        echo "[generate-nginx] Generated $outfile"
    done
