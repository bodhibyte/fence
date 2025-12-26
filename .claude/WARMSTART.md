# Warmstart: Pre-Authorized Scheduled Blocks (No Password Per Segment)

## Current Status: WORKING ✅

Both "Start Block" (manual) and "Commit to Week" (scheduled) now install the daemon automatically. Password is prompted once at commit time, then all scheduled segments start without prompts.

---

## What We Built

**Goal:** When user commits to a weekly schedule, only prompt for password ONCE at commit time. All subsequent scheduled blocks should start without password prompts.

**Why it was prompting every time:**
1. Daemon auto-terminates after 2 min idle (calls `SMJobRemove`)
2. Next scheduled block triggers CLI
3. CLI calls `installDaemon:` → `SMJobBless` → password prompt

---

## Architecture: Pre-Authorization "Ticket" System

### The Flow

```
COMMIT TIME (password required once):
  App → registerScheduleWithID → daemon stores in root-only settings
  App → creates launchd jobs with --schedule-id (not --blocklist)

SCHEDULED TIME (no password):
  launchd → selfcontrol-cli start --schedule-id UUID --enddate ISO8601
  CLI → startScheduledBlockWithID → daemon looks up pre-approved schedule
  daemon → starts block (no auth check needed)
```

### New XPC Methods Added

| Method | Auth Required? | Purpose |
|--------|---------------|---------|
| `registerScheduleWithID:blocklist:isAllowlist:blockSettings:controllingUID:authorization:reply:` | YES | Store approved schedule in daemon |
| `startScheduledBlockWithID:endDate:reply:` | NO | Start pre-approved schedule |
| `unregisterScheduleWithID:authorization:reply:` | YES | Remove approved schedule |

---

## Files Modified

| File | Changes |
|------|---------|
| `Daemon/SCDaemonProtocol.h` | Added 3 new XPC method signatures |
| `Daemon/SCDaemonXPC.m` | Implemented the 3 methods |
| `Daemon/SCDaemon.m` | Disabled inactivity termination (daemon runs forever) |
| `Common/SCXPCClient.h/m` | Added client-side methods for schedule registration |
| `cli-main.m` | Added `--schedule-id` argument, uses `startScheduledBlockWithID` |
| `Block Management/SCScheduleLaunchdBridge.m` | Registers schedules at commit, uses `--schedule-id` in launchd plists |

---

## Key Code Locations

### Daemon stores approved schedules
`Daemon/SCDaemonXPC.m` lines 79-123:
- `registerScheduleWithID:` stores schedule in `SCSettings` (root-only file)
- Keyed by UUID, contains blocklist, settings, controllingUID

### Daemon starts scheduled block (no auth)
`Daemon/SCDaemonXPC.m` lines 125-161:
- `startScheduledBlockWithID:` looks up UUID in settings
- If found, calls `SCDaemonBlockMethods.startBlock` with `authorization:nil`

### CLI handles --schedule-id
`cli-main.m` lines 89-127:
- If `--schedule-id` is passed, uses `startScheduledBlockWithID` (no password)
- Otherwise uses old flow with `installDaemon` (password required)

### Bridge registers at commit time
`Block Management/SCScheduleLaunchdBridge.m` lines 616-730:
- `installJobForSegmentWithBundles:` registers schedule with daemon first
- Then creates launchd plist with `--schedule-id` instead of `--blocklist`

---

## Bugs Fixed

### 1. Deadlock on main thread
**Problem:** `dispatch_semaphore_wait` blocked main thread while XPC callback needed main thread.

**Fix:** Use run loop-based wait:
```objc
if (![NSThread isMainThread]) {
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
} else {
    while (dispatch_semaphore_wait(sema, DISPATCH_TIME_NOW)) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}
```

### 2. Daemon not found after protocol changes
**Problem:** Old daemon binary doesn't have new XPC methods, crashes on call.

**Fix:** Reinstall daemon:
```bash
sudo launchctl unload /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist
sudo rm -f /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist
sudo rm -f /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
```
Then start a manual block to trigger `SMJobBless`.

---

## Testing

### To verify daemon is running:
```bash
ps aux | grep selfcontrold
```

### To verify schedule registration worked:
Check daemon logs for:
```
XPC method called: registerScheduleWithID: <UUID>
INFO: Schedule <UUID> registered successfully
```

### To verify launchd plists use --schedule-id:
```bash
cat ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist | grep schedule-id
```

Should show `--schedule-id` not `--blocklist`.

---

## Next Steps

1. **Start a manual block** to install the new daemon (will prompt for password)
2. **Then try committing to schedule** - should only prompt once at commit
3. **Wait for next scheduled segment** - should start without password

---

## Debug Commands

```bash
# Check daemon status
ps aux | grep selfcontrold
launchctl list | grep selfcontrold

# Check launchd schedule jobs
ls ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*
launchctl list | grep selfcontrol.schedule

# View daemon logs
log show --predicate 'process == "org.eyebeam.selfcontrold"' --last 5m

# View schedule job logs
cat /tmp/selfcontrol-schedule.log
```
