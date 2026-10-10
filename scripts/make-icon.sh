#!/bin/zsh
# Regenerates Resources/AppIcon.icns and AppIcon-source.png from the editable
# Resources/AppIcon.svg. Requires rsvg-convert (brew install librsvg).
set -euo pipefail

cd "$(dirname "$0")/.."

SVG="Resources/AppIcon.svg"
WORK=$(mktemp -d)
ICONSET="$WORK/AppIcon.iconset"
mkdir "$ICONSET"

for size in 16 32 128 256 512; do
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$ICONSET/icon_${size}x${size}.png"
    double=$((size * 2))
    rsvg-convert -w "$double" -h "$double" "$SVG" -o "$ICONSET/icon_${size}x${size}@2x.png"
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$ICONSET/icon_512x512@2x.png" Resources/AppIcon-source.png
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns and Resources/AppIcon-source.png"
