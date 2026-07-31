#!/bin/bash
# Verify Dicticus memory usage against the 3 GB budget (INFRA-04).
#
# Usage: ./scripts/verify-memory.sh
#
# Prerequisites: Dicticus.app must be running with both ASR and LLM models loaded.
# Wait for the menu bar dropdown to show "Ready" status for both models before running.
#
# The key metric is phys_footprint -- this matches Activity Monitor's "Memory" column
# and represents the app's actual impact on system memory.
set -euo pipefail

BUDGET_BYTES=3221225472  # 3 GB in bytes
BUDGET_MB=3072           # 3 GB in MB
APP_NAME="Dicticus"

echo "=== Dicticus Memory Budget Verification ==="
echo "Budget: ${BUDGET_MB} MB (3 GB)"
echo ""

# Check if Dicticus is running
PID=$(pgrep -x "$APP_NAME" 2>/dev/null || true)
if [ -z "$PID" ]; then
    echo "ERROR: $APP_NAME is not running."
    echo "Launch $APP_NAME and wait for both ASR and LLM models to load,"
    echo "then re-run this script."
    exit 1
fi

echo "Found $APP_NAME (PID: $PID)"
echo ""

# Capture full footprint
echo "=== Full Memory Footprint ==="
footprint -p "$APP_NAME"

echo ""
echo "=== Detailed Breakdown ==="
footprint -p "$APP_NAME" -w

echo ""
echo "=== Budget Check ==="

# Extract phys_footprint value
FOOTPRINT_LINE=$(footprint -p "$APP_NAME" 2>/dev/null | grep "phys_footprint" | head -1)
echo "Measured: $FOOTPRINT_LINE"

# Parse the MB value (footprint outputs like "phys_footprint: 1234 MB")
FOOTPRINT_MB=$(echo "$FOOTPRINT_LINE" | grep -oE '[0-9]+' | head -1)

if [ -n "$FOOTPRINT_MB" ]; then
    if [ "$FOOTPRINT_MB" -le "$BUDGET_MB" ]; then
        echo "PASS: ${FOOTPRINT_MB} MB <= ${BUDGET_MB} MB budget"
    else
        echo "FAIL: ${FOOTPRINT_MB} MB > ${BUDGET_MB} MB budget"
        echo ""
        echo "Recommendations if over budget:"
        echo "  1. Unload LLM model between uses (lazy loading)"
        echo "  2. Use smaller LLM quantization"
        echo "  3. Reduce CoreML batch size"
        exit 1
    fi
else
    echo "WARNING: Could not parse phys_footprint value"
    echo "Check the output above manually."
fi
