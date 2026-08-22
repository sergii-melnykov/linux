#!/bin/bash
set -e

if command -v ollama &> /dev/null; then
    echo "Already installed."
else
    echo "Installing Ollama..."
    # Install/Update Ollama
    curl -fsSL https://ollama.com/install.sh | sh
fi

echo "Ollama operation complete."
