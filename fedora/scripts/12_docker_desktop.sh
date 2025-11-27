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

# Add Docker CE repository (required for docker-ce-cli dependency)
echo "Adding Docker CE repository..."
dnf config-manager addrepo --overwrite --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# Install Docker CE CLI (required dependency for Docker Desktop)
echo "Installing Docker CE CLI..."
dnf install -y docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Download Docker Desktop RPM
echo "Downloading Docker Desktop RPM..."
DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm"
if ! curl -L -o docker-desktop-x86_64.rpm "$DOCKER_DESKTOP_URL"; then
    echo "❌ Failed to download Docker Desktop. Please check your internet connection or try manually from:"
    echo "   https://docs.docker.com/desktop/install/fedora/"
    exit 1
fi

# Verify the file was downloaded
if [ ! -f docker-desktop-x86_64.rpm ]; then
    echo "❌ Docker Desktop RPM file not found after download."
    exit 1
fi

# Install Docker Desktop
echo "Installing Docker Desktop RPM..."
dnf install -y ./docker-desktop-x86_64.rpm

# Clean up
rm -f docker-desktop-x86_64.rpm

# Enable Docker Desktop to start automatically on boot
echo "Enabling Docker Desktop to start on boot..."
systemctl --user enable docker-desktop || {
    echo "⚠️  Could not enable auto-start (user may need to be logged in)"
    echo "   You can enable it manually later with: systemctl --user enable docker-desktop"
}

# Start Docker Desktop now (if user session is available)
echo "Starting Docker Desktop..."
systemctl --user start docker-desktop || {
    echo "⚠️  Could not start Docker Desktop automatically"
    echo "   You can start it manually from your application menu or with: systemctl --user start docker-desktop"
}

echo "✅ Docker Desktop installed successfully."
echo "✅ Docker Desktop is configured to start automatically on boot."
