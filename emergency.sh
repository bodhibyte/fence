#!/bin/bash
# SelfControl Emergency Wipe Script
# Run with: sudo ./emergency.sh

set -e

echo "=== SelfControl Emergency Wipe ==="

# 1. Stop daemon
echo "Stopping daemon..."
launchctl bootout system/org.eyebeam.selfcontrold 2>/dev/null || echo "Daemon not running"

# 2. Clear firewall rules
echo "Clearing firewall rules..."
pfctl -a org.eyebeam -F all 2>/dev/null || echo "No pf rules to clear"

# 3. Clear hosts file
echo "Clearing hosts file..."
sed -i '' '/# BEGIN SELFCONTROL BLOCK/,/# END SELFCONTROL BLOCK/d' /etc/hosts

# 4. Flush DNS cache
echo "Flushing DNS cache..."
dscacheutil -flushcache
killall -HUP mDNSResponder 2>/dev/null || true

# 5. Clear settings plist
# (only non app specific step - this should be fine since explicitly chosen to be /usr/local/etc seperate from other app plists)
echo "Clearing settings plist..."
rm /usr/local/etc/.*.plist 2>/dev/null || echo "No settings plist found"

# 6. Clear schedule/commitment data from user defaults (run as actual user, not root)
echo "Clearing user defaults..."
CONSOLE_USER=$(stat -f "%Su" /dev/console)
sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.SelfControl SCIsCommitted 2>/dev/null || true
sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.SelfControl SCWeeklySchedules 2>/dev/null || true

# Clear week-specific keys (check for any SCWeekSchedules_* or SCWeekCommitment_*)
for key in $(sudo -u "$CONSOLE_USER" defaults read org.eyebeam.SelfControl 2>/dev/null | grep -oE "SCWeek(Schedules|Commitment)_[0-9-]+" | sort -u); do
    echo "  Deleting $key..."
    sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.SelfControl "$key" 2>/dev/null || true
done

echo ""
echo "=== Wipe Complete ==="
echo "Verify with:"
echo "  pfctl -a org.eyebeam -sr  (should show nothing)"
echo "  cat /etc/hosts  (no SelfControl entries)"
