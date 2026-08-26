#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST="$ROOT/dist"
APP="$DIST/Pipo.app"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required. Install Xcode, then select it with xcode-select."
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Legal" "$APP/Contents/Frameworks"

cargo build --manifest-path "$ROOT/rust/Cargo.toml" --release --bin pipo-core
swift build --package-path "$ROOT" -c release
SWIFT_BIN_PATH=$(swift build --package-path "$ROOT" -c release --show-bin-path)

cp "$ROOT/.build/release/PipoApp" "$APP/Contents/MacOS/PipoApp"
cp "$ROOT/rust/target/release/pipo-core" "$APP/Contents/MacOS/pipo-core"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/app/Resources/PipoIcon.png" "$APP/Contents/Resources/PipoIcon.png"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Legal/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"
test -s "$APP/Contents/Resources/Legal/LICENSE.txt"
test -s "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"

PIPO_UI_BUNDLE="$SWIFT_BIN_PATH/Pipo_PipoUI.bundle"
if [ ! -d "$PIPO_UI_BUNDLE/MenuWeb" ]; then
  echo "PipoUI resource bundle was not produced with MenuWeb assets."
  exit 1
fi
cp -R "$PIPO_UI_BUNDLE" "$APP/Contents/Resources/Pipo_PipoUI.bundle"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/index.html"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/css/fontawesome.min.css"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/webfonts/fa-solid-900.woff2"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/PipoLogoHollow.png"

SPARKLE_FRAMEWORK=$(find "$ROOT/.build" -type d -name Sparkle.framework -print -quit)
if [ -z "$SPARKLE_FRAMEWORK" ]; then
  echo "Sparkle.framework was not produced by the Swift build."
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# SwiftPM links Sparkle with @rpath; point that lookup at the app framework folder.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/PipoApp"

# Re-seal the assembled bundle after copying resources and nested code. Release
# automation supplies a Developer ID identity; local builds stay ad-hoc signed.
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
if [ "$CODESIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

echo "$APP"
