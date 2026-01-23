#!/bin/bash

export NPM_CONFIG_PREFIX="/config/npm"
export NODE_OPTIONS="${NODE_OPTIONS:-} --no-deprecation"

if [ -d /config/npm/bin ]; then
    case ":$PATH:" in
        *":/config/npm/bin:"*) ;;
        *) export PATH="/config/npm/bin:$PATH" ;;
    esac
fi
