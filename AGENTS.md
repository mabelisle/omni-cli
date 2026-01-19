# Repository Guidelines

## Project Structure & Module Organization
- `Dockerfile` defines the multi-stage image build and installed CLI tools.
- `entrypoint.sh` bootstraps the container (UID/GID mapping, SSH keys, volume ownership).
- `omni-cli.sh` is the menu-driven interface launched on login.
- `.gitlab-ci.yml` uses GitLab Auto-DevOps templates.
- `README.md` documents setup and runtime configuration.

## Build, Test, and Development Commands
- `docker build -t omni-cli .` builds the image locally.
- `docker run -d -p 2222:22 -v $(pwd)/omni-data:/data -v $(pwd)/omni-config:/config omni-cli` starts a container with persistent volumes.
- `docker-compose up -d` (when a compose file is present) runs the full stack locally.
- `ssh omni@localhost -p 2222` connects to the running container.

## Coding Style & Naming Conventions
- Shell scripts use Bash (`#!/bin/bash`) with 4-space indentation.
- Keep function names and variables lowercase with underscores (e.g., `launch_ai`, `USER_NAME`).
- Favor small, readable functions and explicit comments for non-obvious logic.

## Testing Guidelines
- No automated test suite is defined in this repo.
- Suggested smoke checks:
  - Build the image and start a container.
  - Verify SSH login works and the `omni-cli` menu appears.
  - Launch each agent option to ensure the CLI binaries resolve.

## Commit & Pull Request Guidelines
- Commit messages in history are short and imperative (e.g., "Edit README.md", "Refactoring").
- PRs should include:
  - A brief description of the change and rationale.
  - Steps to verify (commands run, manual checks).
  - Notes on config or environment variable changes, if any.

## Security & Configuration Tips
- Set `PUID`/`PGID` to match your host user to avoid permission issues.
- Rotate `USER_PASS` if exposing SSH beyond local development.
- Persistent data lives in `/data`; tool configs live in `/config`.

## Documentation
- Review the README.md after making any changes
