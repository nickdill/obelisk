#!/bin/sh
set -e

# sync-static.sh — pull each static module's artifact image and extract its
# built assets into the shared `obelisk_static` named volume, under a
# per-module subdirectory that nginx serves from /obelisk/static/<name>/.
#
# This is the single source of truth for static asset delivery. It is called
# two ways:
#   * run.sh (manual path)  — no OBELISK_MODULE set: sync ALL static modules.
#   * the agent (CLI path)  — OBELISK_MODULE + OBELISK_IMAGE set: sync one.
#
# Registry login is assumed to have already happened (run.sh / the agent do it).

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

if [ -f obelisk.local.yml ]; then
    CONFIG_FILE=obelisk.local.yml
elif [ -f obelisk.yml ]; then
    CONFIG_FILE=obelisk.yml
else
    echo "[Obelisk] sync-static: no obelisk.yml found, nothing to do" >&2
    exit 0
fi

VOLUME="${OBELISK_STATIC_VOLUME:-obelisk_static}"

# extract <name> <image> — pull the image and copy /static into the volume at
# /<name> via an atomic temp-dir swap so nginx never serves a half-written site.
extract() {
    name="$1"
    image="$2"
    if [ -z "$image" ] || [ "$image" = "null" ]; then
        echo "[Obelisk] sync-static: skipping '${name}' (no image)" >&2
        return 0
    fi
    echo "[Obelisk] sync-static: pulling ${image} for '${name}'..."
    docker pull "$image"
    echo "[Obelisk] sync-static: extracting '${name}' into ${VOLUME}..."
    docker run --rm -v "${VOLUME}:/dest" "$image" sh -c "
        rm -rf '/dest/.tmp-${name}' &&
        mkdir -p '/dest/.tmp-${name}' &&
        cp -a /static/. '/dest/.tmp-${name}/' &&
        rm -rf '/dest/${name}' &&
        mv '/dest/.tmp-${name}' '/dest/${name}'"
}

# Resolve a module's effective type, falling back to its own obelisk.yml.
module_type_of() {
    name="$1"
    t=$(yq e ".modules[\"${name}\"].type" "$CONFIG_FILE")
    if [ -z "$t" ] || [ "$t" = "null" ]; then
        gs=$(yq e ".modules[\"${name}\"].git_source" "$CONFIG_FILE")
        if [ "$gs" != "null" ] && [ -n "$gs" ] && [ -f "${gs}/obelisk.yml" ]; then
            t=$(yq e ".type // \"module\"" "${gs}/obelisk.yml")
        else
            t="module"
        fi
    fi
    echo "$t"
}

if [ -n "${OBELISK_MODULE:-}" ]; then
    # Single-module path (agent). Image from env (the published tag) when set,
    # else from obelisk.yml. With OBELISK_IMAGE set this needs no yq.
    name="$OBELISK_MODULE"
    image="${OBELISK_IMAGE:-}"
    if [ -z "$image" ]; then
        image=$(yq e ".modules[\"${name}\"].image // \"\"" "$CONFIG_FILE")
    fi
    extract "$name" "$image"
else
    # All-modules path (run.sh). Sync every static module that has an image;
    # git_source-only static modules are dev-only (bind-mounted) and skipped.
    yq e '.modules // {} | keys | .[]' "$CONFIG_FILE" | while read -r name; do
        [ -z "$name" ] && continue
        [ "$(module_type_of "$name")" = "static" ] || continue
        image=$(yq e ".modules[\"${name}\"].image // \"\"" "$CONFIG_FILE")
        extract "$name" "$image"
    done
fi

echo "[Obelisk] sync-static: done."
