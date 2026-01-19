# Omni-CLI: All-in-One AI CLI Hub over SSH

![Docker](https://img.shields.io/badge/Docker-Enabled-blue?logo=docker)
![Node.js](https://img.shields.io/badge/Node.js-25--slim-green?logo=node.js)
![Status](https://img.shields.io/badge/Status-Active-success)

**Omni-CLI** is a Dockerized SSH workspace that bundles multiple AI CLIs in one place. Connect once and use **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** without installing anything on your laptop. Your tools and configs live in a single remote workspace, so you do not need to log in on every device.

Think of it as an all-in-one AI CLI cockpit you can reach from anywhere over SSH.

---

## 📸 Screenshots

![Omni-CLI overview](images/Multi-CLI.png)
![Omni-CLI menu](images/Omni-CLI-menu.png)

---

## 🚀 Features

*   **🔑 SSH-First Workflow:** Connect remotely and launch AI CLIs immediately.
*   **🤖 Preinstalled Agents:** **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** are ready out of the box.
*   **💾 Persistent Workspace:** Projects and auth/config live in Docker volumes, not on each device.
*   **🧭 Unified Menu:** The `omni-cli` dashboard navigates nested folders, shows breadcrumbs, and launches tools.
*   **🔒 Isolated Runtime:** Everything runs in Docker, keeping your host clean.
*   **👤 Smart UID/GID Mapping:** Avoids permission issues on mounted volumes.
*   **🧪 Aider Power-User Flow:** Provider selection (DeepSeek/OpenRouter/Ollama), recent models, and OpenRouter category pricing.
*   **🗝️ API Key Status:** Quick status panel for configured API keys.
*   **🔌 OpenAI-Style API:** Local HTTP server that proxies chat completions to Codex or Gemini.

---

## 📋 Prerequisites

*   [Docker Engine](https://docs.docker.com/get-docker/) installed on your machine.
*   [Docker Compose](https://docs.docker.com/compose/install/) (Optional, but recommended for easier management).

---

## 🛠️ Quick Start

Get up and running in seconds.

### 1. Start
Create a `docker-compose.yml` file (or clone the repo) and start the service:

```bash
# Start the container in the background
docker-compose up -d
```

Or pull the prebuilt image and run it directly:

```bash
docker pull ghcr.io/mabelisle/omni-cli:main

docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  ghcr.io/mabelisle/omni-cli:main
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
| `CODEX_PASSTHROUGH_PORT` | `8000` | **API Server Port**. Port exposed by the Codex/Gemini passthrough server. |
| `CODEX_TIMEOUT_SECONDS` | `300` | **API Timeout**. Max runtime for Codex/Gemini requests. |

### Aider Provider Variables

| Variable | Description |
| :--- | :--- |
| `DEEPSEEK_API_KEY` | Enables Aider + DeepSeek. |
| `OPENROUTER_API_KEY` / `OR_API_KEY` | Enables Aider + OpenRouter. |
| `OLLAMA_API_BASE` | Enables Aider + Ollama (e.g., `http://127.0.0.1:11434`). |

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

### Option B: Docker CLI (Pull Image)

```bash
docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  ghcr.io/mabelisle/omni-cli:main
```

### Option C: Docker CLI (Build Locally)

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

### The Menu Interface (`omni-cli.sh`)
When you log in, `omni-cli.sh` is sourced. It provides an ASCII-art menu to:
*   Navigate folders and subfolders in `/data` with breadcrumb paths.
*   Create/Delete folders.
*   Launch context-aware AI sessions within those folders (**Gemini**, **Codex**, **Copilot**, **Claude**, **Aider**).
*   View API key status and recent Aider models.

---

## 💡 Usage & Authentication

**Important:** Omni-CLI provides the *environment* and *tools*, but **you must provide the access**.

Each AI CLI (**Gemini**, **Codex**, **Copilot**, **Claude**, **Aider**) is pre-installed software that requires its own authentication. When you launch a tool for the first time, you will typically be prompted to login or provide an API key.

Aider uses environment variables for providers like OpenRouter, DeepSeek, and Ollama. Set those variables in your container environment and confirm them from the **API keys status** menu.

### Pro Tip: The "Free Tier" Rotation 🔄
There are plenty of ways to get free AI access using these tools! Since you have all of them at your fingertips:
1.  Start with your preferred agent.
2.  If you hit a rate limit or a free tier cap, simply **switch to the next one** in the menu.
3.  Cycle through **Gemini**, **Codex**, **Copilot**, **Claude**, and **Aider** to maximize your productivity without needing a paid subscription for every single service.

---

## 🔌 API Passthrough (OpenAI-Style)

Omni-CLI starts a lightweight HTTP server inside the container that proxies chat completions to **Codex** or **Gemini**. It exposes OpenAI-compatible endpoints:

*   `GET /` for health
*   `GET /v1/models` for the model catalog
*   `POST /v1/chat/completions` for chat completions

### 1. Expose the API Port
Map the default port `8000` (or the value of `CODEX_PASSTHROUGH_PORT`) when you run the container:

```bash
docker run -d \
  --name omni-cli \
  -p 2222:22 \
  -p 8000:8000 \
  -v $(pwd)/omni-data:/data \
  -v $(pwd)/omni-config:/config \
  -e PUID=$(id -u) \
  -e PGID=$(id -g) \
  ghcr.io/mabelisle/omni-cli:main
```

Docker Compose:

```yaml
ports:
  - "2222:22"
  - "8000:8000"
```

### 2. Call the API
Use `codex-default` (default) or `gemini-default`, or pick a model from `GET /v1/models`:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "codex-default",
    "messages": [
      { "role": "user", "content": "Write a haiku about SSH." }
    ]
  }'
```

*Tip:* if your OpenRouter key is set, the model catalog also includes verified OpenRouter Codex/Gemini models.

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
