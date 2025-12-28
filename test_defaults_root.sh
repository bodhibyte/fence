#!/bin/bash
# Test: Does root see the same NSUserDefaults as the user?

KEY="SCWeekCommitment_2025-12-22"

echo "=== As user ($(whoami)) ==="
defaults read org.eyebeam.SelfControl "$KEY" 2>&1

echo ""
echo "=== As root ==="
sudo defaults read org.eyebeam.SelfControl "$KEY" 2>&1

echo ""
echo "=== Conclusion ==="
echo "If root shows 'does not exist' but user shows a date,"
echo "that proves the daemon can't read user preferences."
