#!/bin/bash
# Archive, sign, export, and upload Dicticus.ipa to App Store Connect (TestFlight).
#
# Usage:
#   op run --env-file=.env.build -- ./scripts/build-ipa.sh
#
# Output: signed .ipa uploaded to App Store Connect; local artifacts in iOS/build/
#
# Requirements:
#   - Xcode, xcodegen
#   - App Store Connect API key (.p8) — Apple Distribution cert + App Store provisioning
#     profile are created automatically on first run via -allowProvisioningUpdates
#   - Environment variables: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID
#   - The .p8 file itself must be at Apple's standard path,
#     ~/.appstoreconnect/private_keys/AuthKey_<APP_STORE_CONNECT_KEY_ID>.p8 — the same
#     convention `xcrun altool` auto-discovers from. The path is derived from the Key ID
#     below rather than taken as a separate variable, so the two can never drift out of
#     sync (2026-09-13: a stale/mismatched path cost significant time to diagnose, since
#     the symptom was an opaque Apple API 401, not a clear "wrong file" error).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/iOS"

# Verify environment variables
if [ -z "${APP_STORE_CONNECT_KEY_ID:-}" ] || [ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
    echo "ERROR: Missing required environment variables."
    echo "Expected: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID"
    echo "Use 'op run --env-file=.env.build -- $0' to inject them safely."
    exit 1
fi

APP_STORE_CONNECT_API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
if [ ! -f "$APP_STORE_CONNECT_API_KEY_PATH" ]; then
    echo "ERROR: No .p8 key file at $APP_STORE_CONNECT_API_KEY_PATH"
    echo "  Apple's standard convention names the file after its Key ID — place it there,"
    echo "  or if APP_STORE_CONNECT_KEY_ID in .env.build is wrong, fix it there."
    exit 1
fi

echo "=== Step 1: Generate Xcode project ==="
cd "$PROJECT_DIR"
xcodegen generate

echo "=== Step 2: Archive Release build ==="
xcodebuild -scheme Dicticus \
    -configuration Release \
    -archivePath build/Dicticus.xcarchive \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH" \
    -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
    archive

echo "=== Step 3: Export and upload to App Store Connect ==="
xcodebuild -exportArchive \
    -archivePath build/Dicticus.xcarchive \
    -exportOptionsPlist exportOptions.plist \
    -exportPath build/export \
    -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH" \
    -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
    -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
    -allowProvisioningUpdates

echo "=== Step 4: Lint plist artifacts ==="
plutil -lint exportOptions.plist
plutil -lint Dicticus/PrivacyInfo.xcprivacy
plutil -lint Dicticus/Info.plist

echo "=== Done ==="
echo "Dicticus.ipa archived, exported, and uploaded to App Store Connect."
echo ""
echo "Next steps:"
echo "  1. Wait for the build to finish processing in App Store Connect."
echo "  2. Add the build to an EXTERNAL testing group in TestFlight (internal-only testing"
echo "     skips Apple's Beta App Review entirely — external testing is required to clear it)."
echo "  3. Testers install/update via the TestFlight app."
