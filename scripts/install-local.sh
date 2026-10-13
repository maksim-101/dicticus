#!/bin/bash
# Consolidate multiple Dicticus.app installations to /Applications/Dicticus.app.
#
# Usage:
#   ./scripts/install-local.sh
#
# Behavior:
#   1. Gracefully quits any running Dicticus instance.
#   2. Enumerates every com.dicticus.app bundle on disk via mdfind.
#   3. Trashes (mv ~/.Trash/) every copy that is NOT /Applications/Dicticus.app,
#      excluding ~/.Trash, Time Machine snapshots, and dev build artifacts
#      (project build/ subdir + Xcode DerivedData).
#   4. Wipes the specific Dicticus DerivedData folder to prevent identity confusion.
#   5. Copies the freshly-built Release .app from macOS/build/ to /Applications/.
#   6. Re-signs the app with the Developer ID identity in DEVID_SIGNING_HASH for TCC persistence.
#   7. Re-launches via explicit `open "$CANONICAL_APP"` path and verifies the running process.
#
# Dev-only — do not run on end-user machines.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")/macOS"
BUNDLE_ID="com.dicticus.app"
CANONICAL_APP="/Applications/Dicticus.app"
BUILD_APP="$PROJECT_DIR/build/Build/Products/Release/Dicticus.app"
RECORDER_APP="$PROJECT_DIR/build/Build/Products/Debug-Recorder/Dicticus.app"
DEBUG_APP="$PROJECT_DIR/build/Build/Products/Debug/Dicticus.app"
SIGNING_ID="${DEVID_SIGNING_HASH:?DEVID_SIGNING_HASH is not set (see env.build.example)}"
ENTITLEMENTS="$PROJECT_DIR/Dicticus/Dicticus.entitlements"
TRASH_DIR="$HOME/.Trash"
TIMESTAMP="$(date +%s)"

echo "=== Step 1: Verify build artefact ==="
if [ -d "$RECORDER_APP" ]; then
    echo "  Using Debug-Recorder build."
    SOURCE_APP="$RECORDER_APP"
elif [ -d "$BUILD_APP" ]; then
    echo "  Using Release build."
    SOURCE_APP="$BUILD_APP"
else
    echo "ERROR: Dicticus.app not found at $BUILD_APP or $RECORDER_APP"
    echo "Run scripts/build-dmg.sh or xcodebuild -scheme Dicticus -configuration Release first."
    exit 1
fi

echo "=== Step 2: Quit any running Dicticus instance ==="
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
for i in 1 2 3; do
    if ! pgrep -x "Dicticus" >/dev/null 2>&1; then break; fi
    sleep 1
done
if pgrep -x "Dicticus" >/dev/null 2>&1; then
    echo "  Dicticus still running after 3s — forcing pkill -f Dicticus.app"
    pkill -f "Dicticus.app" || true
    sleep 1
fi

echo "=== Step 3: Enumerate stale Dicticus.app copies ==="
STALE_COPIES=()
while IFS= read -r path; do
    [ -z "$path" ] && continue
    # Whitelist guard — must be a Dicticus.app bundle
    case "$path" in
      */Dicticus.app) ;;
      *) continue ;;
    esac
    # Exclude canonical, Trash, Time Machine, and dev build artifacts
    case "$path" in
      "$CANONICAL_APP") continue ;;
      "$HOME/.Trash"/*) continue ;;
      */Backups.backupdb/*) continue ;;
      */.MobileBackups/*) continue ;;
      /Volumes/com.apple.TimeMachine.localsnapshots/*) continue ;;
      */build/Build/Products/*) continue ;;        # local xcodebuild output
    esac
    STALE_COPIES+=("$path")
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'")

if [ ${#STALE_COPIES[@]} -eq 0 ]; then
    echo "  No stale copies found."
else
    echo "  Found ${#STALE_COPIES[@]} stale copy/copies:"
    for p in "${STALE_COPIES[@]}"; do echo "    - $p"; done
fi

echo "=== Step 4: Trash stale copies & wipe DerivedData ==="
if [ ${#STALE_COPIES[@]} -gt 0 ]; then
    idx=0
    for p in "${STALE_COPIES[@]}"; do
        idx=$((idx + 1))
        # Include an index AND a hash of the path to guarantee unique trash filenames
        # when multiple stale copies share the same config name (e.g. all "Debug" from
        # different DerivedData folders).
        path_hash=$(printf '%s' "$p" | shasum | cut -c1-8)
        dest="$TRASH_DIR/Dicticus-stale-$TIMESTAMP-$(basename "$(dirname "$p")")-${idx}-${path_hash}.app"
        echo "  mv $p -> $dest"
        mv "$p" "$dest"
    done
fi
# Wipe Dicticus-specific DerivedData to prevent identity desync
DD_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Dicticus-*" -type d -maxdepth 1 2>/dev/null || true)
if [ -n "$DD_PATH" ]; then
    echo "  Cleaning DerivedData: $DD_PATH"
    rm -rf "$DD_PATH"
fi

echo "=== Step 5: Install fresh build to $CANONICAL_APP ==="
if [ -d "$CANONICAL_APP" ]; then
    dest="$TRASH_DIR/Dicticus-prev-$TIMESTAMP.app"
    echo "  Existing canonical install -> $dest"
    mv "$CANONICAL_APP" "$dest"
fi
cp -R "$SOURCE_APP" "$CANONICAL_APP"

echo "=== Step 5a: Prune old trashed Dicticus builds (keep newest 2) ==="
# Every run moves the replaced canonical + stale copies to ~/.Trash but never
# reclaims them, so repeated test iterations pile large bundles into Trash.
# Prune to the 2 most recent (undo safety), touching only bundles THIS script
# created (Dicticus-prev-* / Dicticus-stale-*). bash 3.2-safe (no mapfile).
TRASHED_BUILDS=()
while IFS= read -r line; do
    [ -z "$line" ] && continue
    TRASHED_BUILDS+=("$line")
done < <(find "$TRASH_DIR" -maxdepth 1 \( -name 'Dicticus-prev-*.app' -o -name 'Dicticus-stale-*.app' \) 2>/dev/null \
    | while IFS= read -r p; do printf '%s\t%s\n' "$(stat -f '%m' "$p" 2>/dev/null)" "$p"; done \
    | sort -rn | cut -f2-)
if [ "${#TRASHED_BUILDS[@]}" -gt 2 ]; then
    tidx=0
    for old in "${TRASHED_BUILDS[@]}"; do
        tidx=$((tidx + 1))
        [ "$tidx" -le 2 ] && continue
        echo "  Purging old trashed build: $(basename "$old")"
        rm -rf "$old"
    done
else
    echo "  ${#TRASHED_BUILDS[@]} trashed Dicticus build(s) — nothing to prune."
fi

echo "=== Step 5b: Inject build metadata ==="
PLIST="$CANONICAL_APP/Contents/Info.plist"
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date +%Y-%m-%d)
/usr/libexec/PlistBuddy -c "Add :GitCommit string $GIT_HASH" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :GitCommit $GIT_HASH" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :BuildDate string $BUILD_DATE" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :BuildDate $BUILD_DATE" "$PLIST"
echo "  Git: $GIT_HASH, Date: $BUILD_DATE"

echo "=== Step 5c: Remove build artifacts to prevent LaunchServices identity confusion ==="
# xcodebuild runs RegisterWithLaunchServices during the build, registering the
# unsigned build artifact. If both that copy and the signed /Applications copy
# exist simultaneously, macOS TCC sees conflicting signing identities for the
# same bundle ID and invalidates permissions on every restart.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
for artifact in "$BUILD_APP" "$RECORDER_APP" "$DEBUG_APP"; do
    if [ -d "$artifact" ]; then
        echo "  Unregistering: $artifact"
        "$LSREGISTER" -u "$artifact" 2>/dev/null || true
        echo "  Removing: $artifact"
        rm -rf "$artifact"
    fi
done
# Re-register ONLY the canonical signed copy
"$LSREGISTER" -f "$CANONICAL_APP" 2>/dev/null || true

source "$SCRIPT_DIR/_signing-guard.sh"

echo "=== Step 6: Re-sign for TCC persistence ==="
echo "  Signing with identity: $SIGNING_ID"
echo "  Hardened runtime + entitlements: $ENTITLEMENTS"
# IMPORTANT: --options runtime and --entitlements are required for the Designated
# Requirement to match what build-dmg.sh produces. Without them the entitlement
# set differs across installs (mic, app-groups, library-validation, etc.), TCC
# treats each install as a "different app" and re-prompts on every cycle.
# --timestamp adds the secure timestamp required for future notarization.
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "ERROR: entitlements file not found at $ENTITLEMENTS"
    exit 1
fi
codesign --force --deep \
    --sign "$SIGNING_ID" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$CANONICAL_APP"

echo "  Verifying signature ..."
codesign -vvv --deep --strict "$CANONICAL_APP" >/dev/null 2>&1 || {
    echo "ERROR: post-sign verification failed"
    exit 1
}

echo "=== Step 7: Relaunch ==="
open "$CANONICAL_APP"
sleep 2
RUNNING_PATH=$(lsappinfo info -only bundlepath -app Dicticus 2>/dev/null \
    | sed 's/.*="\(.*\)"/\1/' || true)
echo "  Running bundle path: $RUNNING_PATH"
if [ "$RUNNING_PATH" != "$CANONICAL_APP" ]; then
    echo "WARNING: running Dicticus is not the canonical copy ($RUNNING_PATH)"
fi

echo ""
echo "=== Done ==="
echo "Canonical install: $CANONICAL_APP"
echo "Stale copies trashed: ${#STALE_COPIES[@]}"
echo ""
echo "NOTE: TCC permission entries (Microphone / Accessibility / Input Monitoring)"
echo "cannot be cleaned programmatically. If hotkeys still misbehave, open"
echo "  System Settings > Privacy & Security"
echo "and remove any leftover Dicticus entries before re-granting."
