# Handover: Schedule Block Transitions & UI Staleness Bugs

**Date:** 2026-01-04
**Context:** Production debugging session for Fence (SelfControl fork)

---

## Summary

User reported that scheduled blocks weren't working after waking laptop from sleep. Investigation revealed multiple issues - one critical bug was fixed, others remain open.

---

## Issue 1: FIXED - Scheduled Block Transitions Not Working

### Symptom
- User set a block schedule with Work + Social Media bundles
- Blocks started correctly initially
- After laptop wake from sleep, nothing was blocked
- Launchd jobs were firing but blocks weren't starting

### Root Cause
The `ArgumentParser` submodule was re-cloned from upstream, losing a critical fix. The parser stripped ALL dashes from switch names:

```objc
// BROKEN (upstream version):
NSString * switchKey = [v stringByReplacingOccurrencesOfString:@"-" withString:@""];
// --schedule-id → "scheduleid" (wrong!)
```

This broke `--schedule-id` argument parsing in the CLI. When launchd triggered `selfcontrol-cli start --schedule-id=XXX`, the CLI couldn't parse it and fell back to the legacy blocklist flow (which was empty).

### Fix Applied
**File:** `ArgumentParser/ArgumentParser/XPMArgumentParser.m` (line 61-67)

```objc
// FIXED: Strip only leading dashes, preserve internal ones
NSString * switchKey = v;
while ([switchKey hasPrefix:@"-"]) {
    switchKey = [switchKey substringFromIndex:1];
}
// --schedule-id → "schedule-id" (correct!)
```

### Commit
```
6106386 Fix scheduled block transitions failing after submodule re-clone
Tag: v5.5
```

### Key Files for Understanding the Flow
1. **Launchd job creation:** `Block Management/SCScheduleLaunchdBridge.m:700-730`
   - Creates plist with `--schedule-id=XXX` argument
2. **CLI entry point:** `cli-main.m:89-130`
   - Parses `--schedule-id`, calls daemon via XPC
3. **Daemon handler:** `Daemon/SCDaemonXPC.m:116-178`
   - `startScheduledBlockWithID:` looks up ApprovedSchedules, starts block
4. **Daemon settings:** `/usr/local/etc/.{hash}.plist`
   - Contains `ApprovedSchedules` dictionary with blocklists

### Debug Logging Added
We added detailed logging to trace the flow:
- `cli-main.m:93-127` - CLI logs with `=== SCHEDULED BLOCK START ===`
- `Daemon/SCDaemonXPC.m:120-177` - Daemon logs with `DAEMON:` prefix
- `Daemon/SCDaemonBlockMethods.m:323-381` - Checkup logs with `CHECKUP:` prefix

### Where to Look for Logs
- `/tmp/selfcontrol-schedule.log` - CLI output from launchd jobs
- `log stream --predicate 'process == "selfcontrold"'` - Daemon logs

---

## Issue 2: OPEN - Week UI Not Live Updating

### Symptom
- Red "NOW" line (current time indicator) shows wrong time after wake
- Week UI showed "Saturday evening" when it was Sunday morning
- Only fixed by quitting and reopening the app

### Evidence Found
Investigation by subagent identified:

1. **No periodic redraw timer** for the NOW line
   - `SCCalendarGridView.m:447-462` - draws NOW line in `drawRect:` but never redraws
   - `SCWeekGridView.m:338-381` - same issue

2. **No wake-from-sleep notification handler**
   - `SCWeekScheduleWindowController.m:268-285` - `setupNotifications` missing `NSWorkspaceDidWakeNotification`

3. **NO wake handlers anywhere in codebase** - searched entire codebase, no matches for `NSWorkspaceDidWake`

### Files to Investigate
- `SCWeekScheduleWindowController.m` - main window controller
- `SCCalendarGridView.m` - draws the calendar with NOW line
- `SCWeekGridView.m` - legacy grid view

### Suggested Fix
Add to `SCWeekScheduleWindowController.m`:
```objc
// In setupNotifications:
[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
    selector:@selector(handleWakeFromSleep:)
    name:NSWorkspaceDidWakeNotification
    object:nil];

// Add periodic timer for NOW line (1-second interval when window visible)
```

---

## Issue 3: OPEN - Status Bar Showing Stale Info

### Symptom
- Status bar showed "blocked till 8:16pm" even after emergency.sh cleared everything
- Information was from yesterday when schedule was first set
- Didn't update after wake from sleep

### Evidence Found
Investigation by subagent identified:

1. **No wake notification** in `SCMenuBarController.m:38-50`
2. **60-second update timer too slow** - `SCMenuBarController.m:387`
3. **Menu only fully rebuilds on click** - `menuWillOpen:` triggers rebuild
4. **No listener for external state changes** - emergency.sh clears daemon state but app doesn't know

### Files to Investigate
- `SCMenuBarController.m` - manages status bar
- `SCScheduleManager.m` - provides schedule data
- `Block Management/SCWeeklySchedule.m` - time calculations

### Suggested Fix
Add wake notification and reduce timer interval:
```objc
// In init:
[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
    selector:@selector(handleWakeFromSleep:)
    name:NSWorkspaceDidWakeNotification
    object:nil];

// Change timer from 60s to 10s
self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 ...];
```

---

## Issue 4: OPEN - Blocklist Showing Empty (Possible Regression)

### Symptom
- Clicking "View Blocklist" in menu shows empty list
- Menu bar correctly shows "4 apps, 10 websites" count

### Previous Fix
Commit `c35e579` fixed this by adding `displayEntries` property to `DomainListWindowController`. The fix reads from currently-blocking bundles instead of `NSUserDefaults[@"Blocklist"]`.

### Files to Investigate
- `AppController.m:550-572` - sets up `displayEntries` when showing blocklist
- `DomainListWindowController.m:68-74` - uses `displayEntries` if provided
- `SCMenuBarController.m:450+` - `showBlocklistClicked:` action

### Possible Cause
The fix depends on `SCScheduleManager.wouldBundleBeAllowed:` working correctly. If schedule calculations are wrong (see Issue 5), the blocklist would appear empty.

---

## Issue 5: LOW PRIORITY - Week Boundary (Probably Not an Issue)

### Note
Initially suspected week boundary calculation issues, but user confirmed blocks set on Sunday Jan 4 work correctly. The week key calculation is likely fine.

This was speculative - the real cause of stale UI is the missing wake notifications (Issues 2 & 3).

---

## Common Theme: Missing Wake-from-Sleep Handling

All UI issues share the same root cause: **No `NSWorkspaceDidWakeNotification` handlers anywhere in the app.**

### Recommended Central Fix
Add a wake handler in `AppController.m` that triggers refresh of all UI components:

```objc
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // ... existing code ...

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
        selector:@selector(systemDidWake:)
        name:NSWorkspaceDidWakeNotification
        object:nil];
}

- (void)systemDidWake:(NSNotification *)notification {
    // Refresh all UI components
    [[SCScheduleManager sharedManager] reloadSchedules];
    [self.menuBarController updateStatus];
    // Post notification for week UI to refresh
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCSystemDidWake" object:nil];
}
```

---

## Test Procedure for Scheduled Blocks

1. Set up a schedule with 2 bundles and short segment times (3-5 min apart)
2. Commit the schedule (requires password)
3. Verify blocking works initially
4. Watch logs: `tail -f /tmp/selfcontrol-schedule.log`
5. Put laptop to sleep spanning a segment transition
6. Wake and verify new segment started correctly
7. Check status bar and week UI updated

---

## Key Architecture Notes

### Schedule Flow
```
User commits schedule
    → SCScheduleManager registers with daemon (XPC)
    → SCScheduleLaunchdBridge creates launchd jobs
    → Daemon stores ApprovedSchedules in /usr/local/etc/.*.plist

Launchd fires at scheduled time
    → selfcontrol-cli start --schedule-id=XXX --enddate=YYY
    → CLI calls daemon via XPC
    → Daemon looks up ApprovedSchedules[XXX]
    → Daemon starts block with that blocklist

Block expires
    → checkupBlock detects expiry
    → Clears block, stops checkup timer
    → Next segment starts via its own launchd job
```

### Reboot Recovery (Different Path)
```
System reboots during scheduled block
    → Daemon starts via launchd
    → SCDaemon.start calls startMissedBlockIfNeeded
    → Directly reads ApprovedSchedules + launchd jobs
    → Starts block without going through CLI
```

---

## Files Modified in This Session

1. `ArgumentParser/ArgumentParser/XPMArgumentParser.m` - dash stripping fix
2. `cli-main.m` - added debug logging
3. `Daemon/SCDaemonXPC.m` - added debug logging
4. `Daemon/SCDaemonBlockMethods.m` - added debug logging

---

## Next Steps (Priority Order)

1. **Add wake notification handlers** - This is the main fix for Issues 2, 3, 4
   - Add `NSWorkspaceDidWakeNotification` observer in `AppController.m`
   - Trigger refresh of menu bar and week UI on wake
2. **Add periodic timer to Week UI** - Redraw NOW line every 1-10 seconds
3. **Reduce status bar timer** from 60s to 10s
4. **Test blocklist display** - May self-resolve after wake handlers are added
