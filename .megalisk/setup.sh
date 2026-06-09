#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

# Install yq if not present
if ! command -v yq > /dev/null 2>&1; then
    echo "[Megalisk] Installing yq..."
    wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    chmod +x /usr/local/bin/yq
fi

# Load environment
[ -f .env ] && . ./.env

# Config file: prefer local override
if [ -f megalisk.local.yml ]; then
    CONFIG_FILE=megalisk.local.yml
else
    CONFIG_FILE=megalisk.yml
fi
export CONFIG_FILE

# Clear space for clean build
docker system prune -f
docker volume prune -f

# ECR auth — one login covers all ECR images
if yq '.modules | to_entries | .[].value.image' "$CONFIG_FILE" | grep -q '\.dkr\.ecr\.'; then
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo "[Megalisk] ERROR: AWS credentials not found."
        echo "  On EC2: attach an IAM Instance Profile with AmazonEC2ContainerRegistryReadOnly."
        echo "  Locally: add AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to .env"
        exit 1
    fi
    echo "[Megalisk] Authenticating to ECR..."
    aws ecr get-login-password --region "${AWS_REGION:-us-east-2}" \
        | docker login --username AWS --password-stdin "$REGISTRY"
fi

# Pull images and extract or clone per-module scripts
yq '.modules | to_entries | .[] | .key + " " + (.value.image // "none") + " " + (.value.git_source // "none")' "$CONFIG_FILE" \
    | while IFS=' ' read -r name image git_source; do
        if [ "$git_source" != "none" ]; then
            case "$git_source" in
                ./*|../*|/*)
                    echo "[Megalisk] Local path for $name: $git_source (skipping clone)"
                    ;;
                *)
                    if [ -d "modules/$name/.git" ]; then
                        echo "[Megalisk] Updating $name..."
                        git -C "modules/$name" fetch origin
                        git -C "modules/$name" merge
                    else
                        echo "[Megalisk] Cloning $name from $git_source..."
                        git clone "$git_source" "modules/$name"
                    fi
                    ;;
            esac
        else
            mkdir -p "modules/$name/.megalisk"
            echo "[Megalisk] Pulling $name ($image)..."
            docker pull "$image"

            cid=$(docker create "$image" /bin/true 2>/dev/null)
            docker cp "$cid":/.megalisk/setup.sh "modules/$name/.megalisk/setup.sh" 2>/dev/null || true
            docker cp "$cid":/.megalisk/run.sh   "modules/$name/.megalisk/run.sh"   2>/dev/null || true
            docker rm "$cid" > /dev/null 2>&1 || true
        fi

        chmod +x "modules/$name/.megalisk/setup.sh" "modules/$name/.megalisk/run.sh" 2>/dev/null || true

        if [ -f "modules/$name/.megalisk/setup.sh" ]; then
            echo "[Megalisk] Running setup for $name..."
            "modules/$name/.megalisk/setup.sh"
        fi

        echo "[Megalisk] $name ready."
    done

echo "[Megalisk] Setup complete."
