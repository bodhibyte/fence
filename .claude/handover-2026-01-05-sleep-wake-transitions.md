# Handover: Sleep/Wake Block Transition Bug

**Date:** 2026-01-05 01:45 AM
**Status:** Investigation in progress, logging added, build pending

---

## The Problem

Scheduled block transitions fail when the Mac sleeps/wakes around a block boundary. User is running the **notarized production build** of Fence (SelfControl rebrand).

### Symptoms Observed
1. Block started at 23:00 with endDate 23:58:59
2. Mac went to sleep at ~23:52
3. Mac woke at 00:08:34
4. Multiple CLI jobs fired and all said "ERROR: Block is already running"
5. Block eventually cleared but **no new block started**

---

## Key Evidence from Logs

### Log file location
`/Users/vishaljain/.fence/logs/fence-logs-2026-01-05-012434.txt`

### What the logs show (EVIDENCE, not guessing):

**1. CLI saw "Block is already running" at 00:08:34:**
```
63747:2026-01-05 00:08:34.161 Df selfcontrol-cli ERROR: Block is already running
```

**2. This is NOT a parsing error** - the CLI would have shown "=== SCHEDULED BLOCK START ===" logs if it had gotten that far. It hit the `anyBlockIsRunning` check first.

**3. Mac was sleeping from 23:52 to 00:08:**
```bash
pmset -g log | grep -E "2026-01-04 23:5|2026-01-05 00:0"
# Shows DarkWake at 23:51:59, sleep until 00:08:34
```

**4. Daemon startup failed to find console user:**
```
=== startMissedBlockIfNeeded 2026-01-05 01:15:44 +0000 ===
consoleUID: 0
EXIT: No console user
```

---

## Two Separate Issues Identified

### Issue 1: Sleep/Wake Race Condition
- When Mac wakes, launchd fires queued CLI jobs
- CLI checks `anyBlockIsRunning` → returns TRUE (stale block from before sleep)
- CLI exits with "Block is already running"
- Daemon checkup hasn't yet cleared the expired block

**What we DON'T know yet:** Exactly why the block was still marked as running. Was it:
- The checkup timer not running during sleep? (likely)
- Some other state issue?

### Issue 2: Boot Recovery Fails
- Daemon's `startMissedBlockIfNeeded` uses `consoleUserUID`
- At boot, before user login, this returns 0
- Method exits early - can't find LaunchAgents directory
- **FIX ADDED:** Now falls back to `controllingUID` from ApprovedSchedules

---

## Changes Made (Not Yet Built)

### 1. cli-main.m (lines 85-107)
Added detailed logging before the "block is already running" check:
```objc
NSLog(@"=== CLI BLOCK STATE CHECK ===");
NSLog(@"CLI: BlockIsRunning flag = %d", blockIsRunningFlag);
NSLog(@"CLI: BlockEndDate = %@", existingEndDate);
NSLog(@"CLI: currentBlockIsExpired = %d", isExpired);
NSLog(@"CLI: modernBlockIsRunning = %d", modernRunning);
NSLog(@"CLI: legacyBlockIsRunning = %d", legacyRunning);
```

### 2. Daemon/SCDaemon.m (lines 187-206)
Added fallback to use `controllingUID` when `consoleUserUID` returns 0:
```objc
if (consoleUID == 0) {
    // Try controllingUID from ApprovedSchedules
    for (NSString *schedId in approvedSchedules) {
        NSDictionary *sched = approvedSchedules[schedId];
        NSNumber *ctrlUID = sched[@"controllingUID"];
        if (ctrlUID && [ctrlUID unsignedIntValue] != 0) {
            consoleUID = [ctrlUID unsignedIntValue];
            break;
        }
    }
}
```

---

## Key Files to Understand

| File | Purpose |
|------|---------|
| `cli-main.m:82-130` | CLI entry point for scheduled blocks, `anyBlockIsRunning` check |
| `Common/Utility/SCBlockUtilities.m:14-24` | `anyBlockIsRunning`, `modernBlockIsRunning` implementations |
| `Daemon/SCDaemon.m:148-350` | `startMissedBlockIfNeeded` - daemon startup recovery |
| `Daemon/SCDaemonBlockMethods.m:306-395` | `checkupBlock` - 1-second timer that clears expired blocks |
| `docs/SCHEDULE_JOB_LIFECYCLE.md` | Full architecture documentation |

---

## Previous Commit Context

Commit `610638617dc82e8a75022f0589d7a5af2a7d2cfb` fixed ArgumentParser stripping internal hyphens from `--schedule-id`. This was verified working - the 23:00 block **did start successfully**. The current issue is about **transitions**, not parsing.

---

## How to Reproduce

1. Commit week schedules with blocks around midnight
2. Put Mac to sleep before a block end time
3. Let Mac wake after the scheduled start of the next block
4. Check logs for "Block is already running" errors

---

## Next Steps

1. **Build and notarize** with the new logging
2. **Run overnight** with sleep occurring during block transitions
3. **Check logs** - the new CLI logging will show:
   - Whether `BlockIsRunning` flag was TRUE
   - What `BlockEndDate` was (was the block expired?)
   - Whether it was modern or legacy block detection
4. **Check `/tmp/selfcontrol_debug.log`** for daemon startup recovery details

---

## Debug Log Locations

| Log | What it shows |
|-----|---------------|
| `~/.fence/logs/fence-logs-*.txt` | App/CLI/Daemon logs (captured via `log stream`) |
| `/tmp/selfcontrol_debug.log` | Daemon `startMissedBlockIfNeeded` debug output |
| `/tmp/selfcontrol-schedule.log` | CLI stdout/stderr from launchd jobs |
| `pmset -g log` | Sleep/wake events |

---

## Build Command

```bash
./scripts/build-release.sh <version>
# Or for quick debug build:
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Release -arch arm64 build
```

---

## Open Questions

1. When the block expired at 23:58:59 and Mac was asleep, what happens to the checkup timer?
2. Why didn't the checkup clear the expired block before the CLI jobs ran at 00:08?
3. Should the CLI check if a block is **expired** (not just running) and allow starting a new block?
