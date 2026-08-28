#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/Pipo.app"
  exit 64
fi

APP=$1

test -x "$APP/Contents/MacOS/PipoApp"
test -x "$APP/Contents/MacOS/pipo-core"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/index.html"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/css/fontawesome.min.css"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/webfonts/fa-solid-900.woff2"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/PipoLogoHollow.png"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/WhatsNew.json"
test -s "$APP/Contents/Resources/Legal/LICENSE.txt"
test -s "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/PipoApp" -verify_arch arm64 x86_64
lipo "$APP/Contents/MacOS/pipo-core" -verify_arch arm64 x86_64
if [ "${REQUIRE_NOTARIZATION:-0}" = "1" ]; then
  spctl --assess --type execute --verbose=2 "$APP"
  xcrun stapler validate "$APP"
else
  spctl --assess --type execute --verbose=2 "$APP" || echo "Gatekeeper acceptance is required only for notarized release builds." >&2
fi
