FROM node:latest

# Install system dependencies
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server \
    bash \
    nano && \
  apt autoremove -y

# Default SSH user + password (override at runtime)
ENV USER_NAME=omni \
    USER_PASS=changeme

# Create the user with a home directory and default shell, then set the password
RUN useradd -m -s /bin/bash $USER_NAME && \
    echo "$USER_NAME:$USER_PASS" | chpasswd

# Persistent locations used by tools
ENV CONFIG_DIR=/config \
  DATA_DIR=/data \
  NPM_CONFIG_CACHE=/config/npm

# Link "dotfile" config paths to /config
# Note: /config will be mounted as a volume at runtime; ensure subfolders exist via entrypoint if needed
RUN mkdir -p /config /data && \
  ln -sf /config/gemini  /home/$USER_NAME/.gemini  && \
  ln -sf /config/codex   /home/$USER_NAME/.codex   && \
  ln -sf /config/copilot /home/$USER_NAME/.copilot && \
  ln -sf /config/npm     /home/$USER_NAME/.npm

RUN chown $USER_NAME:$USER_NAME -R /config

# Upgrade npm and install AI CLIs globally
RUN npm install -g npm@latest && \
  npm install -g @google/gemini-cli @google/gemini-cli-core @openai/codex @github/copilot && \
  (npm cache verify || true)

# Add the alias "ll" to the system-wide bashrc file.
RUN echo 'alias ll="ls -alF"' >> /etc/bash.bashrc

# Optional project menu
COPY omni-cli.sh /usr/local/bin/omni-cli
RUN chmod +x /usr/local/bin/omni-cli && \
  echo '/usr/local/bin/omni-cli' >> /home/$USER_NAME/.profile

WORKDIR /data

VOLUME ["/data", "/config"]

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
