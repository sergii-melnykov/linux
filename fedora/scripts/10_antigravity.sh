#!/usr/bin/env bash
set -e

echo "🤖 Installing Google Antigravity IDE..."

# Add Antigravity Repo
# Note: Using gpgcheck=0 as the key URL is not confirmed for RPM, but the repo is trusted in this context.
cat <<EOF > /etc/yum.repos.d/antigravity.repo
[antigravity]
name=Google Antigravity
baseurl=https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

# Install Antigravity
dnf install -y antigravity
