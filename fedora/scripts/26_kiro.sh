#!/usr/bin/env bash
set -e

echo "🧠 Installing Kiro IDE (local DNF repository)..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SRC="${SCRIPT_DIR}/kiro/kiro-repo-sync.sh"
SYNC_DST="/usr/local/lib/kiro/kiro-repo-sync.sh"
SYNC_BIN="/usr/local/bin/kiro-repo-sync"

if [[ ! -f "$SYNC_SRC" ]]; then
    echo "ERROR: Missing sync script at $SYNC_SRC"
    exit 1
fi

# A previous failed run may have enabled the repo before repodata existed.
if [[ -f /etc/yum.repos.d/kiro.repo ]] && [[ ! -f /var/lib/kiro-rpm-repo/repodata/repomd.xml ]]; then
    rm -f /etc/yum.repos.d/kiro.repo
fi

echo "Installing build and sync dependencies..."
dnf install -y jq curl tar rpm-build createrepo_c

echo "Installing Kiro repository sync tooling..."
mkdir -p /usr/local/lib/kiro
install -m 755 "$SYNC_SRC" "$SYNC_DST"
ln -sf "$SYNC_DST" "$SYNC_BIN"

cat > /etc/systemd/system/kiro-repo-sync.service <<'UNIT'
[Unit]
Description=Sync Kiro IDE tarball into local DNF repository
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/kiro/kiro-repo-sync.sh
UNIT

cat > /etc/systemd/system/kiro-repo-sync.timer <<'UNIT'
[Unit]
Description=Daily sync of Kiro IDE local DNF repository

[Timer]
OnBootSec=15min
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now kiro-repo-sync.timer

echo "Running initial Kiro repository sync..."
"$SYNC_DST"

echo "Writing local Kiro DNF repository..."
cat > /etc/yum.repos.d/kiro.repo <<'EOF'
[kiro]
name=Kiro IDE (local)
baseurl=file:///var/lib/kiro-rpm-repo
enabled=1
gpgcheck=0
priority=10
EOF

echo "Installing Kiro via DNF..."
dnf install -y kiro

echo ""
echo "✅ Kiro IDE installed successfully."
echo ""
echo "Launch: kiro"
echo "Repo:   /var/lib/kiro-rpm-repo"
echo ""
echo "Updates:"
echo "  sudo kiro-repo-sync    # check upstream and refresh local repo"
echo "  sudo dnf update kiro   # upgrade after repo sync"
echo ""
echo "A daily systemd timer keeps the local repo in sync automatically."
