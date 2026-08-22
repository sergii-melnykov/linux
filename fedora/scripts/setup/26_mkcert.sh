#!/usr/bin/env bash
set -e

echo "🔐 Installing mkcert (local TLS CA for *.local ingress)..."

if command -v mkcert >/dev/null 2>&1; then
    echo "ℹ️  mkcert is already installed: $(mkcert -version 2>/dev/null || echo 'version unknown')"
else
    dnf install -y mkcert nss-tools
    echo "✅ mkcert and nss-tools installed."
fi

# mkcert CAROOT is per-user. setup.sh runs as root via sudo, but
# generate-prod-tls-cert.sh runs as the normal user later.
if [ -n "$SUDO_USER" ]; then
    echo "Installing mkcert root CA for user $SUDO_USER..."
    sudo -u "$SUDO_USER" -H mkcert -install
    echo "CAROOT: $(sudo -u "$SUDO_USER" -H mkcert -CAROOT)"
    echo "✅ mkcert root CA installed for $SUDO_USER."
else
    echo "⚠️  Running as root without SUDO_USER - skipping mkcert -install."
    echo "   Run as your user: mkcert -install"
fi

echo "✅ mkcert setup complete."
