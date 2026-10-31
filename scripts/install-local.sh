#!/bin/bash
# Consolidate multiple Dicticus.app installations to /Applications/Dicticus.app.
#
# Usage:
#   ./scripts/install-local.sh
#
# Behavior:
#   1. Quits every running Dicticus instance, including xcodebuild test hosts
#      and old DerivedData builds (pkill by path, not only the bundle id).
#   2. Enumerates Dicticus.app bundles from the LaunchServices database plus a
#      `find` over the known build locations. Spotlight (`mdfind`) is not used:
#      it hung for 30 minutes on this query on 2026-10-17 and a hung sweep
#      silently installs on top of the stale copies it was meant to remove.
#   3. Trashes (mv ~/.Trash/) every on-disk copy that is NOT /Applications/Dicticus.app,
#      excluding ~/.Trash, Time Machine snapshots, and dev build artifacts
#      (project build/ subdir + Xcode DerivedData), and unregisters EVERY
#      non-canonical LaunchServices entry, dead paths included, then compacts
#      the database. Stale registrations are what let a bundle-id launch pick
#      an old copy (73 of them had accumulated by 2026-10-17).
#   4. Wipes every Dicticus-* DerivedData folder to prevent identity confusion.
#   5. Copies the freshly-built Release .app from macOS/build/ to /Applications/.
#   6. Re-signs the app with the Developer ID identity in DEVID_SIGNING_HASH for TCC persistence.
#   7. Re-launches via explicit `open "$CANONICAL_APP"` path and FAILS (exit 1)
#      unless the only running Dicticus binary is the canonical one.
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
RECORDER_TEST_APP="$PROJECT_DIR/build/Build/Products/Debug-Recorder-Test/Dicticus.app"
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
# The AppleScript quit reaches one process per bundle id; a test host or an old
# DerivedData build running alongside survives it. Kill by binary path.
STRAYS=$(ps -axo pid=,comm= | grep "Dicticus.app/Contents/MacOS/Dicticus$" || true)
if [ -n "$STRAYS" ]; then
    echo "  Killing Dicticus processes still running:"
    printf '%s\n' "$STRAYS" | awk '{print "    pid " $1 ": " $2}'
    printf '%s\n' "$STRAYS" | awk '{print $1}' | xargs kill -9 2>/dev/null || true
    sleep 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "=== Step 3: Enumerate stale Dicticus.app copies (LaunchServices + find, no Spotlight) ==="
# Every registered path, live or dead, minus the canonical one. Dead paths are
# unregistered below; live ones also go through the trash step.
LS_REGISTERED=()
while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ "$path" = "$CANONICAL_APP" ] && continue
    LS_REGISTERED+=("$path")
done < <("$LSREGISTER" -dump 2>/dev/null \
    | grep -E '^[[:space:]]*path:[[:space:]]*.*Dicticus' \
    | sed -e 's/^[[:space:]]*path:[[:space:]]*//' -e 's/ (0x[0-9a-f]*)$//' \
    | grep -E '/Dicticus(-[^/]*)?\.app$' \
    | grep -v -E 'Debug-iphone|DicticusUITests|\.xcarchive/|XcodeDistPipeline' \
    | sort -u)
echo "  LaunchServices entries besides canonical: ${#LS_REGISTERED[@]}"

STALE_COPIES=()
while IFS= read -r path; do
    [ -z "$path" ] && continue
    [ -d "$path" ] || continue
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
done < <( { printf '%s\n' "${LS_REGISTERED[@]+"${LS_REGISTERED[@]}"}"; \
            find /Applications "$HOME/Applications" "$HOME/Desktop" "$HOME/Downloads" \
                 "$HOME/Library/Developer/Xcode/DerivedData" "$PROJECT_DIR/build" \
                 -maxdepth 6 -name 'Dicticus.app' -type d 2>/dev/null; } \
          | grep -v -E 'Debug-iphone|\.xcarchive/' | sort -u)

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
# Wipe Dicticus-specific DerivedData to prevent identity desync. One folder per
# line: with two folders (macOS + iOS) the old single-variable form passed a
# path containing a newline to rm -rf, which deleted nothing and said nothing.
while IFS= read -r dd; do
    [ -z "$dd" ] && continue
    echo "  Cleaning DerivedData: $dd"
    rm -rf "$dd"
done < <(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "Dicticus-*" -type d 2>/dev/null || true)

echo "=== Step 4a: Unregister stale LaunchServices entries ==="
# Trashing a bundle leaves its registration behind, and a dead registration is
# enough for a bundle-id launch (osascript, open -b, Sparkle, login item) to
# resolve to the wrong copy. Unregister everything that is not canonical.
UNREG=0
for p in "${LS_REGISTERED[@]+"${LS_REGISTERED[@]}"}" "${STALE_COPIES[@]+"${STALE_COPIES[@]}"}"; do
    [ -z "$p" ] && continue
    "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true   # duplicate IDs for one path need a second pass
    UNREG=$((UNREG + 1))
done
"$LSREGISTER" -gc >/dev/null 2>&1 || true
echo "  Unregistered $UNREG path(s), database compacted."

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
for artifact in "$BUILD_APP" "$RECORDER_APP" "$DEBUG_APP" "$RECORDER_TEST_APP"; do
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
sleep 4
# Hard check by binary path (lsappinfo's output format is not stable across
# macOS versions and the old parse printed garbage). Exit 1 so an automated
# caller sees the failure instead of a WARNING line scrolling past.
if ! "$SCRIPT_DIR/check-running-copy.sh"; then
    echo "ERROR: the running Dicticus is not (only) $CANONICAL_APP — see above."
    exit 1
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
