#!/bin/bash
# Builds and packages a release zip. Usage: VERSION=1.1 ./release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${VERSION:-1.0}"
APP_NAME="Vibe Translate"
DIST="$ROOT/dist"
ZIP="$DIST/VibeTranslate-$VERSION.zip"

VERSION="$VERSION" "$ROOT/build.sh"

rm -rf "$DIST"
mkdir -p "$DIST"

# ditto preserves the code signature; a plain `zip` does not.
ditto -c -k --keepParent "$ROOT/build/$APP_NAME.app" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo
echo "Release artifact: $ZIP"
