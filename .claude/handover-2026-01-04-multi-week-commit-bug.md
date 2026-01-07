# Handover: Multi-Week Commit Bug + Job Cleanup Issues

**Date:** 2026-01-04
**Context:** Critical bugs in schedule job management discovered during Sunday commit scenario

---

## Summary

Three related bugs were discovered when a user tries to commit to both "This Week" and "Next Week" on a Sunday:

| Bug | Severity | Status |
|-----|----------|--------|
| #1: Multi-week commit deletes all jobs | Critical | Not fixed |
| #2: Jobs don't self-cleanup after commitment expires | High | Not fixed |
| #3: emergency.sh didn't clear schedule jobs | Medium | **Fixed** (commit pending) |

---

## Bug #1: Multi-Week Commit Deletes All Jobs

### Problem

In `SCScheduleManager.m` line 461, `commitToWeekWithOffset:` calls:
```objc
[bridge uninstallAllScheduleJobs:nil];
```

This deletes **ALL** schedule jobs regardless of which week is being committed.

### Impact

If user commits "This Week", then commits "Next Week":
1. This Week's jobs are created
2. Next Week commit **deletes all jobs** (including This Week's)
3. Only Next Week's jobs remain
4. This Week's remaining blocks (e.g., Sunday) never fire

### Root Cause

Job labels have no week identifier:
```
Current format: org.eyebeam.selfcontrol.schedule.merged-{UUID}.{day}.{time}
```

`uninstallAllScheduleJobs` finds all jobs with prefix `org.eyebeam.selfcontrol.schedule.` and deletes them all.

### Proposed Fix

1. Add week key to job labels:
   ```
   New format: org.eyebeam.selfcontrol.schedule.w{weekKey}.merged-{UUID}.{day}.{time}
   Example:    org.eyebeam.selfcontrol.schedule.w2026-01-05.merged-abc123.monday.0900
   ```

2. Add new method `uninstallJobsForWeekKey:` that only deletes jobs matching that week

3. Change `commitToWeekWithOffset:` to call the week-specific uninstall

4. **Label parsing is safe**: Existing code splits on `.merged-` and takes what's after, so adding week key before `.merged-` is backwards compatible.

---

## Bug #2: Jobs Don't Self-Cleanup

### Problem

Jobs use `StartCalendarInterval` which fires **every week** at the scheduled time. There's no mechanism to stop them after the commitment expires.

A method `cleanupExpiredCommitments` exists but is **never called** anywhere.

### Impact

After commitment ends (Sunday 23:59:59), jobs continue firing every week forever until:
- User commits again (which deletes all jobs), or
- User runs emergency.sh

### Additional Complication

If both weeks are committed on Sunday, both have Sunday jobs. Since `StartCalendarInterval` fires every Sunday, next week's Sunday job would fire TODAY (prematurely).

### Proposed Fix

When the CLI (`selfcontrol-cli start`) is invoked by a job:
1. Parse the week key from job label or schedule-id
2. Check if today is within that week's date range
3. If NO → Don't start block, uninstall this job, exit
4. If YES → Start block normally

This makes jobs self-cleaning and prevents premature firing.

---

## Bug #3: emergency.sh Missing Job Cleanup (FIXED)

### Problem

`emergency.sh` didn't uninstall schedule launchd jobs in `~/Library/LaunchAgents/`.

### Fix Applied

Added step 7 to `emergency.sh`:
```bash
# 7. Uninstall schedule launchd jobs
for plist in /Users/"$CONSOLE_USER"/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist; do
    if [ -f "$plist" ]; then
        label=$(basename "$plist" .plist)
        sudo -u "$CONSOLE_USER" launchctl bootout gui/"$CONSOLE_UID"/"$label" 2>/dev/null || true
        rm "$plist"
    fi
done
```

---

## Previous Commit Context

The most recent commit `b4468bd` added Sparkle auto-update functionality:
- Initialized `SPUStandardUpdaterController` in `AppController.m`
- Added "Check for Updates..." menu item in `SCMenuBarController.m`
- Updated version to 3.0 (build 600) in `Info.plist`
- Updated `web/updates/appcast.xml` with `sparkle:version=600`

**This commit is unrelated to the bugs above** - it was completed successfully before bug investigation began.

---

## Key Files to Understand

### Schedule Management
| File | Purpose |
|------|---------|
| `Block Management/SCScheduleManager.m` | Main schedule logic, `commitToWeekWithOffset:` at line 429 |
| `Block Management/SCScheduleManager.h` | Public interface |
| `Block Management/SCScheduleLaunchdBridge.m` | Creates/uninstalls launchd jobs |
| `Block Management/SCScheduleLaunchdBridge.h` | Job management interface |

### Job Label Parsing (must remain compatible)
| File | Lines | What it does |
|------|-------|--------------|
| `Daemon/SCDaemon.m` | 231-233 | Extracts segment ID by splitting on `.merged-` |
| `Block Management/SCScheduleLaunchdBridge.m` | 374-376 | Same parsing for cleanup |

### CLI (where self-cleanup should be added)
| File | Purpose |
|------|---------|
| `selfcontrol-cli/` | CLI tool invoked by launchd jobs |

### Emergency Scripts
| File | Status |
|------|--------|
| `emergency.sh` | Fixed - now includes job cleanup |
| `emergency_complete.sh` | Calls emergency.sh, inherits fix |

---

## Debug Logging Suggestions

### 1. In `commitToWeekWithOffset:` (SCScheduleManager.m ~line 461)

Add before/after uninstall:
```objc
NSLog(@"SCScheduleManager: Committing week offset %ld, weekKey=%@", (long)weekOffset, weekKey);
NSLog(@"SCScheduleManager: Jobs before uninstall: %@", [bridge allInstalledScheduleJobLabels]);
[bridge uninstallAllScheduleJobs:nil];
NSLog(@"SCScheduleManager: Jobs after uninstall: %@", [bridge allInstalledScheduleJobLabels]);
```

### 2. In `installMergedJobForSegment:` (SCScheduleLaunchdBridge.m ~line 694)

Log job creation:
```objc
NSLog(@"SCScheduleLaunchdBridge: Creating job with label: %@", label);
```

### 3. In CLI start command

Log when job fires:
```objc
NSLog(@"selfcontrol-cli: Job fired with schedule-id=%@, checking commitment validity...", scheduleID);
```

---

## How to Test

### Reproduce Bug #1
1. Build and run on a Sunday
2. Commit "This Week"
3. Check jobs: `ls ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*`
4. Commit "Next Week"
5. Check jobs again - This Week's jobs are gone!

### Verify emergency.sh Fix
1. Commit to a week (creates jobs)
2. Run `sudo ./emergency.sh`
3. Check jobs are removed: `ls ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*`

---

## Implementation Checklist

- [ ] Add week key to job label format in `SCScheduleLaunchdBridge.m`
- [ ] Add `uninstallJobsForWeekKey:` method
- [ ] Update `commitToWeekWithOffset:` to use week-specific uninstall
- [ ] Add date validation in CLI before starting block
- [ ] Add self-uninstall logic in CLI for expired commitments
- [ ] Test multi-week commit scenario
- [ ] Test job self-cleanup after week ends

---

## Terminology Reference

| Term | Definition |
|------|------------|
| **Week Key** | Monday's date string (e.g., "2026-01-05") identifying a week |
| **Segment** | Merged time slice where bundles overlap, has start/end time + blocklist |
| **Job** | Launchd plist with `StartCalendarInterval`, fires weekly at day+time |
| **Commitment** | Per-week lock stored as `SCWeekCommitment_{weekKey}` |

---

*Created: 2026-01-04*
