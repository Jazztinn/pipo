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

RUST_TARGETS="aarch64-apple-darwin x86_64-apple-darwin"
for target in $RUST_TARGETS; do
  rustup target add "$target"
  cargo build --manifest-path "$ROOT/rust/Cargo.toml" --release --bin pipo-core --target "$target"
done

SWIFT_ARM_BUILD="$ROOT/.build/pipo-release-arm64"
SWIFT_INTEL_BUILD="$ROOT/.build/pipo-release-x86_64"
swift build --package-path "$ROOT" -c release --arch arm64 --scratch-path "$SWIFT_ARM_BUILD"
swift build --package-path "$ROOT" -c release --arch x86_64 --scratch-path "$SWIFT_INTEL_BUILD"
SWIFT_ARM_BIN=$(swift build --package-path "$ROOT" -c release --arch arm64 --scratch-path "$SWIFT_ARM_BUILD" --show-bin-path)
SWIFT_INTEL_BIN=$(swift build --package-path "$ROOT" -c release --arch x86_64 --scratch-path "$SWIFT_INTEL_BUILD" --show-bin-path)

lipo -create "$SWIFT_ARM_BIN/PipoApp" "$SWIFT_INTEL_BIN/PipoApp" -output "$APP/Contents/MacOS/PipoApp"
lipo -create \
  "$ROOT/rust/target/aarch64-apple-darwin/release/pipo-core" \
  "$ROOT/rust/target/x86_64-apple-darwin/release/pipo-core" \
  -output "$APP/Contents/MacOS/pipo-core"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/app/Resources/PipoIcon.png" "$APP/Contents/Resources/PipoIcon.png"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Legal/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"
test -s "$APP/Contents/Resources/Legal/LICENSE.txt"
test -s "$APP/Contents/Resources/Legal/THIRD_PARTY_NOTICES.md"

PIPO_UI_BUNDLE="$SWIFT_ARM_BIN/Pipo_PipoUI.bundle"
if [ ! -d "$PIPO_UI_BUNDLE/MenuWeb" ]; then
  echo "PipoUI resource bundle was not produced with MenuWeb assets."
  exit 1
fi
cp -R "$PIPO_UI_BUNDLE" "$APP/Contents/Resources/Pipo_PipoUI.bundle"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/index.html"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/css/fontawesome.min.css"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/MenuWeb/webfonts/fa-solid-900.woff2"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/PipoLogoHollow.png"
test -f "$APP/Contents/Resources/Pipo_PipoUI.bundle/WhatsNew.json"

SPARKLE_FRAMEWORK=$(find "$SWIFT_ARM_BUILD" -type d -name Sparkle.framework -print -quit)
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
sign_path() {
  target=$1
  if [ "$CODESIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$target"
  else
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$target"
  fi
}

# Sign nested Sparkle code from the deepest executables outward.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign_path "$SPARKLE/Versions/B/Autoupdate"
sign_path "$SPARKLE/Versions/B/Updater.app"
sign_path "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign_path "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign_path "$SPARKLE"
sign_path "$APP/Contents/MacOS/pipo-core"
sign_path "$APP/Contents/MacOS/PipoApp"
sign_path "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/PipoApp" -verify_arch arm64 x86_64
lipo "$APP/Contents/MacOS/pipo-core" -verify_arch arm64 x86_64

echo "$APP"
