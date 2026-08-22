#!/usr/bin/env bash
set -e

echo "🌐 Installing cloudflared (Cloudflare Tunnel client)..."

if command -v cloudflared >/dev/null 2>&1; then
  echo "ℹ️  cloudflared is already installed: $(cloudflared --version 2>/dev/null || echo 'version unknown')"
  exit 0
fi

if ! command -v dnf >/dev/null 2>&1; then
  echo "⚠️  dnf not found; install cloudflared manually from Cloudflare docs."
  exit 0
fi

CLOUDFLARED_REPO="/etc/yum.repos.d/cloudflared.repo"
LEGACY_BAD_REPO="/etc/yum.repos.d/cloudflare.repo"

# Older versions of this script wrote the GPG key into cloudflare.repo by mistake.
if [[ -f "$LEGACY_BAD_REPO" ]] && ! grep -q '^\[.*\]' "$LEGACY_BAD_REPO" 2>/dev/null; then
  echo "Removing invalid $LEGACY_BAD_REPO (was GPG key, not a repo file)..."
  rm -f "$LEGACY_BAD_REPO"
fi

add_cloudflared_repo() {
  if [[ -f "$CLOUDFLARED_REPO" ]]; then
    return 0
  fi

  echo "Adding Cloudflare package repository..."

  # DNF5 (Fedora 41+): addrepo --from-repofile=...
  if dnf config-manager addrepo --help >/dev/null 2>&1; then
    dnf config-manager addrepo --from-repofile=https://pkg.cloudflare.com/cloudflared.repo
    return 0
  fi

  # DNF4: config-manager --add-repo ...
  if dnf config-manager --help 2>&1 | grep -q '\-\-add-repo'; then
    dnf config-manager --add-repo https://pkg.cloudflare.com/cloudflared.repo
    return 0
  fi

  # Fallback: write the official repo definition directly.
  cat > "$CLOUDFLARED_REPO" <<'EOF'
[cloudflared-stable]
name=cloudflared-stable
baseurl=https://pkg.cloudflare.com/cloudflared/rpm
enabled=1
type=rpm
gpgcheck=1
gpgkey=https://pkg.cloudflare.com/cloudflare-ascii-pubkey.gpg
EOF
}

add_cloudflared_repo

dnf install -y cloudflared
echo "✅ cloudflared installed."
echo ""
echo "ℹ️  Tunnel provisioning is opt-in (not run during setup.sh)."
echo "   Token mode:  sudo hostkit tunnel install --token YOUR_TOKEN"
echo "   Config mode: cloudflared tunnel login && cloudflared tunnel create NAME"
echo "                sudo hostkit tunnel install --name NAME --hostname app.example.com --credentials-file ~/.cloudflared/UUID.json"
