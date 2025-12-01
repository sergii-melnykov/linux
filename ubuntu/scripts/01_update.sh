#!/usr/bin/env bash
set -e

echo "🔧 Updating system..."
apt update -y
apt full-upgrade -y