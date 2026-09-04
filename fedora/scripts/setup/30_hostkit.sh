#!/usr/bin/env bash
set -e

echo "🧰 Installing hostkit (agnostic host infrastructure CLI)..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/../../lib/hostkit"
INSTALL_LIB="/usr/local/lib/hostkit"
INSTALL_BIN="/usr/local/bin/hostkit"
INSTALL_SBIN="/usr/local/sbin/hostkit"
LEGO_VERSION="${LEGO_VERSION:-v4.23.1}"

if [[ ! -f "${SOURCE_DIR}/hostkit" ]]; then
  echo "❌ hostkit source not found at ${SOURCE_DIR}"
  exit 1
fi

echo "Installing hostkit library to ${INSTALL_LIB}..."
rm -rf "${INSTALL_LIB}"
mkdir -p "${INSTALL_LIB}/lib"
install -m 755 "${SOURCE_DIR}/hostkit" "${INSTALL_LIB}/hostkit"
install -m 644 "${SOURCE_DIR}/lib/"*.sh "${INSTALL_LIB}/lib/"
mkdir -p "$(dirname "${INSTALL_BIN}")" "$(dirname "${INSTALL_SBIN}")"
ln -sf "${INSTALL_LIB}/hostkit" "${INSTALL_BIN}"
ln -sf "${INSTALL_LIB}/hostkit" "${INSTALL_SBIN}"
chmod +x "${INSTALL_LIB}/hostkit"

if [[ ! -x "${INSTALL_BIN}" || ! -x "${INSTALL_SBIN}" ]]; then
  echo "❌ Failed to install hostkit symlinks under /usr/local/bin and /usr/local/sbin"
  exit 1
fi

echo "✅ hostkit installed: ${INSTALL_BIN} (also ${INSTALL_SBIN})"
"${INSTALL_BIN}" version || true

install_lego() {
  if command -v lego >/dev/null 2>&1; then
    echo "ℹ️  lego is already installed: $(lego --version 2>/dev/null || echo 'version unknown')"
    return 0
  fi

  local arch os tmp
  arch="$(uname -m)"
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${arch}" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "⚠️  Unsupported architecture for lego auto-install: ${arch}"
      return 0
      ;;
  esac

  tmp="$(mktemp -d)"
  echo "⬇️  Downloading lego ${LEGO_VERSION} (${os}/${arch})..."
  curl -fsSL "https://github.com/go-acme/lego/releases/download/${LEGO_VERSION}/lego_${LEGO_VERSION}_${os}_${arch}.tar.gz" \
    | tar -xz -C "${tmp}"
  install -m 755 "${tmp}/lego" /usr/local/bin/lego
  rm -rf "${tmp}"
  echo "✅ lego installed: $(lego --version)"
}

install_lego

mkdir -p /etc/hostkit /var/lib/hostkit/acme
chmod 700 /etc/hostkit /var/lib/hostkit /var/lib/hostkit/acme

if [[ ! -f /etc/hostkit/acme.env.example ]]; then
  cat > /etc/hostkit/acme.env.example <<'EOF'
# Copy to /etc/hostkit/acme.env and chmod 600
# Enable API access for your domain in Porkbun: Account -> Domain Management -> Details -> API Access
PORKBUN_API_KEY=
PORKBUN_SECRET_API_KEY=
EOF
fi

install_systemd_renew_timer() {
  cat > /etc/systemd/system/hostkit-cert-renew.service <<'EOF'
[Unit]
Description=Renew hostkit ACME certificates
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/hostkit cert renew
EOF

  cat > /etc/systemd/system/hostkit-cert-renew.timer <<'EOF'
[Unit]
Description=Daily hostkit ACME certificate renewal

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable hostkit-cert-renew.timer >/dev/null 2>&1 || true
  echo "✅ hostkit-cert-renew.timer installed (enabled; runs daily when ACME renew.conf exists)."
}

install_systemd_renew_timer

echo ""
echo "📝 hostkit commands:"
echo "   sudo hostkit cluster up"
echo "   hostkit cert local --out DIR --host example.local ..."
echo "   sudo hostkit tunnel install --token TOKEN"
echo ""
echo "✅ hostkit setup complete."
