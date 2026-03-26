#!/usr/bin/env bash
set -e

echo "📉 Installing RTK (Rust Token Killer) prerequisites..."
dnf install -y jq curl

if [ -z "${SUDO_USER:-}" ]; then
    echo "Warning: SUDO_USER not set; skipping per-user RTK install (avoid installing as root)."
    exit 0
fi

echo "🛠 Installing RTK for user $SUDO_USER and running global init..."

sudo -u "$SUDO_USER" -H bash -lc '
set -e

ensure_local_bin_path() {
    local f="$1"
    [ -f "$f" ] || return 0
    if grep -q "# RTK: ~/.local/bin PATH" "$f" 2>/dev/null; then
        return 0
    fi
    printf "\n# RTK: ~/.local/bin PATH\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\n" >> "$f"
}

ensure_local_bin_path "$HOME/.bashrc"
ensure_local_bin_path "$HOME/.zshrc"

export PATH="$HOME/.local/bin:$PATH"

curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

rtk --version
rtk gain

rtk init --global --auto-patch
'

echo ""
echo "✅ RTK installation and global hook init finished."
echo "   Restart Claude Code so hooks take effect."
echo "   In Cursor: open Settings → Hooks and confirm the RTK hook runs; enable Claude/third-party"
echo "   hook compatibility if your Cursor version requires it for ~/.claude/settings.json."
echo "   Optional: run 'rtk init --show' as $SUDO_USER to verify hook and settings.json."
