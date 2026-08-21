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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cargo build --manifest-path "$ROOT/rust/Cargo.toml" --release --bin pipo-core
swift build --package-path "$ROOT" -c release

cp "$ROOT/.build/release/PipoApp" "$APP/Contents/MacOS/PipoApp"
cp "$ROOT/rust/target/release/pipo-core" "$APP/Contents/MacOS/pipo-core"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "$APP"

