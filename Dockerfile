# syntax=docker/dockerfile:1
# ^ Enable BuildKit features

# ---- Base Stage ----
FROM node:25-slim AS base
LABEL maintainer="mabelisle <mabelisle@gmail.com>" \
      org.opencontainers.image.title="Omni-CLI" \
      org.opencontainers.image.description="Multi AI CLI interface environment" \
      org.opencontainers.image.source="https://github.com/mabelisle/omni-cli" \
      org.opencontainers.image.vendor="Smartypants LLC"

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production

# Install runtime dependencies
# tini: Proper init process for handling signals and zombie processes
# openssh-server: Required for remote access feature
# nano, git, curl: Standard CLI tools for user convenience
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tini \
    openssh-server \
    bash \
    nano \
    git \
    curl \
    ca-certificates \
    procps \
    python3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---- Build Stage ----
FROM base AS builder
# Install globally. We do this in a separate stage to potentially 
# keep the final layer clean, though strictly for globals it's less critical.
# It helps if we needed build tools (python/make) that we don't want in final.
RUN npm install -g \
    npm@latest \
    @google/gemini-cli \
    @google/gemini-cli-core \
    @openai/codex \
    @github/copilot \
    @anthropic-ai/claude-code \
    opencode-ai && \
    npm cache clean --force

# ---- Final Stage ----
FROM base AS final

# Create non-root user
ARG USER_NAME=omni
ARG USER_PASS=changeme
ENV USER_NAME=${USER_NAME} \
    NPM_CONFIG_PREFIX=/config/npm \
    PATH="/config/npm/bin:${PATH}"
# UID/GID can be overridden at runtime via entrypoint if needed, 
# but we set a default here. We remove the 'node' user first to free up UID 1000.
RUN userdel -r node && \
    useradd -m -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME}:${USER_PASS}" | chpasswd

# Copy installed node modules and binaries from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin /usr/local/bin

RUN mkdir -p /config/gemini /config/codex /config/copilot /config/claude /config/npm /config/opencode/config /config/opencode/data /config/opencode/cache /data && \
    ln -sf /config/gemini  /home/${USER_NAME}/.gemini  && \
    ln -sf /config/codex   /home/${USER_NAME}/.codex   && \
    ln -sf /config/copilot /home/${USER_NAME}/.copilot && \
    ln -sf /config/claude /home/${USER_NAME}/.claude && \
    ln -sf /config/npm     /home/${USER_NAME}/.npm && \
    ln -sf /config/opencode /home/${USER_NAME}/.opencode && \
    echo 'alias ll="ls -alF"' >> /etc/bash.bashrc

# Copy scripts
COPY omni-cli.sh /usr/local/bin/omni-cli
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY api.js /usr/local/bin/api.js
COPY omni-env.sh /etc/profile.d/omni-env.sh
RUN chmod +x /usr/local/bin/omni-cli /usr/local/bin/entrypoint.sh && \
    chmod 0644 /etc/profile.d/omni-env.sh && \
    echo '/usr/local/bin/omni-cli' >> /home/${USER_NAME}/.profile

# Expose SSH port
EXPOSE 22

# Volumes for persistence
VOLUME ["/data", "/config"]

# Set Tini as init process
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
