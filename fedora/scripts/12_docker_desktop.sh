#!/usr/bin/env bash
set -e

echo "🐳 Installing Docker Desktop..."

# Remove conflicting packages if they exist (standard Docker Engine / Moby)
# This ensures Docker Desktop can install without conflicts.
echo "Removing conflicting Docker Engine packages..."
dnf remove -y docker \
              docker-client \
              docker-client-latest \
              docker-common \
              docker-latest \
              docker-latest-logrotate \
              docker-logrotate \
              docker-selinux \
              docker-engine-selinux \
              docker-engine \
              docker-ce \
              docker-ce-cli \
              containerd.io || true

# Install dependencies
dnf install -y dnf-plugins-core

# Download Docker Desktop RPM
echo "Downloading Docker Desktop RPM..."
curl -L -o docker-desktop-x86_64.rpm "https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm?utm_source=docker&utm_medium=webreferral&utm_campaign=docs-driven-download-linux-amd64"

# Install Docker Desktop
echo "Installing Docker Desktop RPM..."
dnf install -y ./docker-desktop-x86_64.rpm

# Clean up
rm docker-desktop-x86_64.rpm

echo "✅ Docker Desktop installed successfully."
echo "⚠️  Note: Docker Desktop runs in a VM. You may need to launch it from your application menu to start the engine."
