#!/usr/bin/env bash
set -e

URL="https://raw.githubusercontent.com/YOUR_USERNAME/fedora-setup/main/setup.sh"
EXPECTED_HASH="186ece0c552a664b43a27ade49f72c9c2b6921a9aca05c9e2ef557f8cf052612"
TMP_FILE="/tmp/setup.sh"

echo "🔽 Downloading setup.sh..."
curl -fsSL "$URL" -o "$TMP_FILE"

echo "🔐 Verifying SHA256..."
DOWNLOADED_HASH=$(sha256sum "$TMP_FILE" | awk '{print $1}')

if [[ "$DOWNLOADED_HASH" != "$EXPECTED_HASH" ]]; then
    echo "❌ ERROR: SHA256 mismatch!"
    echo "Expected: $EXPECTED_HASH"
    echo "Got     : $DOWNLOADED_HASH"
    echo "⚠️ Aborting installation."
    rm -f "$TMP_FILE"
    exit 1
fi

echo "✔ Hash valid. Executing setup.sh..."
sudo bash "$TMP_FILE"
