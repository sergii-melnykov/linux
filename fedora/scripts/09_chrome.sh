#!/usr/bin/env bash
set -e

echo "🌐 Installing Google Chrome..."

# Install dnf plugins core for config-manager
dnf install -y dnf-plugins-core

# Install fedora-workstation-repositories if not present (contains google-chrome repo)
dnf install -y fedora-workstation-repositories

# Enable Google Chrome repository
dnf config-manager setopt google-chrome.enabled=1

# Install Google Chrome
dnf install -y google-chrome-stable
