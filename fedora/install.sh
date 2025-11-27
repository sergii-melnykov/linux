#!/usr/bin/env bash
set -e

URL="https://raw.githubusercontent.com/sergii-melnykov/linux/refs/heads/main/fedora/setup.sh"
EXPECTED_HASH="f1d8dd5bdb7b4deceeb756f7d907dafb9911d9f3dfeb1a4a2ce5f27cce374540"
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
# sudo bash "$TMP_FILE"
