#!/usr/bin/env bash
set -e

echo "🔧 Installing build-essential, linux-headers-generic, and dkms..."
apt install build-essential linux-headers-generic dkms -y