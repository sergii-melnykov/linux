#!/usr/bin/env bash
set -e

echo "🦈 Installing Wireshark..."

# Prefer official Fedora repositories first.
if dnf list --available wireshark-qt >/dev/null 2>&1; then
    dnf install -y wireshark-qt wireshark-cli

    # Allow the invoking user to capture packets without running Wireshark as root.
    if [ -n "${SUDO_USER:-}" ] && getent group wireshark >/dev/null 2>&1; then
        usermod -aG wireshark "$SUDO_USER"
        echo "✅ Added $SUDO_USER to the wireshark group."
        echo "ℹ️  Log out and log back in for group changes to take effect."
    fi
else
    echo "⚠️  wireshark-qt is not available in enabled Fedora repositories."
    echo "Trying Flatpak (Flathub) fallback..."

    if ! command -v flatpak >/dev/null 2>&1; then
        dnf install -y flatpak
    fi

    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub org.wireshark.Wireshark
fi

echo "✅ Wireshark installation finished."
