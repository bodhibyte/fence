#!/bin/bash
# Fence Emergency Wipe Script
# Run with: sudo ./emergency.sh

set -e

echo "=== Fence Emergency Wipe ==="

# 1. Stop daemon
echo "Stopping daemon..."
launchctl bootout system/org.eyebeam.selfcontrold 2>/dev/null || echo "Daemon not running"

# 2. Clear firewall rules
echo "Clearing firewall rules..."
# Flush rules from anchor
pfctl -a org.eyebeam -F all 2>/dev/null || echo "No pf rules to clear"
# Empty the anchor file
: > /etc/pf.anchors/org.eyebeam 2>/dev/null || true
# Remove org.eyebeam references from pf.conf
if [ -f /etc/pf.conf ]; then
    sed -i '' '/org\.eyebeam/d' /etc/pf.conf
    echo "Cleaned pf.conf"
fi
# Reload pf config
pfctl -f /etc/pf.conf 2>/dev/null || true

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
sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.Fence SCIsCommitted 2>/dev/null || true
sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.Fence SCWeeklySchedules 2>/dev/null || true

# Clear week-specific keys (check for any SCWeekSchedules_* or SCWeekCommitment_*)
for key in $(sudo -u "$CONSOLE_USER" defaults read org.eyebeam.Fence 2>/dev/null | grep -oE "SCWeek(Schedules|Commitment)_[0-9-]+" | sort -u); do
    echo "  Deleting $key..."
    sudo -u "$CONSOLE_USER" defaults delete org.eyebeam.Fence "$key" 2>/dev/null || true
done

echo ""
echo "=== Wipe Complete ==="
echo "Verify with:"
echo "  pfctl -a org.eyebeam -sr  (should show nothing)"
echo "  cat /etc/hosts  (no SelfControl entries)"
