#!/usr/bin/env bash
set -e

echo "🐙 Installing Git..."
dnf install -y git

echo "🛠 Applying Git config for user $SUDO_USER..."
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" git config --global init.defaultBranch main
    sudo -u "$SUDO_USER" git config --global pull.rebase false
    sudo -u "$SUDO_USER" git config --global core.editor "vim"
    sudo -u "$SUDO_USER" git config --global color.ui auto
else
    echo "Warning: SUDO_USER not set, applying config to current user (root?)"
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    git config --global core.editor "vim"
    git config --global color.ui auto
fi
