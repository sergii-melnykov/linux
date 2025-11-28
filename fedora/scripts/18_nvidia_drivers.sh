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
