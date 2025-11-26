#!/usr/bin/env bash

SETUP_FILE="fedora/setup.sh"
INSTALL_FILE="fedora/install.sh"

if [[ ! -f "$SETUP_FILE" ]]; then
  echo "❌ fedora/setup.sh not found!"
  exit 1
fi

HASH=$(sha256sum "$SETUP_FILE" | awk '{print $1}')

echo "🔐 Generated SHA256:"
echo "$HASH"

echo "🔄 Updating install.sh..."

sed -i "s/^EXPECTED_HASH=.*/EXPECTED_HASH=\"$HASH\"/" "$INSTALL_FILE"

echo "✔ install.sh updated!"
