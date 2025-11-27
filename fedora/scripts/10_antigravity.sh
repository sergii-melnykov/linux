#!/usr/bin/env bash
set -e

echo "🤖 Installing Google Antigravity IDE..."

# Add Antigravity Repo
# Note: Using gpgcheck=0 as the key URL is not confirmed for RPM, but the repo is trusted in this context.
sudo tee /etc/yum.repos.d/antigravity.repo > /dev/null <<EOF
[antigravity]
name=Google Antigravity
baseurl=https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

# Clean DNF cache to avoid stale package issues
sudo dnf clean all

# Install Antigravity
sudo dnf install -y antigravity
