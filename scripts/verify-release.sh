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
test -s "$APP/Contents/Resources/Legal/LICENSE.txt"
test -s "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
if spctl --assess --type execute --verbose=2 "$APP"; then
  echo "Gatekeeper accepted the app."
else
  echo "Gatekeeper did not accept this unnotarized testing build; the in-app pre-release notice covers this expected warning." >&2
fi
