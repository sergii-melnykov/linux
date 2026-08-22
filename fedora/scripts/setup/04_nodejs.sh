#!/usr/bin/env bash
set -e

echo "🟩 Installing nvm (Node Version Manager)..."

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    echo "Installing for user: $SUDO_USER (Home: $USER_HOME)"

    # Install nvm as user
    sudo -u "$SUDO_USER" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

    # Install Node.js LTS and pnpm as user
    # We need to source nvm.sh within the same bash session
    sudo -u "$SUDO_USER" bash -c "export NVM_DIR='$USER_HOME/.nvm'; [ -s '$USER_HOME/.nvm/nvm.sh' ] && . '$USER_HOME/.nvm/nvm.sh'; nvm install --lts; nvm use --lts; npm install -g pnpm"
else
    echo "⚠️  SUDO_USER not set. Installing for root (not recommended for development environments)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    npm install -g pnpm
fi

echo "✅ nvm and Node.js LTS installed successfully."
echo "💡 To use nvm in new shells, restart your terminal or run: source ~/.bashrc"
