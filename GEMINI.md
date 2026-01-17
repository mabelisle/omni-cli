# Omni-CLI Context

## Project Overview
**Omni-CLI** is a Dockerized, neural interface environment designed to unify access to various AI CLI tools (**Gemini**, **Codex**, **Copilot**, **Aider**). It provides a secure, sandboxed workspace that can be accessed via SSH or direct Docker attachment. The project is built on top of a lightweight Node.js image and includes custom shell scripts for project management and tool invocation.

## Architecture & Core Components

### Docker Structure
*   **Base Image:** `node:25-slim` (Debian-based).
*   **Multi-Stage Build:** Uses a `builder` stage for installing global npm packages (`@google/gemini-cli`, etc.) to keep the final image clean.
*   **User Management:**
    *   The default `node` user (UID 1000) is **removed** in the final stage to avoid conflicts.
    *   A custom `omni` user is created.
    *   **Runtime Mapping:** `entrypoint.sh` dynamically updates the `omni` user's UID/GID to match the host system (via `PUID`/`PGID` env vars), ensuring correct file permissions for mounted volumes.

### Key Scripts
*   **`entrypoint.sh`:** The container entrypoint. Handles:
    *   User ID mapping (usermod/groupmod).
    *   SSH host key generation.
    *   Directory permission fixes.
    *   Starting `sshd` or executing command arguments.
*   **`omni-cli.sh`:** The interactive "Neural Interface".
    *   A generic `bash` script providing a menu-driven UI.
    *   Manages projects in the `/data` directory.
    *   Wraps AI CLI tool execution.

## Building and Running

### Build
```bash
docker build -t omni-cli .
```

### Run (Development/Testing)
The container is designed to be persistent. It requires mapping volumes for data and configuration.

```bash
docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  omni-cli
```

### Access
*   **SSH:** `ssh omni@localhost -p 2222` (Password: `changeme` or as configured).
*   **Interactive Shell:** The `omni-cli` menu launches automatically upon login (configured in `.profile`).

## Development Conventions

*   **Shell Scripting:**
    *   Scripts use `#!/bin/bash`.
    *   Prefer clear variable naming and structure (e.g., `launch_ai` function in `omni-cli.sh`).
    *   Menu interfaces utilize `case` statements for navigation.
*   **Docker:**
    *   Prioritize image size (slim variants, cleaning apt caches).
    *   Use `tini` as the init process to handle signals correctly.
    *   Separate build dependencies from runtime dependencies using multi-stage builds.
    *   **Security:** Never run as root effectively; use `entrypoint.sh` to drop privileges or run as the `omni` user.

## Directory Structure
*   `/data`: Intended for project workspaces (persisted).
*   `/config`: Intended for tool configurations (npm cache, auth tokens) (persisted).
*   `/usr/local/bin`: Location of executable scripts (`omni-cli`, `entrypoint.sh`).
