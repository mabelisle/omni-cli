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
        OPENROUTER_API_KEY
        OR_API_KEY
        OPENAI_API_KEY
        OPENAI_API_BASE
        OPENAI_LIKE_API_KEY
        ANTHROPIC_API_KEY
        GEMINI_API_KEY
        GROQ_API_KEY
        XAI_API_KEY
        COHERE_API_KEY
        GOOGLE_API_KEY
        PALM_API_KEY
        DEEPSEEK_API_KEY
        OLLAMA_API_BASE
        OLLAMA_API_KEY
        LM_STUDIO_API_KEY
        LM_STUDIO_API_BASE
        AZURE_API_KEY
        AZURE_API_VERSION
        AZURE_API_BASE
        AZURE_OPENAI_API_KEY
        AZURE_AI_API_KEY
        ALEPH_ALPHA_API_KEY
        ALEPHALPHA_API_KEY
        ANYSCALE_API_KEY
        ARK_API_KEY
        BASETEN_API_KEY
        BYTEZ_API_KEY
        CEREBRAS_API_KEY
        CLARIFAI_API_KEY
        CLOUDFLARE_API_KEY
        CO_API_KEY
        CODESTRAL_API_KEY
        COMPACTIFAI_API_KEY
        DASHSCOPE_API_KEY
        DATABRICKS_API_KEY
        DEEPINFRA_API_KEY
        FEATHERLESS_AI_API_KEY
        FIREWORKS_AI_API_KEY
        FIREWORKS_API_KEY
        FIREWORKSAI_API_KEY
        HUGGINGFACE_API_KEY
        INFINITY_API_KEY
        MARITALK_API_KEY
        MISTRAL_API_KEY
        MOONSHOT_API_KEY
        NEBIUS_API_KEY
        NLP_CLOUD_API_KEY
        NOVITA_API_KEY
        NVIDIA_NIM_API_KEY
        OVHCLOUD_API_KEY
        PERPLEXITYAI_API_KEY
        PREDIBASE_API_KEY
        PROVIDER_API_KEY
        REPLICATE_API_KEY
        SAMBANOVA_API_KEY
        TOGETHERAI_API_KEY
        USER_API_KEY
        VERCEL_AI_GATEWAY_API_KEY
        VOLCENGINE_API_KEY
        VOYAGE_API_KEY
        WANDB_API_KEY
        WATSONX_API_KEY
        WX_API_KEY
        XINFERENCE_API_KEY
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
for subdir in gemini codex copilot claude npm .aider; do
    if [ ! -d "/config/$subdir" ]; then
        echo "Creating missing config directory: /config/$subdir"
        mkdir -p "/config/$subdir"
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
ensure_symlink /config/.aider "/home/${USER_NAME}/.aider"

persist_env_vars

# Logic:
# 1. If no arguments are provided, start SSHD (as root).
# 2. If arguments are provided, execute them as the non-root user.
if [ "$#" -eq 0 ]; then
    echo "Starting SSH server..."
    exec /usr/sbin/sshd -D -e
else
    # executing command as user
    exec runuser -u "$USER_NAME" -- "$@"
fi
