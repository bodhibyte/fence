# Warmstart: Weekly Schedule → CLI Bridge

## Current State

**Blocking connection is NOW DONE.** When you commit, launchd jobs are created and blocks start.

### What's Working

1. **Weekly Schedule UX** (committed, working):
   - `SCWeekScheduleWindowController` - main window
   - `SCWeekGridView` - visual grid (bundles × days)
   - `SCScheduleManager` - app-side storage in NSUserDefaults
   - `SCBlockBundle`, `SCWeeklySchedule`, `SCTimeRange` - data models
   - Access: `Debug > Week Schedule (New UX)...` or `Cmd+Option+W`

2. **launchd Bridge** (NEW - implemented):
   - `SCScheduleLaunchdBridge` - creates/manages launchd jobs
   - Jobs stored in: `~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist`
   - Blocklist files: `~/Library/Application Support/SelfControl/Schedules/*.selfcontrol`

3. **Features Implemented**:
   - ✅ Commit creates launchd jobs for future block windows
   - ✅ In-progress blocks start immediately on commit
   - ✅ Live strictifying: adding sites/apps to bundle updates running block
   - ✅ App strictifying fixed (findAndKillBlockedApps in finishAppending)
   - ✅ Debug clear removes all schedule jobs
   - ✅ Status bar reads from week-specific schedules (not base)

## Known Issues / TODO

### Base Storage vs Week-Specific Storage (NEEDS CLEANUP)

There are **two schedule storage systems** that may be out of sync:

| Storage | Key | Accessed Via |
|---------|-----|--------------|
| Base/Default | `SCWeeklySchedules` | `scheduleForBundleID:` |
| Week-Specific | `SCWeekSchedules_2024-12-22` | `scheduleForBundleID:weekOffset:` |

**Problem:** The Week UI edits week-specific storage, but base storage may have stale data.

**Recommendation:** Either:
1. Remove base storage entirely, always use week-specific
2. Or sync them when edits happen

For now, code tries week-specific first, falls back to base. Works but confusing.

## Key Files

| File | Purpose |
|------|---------|
| `Block Management/SCScheduleLaunchdBridge.h/m` | NEW - launchd job management |
| `Block Management/SCScheduleManager.m` | `commitToWeekWithOffset:` installs jobs |
| `Block Management/BlockManager.m` | `finishAppending` now kills apps immediately |
| `cli-main.m` | CLI entry point - unchanged |
| `SCWeekScheduleWindowController.m` | UI controller |

## Testing

```bash
# Check launchd jobs
ls ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*

# Check blocklist files
ls ~/Library/Application\ Support/SelfControl/Schedules/

# View job content
cat ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist

# Check if jobs are loaded
launchctl list | grep selfcontrol.schedule

# View logs
log show --predicate 'process == "SelfControl"' --last 5m | grep -i schedule
```

## Debug Cleanup

Use **Debug > Clear Week Commitment** in the app, or manually:
```bash
launchctl unload ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist
rm ~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.*.plist
```
