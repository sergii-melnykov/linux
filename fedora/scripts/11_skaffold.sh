#!/usr/bin/env bash
set -e

echo "⛵ Installing Google Skaffold..."

# Download the latest stable binary
curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64

# Install to /usr/local/bin
install skaffold /usr/local/bin/

# Clean up
rm skaffold

echo "✅ Skaffold installed successfully."
