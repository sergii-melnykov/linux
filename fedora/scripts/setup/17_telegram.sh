#!/usr/bin/env bash
set -e

echo "💬 Installing Telegram..."

# Install Telegram Desktop from Flathub
echo "Installing Telegram Desktop via Flatpak..."

# Ensure Flathub is enabled
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Telegram Desktop
flatpak install -y flathub org.telegram.desktop

echo "✅ Telegram installation completed."
echo ""
echo "📝 To run Telegram, use: flatpak run org.telegram.desktop"
echo "   Or search for 'Telegram' in your applications menu"
