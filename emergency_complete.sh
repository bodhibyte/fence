#!/bin/bash
# Complete Emergency Wipe - kills processes too
# For TERMINAL USE ONLY (not called from app UI)
# Run with: sudo ./emergency_complete.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Fence Complete Emergency Wipe ==="
echo "(Terminal use only - will kill app processes)"
echo ""

# Run the standard emergency cleanup
"$SCRIPT_DIR/emergency.sh"

# Kill all related processes
echo "Killing Fence/SelfControl processes..."
pkill -9 -f Fence 2>/dev/null || true
pkill -9 -f selfcontrol 2>/dev/null || true
killall org.eyebeam.selfcontrold 2>/dev/null || true

sleep 0.5

# Verify no processes remain
echo ""
echo "=== Process Check ==="
if ps aux | grep -iE "[F]ence|[s]elfcontrol" | grep -v grep; then
    echo "WARNING: Some processes may still be running"
else
    echo "All processes terminated"
fi

echo ""
echo "=== Complete Wipe Done ==="
