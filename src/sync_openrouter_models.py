#!/usr/bin/env python3
"""
OpenRouter model sync utility for OpenCode configuration.
Syncs OpenRouter models into OpenCode config for auto-complete.
"""

import json
import sys
from pathlib import Path


def sync_models(config_file, models_data):
    """
    Sync OpenRouter models into OpenCode configuration.
    
    Args:
        config_file: Path to OpenCode config file
        models_data: JSON data containing OpenRouter models
    
    Returns:
        True if successful, False otherwise
    """
    try:
        payload = json.loads(models_data) if isinstance(models_data, str) else models_data
        
        if not isinstance(payload, dict):
            return False
        
        data = payload.get("data")
        if not isinstance(data, list):
            return False
        
        model_ids = sorted({m.get("id") for m in data if m.get("id")})
        if not model_ids:
            return False
        
        config_path = Path(config_file)
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
        return True
        
    except Exception as e:
        print(f"Error syncing models: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: sync_openrouter_models.py <config_file> [models_file]", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    models_file = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        if models_file:
            models_data = Path(models_file).read_text()
        else:
            models_data = sys.stdin.read()
    except Exception as e:
        print(f"Error reading models data: {e}", file=sys.stderr)
        sys.exit(1)

    if not sync_models(config_file, models_data):
        sys.exit(1)


if __name__ == "__main__":
    main()