#!/bin/bash

# ==============================================================================
# OMNI-CLI
# An interactive menu for navigating /data, managing API keys, and launching
# AI tools (Gemini, Codex, Copilot, Claude, OpenCode).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. CONFIGURATION & GLOBAL STATE
# ------------------------------------------------------------------------------

# Safer defaults without breaking interactive flows.
set -u
set -o pipefail

readonly ROOT_DIR="/data"
readonly OMNI_CLI_REPO="/data/omni-cli"
readonly CONFIG_DIR="/config/opencode"
readonly OPENCODE_CONFIG_DIR="${CONFIG_DIR}/config/opencode"
readonly OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
readonly OPENCODE_CACHE_DIR="${CONFIG_DIR}/data"

# Initialize color variables to avoid unbound errors before setup.
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""

# List of API keys and env vars to monitor.
declare -a ALL_ENV_VARS=(
    ANTHROPIC_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY GEMINI_API_KEY
    AICORE_SERVICE_KEY AICORE_DEPLOYMENT_ID AICORE_RESOURCE_GROUP
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_PROFILE
    AWS_BEARER_TOKEN_BEDROCK AWS_WEB_IDENTITY_TOKEN_FILE AWS_ROLE_ARN
    AZURE_RESOURCE_NAME AZURE_COGNITIVE_SERVICES_RESOURCE_NAME
    CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_GATEWAY_ID CLOUDFLARE_API_TOKEN
    GITLAB_INSTANCE_URL GITLAB_TOKEN GITLAB_AI_GATEWAY_URL GITLAB_OAUTH_CLIENT_ID
    GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CLOUD_PROJECT VERTEX_LOCATION
)

# Global state used across menus.
declare -a projects=()
current_dir="$ROOT_DIR"
OMNI_CLI_VERSION=""

# Load persisted environment variables.
if [ -f /etc/profile.d/omni-cli-env.sh ]; then
    # shellcheck source=/dev/null
    . /etc/profile.d/omni-cli-env.sh
fi

# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS
# ------------------------------------------------------------------------------

init_colors() {
    local use_color=0
    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        use_color=1
    fi

    if [ "$use_color" -eq 1 ]; then
        C_RESET=$(tput sgr0)
        C_BOLD=$(tput bold)
        C_DIM=$(tput dim)
        C_RED=$(tput setaf 1)
        C_GREEN=$(tput setaf 2)
        C_YELLOW=$(tput setaf 3)
        C_BLUE=$(tput setaf 4)
        C_CYAN=$(tput setaf 6)
    else
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
    fi
}

# Get version from env or git.
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

# Check if a variable is set (green) or unset (red).
env_status() {
    local name=$1
    if [ -n "${!name:-}" ]; then
        echo "${C_GREEN}set${C_RESET}"
    else
        echo "${C_RED}unset${C_RESET}"
    fi
}

# Mask API keys for display.
mask_api_key() {
    local value=$1
    local length=${#value}
    if [ "$length" -le 4 ]; then
        echo "****"
    elif [ "$length" -le 8 ]; then
        echo "${value:0:2}..."
    else
        echo "${value:0:4}...${value: -4}"
    fi
}

# Format the current path relative to ROOT_DIR with arrows.
format_path() {
    local current_path=$1
    if [ "$current_path" = "$ROOT_DIR" ]; then
        echo "$ROOT_DIR"
        return
    fi

    local relative="${current_path#$ROOT_DIR/}"
    local formatted="$ROOT_DIR"
    local IFS='/'
    read -ra parts <<< "$relative"
    for part in "${parts[@]}"; do
        formatted+=" > $part"
    done
    echo "$formatted"
}

# Wait for user input before returning to the previous menu.
pause_prompt() {
    local prompt=${1:-"Press Enter to go back: "}
    read -r -p "$prompt" _
}

# Check existence of required tools.
check_dependencies() {
    local missing=()
    local tool
    for tool in curl python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "${C_RED}Warning: Missing dependencies: ${missing[*]}${C_RESET}"
        sleep 2
    fi
}

# Validate folder name to prevent traversal/absolute paths.
is_valid_folder_name() {
    local name=$1
    if [ -z "$name" ]; then
        return 1
    fi
    if [[ "$name" == /* ]] || [[ "$name" == *".."* ]]; then
        return 1
    fi
    if [[ "$name" =~ [^a-zA-Z0-9._-] ]]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. STATUS CHECKS
# ------------------------------------------------------------------------------

# Check for installed AI CLI tools.
cli_status() {
    local missing=()
    local tools=(gemini codex copilot claude opencode)
    local tool
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "${C_GREEN}OK${C_RESET}"
    else
        echo "${C_RED}Missing:${C_RESET} ${missing[*]}"
    fi
}

# Check if the local API server is running.
api_server_status() {
    local port="${CODEX_PASSTHROUGH_PORT:-8000}"
    if curl -s "http://localhost:${port}/" >/dev/null 2>&1; then
        echo "${C_GREEN}Running on port ${port}${C_RESET}"
    else
        echo "${C_RED}Not running${C_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 4. OPENROUTER & OPENCODE LOGIC
# ------------------------------------------------------------------------------

# Sync OpenRouter models into OpenCode config for auto-complete.
sync_opencode_openrouter_models() {
    local models_path="${1:-}"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "python3 not found; cannot update OpenCode model list." >&2
        return 1
    fi

    mkdir -p "$OPENCODE_CONFIG_DIR"

    python3 -c '
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
models_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ""

try:
    if models_path:
        payload = json.loads(Path(models_path).read_text())
    else:
        payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)

if not isinstance(payload, dict):
    sys.exit(1)

data = payload.get("data")
if not isinstance(data, list):
    sys.exit(2)

model_ids = sorted({m.get("id") for m in data if m.get("id")})
if not model_ids:
    sys.exit(3)

config = {}
if config_path.exists():
    try:
        config = json.loads(config_path.read_text())
    except Exception:
        config = {}

config.setdefault("$schema", "https://opencode.ai/config.json")
provider = config.setdefault("provider", {})
openrouter = provider.setdefault("openrouter", {})
models = openrouter.setdefault("models", {})

for model_id in model_ids:
    model_entry = models.setdefault(model_id, {})
    options = model_entry.setdefault("options", {})
    provider_opts = options.setdefault("provider", {})
    provider_opts["allow_fallbacks"] = False

config_path.write_text(json.dumps(config, indent=2) + "\n")
' "$OPENCODE_CONFIG_FILE" "$models_path"
}

# Background fetch of models.
prefetch_openrouter_models() {
    local cache_path="${OPENCODE_CACHE_DIR}/openrouter_models.json"
    local cache_tmp="${cache_path}.tmp"

    mkdir -p "$OPENCODE_CACHE_DIR"
    if curl -s "https://openrouter.ai/api/v1/models" \
        -H "Authorization: Bearer ${OPENROUTER_API_KEY:-}" \
        -o "$cache_tmp"; then
        if [ -s "$cache_tmp" ]; then
            mv "$cache_tmp" "$cache_path"
            sync_opencode_openrouter_models "$cache_path" >/dev/null 2>&1 || true
        else
            rm -f "$cache_tmp"
        fi
    else
        rm -f "$cache_tmp"
    fi
}

# Format the model list for selection (sorted by avg input/output price).
format_model_list_python() {
    python3 -c '
import json
import sys
try:
    content = sys.stdin.read()
    if not content:
        sys.exit(0)
    payload = json.loads(content)
except Exception as e:
    print(f"DEBUG: JSON parse error: {e}", file=sys.stderr)
    sys.exit(0)

if not isinstance(payload, dict):
    print("DEBUG: Payload is not a dictionary", file=sys.stderr)
    sys.exit(0)

if "error" in payload:
    err = payload.get("error", {})
    msg = err.get("message", "Unknown OpenRouter error")
    print(f"DEBUG: OpenRouter API error: {msg}", file=sys.stderr)
    sys.exit(0)

data = payload.get("data", [])
if not isinstance(data, list):
    print("DEBUG: \"data\" key is not a list", file=sys.stderr)
    sys.exit(0)

rows = []
for item in data:
    model_id = item.get("id")
    pricing = item.get("pricing")
    if not model_id or not isinstance(pricing, dict):
        continue

    completion_val = pricing.get("completion")
    if completion_val is None:
        continue

    try:
        price = float(completion_val)
        prompt_val = pricing.get("prompt", 0)
        prompt_price = float(prompt_val) if prompt_val is not None else 0.0
    except (ValueError, TypeError):
        continue

    if price < 0 or prompt_price < 0:
        continue

    out_price = price * 1_000_000
    in_price = prompt_price * 1_000_000
    avg_price = (out_price + in_price) / 2
    rows.append((avg_price, out_price, in_price, model_id))

for avg_p, out_p, in_p, mid in sorted(rows, key=lambda x: x[0]):
    in_str = f"{in_p:.6f}"
    print(f"{out_p:.6f}\t{in_str}\t{mid}")
'
}

# Select an OpenRouter model. Return 2 when the user backs out.
select_openrouter_model() {
    local target_var=$1
    if [ -z "$target_var" ]; then
        echo "Missing output variable for OpenRouter model selection." >&2
        return 1
    fi

    printf -v "$target_var" '%s' ""

    local answer
    local categories=(programming roleplay marketing seo technology science translation legal finance health trivia academia)

    while true; do
        read -r -p "Load latest OpenRouter models? (y/N): " answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            return 1
        fi

        while true; do
            local cat_choice
            local curl_args=()

            echo -e "\n${C_BOLD}OpenRouter Categories:${C_RESET}"
            for i in "${!categories[@]}"; do
                printf "  %s%2d)%s %s\n" "$C_YELLOW" "$((i+1))" "$C_RESET" "${categories[$i]^}"
            done
            echo "  ${C_YELLOW} a)${C_RESET} All"
            echo "  ${C_YELLOW} b)${C_RESET} Back"

            read -r -p "Select category: " cat_choice

            if [[ "$cat_choice" =~ ^[Bb]$ ]]; then
                return 2
            fi

            if [[ "$cat_choice" =~ ^[0-9]+$ ]]; then
                local idx=$((cat_choice-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#categories[@]} ]; then
                    curl_args=(-G -d "category=${categories[$idx]}")
                else
                    echo "${C_RED}Invalid category.${C_RESET}"
                    continue
                fi
            elif [[ ! "$cat_choice" =~ ^[Aa]$ ]] && [ -n "$cat_choice" ]; then
                echo "${C_RED}Invalid selection.${C_RESET}"
                continue
            fi

            echo "Fetching models..."
            local models_json
            models_json=$(curl -s "${curl_args[@]}" "https://openrouter.ai/api/v1/models" \
                -H "Authorization: Bearer ${OPENROUTER_API_KEY:-}")

            if [ -z "$models_json" ]; then
                echo "${C_RED}Failed to fetch OpenRouter models (empty response).${C_RESET}"
                continue
            fi

            printf '%s' "$models_json" | sync_opencode_openrouter_models >/dev/null 2>&1 || true

            local model_list
            model_list=$(printf '%s' "$models_json" | format_model_list_python)

            if [ -z "$model_list" ]; then
                echo "${C_RED}No models found with valid pricing.${C_RESET}"
                if [[ "$models_json" == *"error"* ]]; then
                    echo "${C_DIM}Response: $(echo "$models_json" | cut -c 1-100)...${C_RESET}"
                fi
                continue
            fi

            local ids=()
            local descriptions=()
            while IFS=$'\t' read -r p_out p_in mid; do
                ids+=("$mid")
                descriptions+=("\$$p_in/M in, \$$p_out/M out")
            done <<< "$model_list"

            while true; do
                echo -e "\n${C_BOLD}Available Models (Sorted by Avg Price):${C_RESET}"
                for i in "${!ids[@]}"; do
                    printf "  %s%2d)%s %-35s %s(%s)%s\n" \
                        "$C_YELLOW" "$((i+1))" "$C_RESET" \
                        "${ids[$i]}" \
                        "$C_DIM" "${descriptions[$i]}" "$C_RESET"
                done

                local model_idx
                read -r -p "Select model # (${C_YELLOW}b${C_RESET} to back): " model_idx
                if [[ "$model_idx" =~ ^[Bb]$ ]]; then
                    break
                fi

                local midx=$((model_idx-1))
                if [ $midx -ge 0 ] && [ $midx -lt ${#ids[@]} ]; then
                    printf -v "$target_var" '%s' "${ids[$midx]}"
                    return 0
                fi
                echo "${C_RED}Invalid model selection.${C_RESET}"
            done
        done
    done
}

launch_opencode() {
    if ! command -v opencode >/dev/null 2>&1; then
        echo "${C_RED}OpenCode CLI not found.${C_RESET}"
        return 1
    fi

    local xdg_env=(
        XDG_CONFIG_HOME="${CONFIG_DIR}/config"
        XDG_DATA_HOME="${CONFIG_DIR}/data"
        XDG_CACHE_HOME="${CONFIG_DIR}/cache"
        XDG_STATE_HOME="${CONFIG_DIR}/state"
    )

    mkdir -p "${CONFIG_DIR}"/{config,data,cache,state}

    local selected_model=""
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        if select_openrouter_model selected_model; then
            [[ "$selected_model" != openrouter/* ]] && selected_model="openrouter/$selected_model"

            # Update small_model in config to match selected model
            python3 -c '
import json, sys
path = sys.argv[1]
model = sys.argv[2]
try:
    with open(path, "r") as f:
        config = json.load(f)
    config["small_model"] = model
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
except Exception:
    pass
' "$OPENCODE_CONFIG_FILE" "$selected_model"

            env "${xdg_env[@]}" opencode -m "$selected_model"
            return $?
        else
            local select_rc=$?
            if [ $select_rc -eq 2 ]; then
                return 2
            fi
        fi
    fi

    env "${xdg_env[@]}" opencode
    return $?
}

# ------------------------------------------------------------------------------
# 5. MENUS & UI
# ------------------------------------------------------------------------------

show_env_summary() {
    local enabled=()
    local var
    for var in "${ALL_ENV_VARS[@]}"; do
        if [[ "$var" == *_API_KEY ]] && [ -n "${!var:-}" ]; then
            enabled+=("$var")
        fi
    done

    if [ ${#enabled[@]} -eq 0 ]; then
        echo "${C_BOLD}API keys status:${C_RESET} ${C_DIM}(none set)${C_RESET}"
    else
        echo "${C_BOLD}API keys status (enabled):${C_RESET}"
        for var in "${enabled[@]}"; do
            echo "  ${C_GREEN}$var${C_RESET}: $(mask_api_key "${!var}")"
        done
    fi
}

show_full_env_menu() {
    clear
    echo "${C_BOLD}API keys status (all):${C_RESET}"
    for var in "${ALL_ENV_VARS[@]}"; do
        printf "  %-35s %s\n" "${C_YELLOW}${var}:${C_RESET}" "$(env_status "$var")"
    done
    echo ""
    pause_prompt
}

show_api_menu() {
    clear
    local port="${CODEX_PASSTHROUGH_PORT:-8000}"
    local status
    status=$(api_server_status)

    echo "${C_BOLD}API Server Status:${C_RESET}"
    echo "  ${C_YELLOW}Status:${C_RESET}   $status"
    echo "  ${C_YELLOW}Port:${C_RESET}     $port"
    echo "  ${C_YELLOW}Endpoints:${C_RESET}"
    echo "    - http://localhost:${port}/"
    echo "    - http://localhost:${port}/v1/models"
    echo "    - http://localhost:${port}/v1/chat/completions"
    echo ""
    echo "${C_BOLD}Configuration:${C_RESET}"
    echo "  ${C_YELLOW}CODEX_PASSTHROUGH_PORT:${C_RESET} ${CODEX_PASSTHROUGH_PORT:-8000}"
    echo "  ${C_YELLOW}CODEX_TIMEOUT_SECONDS:${C_RESET}  ${CODEX_TIMEOUT_SECONDS:-300}"
    echo "  ${C_YELLOW}OPENROUTER_API_KEY:${C_RESET}     $(env_status OPENROUTER_API_KEY)"
    echo ""
    echo "${C_BOLD}Test Command:${C_RESET}"
    echo "  curl http://localhost:${port}/v1/chat/completions \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"model\":\"codex-default\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello!\"}]}'"
    echo ""
    pause_prompt
}

launch_ai_wrapper() {
    local target_dir=$1
    local ai_choice=$2

    clear
    echo "-----------------------------------"
    echo " Working Directory: $target_dir"

    if ! cd "$target_dir"; then
        echo "${C_RED}Error: Could not access directory.${C_RESET}"
        sleep 2
        return 1
    fi

    local tool_name=""
    local tool_rc=0
    case $ai_choice in
        1) tool_name="Gemini CLI"; gemini; tool_rc=$? ;;
        2) tool_name="OpenAI Codex"; codex; tool_rc=$? ;;
        3) tool_name="GitHub Copilot"; copilot; tool_rc=$? ;;
        4) tool_name="Anthropic Claude"; claude; tool_rc=$? ;;
        5) tool_name="OpenCode"; launch_opencode; tool_rc=$? ;;
    esac

    if [ "$ai_choice" -eq 5 ] && [ $tool_rc -eq 2 ]; then
        return
    fi

    echo "-----------------------------------"
    echo "$tool_name session closed."
    read -r -p "Press Enter to return to menu (or 'q' to quit): " post_choice
    if [[ "$post_choice" =~ ^[Qq]$ ]]; then
        exit 0
    fi
}

ai_menu() {
    local target_dir=$1
    while true; do
        echo -e "\n${C_BOLD}Select AI Agent:${C_RESET}"
        echo "  ${C_YELLOW}1)${C_RESET} Gemini"
        echo "  ${C_YELLOW}2)${C_RESET} Codex"
        echo "  ${C_YELLOW}3)${C_RESET} Copilot"
        echo "  ${C_YELLOW}4)${C_RESET} Claude"
        echo "  ${C_YELLOW}5)${C_RESET} OpenCode"
        echo "  ${C_YELLOW}b)${C_RESET} Back"

        local choice
        read -r -p "> " choice

        if [[ "$choice" =~ ^[Bb]$ ]]; then
            return
        fi
        if [[ "$choice" =~ ^[1-5]$ ]]; then
            launch_ai_wrapper "$target_dir" "$choice"
            return
        fi
    done
}

load_projects() {
    projects=()
    mapfile -t projects < <(find "$current_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
}

draw_main_menu() {
    clear
    cat << OMNI_MENU
${C_CYAN}${C_BOLD}
 ██████  ███    ███ ███    ██ ██        ██████ ██      ██
██    ██ ████  ████ ████   ██ ██       ██      ██      ██
██    ██ ██ ████ ██ ██ ██  ██ ██ █████ ██      ██      ██
██    ██ ██  ██  ██ ██  ██ ██ ██       ██      ██      ██
 ██████  ██      ██ ██   ████ ██        ██████ ███████ ██

${C_DIM}    [ OMNI-CLI ${OMNI_CLI_VERSION} ]      [ STATUS: $(cli_status) ]${C_RESET}
${C_BLUE}---------------------------------------------------------${C_RESET}
OMNI_MENU
    echo ""
    echo "${C_BOLD}Root:${C_RESET} $ROOT_DIR"
    echo "${C_BOLD}Path:${C_RESET} $(format_path "$current_dir")"
    echo ""
    show_env_summary
    echo ""
    echo "${C_BOLD}Directories:${C_RESET}"

    load_projects
    if [ ${#projects[@]} -gt 0 ]; then
        for i in "${!projects[@]}"; do
            printf "  %s%2d)%s %s\n" "$C_YELLOW" "$((i+1))" "$C_RESET" "${projects[$i]}"
        done
    else
        echo "  ${C_DIM}(no folders yet)${C_RESET}"
    fi

    echo ""
    echo "${C_BOLD}Actions:${C_RESET} ${C_YELLOW}n)${C_RESET} New Folder  ${C_YELLOW}d)${C_RESET} Delete Folder  ${C_YELLOW}b)${C_RESET} Back  ${C_YELLOW}r)${C_RESET} Root"
    echo "${C_BOLD}Tools:${C_RESET}   ${C_YELLOW}l)${C_RESET} Launch AI   ${C_YELLOW}k)${C_RESET} API Keys       ${C_YELLOW}a)${C_RESET} API Server  ${C_YELLOW}q)${C_RESET} Exit"
    echo "-----------------------------------"
}

# ------------------------------------------------------------------------------
# 6. MAIN LOOP
# ------------------------------------------------------------------------------

prompt_new_folder() {
    local folder_name
    read -r -p "Folder name (relative): " folder_name
    if [[ "$folder_name" =~ ^[Bb]$ ]] || [ -z "$folder_name" ]; then
        return
    fi

    if ! is_valid_folder_name "$folder_name"; then
        echo "${C_RED}Invalid folder name. Use alphanumeric, dot, underscore, or dash.${C_RESET}"
        sleep 2
        return
    fi

    mkdir -p "$current_dir/$folder_name"
}

prompt_delete_folder() {
    local delete_idx
    read -r -p "Project # to delete (${C_YELLOW}b${C_RESET} to back): " delete_idx
    if [[ "$delete_idx" =~ ^[Bb]$ ]]; then
        return
    fi

    if [[ "$delete_idx" =~ ^[0-9]+$ ]]; then
        local idx=$((delete_idx-1))
        if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
            local target_to_del="${projects[$idx]}"
            read -r -p "${C_RED}Are you sure you want to DELETE '$target_to_del'? (yes/N): ${C_RESET}" confirm
            if [[ "$confirm" == "yes" ]]; then
                rm -rf "$current_dir/$target_to_del"
            fi
        fi
    fi
}

select_project_by_index() {
    local choice=$1
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        return
    fi

    local idx=$((choice-1))
    if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
        current_dir="$current_dir/${projects[$idx]}"
    fi
}

menu_loop() {
    while true; do
        draw_main_menu
        local choice
        read -r -p "Select project or action: " choice

        case $choice in
            n|N)
                prompt_new_folder
                ;;
            d|D)
                prompt_delete_folder
                ;;
            l|L)
                ai_menu "$current_dir"
                ;;
            k|K)
                show_full_env_menu
                ;;
            a|A)
                show_api_menu
                ;;
            b|B)
                if [ "$current_dir" != "$ROOT_DIR" ]; then
                    current_dir=$(dirname "$current_dir")
                fi
                ;;
            r|R)
                current_dir="$ROOT_DIR"
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            [0-9]*)
                select_project_by_index "$choice"
                ;;
            *)
                ;;
        esac
    done
}

main() {
    init_colors
    OMNI_CLI_VERSION="$(get_version)"
    current_dir="$ROOT_DIR"

    check_dependencies

    if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        prefetch_openrouter_models >/dev/null 2>&1 &
    fi

    menu_loop
}

main "$@"
