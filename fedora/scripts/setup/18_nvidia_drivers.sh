#!/bin/bash

# 18_nvidia_drivers.sh
# Installs NVIDIA drivers for Fedora

set -e

echo "Checking for NVIDIA GPU..."
if lspci | grep -i "nvidia" > /dev/null; then
    echo "NVIDIA GPU detected."
else
    echo "No NVIDIA GPU detected. Skipping driver installation."
    exit 0
fi

echo "Installing NVIDIA drivers..."
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda

echo "Force building kernel modules..."
sudo akmods --force

echo "NVIDIA drivers installed. Please reboot your system for changes to take effect."

echo "Installing NVIDIA Container Toolkit..."
# Add the repository
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

# Remove conflicting packages if present (ignore error if not installed)
echo "Removing potential conflicting packages..."
sudo dnf remove -y golang-github-nvidia-container-toolkit || true

# Install the toolkit
echo "Installing nvidia-container-toolkit..."
sudo dnf install -y nvidia-container-toolkit

# Configure Docker to use the NVIDIA runtime
echo "Configuring Docker runtime..."
sudo nvidia-ctk runtime configure --runtime=docker

echo "Restarting Docker daemon..."
sudo systemctl restart docker

echo "✅ NVIDIA setup complete. You can now use --gpus=all with Docker and Minikube."
