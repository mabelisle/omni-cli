# AGENTS.md - Omni-CLI Repository Guidelines

This file provides guidance for AI coding agents working on the Omni-CLI project.

## 📦 Project Structure

### Core Files
- **Dockerfile** - Multi-stage build (base → builder → final) with Node.js 25-slim
- **entrypoint.sh** - Container initialization (UID/GID mapping, SSH keys, volume ownership, API server startup)
- **omni-cli.sh** - Menu-driven interactive CLI interface (main user-facing script)
- **omni-env.sh** - Environment variable setup for npm and Node.js
- **api.js** - OpenAI-compatible API server for Codex/Gemini passthrough
- **src/sync_openrouter_models.py** - Python utility to sync OpenRouter models into OpenCode config
- **.gitlab-ci.yml** - GitLab Auto-DevOps configuration
- **README.md** - User-facing documentation

### Configuration Directories (mounted volumes)
- `/data` - Workspace storage (projects, repos)
- `/config` - Tool configs (npm cache, CLI auth tokens)
  - `/config/gemini` - Gemini CLI config
  - `/config/codex` - Codex CLI config
  - `/config/copilot` - Copilot CLI config
  - `/config/claude` - Claude CLI config
  - `/config/npm` - Global npm packages and cache
  - `/config/opencode` - OpenCode config, data, cache

### Installed CLI Tools (in container)
- `@google/gemini-cli` - Gemini CLI
- `@openai/codex` - OpenAI Codex CLI
- `@github/copilot` - GitHub Copilot CLI
- `@anthropic-ai/claude-code` - Anthropic Claude CLI
- `opencode-ai` - OpenCode CLI

## 🛠️ Build, Lint, and Test Commands

### Build Commands
```bash
# Build the Docker image locally
docker build -t omni-cli .

# Build with custom version tag
docker build -t omni-cli:latest --build-arg OMNI_CLI_VERSION=v1.0.0 .

# Build with custom SSH password
docker build -t omni-cli --build-arg USER_PASS=newpassword .
```

### Run Commands
```bash
# Run with Docker Compose (recommended)
docker-compose up -d

# Run with Docker CLI (persistent volumes)
docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -p 8000:8000 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  -e OPENAI_API_KEY=sk-... \
  -e GEMINI_API_KEY=AIza... \
  omni-cli

# Connect to running container
ssh omni@localhost -p 2222
# Password: changeme (or whatever was set during build)
```

### API Server Commands
```bash
# API server runs automatically in container on port 8000 (default)
# Test the API from host:
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"codex-default","messages":[{"role":"user","content":"Hello!"}]}'

# List available models
curl http://localhost:8000/v1/models
```

### Testing Commands
```bash
# Smoke test: Verify container is healthy
docker exec omni-cli cat /etc/omni-cli-version

# Test SSH connectivity
ssh omni@localhost -p 2222 "echo 'SSH OK'"

# Test individual CLI tools inside container
docker exec -it omni-cli bash -c "gemini --version"
docker exec -it omni-cli bash -c "codex --help"
docker exec -it omni-cli bash -c "opencode --version"

# Test API server logs
docker exec omni-cli cat /tmp/omni-codex-server.log

# Test environment variables are persisted
docker exec omni-cli bash -c 'echo $OPENAI_API_KEY'

# Run Python sync script manually
docker exec omni-cli python3 /data/omni-cli/src/sync_openrouter_models.py /config/opencode/config/opencode.json

# Test shell scripts with shellcheck (if installed locally)
shellcheck omni-cli.sh entrypoint.sh omni-env.sh
```

### Local Development (without Docker)
```bash
# Run API server locally (for testing api.js changes)
node api.js --help
node api.js -C /tmp/workspace

# Run Python sync script locally
python3 src/sync_openrouter_models.py /tmp/test-config.json /tmp/models.json
```

## 📝 Code Style Guidelines

### General Principles
- **Favor small, readable functions** - Keep functions under 50 lines where possible
- **Explicit over implicit** - Use clear variable names and avoid magic numbers
- **Defensive programming** - Validate inputs, handle errors gracefully
- **No secrets in code** - Never hardcode API keys or credentials

### Shell Scripts (Bash)
**File Headers:**
```bash
#!/bin/bash
set -euo pipefail  # Strict mode: exit on error, undefined vars, pipe failures
```

**Naming Conventions:**
- **Functions:** lowercase with underscores (`launch_ai`, `check_dependencies`)
- **Variables:** lowercase with underscores (`current_dir`, `target_var`)
- **Constants:** uppercase with underscores (`ROOT_DIR`, `OMNI_CLI_VERSION`)
- **Private functions:** add underscore prefix (`_internal_helper`)

**Indentation & Formatting:**
- 4-space indentation (no tabs)
- Align opening braces on same line:
  ```bash
  function_name() {
      # body
  }
  ```
- Use `local` for function-scoped variables
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals (more features than `[ ]`)

**Error Handling:**
```bash
# Check command existence
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found" >&2
    return 1
fi

# Validate inputs
if [ -z "$input" ]; then
    echo "Error: input required" >&2
    return 1
fi

# Use proper exit codes
return 0  # Success
return 1  # Failure
```

**String Manipulation:**
```bash
# Prefer parameter expansion over external commands
local relative="${current_path#$ROOT_DIR/}"  # Remove prefix
local basename="${filename%.*}"              # Remove suffix

# Use printf for formatting
printf "  %s)%s %s\n" "$C_YELLOW" "$C_RESET" "$description"
```

**Command Execution:**
```bash
# Capture output safely
if ! output=$(command 2>&1); then
    echo "Command failed: $output" >&2
    return 1
fi

# Use long options for clarity
curl -fsSL "https://example.com"  # Fail silently, follow redirects, show errors

# Avoid unnecessary pipes when builtins exist
# Good: mapfile -t array < <(find ...)
# Bad: find ... | while read -r line; do array+=("$line"); done
```

### JavaScript (Node.js - api.js)
**File Headers:**
```javascript
#!/usr/bin/env node
"use strict";
```

**Naming Conventions:**
- **Functions:** camelCase (`buildPromptFromMessages`, `resolveProvider`)
- **Variables:** camelCase (`openrouterModelState`, `workspaceDir`)
- **Constants:** UPPER_SNAKE_CASE (`CODEX_TIMEOUT_SECONDS`, `PORT`)
- **Classes:** PascalCase (`HttpError`, `AgentError`)

**Formatting:**
- 4-space indentation
- Double quotes for strings (consistent with JSON)
- Trailing commas in multiline objects/arrays
- Use `const` by default, `let` only when reassignment is needed

**Error Handling:**
```javascript
// Use custom error classes
class HttpError extends Error {
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}

// Validate inputs with clear errors
if (!Array.isArray(messages)) {
    throw new HttpError(400, "Messages must be an array");
}

// Async/await with try/catch
try {
    const result = await someAsyncOperation();
} catch (err) {
    console.error("Operation failed:", err.message);
    throw;
}
```

**Async Patterns:**
```javascript
// Prefer async/await over callbacks
async function handleRequest(req, res) {
    try {
        const data = await parseBody(req);
        jsonResponse(res, 200, data);
    } catch (err) {
        jsonResponse(res, 400, { detail: err.message });
    }
}

// Promise.all for parallel operations
const [codex, gemini] = await Promise.all([
    verifyModels(codexModels, "codex"),
    verifyModels(geminiModels, "gemini"),
]);
```

### Python (sync_openrouter_models.py)
**File Headers:**
```python
#!/usr/bin/env python3
"""
OpenRouter model sync utility for OpenCode configuration.
"""

import json
import sys
from pathlib import Path
```

**Naming Conventions:**
- **Functions:** snake_case (`sync_models`, `main`)
- **Variables:** snake_case (`config_file`, `model_ids`)
- **Constants:** UPPER_SNAKE_CASE (`MAX_RETRIES`)
- **Classes:** PascalCase (`ModelSyncError`)

**Formatting:**
- 4-space indentation (PEP 8)
- Use `pathlib.Path` for filesystem operations
- Type hints where practical (Python 3.6+)

**Error Handling:**
```python
try:
    config = json.loads(config_path.read_text())
except (FileNotFoundError, json.JSONDecodeError) as e:
    print(f"Error reading config: {e}", file=sys.stderr)
    config = {}
```

**Context Managers:**
```python
# Use context managers for file operations
with open(path, "r") as f:
    data = json.load(f)

# Or with pathlib (preferred)
from pathlib import Path
content = Path(file).read_text()
```

### Environment Variables
**Naming:**
- Use uppercase with underscores (`CODEX_PASSTHROUGH_PORT`)
- Provide sensible defaults in scripts
- Document all supported variables

**Validation:**
```bash
# Validate required env vars
if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo "Warning: OPENAI_API_KEY not set" >&2
fi

# Parse with defaults
PORT="${CODEX_PASSTHROUGH_PORT:-8000}"
TIMEOUT="${CODEX_TIMEOUT_SECONDS:-300}"
```

### API Design (api.js)
**OpenAI-Compatible Responses:**
```javascript
// Standard response structure
{
    "id": "chatcmpl-abc123",
    "object": "chat.completion",
    "created": 1234567890,
    "model": "codex-default",
    "choices": [{
        "index": 0,
        "message": {
            "role": "assistant",
            "content": "Response text"
        },
        "finish_reason": "stop"
    }],
    "usage": {
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0
    }
}
```

**HTTP Status Codes:**
- 200: Success
- 400: Invalid request (bad JSON, missing fields)
- 404: Endpoint not found
- 500: CLI execution failed
- 504: Request timeout

**Logging:**
- Use `console.log` for informational messages
- Use `console.warn` for non-fatal issues
- Use `console.error` for errors
- Include context (model, provider, workspace) in logs

## 📋 Specific Conventions

### Shell Script Patterns

**Menu/Loop Structure:**
```bash
while true; do
    draw_menu
    read -r -p "> " choice
    
    case $choice in
        q|Q) echo "Goodbye!"; exit 0 ;;
        *) ;;  # Ignore invalid input
    esac
done
```

**Safe Directory Navigation:**
```bash
if ! cd "$target_dir"; then
    echo "Error: Could not access directory" >&2
    return 1
fi
```

**Input Validation:**
```bash
is_valid_folder_name() {
    local name=$1
    if [ -z "$name" ]; then
        return 1
    fi
    if [[ "$name" == /* ]] || [[ "$name" == *".."* ]]; then
        return 1  # Prevent path traversal
    fi
    return 0
}
```

**Array Handling:**
```bash
# Declare array
declare -a items=()

# Add items
items+=("value1")
items+=("value2")

# Iterate
for item in "${items[@]}"; do
    echo "$item"
done

# Map from command output
mapfile -t projects < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
```

### JavaScript Patterns

**Promise-based CLI execution:**
```javascript
function spawnCli(command, args, timeoutMs, options = {}) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, {
            stdio: ["ignore", "pipe", "pipe"],
            cwd: options.cwd,
        });
        // ... handle stdout, stderr, timeout, close
    });
}
```

**Temporary Workspace Management:**
```javascript
function createTempWorkspace() {
    const prefix = path.join(WORKSPACE_ROOT, "codex_workspace_");
    return fs.mkdtempSync(prefix);
}

// Always cleanup in finally block
try {
    // ... work in workspace
} finally {
    removeTempWorkspace(workspaceDir);
}
```

**Parallel Model Verification:**
```javascript
async function verifyModels(models, provider) {
    const verified = new Set();
    let cursor = 0;
    const concurrency = Math.min(OPENROUTER_VERIFY_CONCURRENCY, models.length);
    
    const workers = Array.from({ length: concurrency }, async () => {
        while (cursor < models.length) {
            const index = cursor++;
            const model = models[index];
            const ok = await probeModel(provider, model);
            if (ok) verified.add(model);
        }
    });
    
    await Promise.all(workers);
    return verified;
}
```

### Dockerfile Patterns

**Multi-stage Build:**
```dockerfile
# Stage 1: Base - runtime dependencies
FROM node:25-slim AS base
RUN apt-get update && apt-get install -y --no-install-recommends \
    tini openssh-server bash nano git curl ca-certificates procps python3

# Stage 2: Builder - install global npm packages
FROM base AS builder
RUN npm install -g @google/gemini-cli @openai/codex ...

# Stage 3: Final - lightweight runtime
FROM base AS final
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin /usr/local/bin
```

**Non-root User:**
```dockerfile
ARG USER_NAME=omni
ARG USER_PASS=changeme
RUN useradd -m -s /bin/bash ${USER_NAME} && \
    echo "${USER_PASS}:${USER_PASS}" | chpasswd
```

**Volume Mounts:**
```dockerfile
VOLUME ["/data", "/config"]
```

### Entrypoint Patterns

**Environment Variable Persistence:**
```bash
persist_env_vars() {
    local env_file="/etc/profile.d/omni-cli-env.sh"
    # Export env vars that are set
    for var in "${vars[@]}"; do
        local val="${!var:-}"
        if [ -n "$val" ]; then
            echo "export $var='$escaped'" >> "$env_file"
        fi
    done
}
```

**UID/GID Mapping:**
```bash
if [ "$(id -u "$USER_NAME")" != "$PUID" ]; then
    usermod -o -u "$PUID" "$USER_NAME"
fi
```

**Privilege Drop:**
```bash
if [ "$#" -eq 0 ]; then
    # Start SSHD as root
    exec /usr/sbin/sshd -D -e
else
    # Execute command as non-root user
    exec runuser -u "$USER_NAME" -- "$@"
fi
```

### Python Patterns

**JSON Handling:**
```python
import json
from pathlib import Path

# Reading
config = json.loads(Path(config_file).read_text())

# Writing
Path(config_file).write_text(json.dumps(config, indent=2) + "\n")
```

**Error Handling:**
```python
def sync_models(config_file, models_data):
    try:
        payload = json.loads(models_data) if isinstance(models_data, str) else models_data
        # ... processing
        return True
    except Exception as e:
        print(f"Error syncing models: {e}", file=sys.stderr)
        return False
```

**Stdin/Stdout:**
```python
# Read from stdin
models_data = sys.stdin.read()

# Write to stderr (not stdout) for errors
print(f"Error: {message}", file=sys.stderr)

# Exit with code
sys.exit(1)  # Error
sys.exit(0)  # Success
```

## 🔒 Security Guidelines

### Never Do:
- ❌ Hardcode API keys or credentials
- ❌ Use `eval` on user input
- ❌ Expose secrets in logs
- ❌ Use `--no-verify` or skip hooks without explicit request
- ❌ Commit `.env`, `credentials.json`, or similar files

### Always Do:
- ✅ Use environment variables for secrets
- ✅ Quote all variable expansions in shell
- ✅ Validate and sanitize user inputs
- ✅ Use HTTPS for external API calls
- ✅ Run containers as non-root when possible
- ✅ Set `set -euo pipefail` in shell scripts
- ✅ Use context managers for file operations (Python)

### API Key Handling:
```bash
# Docker run with secrets (not in Dockerfile!)
docker run -e OPENAI_API_KEY="sk-..." ...

# Or use docker-compose.yml (not committed with secrets!)
# Use .env file (add to .gitignore)
```

## 🧪 Testing Approach

### No Automated Test Suite
This repository does not have automated unit/integration tests. Instead:

### Manual Smoke Tests
1. **Build & Start:**
   ```bash
   docker build -t omni-cli .
   docker run -d --name omni-cli -p 2222:22 -p 8000:8000 omni-cli
   ```

2. **SSH Login:**
   ```bash
   ssh omni@localhost -p 2222
   # Should see omni-cli menu
   ```

3. **CLI Tools:**
   - Launch each AI agent (1-5) from menu
   - Verify binaries resolve: `which gemini codex copilot claude opencode`

4. **API Server:**
   ```bash
   curl http://localhost:8000/v1/models
   curl http://localhost:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"codex-default","messages":[{"role":"user","content":"Test"}]}'
   ```

5. **Environment Variables:**
   ```bash
   docker exec omni-cli bash -c 'echo $OPENAI_API_KEY'
   docker exec omni-cli cat /etc/profile.d/omni-cli-env.sh
   ```

6. **Volume Persistence:**
   ```bash
   docker exec omni-cli touch /data/test-file
   docker restart omni-cli
   docker exec omni-cli ls /data/test-file  # Should still exist
   ```

### Testing Changes
- **Shell scripts:** Use `shellcheck` if available
- **Python:** Run `python3 -m py_compile src/sync_openrouter_models.py`
- **JavaScript:** Run `node --check api.js` for syntax validation
- **Dockerfile:** Build and run container

## 📤 Commit & PR Guidelines

### Commit Messages
Use imperative tense, short and descriptive:
- `Edit README.md`
- `Fix API server timeout handling`
- `Add OpenRouter model verification`
- `Refactor shell script utility functions`

### Pull Request Checklist
Before creating a PR, ensure:
1. **Build succeeds:** `docker build -t omni-cli .`
2. **Container starts:** Docker runs without errors
3. **SSH works:** Can connect and see menu
4. **All agents launch:** Each AI tool resolves correctly
5. **API server responds:** `/v1/models` endpoint works
6. **No secrets committed:** Verify with `git diff --cached`

### PR Description Template
```
## Summary
<What does this change do?>

## Rationale
<Why is this change needed?>

## Testing
- [ ] Build image: `docker build -t omni-cli .`
- [ ] Start container with API port
- [ ] Test SSH login
- [ ] Test all AI agents
- [ ] Test API endpoints

## Configuration Changes
- Added/modified env vars: <list>
- Volume changes: <list>
```

## 🎯 Quick Reference

### Docker Commands
```bash
# Build
docker build -t omni-cli .

# Run
docker run -d -p 2222:22 -p 8000:8000 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  omni-cli

# Connect
ssh omni@localhost -p 2222

# View logs
docker logs -f omni-cli

# Execute command
docker exec omni-cli bash -c "command"
```

### API Endpoints
- `GET /` - Health check
- `GET /v1/models` - Model catalog
- `POST /v1/chat/completions` - Chat completion (OpenAI-compatible)

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `CODEX_PASSTHROUGH_PORT` | `8000` | API server port |
| `CODEX_TIMEOUT_SECONDS` | `300` | Request timeout |
| `OPENROUTER_API_KEY` | - | OpenRouter API key |
| `PUID` | `1000` | User ID for volume permissions |
| `PGID` | `1000` | Group ID for volume permissions |

### File Locations
- Scripts: `/data/omni-cli/`
- User data: `/data/`
- Configs: `/config/`
- API logs: `/tmp/omni-codex-server.log`
- Version: `/etc/omni-cli-version`

## 📚 References
- **README.md** - User documentation
- **Dockerfile** - Container build process
- **entrypoint.sh** - Container initialization
- **omni-cli.sh** - Interactive menu interface
- **api.js** - API server implementation
- **src/sync_openrouter_models.py** - OpenRouter sync utility
