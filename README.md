# Omni-CLI: SSH Into Ready-to-Use AI CLIs

![Docker](https://img.shields.io/badge/Docker-Enabled-blue?logo=docker)
![Node.js](https://img.shields.io/badge/Node.js-25--slim-green?logo=node.js)
![Status](https://img.shields.io/badge/Status-Active-success)

**Omni-CLI** is a Dockerized SSH environment that gives you instant access to preinstalled AI CLIs. Connect once and use **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** without installing anything on your laptop. Your tools and configs live in a single remote workspace, so you do not need to log in on every device.

Use it as a personal AI terminal you can reach from anywhere via SSH, with everything ready to run.

---

## 📸 Screenshots

![Omni-CLI overview](images/Multi-CLI.png)
![Omni-CLI menu](images/Omni-CLI-menu.png)

---

## 🚀 Features

*   **🔑 SSH-First Workflow:** Connect remotely and launch AI CLIs immediately.
*   **🤖 Preinstalled Agents:** **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** are ready out of the box.
*   **💾 Persistent Workspace:** Projects and auth/config live in Docker volumes, not on each device.
*   **🧭 Unified Menu:** The `omni-cli` dashboard lists projects and launches tools.
*   **🔒 Isolated Runtime:** Everything runs in Docker, keeping your host clean.
*   **👤 Smart UID/GID Mapping:** Avoids permission issues on mounted volumes.

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

*🎉 You are now inside Omni-CLI. The AI menu launches automatically and tools are ready to use.*

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
*   Launch context-aware AI sessions within those projects (**Gemini**, **Codex**, **Copilot**, **Claude**, **Aider**).

---

## 💡 Usage & Authentication

**Important:** Omni-CLI provides the *environment* and *tools*, but **you must provide the access**.

Each AI CLI (**Gemini**, **Codex**, **Copilot**, **Claude**, **Aider**) is pre-installed software that requires its own authentication. When you launch a tool for the first time, you will typically be prompted to login or provide an API key.

### Pro Tip: The "Free Tier" Rotation 🔄
There are plenty of ways to get free AI access using these tools! Since you have all of them at your fingertips:
1.  Start with your preferred agent.
2.  If you hit a rate limit or a free tier cap, simply **switch to the next one** in the menu.
3.  Cycle through **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** to maximize your productivity without needing a paid subscription for every single service.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---

## ❤️ Special Thanks

This project stands on the shoulders of giants. A huge thank you to the teams behind these amazing tools:

*   **Gemini:** [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)
*   **Codex:** [openai/codex](https://github.com/openai/codex)
*   **Copilot:** [github/copilot-cli](https://github.com/github/copilot-cli)
*   **Claude:** [anthropics/claude-code](https://github.com/anthropics/claude-code)
*   **Aider:** [Aider-AI/aider](https://github.com/Aider-AI/aider)

---

*Generated with ❤️ by Gemini*
