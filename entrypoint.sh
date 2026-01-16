#!/bin/sh
set -e

mkdir -p /config/gemini /config/codex /config/copilot /config/npm /data

chown -R 1001:1001 -R /data || true
chown -R 1001:1001 -R /config || true

# Ensure runtime dirs exist (common requirement)
mkdir -p /var/run/sshd

# Ensure host keys exist (required for sshd to start)
# This path is typical on Debian/Ubuntu; on Alpine it's also common.
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
  ssh-keygen -A
fi

# If no command was provided, start sshd in foreground and log to stderr
if [ "$#" -eq 0 ]; then
  exec /usr/sbin/sshd -D -e
fi

# Otherwise run whatever command was provided (docker run ... <cmd>)
exec "$@"
