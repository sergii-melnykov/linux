#!/usr/bin/env bash
set -e

echo "🐳 Installing Docker Engine (for Minikube)..."

# Remove conflicting packages if they exist
echo "Removing conflicting Docker packages..."
dnf remove -y docker \
              docker-client \
              docker-client-latest \
              docker-common \
              docker-latest \
              docker-latest-logrotate \
              docker-logrotate \
              docker-selinux \
              docker-engine-selinux \
              docker-engine || true

# Install dependencies
echo "Installing dependencies..."
dnf install -y dnf-plugins-core

# Add Docker CE repository
echo "Adding Docker CE repository..."
dnf config-manager addrepo --overwrite --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo

# Install Docker Engine and components
echo "Installing Docker Engine..."
dnf install -y docker-ce \
               docker-ce-cli \
               containerd.io \
               docker-buildx-plugin \
               docker-compose-plugin

# Start and enable Docker service
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Add current user to docker group (to run docker without sudo)
if [ -n "$SUDO_USER" ]; then
    echo "Adding user $SUDO_USER to docker group..."
    usermod -aG docker "$SUDO_USER"
    echo "⚠️  Note: You'll need to log out and back in for group changes to take effect"
else
    echo "⚠️  Running as root - skipping user group addition"
    echo "   To run docker without sudo, add your user to the docker group:"
    echo "   sudo usermod -aG docker \$USER"
fi

# Verify installation
echo "Verifying Docker installation..."
docker --version

echo "✅ Docker Engine installed successfully."
echo "✅ Docker service is running and enabled on boot."
echo ""
echo "📝 Next steps:"
echo "   1. Log out and back in for group changes to take effect"
echo "   2. Test Docker: docker run hello-world"
echo "   3. Install Minikube to use Docker as the driver"
