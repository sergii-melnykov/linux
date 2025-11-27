#!/usr/bin/env bash
set -e

echo "🟩 Installing nvm (Node Version Manager)..."

# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Load nvm into current shell
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "📦 Installing Node.js LTS via nvm..."
nvm install --lts
nvm use --lts

echo "📦 Installing pnpm..."
npm install -g pnpm

echo "✅ nvm and Node.js LTS installed successfully."
echo "💡 To use nvm in new shells, restart your terminal or run: source ~/.bashrc"
