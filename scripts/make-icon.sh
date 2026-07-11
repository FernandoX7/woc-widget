#!/bin/bash
# Regenerate Resources/AppIcon.icns from the companion's original scripts/icon-source.png art.
# Keep this source independent from the World of ClaudeCraft crest; the build copies the result.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="scripts/icon-source.png"
WORK="$(mktemp -d)"
MASTER="$WORK/master.png"

echo "› Rendering rounded 1024 master…"
swiftc -O scripts/make-icon.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$SRC" "$MASTER"

echo "› Building AppIcon.iconset…"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
gen() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"   # 1024

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"

rm -rf "$WORK"
