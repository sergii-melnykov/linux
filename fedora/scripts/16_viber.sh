#!/usr/bin/env bash
set -e

echo "💬 Installing Viber..."

# Download Viber RPM package
VIBER_URL="https://download.cdn.viber.com/cdn/desktop/Linux/viber.rpm"
TEMP_RPM="/tmp/viber.rpm"

echo "Downloading Viber..."
curl -L -o "$TEMP_RPM" "$VIBER_URL"

# Install Viber
echo "Installing Viber..."
dnf install -y "$TEMP_RPM"

# Clean up
rm -f "$TEMP_RPM"

echo "✅ Viber installation completed."
