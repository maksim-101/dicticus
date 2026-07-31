#!/bin/bash
# Remove Dicticus from this Mac.
#
# Removes (without prompting):
#   /Applications/Dicticus.app
#   ~/Library/Preferences/com.dicticus.*.plist
#   ~/Library/LaunchAgents/com.dicticus.app.plist (LaunchAtLogin entry)
#
# Prompts before removing:
#   ~/Library/Application Support/Dicticus/  (~3 GB models + history.sqlite)
#
# TCC permission entries cannot be cleaned programmatically — see final notes.
set -euo pipefail

APP_NAME="Dicticus"
APP_BUNDLE="/Applications/Dicticus.app"
PREFS_GLOB="$HOME/Library/Preferences/com.dicticus.*.plist"
APP_SUPPORT="$HOME/Library/Application Support/Dicticus"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.dicticus.app.plist"

echo "=== Step 1: Quit running $APP_NAME instance ==="
osascript -e 'tell application id "com.dicticus.app" to quit' 2>/dev/null || true
for i in 1 2 3; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then break; fi
    sleep 1
done
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -f "Dicticus.app" || true
    sleep 1
fi

echo "=== Step 2: Remove $APP_BUNDLE ==="
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
    echo "  Removed $APP_BUNDLE"
else
    echo "  Not present, skipping."
fi

echo "=== Step 3: Remove preference files and LaunchAtLogin entry ==="
for f in $PREFS_GLOB; do
    [ -e "$f" ] || continue
    rm -f "$f"
    echo "  Removed $f"
done
if [ -e "$LAUNCH_AGENT" ]; then
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
    echo "  Removed $LAUNCH_AGENT"
fi

echo "=== Step 4: Application Support directory (~3 GB) ==="
if [ -d "$APP_SUPPORT" ]; then
    SIZE=$(du -sh "$APP_SUPPORT" 2>/dev/null | cut -f1 || echo "?")
    echo "  $APP_SUPPORT ($SIZE)"
    echo "  Contains: Gemma LLM model, Parakeet ASR cache, history.sqlite"
    read -r -p "  Delete this directory? [y/N] " reply
    case "$reply" in
        [yY]|[yY][eE][sS])
            rm -rf "$APP_SUPPORT"
            echo "  Removed."
            ;;
        *)
            echo "  Kept."
            ;;
    esac
else
    echo "  Not present, skipping."
fi

echo ""
echo "=== Done ==="
echo ""
echo "NOTE: macOS TCC permission entries cannot be cleaned programmatically."
echo "If you plan to reinstall, open"
echo "  System Settings > Privacy & Security"
echo "and remove '$APP_NAME' from these panes:"
echo "  - Microphone"
echo "  - Accessibility"
echo "  - Input Monitoring"
