#!/usr/bin/env bash
set -e

echo "🔐 Generating SSH keys (ed25519)..."
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" ssh-keygen -t ed25519 -f "/home/$SUDO_USER/.ssh/id_ed25519" -q -N "" || echo "SSH key already exists"
else
    echo "Warning: SUDO_USER not set, skipping SSH key generation"
fi
