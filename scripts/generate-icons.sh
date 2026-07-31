#!/bin/bash
# Regenerate Dicticus app icons from assets/icon-master.png.
#
# Reads:    assets/icon-master.png (must be 1024×1024 PNG)
# Writes:   macOS/Dicticus/Assets.xcassets/AppIcon.appiconset/icon_*.png  (10 files)
#           iOS/Dicticus/Assets.xcassets/AppIcon.appiconset/AppIcon.png   (1 file)
#
# Generated outputs are committed to git so PR diffs catch unintended icon changes.
#
# Usage:
#   ./scripts/generate-icons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MASTER="$REPO_ROOT/assets/icon-master.png"
MAC_APPICONSET="$REPO_ROOT/macOS/Dicticus/Assets.xcassets/AppIcon.appiconset"
IOS_APPICON="$REPO_ROOT/iOS/Dicticus/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

echo "=== Step 1: Verify master ==="
if [ ! -f "$MASTER" ]; then
    echo "ERROR: $MASTER not found."
    echo "Place a 1024×1024 PNG at assets/icon-master.png and re-run."
    exit 1
fi
W=$(sips -g pixelWidth  "$MASTER" 2>/dev/null | awk '/pixelWidth/  {print $2}')
H=$(sips -g pixelHeight "$MASTER" 2>/dev/null | awk '/pixelHeight/ {print $2}')
if [ "$W" != "1024" ] || [ "$H" != "1024" ]; then
    echo "ERROR: $MASTER is ${W}x${H}; must be 1024x1024."
    exit 1
fi

echo "=== Step 2: Verify macOS appiconset ==="
if [ ! -d "$MAC_APPICONSET" ]; then
    echo "ERROR: $MAC_APPICONSET not found."
    exit 1
fi
if [ ! -f "$MAC_APPICONSET/Contents.json" ]; then
    echo "ERROR: $MAC_APPICONSET/Contents.json missing."
    exit 1
fi

echo "=== Step 3: Generate macOS appiconset PNGs ==="
# Format: "filename:size_px"
SLOTS=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)
for slot in "${SLOTS[@]}"; do
    filename="${slot%%:*}"
    size="${slot##*:}"
    out="$MAC_APPICONSET/$filename"
    sips -z "$size" "$size" "$MASTER" --out "$out" >/dev/null
    echo "  $filename (${size}x${size})"
done

echo "=== Step 4: Overwrite iOS AppIcon.png ==="
if [ ! -d "$(dirname "$IOS_APPICON")" ]; then
    echo "ERROR: $(dirname "$IOS_APPICON") not found."
    exit 1
fi
cp "$MASTER" "$IOS_APPICON"
echo "  $IOS_APPICON"

echo ""
echo "=== Done ==="
echo "macOS: 10 PNGs regenerated in $MAC_APPICONSET"
echo "iOS:   1 PNG overwritten at $IOS_APPICON"
echo ""
echo "Next steps:"
echo "  1. Review the diff visually:  git diff -- macOS/Dicticus/Assets.xcassets/AppIcon.appiconset iOS/Dicticus/Assets.xcassets/AppIcon.appiconset"
echo "  2. Commit the regenerated icons."
echo "  3. Clean-build and verify the icon appears in Finder for /Applications/Dicticus.app."
echo "     If it does not, run /gsd-debug to isolate (xcodegen, codesign, asset catalog, LaunchServices cache)."
