#!/bin/bash
# Build, Sign, and Notarize Dicticus.app and package as a styled DMG.
#
# Usage:
#   op run --env-file=.env -- ./scripts/build-dmg.sh
#
# Output: Dicticus.dmg in the project root
#
# Requirements:
#   - Xcode, xcodegen, create-dmg (brew install create-dmg)
#   - Apple Developer ID Application certificate in Keychain
#   - Environment variables: DEVELOPER_TEAM_ID, APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, SPARKLE_PRIVATE_KEY
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/macOS"
OUTPUT_DIR="$(dirname "$SCRIPT_DIR")"
DMG_NAME="Dicticus.dmg"

# Verify environment variables
if [ -z "${DEVELOPER_TEAM_ID:-}" ] || [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] || [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
    echo "ERROR: Missing required environment variables."
    echo "Expected: DEVELOPER_TEAM_ID, APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, SPARKLE_PRIVATE_KEY"
    echo "Use 'op run --env-file=.env.build -- $0' to inject them safely."
    exit 1
fi

echo "=== Step 1: Generate Xcode project ==="
cd "$PROJECT_DIR"
# DEVELOPER_TEAM_ID is passed to xcodegen for the project.yml reference
export DEVELOPER_TEAM_ID
xcodegen generate

echo "=== Step 2: Build Release .app (Unsigned) ==="
# Build unsigned. Step 3 does the real Developer ID signing with --deep --force.
# This avoids xcodebuild's provisioning-profile requirement triggered by the
# com.apple.security.application-groups entitlement under manual signing,
# and keeps SPM resource bundles (KeyboardShortcuts, GRDB) from trying to
# sign with a Developer ID identity that doesn't apply to them.
xcodebuild -scheme Dicticus \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_DIR="build/Build/Products/Release"

# Verify the .app exists
if [ ! -d "$APP_DIR/Dicticus.app" ]; then
    echo "ERROR: Dicticus.app not found at $APP_DIR/"
    exit 1
fi

# Ensure the Developer ID key is present; auto-restore from 1Password if missing (D-02/D-03).
# shellcheck source=scripts/_signing-guard.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_signing-guard.sh"

# Re-sign the entire app bundle (including embedded frameworks) with the real identity.
echo "=== Step 3: Re-sign app bundle with Developer ID ==="
codesign --force --deep --sign "Developer ID Application" \
    --options runtime \
    --entitlements "Dicticus/Dicticus.entitlements" \
    "$APP_DIR/Dicticus.app"

echo "=== Step 4: Verify signing and entitlements ==="
codesign -vvv --deep --strict "$APP_DIR/Dicticus.app"
codesign -d --entitlements :- "$APP_DIR/Dicticus.app" 2>/dev/null || echo "WARNING: Could not read entitlements"

echo "=== Step 5: Create styled DMG ==="
# Remove existing DMG if present
rm -f "$OUTPUT_DIR/$DMG_NAME"

# Stage only Dicticus.app
STAGING_DIR=$(mktemp -d)
cp -R "$APP_DIR/Dicticus.app" "$STAGING_DIR/"
trap "rm -rf '$STAGING_DIR'" EXIT

EXIT_CODE=0
create-dmg \
    --volname "Dicticus" \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "Dicticus.app" 180 200 \
    --app-drop-link 480 200 \
    --no-internet-enable \
    --hide-extension "Dicticus.app" \
    "$OUTPUT_DIR/$DMG_NAME" \
    "$STAGING_DIR/" || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] && [ ! -f "$OUTPUT_DIR/$DMG_NAME" ]; then
    echo "ERROR: create-dmg failed (exit code $EXIT_CODE)"
    exit 1
fi

echo "=== Step 6: Notarize DMG ==="
xcrun notarytool submit "$OUTPUT_DIR/$DMG_NAME" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$DEVELOPER_TEAM_ID" \
    --wait

echo "=== Step 7: Staple Notarization Ticket ==="
xcrun stapler staple "$OUTPUT_DIR/$DMG_NAME"

echo "=== Step 8: Generate Sparkle Appcast Metadata ==="
SIGN_UPDATE_TOOL="$PROJECT_DIR/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
if [ ! -f "$SIGN_UPDATE_TOOL" ]; then
    echo "WARNING: Sparkle sign_update tool not found at $SIGN_UPDATE_TOOL"
else
    # sign_update prints an <enclosure> tag for the appcast.xml
    # It requires the private key as a string (passed via env or stdin)
    echo "Sparkle Enclosure Metadata:"
    echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE_TOOL" "$OUTPUT_DIR/$DMG_NAME"
fi

echo "=== Done ==="
echo "DMG created and notarized: $OUTPUT_DIR/$DMG_NAME"
echo ""
echo "To install:"
echo "  1. Double-click $DMG_NAME to mount"
echo "  2. Drag Dicticus.app to Applications"
echo "  3. Open Dicticus from Applications (no Gatekeeper override needed)"
echo ""
echo "Next Steps for Update Distribution:"
echo "  1. Upload $DMG_NAME to a GitHub Release."
echo "  2. Update the appcast.xml on GitHub Pages using the metadata printed above."
