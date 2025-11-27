#!/usr/bin/env bash
set -e

URL="https://raw.githubusercontent.com/sergii-melnykov/linux/refs/heads/main/fedora/setup.sh"
EXPECTED_HASH="ed703fbb6c18774af88cd7031a305274dacc2a1526c4edcbd7227ae7613aef5c"
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
