#!/bin/bash

# Load persisted environment variables created by the entrypoint.
if [ -f /etc/profile.d/omni-cli-env.sh ]; then
    . /etc/profile.d/omni-cli-env.sh
fi

# Core paths.
ROOT_DIR="/data"
OMNI_CLI_REPO="/data/omni-cli"

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
    ANTHROPIC_API_KEY
    OPENAI_API_KEY
    OPENROUTER_API_KEY
    GEMINI_API_KEY
    CEREBRAS_API_KEY
    HF_TOKEN
    VERTEXAI_PROJECT
    VERTEXAI_LOCATION
    GROQ_API_KEY
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_REGION
    AWS_PROFILE
    AWS_BEARER_TOKEN_BEDROCK
    AZURE_OPENAI_API_ENDPOINT
    AZURE_OPENAI_API_KEY
    AZURE_OPENAI_API_VERSION
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
    local tools=(gemini codex copilot claude)
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if ! command -v crush >/dev/null 2>&1; then
        missing+=("crush")
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        echo "${COLOR_GREEN}OK${COLOR_RESET}"
    else
        echo "${COLOR_RED}Missing:${COLOR_RESET} ${missing[*]}"
    fi
}

# Check if API server is running.
api_server_status() {
    local port="${CODEX_PASSTHROUGH_PORT:-8000}"
    if curl -s "http://localhost:${port}/" >/dev/null 2>&1; then
        echo "${COLOR_GREEN}Running on port ${port}${COLOR_RESET}"
    else
        echo "${COLOR_RED}Not running${COLOR_RESET}"
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

show_api_menu() {
    clear
    local port="${CODEX_PASSTHROUGH_PORT:-8000}"
    local status=$(api_server_status)
    
    echo "${COLOR_BOLD}API Server Status:${COLOR_RESET}"
    echo "  ${COLOR_YELLOW}Status:${COLOR_RESET} $status"
    echo "  ${COLOR_YELLOW}Port:${COLOR_RESET} $port"
    echo "  ${COLOR_YELLOW}Health:${COLOR_RESET} http://localhost:${port}/"
    echo "  ${COLOR_YELLOW}Models:${COLOR_RESET} http://localhost:${port}/v1/models"
    echo "  ${COLOR_YELLOW}Endpoint:${COLOR_RESET} http://localhost:${port}/v1/chat/completions"
    echo ""
    echo "${COLOR_BOLD}Environment Variables:${COLOR_RESET}"
    echo "  ${COLOR_YELLOW}CODEX_PASSTHROUGH_PORT:${COLOR_RESET} ${CODEX_PASSTHROUGH_PORT:-8000}"
    echo "  ${COLOR_YELLOW}CODEX_TIMEOUT_SECONDS:${COLOR_RESET} ${CODEX_TIMEOUT_SECONDS:-300}"
    echo "  ${COLOR_YELLOW}OPENROUTER_API_KEY:${COLOR_RESET} $(env_status OPENROUTER_API_KEY)"
    echo ""
    echo "${COLOR_BOLD}Usage Example:${COLOR_RESET}"
    echo "  curl http://localhost:${port}/v1/chat/completions \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"model\":\"codex-default\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
    echo ""
    read -p "Press Enter to go back: " _
}

# Crush helper.
launch_crush() {
    if command -v crush >/dev/null 2>&1; then
        XDG_CONFIG_HOME="/config/crush/config" \
        XDG_DATA_HOME="/config/crush/data" \
        XDG_CACHE_HOME="/config/crush/cache" \
        crush
        return $?
    fi
    echo "Crush CLI not found."
    return 1
}

# AI agent selection menu.
ai_menu() {
    local target_dir=$1
    local ai_idx

    while true; do
        echo -e "\n${COLOR_BOLD}Select AI Agent:${COLOR_RESET}"
        echo "  ${COLOR_YELLOW}1)${COLOR_RESET} Gemini  ${COLOR_YELLOW}2)${COLOR_RESET} Codex  ${COLOR_YELLOW}3)${COLOR_RESET} Copilot  ${COLOR_YELLOW}4)${COLOR_RESET} Claude  ${COLOR_YELLOW}5)${COLOR_RESET} Crush  ${COLOR_YELLOW}b)${COLOR_RESET} Back"
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
        5) echo " Tool: Crush"; launch_crush; launched=$? ;;
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
    echo "${COLOR_BOLD}Other:${COLOR_RESET}   ${COLOR_YELLOW}l)${COLOR_RESET} Launch AI  ${COLOR_YELLOW}k)${COLOR_RESET} API keys status  ${COLOR_YELLOW}a)${COLOR_RESET} API Server  ${COLOR_YELLOW}q)${COLOR_RESET} Exit"
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
        a|A)
            show_api_menu
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
