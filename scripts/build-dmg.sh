#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 /path/to/Pipo.app /path/to/Pipo.dmg"
  exit 64
fi

APP=$1
OUTPUT=$2
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BACKGROUND="$ROOT/app/Resources/DMGBackground.png"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/pipo-dmg.XXXXXX")
RW_DMG=$(mktemp "${TMPDIR:-/tmp}/pipo-rw.XXXXXX.dmg")
MOUNT_POINT="/Volumes/Pipo Installer"
trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW_DMG"' EXIT

test -d "$APP"
test -f "$BACKGROUND"

cp -R "$APP" "$STAGE/Pipo.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/background.png"

hdiutil create -quiet -volname "Pipo Installer" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG"

osascript <<'APPLESCRIPT'
tell application "Finder"
  tell disk "Pipo Installer"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 760, 520}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Pipo.app" of container window to {190, 238}
    set position of item "Applications" of container window to {470, 238}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"
echo "$OUTPUT"
