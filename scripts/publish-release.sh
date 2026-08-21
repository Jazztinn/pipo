#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 VERSION /path/to/Pipo.zip /path/to/Sparkle/bin"
  exit 64
fi

VERSION=$1
ARCHIVE=$2
SPARKLE_BIN=$3
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TAG="v$VERSION"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/pipo-release.XXXXXX")
EXTRACTED="$WORK/extracted"
UPDATES="$WORK/updates"
trap 'rm -rf "$WORK"' EXIT

test -f "$ARCHIVE"
test -x "$SPARKLE_BIN/generate_appcast"

mkdir "$EXTRACTED" "$UPDATES"
ditto -x -k "$ARCHIVE" "$EXTRACTED"
test -d "$EXTRACTED/Pipo.app"
"$ROOT/scripts/build-dmg.sh" "$EXTRACTED/Pipo.app" "$UPDATES/Pipo-$VERSION-arm64.dmg"

/usr/bin/script -q /dev/null "$SPARKLE_BIN/generate_appcast" \
  --account com.jazztinn.pipo \
  --download-url-prefix "https://github.com/Jazztinn/pipo/releases/download/$TAG/" \
  --link "https://github.com/Jazztinn/pipo" \
  --maximum-deltas 0 \
  -o "$ROOT/appcast.xml" \
  "$UPDATES"

gh release create "$TAG" \
  "$UPDATES/Pipo-$VERSION-arm64.dmg" \
  "$ARCHIVE#Pipo $VERSION portable ZIP" \
  --repo Jazztinn/pipo \
  --title "Pipo $VERSION" \
  --generate-notes

echo "Published $TAG. Commit and push appcast.xml to activate the update."
