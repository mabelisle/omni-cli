#!/bin/bash

# Load persisted environment variables created by the entrypoint.
if [ -f /etc/profile.d/omni-cli-env.sh ]; then
    . /etc/profile.d/omni-cli-env.sh
fi

# Core paths.
ROOT_DIR="/data"
OMNI_CLI_REPO="/data/omni-cli"
RECENT_MODELS_FILE="/config/.aider/omni-cli-recent-models"

# Color palette (TTY-only).
USE_COLOR=0
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    USE_COLOR=1
fi

COLOR_RESET=""
COLOR_BOLD=""
COLOR_DIM=""
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""

if [ "$USE_COLOR" -eq 1 ]; then
    COLOR_RESET=$(tput sgr0)
    COLOR_BOLD=$(tput bold)
    COLOR_DIM=$(tput dim)
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_CYAN=$(tput setaf 6)
fi

# Version is sourced from env or git.
get_version() {
    if [ -n "${OMNI_CLI_VERSION:-}" ]; then
        echo "$OMNI_CLI_VERSION"
        return
    fi
    if command -v git >/dev/null 2>&1 && [ -d "$OMNI_CLI_REPO/.git" ]; then
        local rev
        rev=$(git -C "$OMNI_CLI_REPO" rev-parse --short HEAD 2>/dev/null)
        if [ -n "$rev" ]; then
            echo "git-$rev"
            return
        fi
    fi
    echo "dev"
}

OMNI_CLI_VERSION="$(get_version)"

# API keys shown in the status menu.
all_env_vars=(
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

# Basic helpers.
env_status() {
    local name=$1
    if [ -n "${!name:-}" ]; then
        echo "${COLOR_GREEN}set${COLOR_RESET}"
    else
        echo "${COLOR_RED}unset${COLOR_RESET}"
    fi
}

openrouter_api_key() {
    echo "${OPENROUTER_API_KEY:-${OR_API_KEY:-}}"
}

mask_api_key() {
    local value=$1
    local length=${#value}
    if [ $length -le 4 ]; then
        echo "****"
    elif [ $length -le 8 ]; then
        echo "${value:0:2}..."
    else
        echo "${value:0:4}...${value: -4}"
    fi
}

# Quick PATH check for installed CLIs.
cli_status() {
    local missing=()
    local tools=(gemini codex copilot claude aider)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "${COLOR_GREEN}OK${COLOR_RESET}"
    else
        echo "${COLOR_RED}Missing:${COLOR_RESET} ${missing[*]}"
    fi
}

format_path() {
    local current_path=$1
    if [ "$current_path" = "$ROOT_DIR" ]; then
        echo "$ROOT_DIR"
        return
    fi

    local relative="${current_path#$ROOT_DIR/}"
    local formatted="$ROOT_DIR"
    IFS='/' read -ra parts <<< "$relative"
    for part in "${parts[@]}"; do
        formatted+=" > $part"
    done
    echo "$formatted"
}

show_env_summary() {
    local enabled=()
    for var in "${all_env_vars[@]}"; do
        if [ -n "${!var:-}" ]; then
            enabled+=("$var")
        fi
    done

    if [ ${#enabled[@]} -eq 0 ]; then
        echo "${COLOR_BOLD}API keys status:${COLOR_RESET} ${COLOR_DIM}(none set)${COLOR_RESET}"
        return
    fi

    echo "${COLOR_BOLD}API keys status (enabled):${COLOR_RESET}"
    for var in "${enabled[@]}"; do
        if [[ "$var" == *_API_KEY ]]; then
            echo "  ${COLOR_GREEN}$var${COLOR_RESET}: $(mask_api_key "${!var}")"
        else
            echo "  ${COLOR_GREEN}$var${COLOR_RESET}"
        fi
    done
}

show_env_menu() {
    clear
    echo "${COLOR_BOLD}API keys status (all):${COLOR_RESET}"
    for var in "${all_env_vars[@]}"; do
        printf "  %-28s %s\n" "${COLOR_YELLOW}${var}:${COLOR_RESET}" "$(env_status "$var")"
    done
    echo ""
    read -p "Press Enter to go back: " _
}

# Aider helpers.
model_is_available() {
    local model=$1
    case $model in
        openrouter/*) [ -n "$(openrouter_api_key)" ] ;;
        ollama/*) [ -n "${OLLAMA_API_BASE:-}" ] ;;
        deepseek) [ -n "${DEEPSEEK_API_KEY:-}" ] ;;
        *) return 1 ;;
    esac
}

run_aider_model() {
    local model=$1
    aider --model "$model"
    record_recent_model "$model"
}

record_recent_model() {
    local model=$1
    [ -z "$model" ] && return
    mkdir -p "$(dirname "$RECENT_MODELS_FILE")"
    {
        echo "$model"
        grep -vxF "$model" "$RECENT_MODELS_FILE" 2>/dev/null
    } | head -n 5 > "${RECENT_MODELS_FILE}.tmp"
    mv "${RECENT_MODELS_FILE}.tmp" "$RECENT_MODELS_FILE"
}

load_recent_models() {
    recent_models=()
    [ -f "$RECENT_MODELS_FILE" ] || return
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if model_is_available "$line"; then
            recent_models+=("$line")
        fi
        if [ ${#recent_models[@]} -ge 5 ]; then
            break
        fi
    done < "$RECENT_MODELS_FILE"
}

# OpenRouter listing helpers.
openrouter_categories=(
    "Programming"
    "Roleplay"
    "Marketing"
    "SEO"
    "Technology"
    "Science"
    "Translation"
    "Legal"
    "Finance"
    "Health"
    "Trivia"
    "Academia"
)

select_openrouter_category() {
    local choice
    echo "Select category (default: Programming):"
    echo "  ${COLOR_YELLOW}b)${COLOR_RESET} Back"
    for i in "${!openrouter_categories[@]}"; do
        printf "  %s%2d)%s %s\n" "$COLOR_YELLOW" "$((i+1))" "$COLOR_RESET" "${openrouter_categories[$i]}"
    done
    read -p "> " choice
    if [[ "$choice" =~ ^[Bb]$ ]]; then
        return 1
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        local idx=$((choice-1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#openrouter_categories[@]} ]; then
            openrouter_category="${openrouter_categories[$idx]}"
            return
        fi
    fi
    openrouter_category="Programming"
}

fetch_openrouter_models() {
    local category=$1
    local cache="/tmp/openrouter-models-${category,,}.json"
    local max_age=3600
    local now
    now=$(date +%s)
    local api_key
    api_key=$(openrouter_api_key)

    if [ -z "$api_key" ]; then
        return 1
    fi

    if [ -f "$cache" ]; then
        local updated
        updated=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
        if [ $((now - updated)) -lt "$max_age" ]; then
            echo "$cache"
            return 0
        fi
    fi

    if curl -fsSL -G "https://openrouter.ai/api/v1/models" \
        -H "Authorization: Bearer ${api_key}" \
        -d "category=${category,,}" \
        -o "$cache"; then
        echo "$cache"
        return 0
    fi

    return 1
}

list_openrouter_models() {
    local category=$1
    local cache
    cache=$(fetch_openrouter_models "$category") || return 1

    python3 - "$cache" <<'PY'
import json
import sys

cache = sys.argv[1]

with open(cache, "r", encoding="utf-8") as handle:
    data = json.load(handle)

matches = data.get("data", [])

for idx, model in enumerate(matches, start=1):
    pricing = model.get("pricing", {})
    completion_raw = pricing.get("completion")
    try:
        completion_value = float(completion_raw)
    except (TypeError, ValueError):
        completion_value = float("inf")
    model["_completion_value"] = completion_value

matches.sort(key=lambda m: m.get("_completion_value", float("inf")))

def per_million(value):
    try:
        return f"${float(value) * 1_000_000:.4g}/M"
    except (TypeError, ValueError):
        return "?"

for idx, model in enumerate(matches, start=1):
    pricing = model.get("pricing", {})
    prompt = per_million(pricing.get("prompt"))
    completion = per_million(pricing.get("completion"))
    model_id = model.get("id", "")
    model_name = model.get("name", model_id)
    print(f"{idx:2d}) {model_id} | {model_name} | prompt {prompt} | completion {completion}")
PY
}

prompt_openrouter_model() {
    openrouter_model_id=""
    while true; do
        read -p "List OpenRouter models now? (${COLOR_YELLOW}y${COLOR_RESET}/${COLOR_YELLOW}N${COLOR_RESET}/${COLOR_YELLOW}b${COLOR_RESET}): " list_choice
        if [[ "$list_choice" =~ ^[Bb]$ ]]; then
            return 1
        fi
        if [[ "$list_choice" =~ ^[Yy]$ ]]; then
            if ! select_openrouter_category; then
                continue
            fi
            if ! list_openrouter_models "$openrouter_category"; then
                echo "OpenRouter list unavailable."
            fi
        fi
        while true; do
            read -p "OpenRouter model id (e.g. anthropic/claude-3.5-sonnet, ${COLOR_YELLOW}b${COLOR_RESET} to back): " openrouter_model_id
            if [[ "$openrouter_model_id" =~ ^[Bb]$ ]]; then
                openrouter_model_id=""
                break
            fi
            if [ -n "$openrouter_model_id" ]; then
                openrouter_model_id="${openrouter_model_id#openrouter/}"
                return 0
            fi
        done
    done
}

# Aider menu with provider selection and recent models.
launch_aider() {
    local aider_choice

    while true; do
        local provider_keys=()
        local provider_labels=()
        if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
            provider_keys+=("deepseek")
            provider_labels+=("DeepSeek")
        fi
        if [ -n "$(openrouter_api_key)" ]; then
            provider_keys+=("openrouter")
            provider_labels+=("OpenRouter")
        fi
        if [ -n "${OLLAMA_API_BASE:-}" ]; then
            provider_keys+=("ollama")
            provider_labels+=("Ollama")
        fi

        if [ ${#provider_keys[@]} -eq 0 ]; then
            echo "No Aider providers configured."
            echo "Set DEEPSEEK_API_KEY, OPENROUTER_API_KEY/OR_API_KEY, or OLLAMA_API_BASE."
            return 1
        fi

        echo -e "\n${COLOR_BOLD}Aider options:${COLOR_RESET}"
        for i in "${!provider_labels[@]}"; do
            echo "  ${COLOR_YELLOW}$((i+1)))${COLOR_RESET} ${provider_labels[$i]}"
        done

        load_recent_models
        if [ ${#recent_models[@]} -gt 0 ]; then
            echo "${COLOR_BOLD}Recent models:${COLOR_RESET}"
            for i in "${!recent_models[@]}"; do
                echo "  ${COLOR_YELLOW}r$((i+1)))${COLOR_RESET} ${recent_models[$i]}"
            done
        fi
        echo "  ${COLOR_YELLOW}b)${COLOR_RESET} Back"
        read -p "> " aider_choice

        if [[ "$aider_choice" =~ ^[Rr][1-5]$ ]]; then
            local r_idx=${aider_choice:1}
            r_idx=$((r_idx-1))
            if [ $r_idx -ge 0 ] && [ $r_idx -lt ${#recent_models[@]} ]; then
                run_aider_model "${recent_models[$r_idx]}"
                return 0
            fi
            continue
        fi

        if ! [[ "$aider_choice" =~ ^[0-9]+$ ]]; then
            if [[ "$aider_choice" =~ ^[Bb]$ ]]; then
                return 1
            fi
            continue
        fi

        local idx=$((aider_choice-1))
        if [ $idx -lt 0 ] || [ $idx -ge ${#provider_keys[@]} ]; then
            continue
        fi

        case "${provider_keys[$idx]}" in
            deepseek)
                run_aider_model "deepseek"
                return 0
                ;;
            openrouter)
                if ! prompt_openrouter_model; then
                    continue
                fi
                if [ -n "$openrouter_model_id" ]; then
                    run_aider_model "openrouter/$openrouter_model_id"
                    return 0
                fi
                continue
                ;;
            ollama)
                read -p "Ollama model id (e.g. llama3.1, ${COLOR_YELLOW}b${COLOR_RESET} to back): " ollama_model_id
                if [[ "$ollama_model_id" =~ ^[Bb]$ ]]; then
                    continue
                fi
                if [ -n "$ollama_model_id" ]; then
                    run_aider_model "ollama/$ollama_model_id"
                    return 0
                fi
                echo "Ollama model id required."
                continue
                ;;
        esac
    done
}

# AI agent selection menu.
ai_menu() {
    local target_dir=$1
    local ai_idx

    while true; do
        echo -e "\n${COLOR_BOLD}Select AI Agent:${COLOR_RESET}"
        echo "  ${COLOR_YELLOW}1)${COLOR_RESET} Gemini  ${COLOR_YELLOW}2)${COLOR_RESET} Codex  ${COLOR_YELLOW}3)${COLOR_RESET} Copilot  ${COLOR_YELLOW}4)${COLOR_RESET} Claude  ${COLOR_YELLOW}5)${COLOR_RESET} Aider  ${COLOR_YELLOW}b)${COLOR_RESET} Back"
        read -p "> " ai_idx
        if [[ "$ai_idx" =~ ^[Bb]$ ]]; then
            return 1
        fi
        if [[ "$ai_idx" =~ ^[1-5]$ ]]; then
            if launch_ai "$target_dir" "$ai_idx"; then
                return 0
            fi
        fi
    done
}

# Tool launcher for the selected project directory.
launch_ai() {
    local target_dir=$1
    local choice=$2
    local launched=1
    clear
    echo "-----------------------------------"
    echo " Location: $target_dir"
    cd "$target_dir" || return
    case $choice in
        1) echo " Tool: Gemini CLI"; gemini; launched=0 ;;
        2) echo " Tool: OpenAI Codex"; codex; launched=0 ;;
        3) echo " Tool: GitHub Copilot"; copilot; launched=0 ;;
        4) echo " Tool: Anthropic Claude Code"; claude; launched=0 ;;
        5) echo " Tool: Aider Chat"; launch_aider; launched=$? ;;
    esac
    if [ $launched -eq 0 ]; then
        echo "-----------------------------------"
        echo "AI Session closed."
        read -p "Press Enter to return to menu or type 'q' to quit: " post_choice
        if [ "$post_choice" = "q" ] || [ "$post_choice" = "Q" ]; then
            exit 0
        fi
        return 0
    fi
    return 1
}

# Main menu loop.
current_dir="$ROOT_DIR"
while true; do
    clear
    # --- OMNI-CLI READABLE LOGO ---
    cat << EOF
${COLOR_CYAN}${COLOR_BOLD}
 ██████  ███    ███ ███    ██ ██        ██████ ██      ██
██    ██ ████  ████ ████   ██ ██       ██      ██      ██
██    ██ ██ ████ ██ ██ ██  ██ ██ █████ ██      ██      ██
██    ██ ██  ██  ██ ██  ██ ██ ██       ██      ██      ██
 ██████  ██      ██ ██   ████ ██        ██████ ███████ ██

${COLOR_DIM}    [ OMNI-CLI ${OMNI_CLI_VERSION} ]      [ STATUS: $(cli_status) ]${COLOR_RESET}
${COLOR_BLUE}---------------------------------------------------------${COLOR_RESET}
EOF

    echo ""
    echo "${COLOR_BOLD}Root:${COLOR_RESET} $ROOT_DIR"
    echo "${COLOR_BOLD}Path:${COLOR_RESET} $(format_path "$current_dir")"
    echo ""
    show_env_summary
    echo ""
    echo "${COLOR_BOLD}Directories:${COLOR_RESET}"
    mapfile -t projects < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
    if [ ${#projects[@]} -gt 0 ]; then
        for i in "${!projects[@]}"; do
            printf "  %s%2d)%s %s\n" "$COLOR_YELLOW" "$((i+1))" "$COLOR_RESET" "${projects[$i]}"
        done
    else
        echo "  ${COLOR_DIM}(no folders yet)${COLOR_RESET}"
    fi

    echo ""
    echo "${COLOR_BOLD}Folders:${COLOR_RESET} ${COLOR_YELLOW}n)${COLOR_RESET} New  ${COLOR_YELLOW}d)${COLOR_RESET} Delete  ${COLOR_YELLOW}u)${COLOR_RESET} Up  ${COLOR_YELLOW}r)${COLOR_RESET} Root"
    echo "${COLOR_BOLD}Other:${COLOR_RESET}   ${COLOR_YELLOW}l)${COLOR_RESET} Launch AI  ${COLOR_YELLOW}k)${COLOR_RESET} API keys status  ${COLOR_YELLOW}q)${COLOR_RESET} Exit"
    echo "-----------------------------------"
    read -p "Select project or action: " choice

    case $choice in
        n|N)
            read -p "Folder name (relative, ${COLOR_YELLOW}b${COLOR_RESET} to back): " p
            if [[ "$p" =~ ^[Bb]$ ]]; then
                continue
            fi
            if [ -n "$p" ] && [[ "$p" != /* ]] && [[ "$p" != *".."* ]]; then
                mkdir -p "$current_dir/$p"
            else
                echo "Invalid folder name."
                sleep 1
            fi
            ;;
        d|D)
            read -p "Project # to delete (${COLOR_YELLOW}b${COLOR_RESET} to back): " d_idx
            if [[ "$d_idx" =~ ^[Bb]$ ]]; then
                continue
            fi
            idx=$((d_idx-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
                rm -rf "$current_dir/${projects[$idx]}"
            fi
            ;;
        l|L)
            ai_menu "$current_dir"
            ;;
        k|K)
            show_env_menu
            ;;
        u|U)
            if [ "$current_dir" != "$ROOT_DIR" ]; then
                current_dir=$(dirname "$current_dir")
            fi
            ;;
        r|R) current_dir="$ROOT_DIR" ;;
        q|Q) exit 0 ;;
        [0-9]*)
            idx=$((choice-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
                current_dir="$current_dir/${projects[$idx]}"
            fi
            ;;
    esac
done
