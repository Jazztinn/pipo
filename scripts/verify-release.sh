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
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
