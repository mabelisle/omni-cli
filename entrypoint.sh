#!/bin/bash
set -e

# Configurable variables with defaults
USER_NAME=${USER_NAME:-omni}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# Update user UID/GID if they differ from current (to match host volume permissions)
if [ "$(id -u "$USER_NAME")" != "$PUID" ]; then
    usermod -o -u "$PUID" "$USER_NAME"
fi
if [ "$(id -g "$USER_NAME")" != "$PGID" ]; then
    groupmod -o -g "$PGID" "$USER_NAME"
fi

# Ensure critical directories exist and have correct ownership
for dir in /data /config /var/run/sshd; do
    mkdir -p "$dir"
done

# Initialize SSH host keys if missing
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    echo "Generating SSH keys..."
    ssh-keygen -A
fi

# Fix ownership of persistent volumes
chown -R "$USER_NAME":"$USER_NAME" /data /config

# Logic:
# 1. If no arguments are provided, start SSHD (as root).
# 2. If arguments are provided, execute them as the non-root user.
if [ "$#" -eq 0 ]; then
    echo "Starting SSH server..."
    exec /usr/sbin/sshd -D -e
else
    # executing command as user
    exec runuser -u "$USER_NAME" -- "$@"
fi