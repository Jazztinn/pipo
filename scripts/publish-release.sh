#!/bin/sh
set -eu

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 VERSION /path/to/Pipo.zip /path/to/Sparkle/bin [stable|beta]"
  exit 64
fi

VERSION=$1
ARCHIVE=$2
SPARKLE_BIN=$3
CHANNEL=${4:-stable}
SPARKLE_KEY_FILE=${SPARKLE_KEY_FILE:-}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TAG="v$VERSION"
APPCAST="$ROOT/appcast.xml"
CHANNEL_ARGS=""
if [ "$CHANNEL" = "beta" ]; then
  APPCAST="$ROOT/appcast-beta.xml"
  CHANNEL_ARGS="--channel beta"
elif [ "$CHANNEL" != "stable" ]; then
  echo "channel must be stable or beta"
  exit 64
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/pipo-release.XXXXXX")
EXTRACTED="$WORK/extracted"
UPDATES="$WORK/updates"
cleanup() {
  status=$?
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT

test -f "$ARCHIVE"
test -x "$SPARKLE_BIN/generate_appcast"

mkdir "$EXTRACTED" "$UPDATES"
ditto -x -k "$ARCHIVE" "$EXTRACTED"
test -d "$EXTRACTED/Pipo.app"
"$ROOT/scripts/build-dmg.sh" "$EXTRACTED/Pipo.app" "$UPDATES/Pipo-$VERSION-arm64.dmg"

set -- --account com.jazztinn.pipo
if [ -n "$SPARKLE_KEY_FILE" ]; then
  set -- --ed-key-file "$SPARKLE_KEY_FILE"
fi

"$SPARKLE_BIN/generate_appcast" \
  "$@" \
  --download-url-prefix "https://github.com/Jazztinn/pipo/releases/download/$TAG/" \
  --link "https://github.com/Jazztinn/pipo" \
  --maximum-deltas 0 \
  $CHANNEL_ARGS \
  -o "$APPCAST" \
  "$UPDATES"

gh release create "$TAG" \
  "$UPDATES/Pipo-$VERSION-arm64.dmg" \
  "$ARCHIVE#Pipo $VERSION portable ZIP" \
  --repo Jazztinn/pipo \
  --title "Pipo $VERSION" \
  --generate-notes

echo "Published $TAG. Commit and push $(basename "$APPCAST") to activate the update."
