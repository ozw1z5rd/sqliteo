#!/usr/bin/env bash
set -euo pipefail

ICON_SRC="AppIcon.png"
ASSETS_DIR="Sources/SQLiteo/Assets.xcassets"
ICON_SET="${ASSETS_DIR}/AppIcon.appiconset"

if [ ! -f "$ICON_SRC" ]; then
    echo "Error: $ICON_SRC not found."
    exit 1
fi

echo "Populating Asset Catalog $ICON_SET from $ICON_SRC..."

mkdir -p "$ICON_SET"

sips -z 16 16     "$ICON_SRC" --out "$ICON_SET/icon_16x16.png" > /dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICON_SET/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$ICON_SRC" --out "$ICON_SET/icon_32x32.png" > /dev/null
sips -z 64 64     "$ICON_SRC" --out "$ICON_SET/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$ICON_SRC" --out "$ICON_SET/icon_128x128.png" > /dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICON_SET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$ICON_SRC" --out "$ICON_SET/icon_256x256.png" > /dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICON_SET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$ICON_SRC" --out "$ICON_SET/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICON_SET/icon_512x512@2x.png" > /dev/null

cat << 'EOF' > "$ICON_SET/Contents.json"
{
  "images": [
    { "size": "16x16",   "idiom": "mac", "filename": "icon_16x16.png",       "scale": "1x" },
    { "size": "16x16",   "idiom": "mac", "filename": "icon_16x16@2x.png",    "scale": "2x" },
    { "size": "32x32",   "idiom": "mac", "filename": "icon_32x32.png",       "scale": "1x" },
    { "size": "32x32",   "idiom": "mac", "filename": "icon_32x32@2x.png",    "scale": "2x" },
    { "size": "128x128", "idiom": "mac", "filename": "icon_128x128.png",     "scale": "1x" },
    { "size": "128x128", "idiom": "mac", "filename": "icon_128x128@2x.png",  "scale": "2x" },
    { "size": "256x256", "idiom": "mac", "filename": "icon_256x256.png",     "scale": "1x" },
    { "size": "256x256", "idiom": "mac", "filename": "icon_256x256@2x.png",  "scale": "2x" },
    { "size": "512x512", "idiom": "mac", "filename": "icon_512x512.png",     "scale": "1x" },
    { "size": "512x512", "idiom": "mac", "filename": "icon_512x512@2x.png",  "scale": "2x" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
EOF

echo "Successfully populated $ICON_SET!"

