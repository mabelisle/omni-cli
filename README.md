# Omni-CLI: Your AI-Powered Terminal Companion

![Docker](https://img.shields.io/badge/Docker-Enabled-blue?logo=docker)
![Node.js](https://img.shields.io/badge/Node.js-25--slim-green?logo=node.js)
![Status](https://img.shields.io/badge/Status-Active-success)

**Omni-CLI** is a robust, Dockerized environment designed to bridge the gap between your terminal and powerful AI agents. It provides a secure, portable, and pre-configured workspace for interacting with **Google Gemini**, **OpenAI Codex**, and **GitHub Copilot** directly from the command line.

Whether you are scaffolding a new project, debugging complex code, or exploring AI capabilities, Omni-CLI offers a unified neural interface to manage it all.

---

## 🚀 Features

*   **🔮 Unified Neural Interface:** A central, menu-driven dashboard (`omni-cli`) to manage workspaces and launch specific AI tools.
*   **🤖 Multi-Agent Support:** Pre-installed and configured CLI tools for:
    *   **Gemini:** Google's multimodal AI.
    *   **Codex:** OpenAI's code generation model.
    *   **Copilot:** GitHub's AI pair programmer.
*   **🔒 Sandboxed Environment:** Runs entirely within Docker, keeping your host system clean and dependencies isolated.
*   **💾 Persistent Workspaces:** Projects and configurations are saved to Docker volumes, ensuring your data survives container restarts.
*   **🔑 Secure Access:** Connect via a standalone SSH server or direct Docker attachment.
*   **👤 Smart User Mapping:** Automatically maps internal container permissions (PUID/PGID) to your host user, preventing file ownership headaches.
*   **⚡ Lightweight Core:** Built on top of the bleeding-edge `node:25-slim` image for maximum efficiency and minimal footprint.

---

## 📋 Prerequisites

*   [Docker Engine](https://docs.docker.com/get-docker/) installed on your machine.
*   [Docker Compose](https://docs.docker.com/compose/install/) (Optional, but recommended for easier management).

---

## 🛠️ Quick Start

Get up and running in seconds.

### 1. Clone & Start
Create a `docker-compose.yml` file (or clone the repo) and start the service:

```bash
# Start the container in the background
docker-compose up -d
```

### 2. Connect
Access the environment via SSH (Password: `changeme`):

```bash
ssh omni@localhost -p 2222
```

*🎉 You are now inside the Omni-CLI. The neural interface menu will launch automatically.*

---

## ⚙️ Configuration

You can customize the environment by setting environment variables in your `docker-compose.yml` or `docker run` command.

### Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PUID` | `1000` | **User ID**. Set this to your host user's UID (run `id -u`) to ensure you have write access to mounted volumes. |
| `PGID` | `1000` | **Group ID**. Set this to your host user's GID (run `id -g`). |
| `USER_PASS`| `changeme`| **SSH Password**. The password for the `omni` user (only effective if set during build via `--build-arg`). |
| `TZ` | `UTC` | **Timezone**. Set container timezone (e.g., `America/New_York`). |

### Volumes

| Volume | Internal Path | Description |
| :--- | :--- | :--- |
| `data` | `/data` | **Workspace Storage**. Maps to your local project directory. |
| `config`| `/config` | **Tool Configs**. Persists npm caches, auth tokens, and CLI settings. |

---

## 📦 Deployment Options

### Option A: Docker Compose (Recommended)

Create a `docker-compose.yml` file:

```yaml
version: '3.8'
services:
  omni-cli:
    build: .
    container_name: omni-cli
    environment:
      - PUID=1000 # Change to $(id -u)
      - PGID=1000 # Change to $(id -g)
      - TZ=UTC
    volumes:
      - ./omni-data:/data
      - ./omni-config:/config
    ports:
      - "2222:22"
    restart: unless-stopped
```

### Option B: Docker CLI

```bash
docker build -t omni-cli .

docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  omni-cli
```

---

## 🏗️ Architecture

### The Entrypoint Logic
The `entrypoint.sh` script is the brain of the container initialization:
1.  **Permission Fix:** It checks the `PUID` and `PGID` env vars and modifies the internal `omni` user to match them.
2.  **Key Gen:** Generates SSH host keys if they are missing.
3.  **Privilege Drop:** While it runs as `root` to perform setup, it executes the final command (or starts the SSH daemon) as the unprivileged `omni` user (or drops privileges appropriately) to ensure security.

### The Neural Interface (`omni-cli.sh`)
When you log in, `omni-cli.sh` is sourced. It provides an ASCII-art menu to:
*   List available projects in `/data`.
*   Create/Delete projects.
*   Launch context-aware AI sessions within those projects.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---

*Generated with ❤️ by Gemini*
