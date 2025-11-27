#!/usr/bin/env bash
set -e

echo "🐙 Installing Git..."
dnf install -y git

echo "🛠 Applying Git config..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "vim"
git config --global color.ui auto
