FROM node:22-alpine

# Install system dependencies
RUN apk add --no-cache \
      openssh \
      bash \
      nano \
      git \
      curl \
      ca-certificates \
    && update-ca-certificates \
    && ssh-keygen -A

# Security & SSH Config
RUN echo 'root:changeme' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Persistent locations used by tools
ENV CONFIG_DIR=/config \
    DATA_DIR=/data \
    NPM_CONFIG_CACHE=/config/npm

# Link "dotfile" config paths to /config (will be created at runtime too)
RUN mkdir -p /config /data \
 && ln -s /config/gemini  /root/.gemini  \
 && ln -s /config/codex   /root/.codex   \
 && ln -s /config/copilot /root/.copilot \
 && ln -s /config/npm     /root/.npm

# Upgrade npm and install AI CLIs globally
RUN npm install -g npm@latest \
 && npm install -g @google/gemini-cli @openai/codex @github/copilot \
 && npm cache verify || true

# Convenience aliases / login profile
RUN echo "alias ll='ls -alF'" >> /root/.profile

# Change root shell from /bin/sh to /bin/bash
RUN sed -i 's|/root:/bin/sh|/root:/bin/bash|' /etc/passwd

# Optional project menu
COPY omni-cli.sh /usr/local/bin/omni-cli
RUN chmod +x /usr/local/bin/omni-cli \
 && echo '/usr/local/bin/omni-cli' >> /root/.profile

WORKDIR /data

VOLUME ["/data", "/config"]

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
