#!/bin/bash
set -e

# Configurable variables with defaults
USER_NAME=${USER_NAME:-omni}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

persist_env_vars() {
    local env_file="/etc/profile.d/omni-cli-env.sh"
    local tmp_file
    tmp_file=$(mktemp)
    echo "#!/bin/bash" > "$tmp_file"

    local vars=(
        ANTHROPIC_API_KEY
        OPENAI_API_KEY
        OPENROUTER_API_KEY
        GEMINI_API_KEY
        AICORE_SERVICE_KEY
        AICORE_DEPLOYMENT_ID
        AICORE_RESOURCE_GROUP
        AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY
        AWS_REGION
        AWS_PROFILE
        AWS_BEARER_TOKEN_BEDROCK
        AWS_WEB_IDENTITY_TOKEN_FILE
        AWS_ROLE_ARN
        AZURE_RESOURCE_NAME
        AZURE_COGNITIVE_SERVICES_RESOURCE_NAME
        CLOUDFLARE_ACCOUNT_ID
        CLOUDFLARE_GATEWAY_ID
        CLOUDFLARE_API_TOKEN
        GITLAB_INSTANCE_URL
        GITLAB_TOKEN
        GITLAB_AI_GATEWAY_URL
        GITLAB_OAUTH_CLIENT_ID
        GOOGLE_APPLICATION_CREDENTIALS
        GOOGLE_CLOUD_PROJECT
        VERTEX_LOCATION
    )
    local has_env=0
    for var in "${vars[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            local escaped
            escaped=$(printf "%s" "$val" | sed "s/'/'\\\\''/g")
            echo "export $var='$escaped'" >> "$tmp_file"
            has_env=1
        fi
    done

    if [ "$has_env" -eq 1 ]; then
        mv "$tmp_file" "$env_file"
        chmod 0644 "$env_file"
    else
        rm -f "$tmp_file" "$env_file"
    fi
}

# Update user UID/GID if they differ from current (to match host volume permissions)
if [ "$(id -u "$USER_NAME")" != "$PUID" ]; then
    usermod -o -u "$PUID" "$USER_NAME"
fi
if [ "$(id -g "$USER_NAME")" != "$PGID" ]; then
    groupmod -o -g "$PGID" "$USER_NAME"
fi

# Ensure critical directories exist and have correct ownership
for dir in /data /config /var/run/sshd; do
    mkdir -p "$dir"
done

# Ensure config subdirectories exist (in case volume mount is empty)
for subdir in gemini codex copilot claude npm opencode; do
    if [ ! -d "/config/$subdir" ]; then
        echo "Creating missing config directory: /config/$subdir"
        mkdir -p "/config/$subdir"
    fi
done

for dir in /config/opencode/config /config/opencode/data /config/opencode/cache; do
    if [ ! -d "$dir" ]; then
        echo "Creating missing Opencode directory: $dir"
        mkdir -p "$dir"
    fi
done

ensure_symlink() {
    local target=$1
    local link=$2
    if [ -L "$link" ]; then
        local current
        current=$(readlink "$link")
        if [ "$current" != "$target" ]; then
            rm -f "$link"
        fi
    elif [ -e "$link" ]; then
        return
    fi

    if [ ! -e "$link" ]; then
        ln -s "$target" "$link"
    fi
}

# Initialize SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH keys..."
    ssh-keygen -A
fi

# Fix ownership of persistent volumes
chown -R "$USER_NAME":"$USER_NAME" /data /config

ensure_symlink /config/gemini "/home/${USER_NAME}/.gemini"
ensure_symlink /config/codex "/home/${USER_NAME}/.codex"
ensure_symlink /config/copilot "/home/${USER_NAME}/.copilot"
ensure_symlink /config/claude "/home/${USER_NAME}/.claude"
ensure_symlink /config/npm "/home/${USER_NAME}/.npm"
ensure_symlink /config/opencode "/home/${USER_NAME}/.opencode"

persist_env_vars

start_codex_node_server() {
    # Try to find api.js in the container first, then fall back to data volume
    local server_path
    if [ -f "/usr/local/bin/api.js" ]; then
        server_path="/usr/local/bin/api.js"
    elif [ -f "/data/omni-cli/api.js" ]; then
        server_path="/data/omni-cli/api.js"
    else
        return
    fi
    if ! command -v node >/dev/null 2>&1; then
        echo "Node.js not available; skipping Codex passthrough server."
        return
    fi

    echo "Starting Codex passthrough server..."
    runuser -u "$USER_NAME" -- node "$server_path" >/tmp/omni-codex-server.log 2>&1 &
}

# Logic:
# 1. If no arguments are provided, start SSHD (as root).
# 2. If arguments are provided, execute them as the non-root user.
if [ "$#" -eq 0 ]; then
    start_codex_node_server
    echo "Starting SSH server..."
    exec /usr/sbin/sshd -D -e
else
    # executing command as user
    exec runuser -u "$USER_NAME" -- "$@"
fi
