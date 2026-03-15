#!/usr/bin/env bash
set -e

echo "⎈ Installing Helm..."

if command -v helm >/dev/null 2>&1; then
    echo "ℹ️  Helm is already installed: $(helm version --short 2>/dev/null || echo 'version unknown')"
    exit 0
fi

# Install Helm from Fedora repositories.
dnf install -y helm

echo "✅ Helm installed successfully."
