#!/bin/bash

launch_ai() {
    local project=$1
    local choice=$2
    clear
    echo "-----------------------------------"
    echo " Project: $project"
    case $choice in
        1) echo " Tool: Gemini CLI"; gemini ;;
        2) echo " Tool: OpenAI Codex"; codex ;;
        3) echo " Tool: GitHub Copilot"; copilot ;;
    esac
    echo "-----------------------------------"
    echo "AI Session closed. Entering shell..."
    bash
}

while true; do
    clear
    # --- OMNI-CLI READABLE LOGO ---
    cat << "EOF"
  ____  __  __ _   _ ___         ____ _      ___
 / __ \|  \/  | \ | |_ _|       / ___| |    |_ _|
| |  | | |\/| |  \| || |  ____ | |   | |     | |
| |__| | |  | | |\  || | |____|| |___| |___  | |
 \____/|_|  |_|_| \_|___|       \____|_____|___|

 [ NEURAL INTERFACE v1.0 ]      [ STATUS: ONLINE ]
--------------------------------------------------
EOF

    echo ""
    echo "Available projects in /data:"
    projects=($(ls -1 /data/ 2>/dev/null))
    if [ ${#projects[@]} -gt 0 ]; then
        for i in "${!projects[@]}"; do
            echo "  $((i+1))) ${projects[$i]}"
        done
    else
        echo "  (no projects yet)"
    fi

    echo ""
    echo "Actions: n) New  d) Delete  q) Exit"
    echo "-----------------------------------"
    read -p "Select project or action: " choice

    case $choice in
        n|N) read -p "Name: " p; [ -n "$p" ] && mkdir -p "/data/$p" ;;
        d|D)
            read -p "Project # to delete: " d_idx
            idx=$((d_idx-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
                rm -rf "/data/${projects[$idx]}"
            fi
            ;;
        q|Q) exit 0 ;;
        [0-9]*)
            idx=$((choice-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#projects[@]} ]; then
                project="${projects[$idx]}"
                cd "/data/$project"
                echo -e "\nSelect AI Agent:\n1) Gemini  2) Codex  3) Copilot  b) Back"
                read -p "> " ai_idx
                [[ "$ai_idx" =~ ^[1-3]$ ]] && launch_ai "$project" "$ai_idx"
            fi
            ;;
    esac
done
