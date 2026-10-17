#!/bin/bash
# Report whether the Dicticus process on this Mac is the canonical install.
#
# Usage:
#   ./scripts/check-running-copy.sh          # exit 0 only if /Applications/Dicticus.app is the sole running copy
#   ./scripts/check-running-copy.sh --fix    # also kill strays and relaunch the canonical copy by path
#   ./scripts/check-running-copy.sh --quiet  # print nothing when everything is fine
#
# Exit codes: 0 canonical copy is the only one running; 1 a stray copy is running
# (an xcodebuild test host, an old DerivedData build, a trashed install); 2 no
# Dicticus is running at all.
#
# Background: `xcodebuild test` launches the Debug Dicticus.app in DerivedData as
# the test host. If that run hangs or the canonical app quits, the stale host
# keeps the hotkey and writes no debug log, and LaunchServices may keep
# relaunching it (2026-10-17). Dev-only.
set -uo pipefail

CANONICAL_APP="/Applications/Dicticus.app"
CANONICAL_BIN="$CANONICAL_APP/Contents/MacOS/Dicticus"
FIX=0
QUIET=0
for arg in "$@"; do
    case "$arg" in
      --fix) FIX=1 ;;
      --quiet) QUIET=1 ;;
    esac
done

running=$(ps -axo pid=,comm= | grep "Dicticus.app/Contents/MacOS/Dicticus$" || true)
strays=$(printf '%s\n' "$running" | awk -v bin="$CANONICAL_BIN" 'NF && $2 != bin')
canonical=$(printf '%s\n' "$running" | awk -v bin="$CANONICAL_BIN" '$2 == bin')

if [ -z "$strays" ] && [ -n "$canonical" ]; then
    [ "$QUIET" = 1 ] || echo "OK: only $CANONICAL_APP is running (pid $(printf '%s' "$canonical" | awk '{print $1}'))"
    exit 0
fi

if [ -n "$strays" ]; then
    echo "STRAY Dicticus process(es) running outside $CANONICAL_APP:"
    printf '%s\n' "$strays" | awk '{print "  pid " $1 ": " $2}'
fi
[ -z "$canonical" ] && echo "Canonical $CANONICAL_APP is not running."

if [ "$FIX" = 1 ]; then
    if [ -n "$strays" ]; then
        printf '%s\n' "$strays" | awk '{print $1}' | xargs kill 2>/dev/null || true
        sleep 1
    fi
    if [ -z "$canonical" ] && [ -d "$CANONICAL_APP" ]; then
        open "$CANONICAL_APP"   # by path, never by bundle id
        sleep 3
    fi
    if [ "$QUIET" = 1 ]; then exec "$0" --quiet; else exec "$0"; fi
fi

[ -n "$strays" ] && exit 1
exit 2
