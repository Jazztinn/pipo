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
trap 'rm -rf "$WORK"' EXIT

test -f "$ARCHIVE"
test -x "$SPARKLE_BIN/generate_appcast"

cp "$ARCHIVE" "$WORK/Pipo-$VERSION-arm64.zip"

"$SPARKLE_BIN/generate_appcast" \
  --account com.jazztinn.pipo \
  --download-url-prefix "https://github.com/Jazztinn/pipo/releases/download/$TAG/" \
  --link "https://github.com/Jazztinn/pipo" \
  --maximum-deltas 0 \
  -o "$ROOT/appcast.xml" \
  "$WORK"

gh release create "$TAG" \
  "$WORK/Pipo-$VERSION-arm64.zip" \
  --repo Jazztinn/pipo \
  --title "Pipo $VERSION" \
  --generate-notes

echo "Published $TAG. Commit and push appcast.xml to activate the update."
