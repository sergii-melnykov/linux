#!/bin/bash

# 19_gpu_app_config.sh
# Configures specific applications to always use the Discrete GPU (NVIDIA)

set -e

# List of applications to configure (partial names are okay, e.g., "chrome" for "google-chrome")
# You can add more apps to this list
APPS_TO_CONFIGURE=(
    "google-chrome"
    "code"
)

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    USER_APPS_DIR="$USER_HOME/.local/share/applications"
    echo "Configuring for user: $SUDO_USER (Home: $USER_HOME)"
else
    USER_APPS_DIR="$HOME/.local/share/applications"
    echo "Warning: SUDO_USER not set, configuring for current user ($USER)"
fi

SYSTEM_APPS_DIRS=("/usr/share/applications" "/var/lib/flatpak/exports/share/applications")

# Create directory as the correct user
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" mkdir -p "$USER_APPS_DIR"
else
    mkdir -p "$USER_APPS_DIR"
fi

echo "Configuring applications to use Discrete GPU..."

for app_name in "${APPS_TO_CONFIGURE[@]}"; do
    echo "Processing: $app_name"
    found=false
    
    for sys_dir in "${SYSTEM_APPS_DIRS[@]}"; do
        if [ ! -d "$sys_dir" ]; then
            continue
        fi
        # Find .desktop files matching the app name (case-insensitive)
        # We use find to handle potential multiple matches or exact matches
        # This looks for *name*.desktop
        matches=$(find "$sys_dir" -maxdepth 1 -iname "*${app_name}*.desktop")
        
        if [ -n "$matches" ]; then
            for desktop_file in $matches; do
                filename=$(basename "$desktop_file")
                target_file="$USER_APPS_DIR/$filename"
                
                echo "  Found: $desktop_file"
                echo "  Copying to: $target_file"
                
                cp "$desktop_file" "$target_file"
                
                # Check if PrefersNonDefaultGPU is already set
                if grep -q "PrefersNonDefaultGPU=true" "$target_file"; then
                    echo "  Already configured for Discrete GPU."
                else
                    # Add the key to the [Desktop Entry] section
                    # We use sed to append it after [Desktop Entry] if it exists, 
                    # or just append to file if we want to be simple, but putting it in the group is safer.
                    # A simple robust way: check if the key exists, if so replace, if not append to [Desktop Entry]
                    
                    if grep -q "PrefersNonDefaultGPU" "$target_file"; then
                        sed -i 's/PrefersNonDefaultGPU=.*/PrefersNonDefaultGPU=true/' "$target_file"
                    else
                        # Append after [Desktop Entry]
                        sed -i '/^\[Desktop Entry\]/a PrefersNonDefaultGPU=true' "$target_file"
                    fi
                    echo "  Updated configuration."
                fi
                
                # Fix ownership
                if [ -n "$SUDO_USER" ]; then
                    chown "$SUDO_USER":"$SUDO_USER" "$target_file"
                fi
                found=true
            done
        fi
    done
    
    if [ "$found" = false ]; then
        echo "  Warning: No .desktop file found for '$app_name'"
    fi
done

echo "Updating desktop database..."
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" update-desktop-database "$USER_APPS_DIR"
else
    update-desktop-database "$USER_APPS_DIR"
fi

echo "Done. The configured applications should now launch using the Discrete GPU."
