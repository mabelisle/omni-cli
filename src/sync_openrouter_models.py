#!/usr/bin/env python3
"""
OpenRouter model sync utility for OpenCode configuration.
Syncs OpenRouter models into OpenCode config for auto-complete.
"""

import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("Usage: sync_openrouter_models.py <config_file> [models_file]", file=sys.stderr)
        sys.exit(1)

    config_path = Path(sys.argv[1])
    models_path = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        if models_path:
            payload = json.loads(Path(models_path).read_text())
        else:
            payload = json.load(sys.stdin)
    except Exception as e:
        print(f"Error reading models data: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(payload, dict):
        print("Invalid payload format", file=sys.stderr)
        sys.exit(1)

    data = payload.get("data")
    if not isinstance(data, list):
        print("Invalid data format", file=sys.stderr)
        sys.exit(2)

    model_ids = sorted({m.get("id") for m in data if m.get("id")})
    if not model_ids:
        print("No models found", file=sys.stderr)
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

    try:
        config_path.write_text(json.dumps(config, indent=2) + "\n")
    except Exception as e:
        print(f"Error writing config file: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()