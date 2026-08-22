#!/usr/bin/env bash
set -e

echo "🧩 Installing GNOME Extensions and Extensions Manager..."

# Install GNOME Extensions app (Extension Manager) and other essential GNOME tools
echo "Installing GNOME Tweaks, Dconf Editor, and Extension Manager..."
dnf install -y gnome-extensions-app gnome-tweaks dconf-editor

# Install dependencies for installing extensions via CLI
echo "Installing gnome-shell-extension-installer dependencies..."
dnf install -y jq curl

# Download gnome-shell-extension-installer script
echo "Downloading gnome-shell-extension-installer..."
INSTALLER_URL="https://raw.githubusercontent.com/brunelli/gnome-shell-extension-installer/master/gnome-shell-extension-installer"
curl -o /usr/local/bin/gnome-shell-extension-installer "$INSTALLER_URL"
chmod +x /usr/local/bin/gnome-shell-extension-installer

# Function to install extension for the actual user (not root)
install_extension_for_user() {
    local extension_id=$1
    local extension_name=$2
    
    if [ -n "$SUDO_USER" ]; then
        echo "Installing $extension_name (ID: $extension_id) for user $SUDO_USER..."
        # The installer downloads and installs to the user's local extensions directory
        sudo -u "$SUDO_USER" gnome-shell-extension-installer "$extension_id" --yes
        
        # Note: Programmatically enabling extensions often requires a shell restart 
        # or can be done via gsettings, but gnome-extensions enable requires the UUID,
        # not the ID. The installer usually handles the download.
    else
        echo "⚠️  Running as root - skipping extension installation"
        echo "   To install extensions, run as your user:"
        echo "   gnome-shell-extension-installer $extension_id --yes"
    fi
}

# Install extensions
echo ""
echo "Installing GNOME Extensions..."

# Vitals - System monitor showing CPU, memory, temperature, etc.
install_extension_for_user 1460 "Vitals"

# Sound Input & Output Device Chooser - Quick audio device switching
install_extension_for_user 906 "Sound Input & Output Device Chooser"

# Tiling Shell - Advanced window tiling
install_extension_for_user 7065 "Tiling Shell"

echo ""
echo "✅ GNOME Extensions installation completed."
echo ""
echo "📝 Installed extensions:"
echo "   • Vitals - System monitoring (CPU, memory, temperature, network, etc.)"
echo "   • Sound Input & Output Device Chooser - Quick audio device switching"
echo "   • Tiling Shell - Advanced window tiling and management"
echo ""
echo "📝 Next steps:"
echo "   1. Log out and log back in (or restart GNOME Shell with Alt+F2, then type 'r')"
echo "   2. Open 'Extensions' app to enable/configure the installed extensions"
echo "   3. You can also install more extensions from https://extensions.gnome.org/"
echo ""
