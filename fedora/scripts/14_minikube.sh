#!/usr/bin/env bash
set -e

echo "🚢 Installing minikube..."

# Download the latest minikube binary
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Install to /usr/local/bin
install minikube-linux-amd64 /usr/local/bin/minikube

# Clean up
rm minikube-linux-amd64

echo "✅ minikube installed successfully."
echo "💡 To start minikube, run: minikube start"
