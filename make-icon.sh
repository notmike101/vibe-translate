#!/bin/bash
# Regenerates Resources/AppIcon.icns from Tools/MakeIcon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O -o "$TMP/makeicon" "$ROOT/Tools/MakeIcon.swift"
"$TMP/makeicon" "$TMP/AppIcon.iconset"
mkdir -p "$ROOT/Resources"
iconutil -c icns -o "$ROOT/Resources/AppIcon.icns" "$TMP/AppIcon.iconset"
echo "Wrote $ROOT/Resources/AppIcon.icns"
