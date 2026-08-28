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
VERIFY_MOUNT=$(mktemp -d "${TMPDIR:-/tmp}/pipo-verify.XXXXXX")
trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; hdiutil detach "$VERIFY_MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW_DMG" "$VERIFY_MOUNT"' EXIT

test -d "$APP"
test -f "$BACKGROUND"
if [ -e "$MOUNT_POINT" ]; then
  echo "error: $MOUNT_POINT is already mounted; eject it before building" >&2
  exit 73
fi

BACKGROUND_WIDTH=$(sips -g pixelWidth "$BACKGROUND" | awk '/pixelWidth/ { print $2 }')
BACKGROUND_HEIGHT=$(sips -g pixelHeight "$BACKGROUND" | awk '/pixelHeight/ { print $2 }')
test "$BACKGROUND_WIDTH" = 1320
test "$BACKGROUND_HEIGHT" = 840

cp -R "$APP" "$STAGE/Pipo.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/background.png"

hdiutil create -quiet -volname "Pipo Installer" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG"

osascript <<'APPLESCRIPT'
tell application "Finder"
  repeat until disk "Pipo Installer" exists
    delay 0.1
  end repeat
  tell disk "Pipo Installer"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 760, 520}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 104
    set text size of theViewOptions to 14
    set label position of theViewOptions to bottom
    set shows icon preview of theViewOptions to false
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Pipo.app" of container window to {190, 238}
    set position of item "Applications" of container window to {470, 238}
    update without registering applications
    delay 1
    close
    delay 0.5
    open
    delay 2
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT"

hdiutil attach -quiet -readonly -noverify -noautoopen -mountpoint "$VERIFY_MOUNT" "$OUTPUT"
test -d "$VERIFY_MOUNT/Pipo.app"
test -L "$VERIFY_MOUNT/Applications"
test -f "$VERIFY_MOUNT/.background/background.png"
test -f "$VERIFY_MOUNT/.DS_Store"
hdiutil detach "$VERIFY_MOUNT" -quiet

echo "$OUTPUT"
