#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/Pipo.dmg"
  exit 64
fi

DMG=$1
: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to the Developer ID Application identity}"
: "${NOTARY_KEY_FILE:?Set NOTARY_KEY_FILE to an App Store Connect API key file}"
: "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID}"

test -f "$DMG"
codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" \
  --key "$NOTARY_KEY_FILE" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
