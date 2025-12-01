#!/usr/bin/env bash
set -e

echo "🔧 Installing build-essential, linux-headers-generic, dkms, wget, unzip, xclip..."
apt install build-essential linux-headers-generic dkms wget unzip xclip -y


echo "⚙️  Configuring pbcopy and pbpaste aliases for all users..."

# Function to add aliases to a user's bashrc
add_aliases_to_user() {
    local username=$1
    local user_home=$2
    local bashrc="$user_home/.bashrc"
    
    # Skip if .bashrc doesn't exist
    if [ ! -f "$bashrc" ]; then
        echo "⚠️  Skipping $username (no .bashrc found)"
        return
    fi
    
    # Add aliases if they don't exist
    if ! grep -q "alias pbcopy" "$bashrc"; then
        echo "" >> "$bashrc"
        echo "# Clipboard aliases (macOS-like)" >> "$bashrc"
        echo "alias pbcopy='xclip -selection clipboard'" >> "$bashrc"
        echo "alias pbpaste='xclip -selection clipboard -o'" >> "$bashrc"
        echo "✅ Added aliases to $username's .bashrc"
    else
        echo "ℹ️  Aliases already exist in $username's .bashrc"
    fi
}

# Get all real users (UID >= 1000, excluding nobody)
while IFS=: read -r username _ uid _ _ home _; do
    if [ "$uid" -ge 1000 ] && [ "$username" != "nobody" ] && [ -d "$home" ]; then
        add_aliases_to_user "$username" "$home"
    fi
done < /etc/passwd
