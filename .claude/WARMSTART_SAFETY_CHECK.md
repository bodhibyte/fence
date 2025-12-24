# Warm Start: Safety Check Feature Debugging

## What We're Building
A startup smoke test that verifies SelfControl's blocking/unblocking works correctly.
- Triggers when macOS version OR app version changes
- Blocks `example.com` + `com.apple.Calculator` for 30 seconds
- Verifies blocking works (hosts file, pf rules, app gets killed)
- Waits for timer to expire
- Verifies unblocking works (hosts clean, pf clean, app can launch)
- DEBUG builds only

---

## CURRENT STATUS: RESOLVED ✅

### Root Cause Found: TESTING=1 Flag in Daemon Build

The daemon's Debug AND Release configurations had `TESTING=1` in `GCC_PREPROCESSOR_DEFINITIONS`.

This caused `SCSettings.m:228-232` to skip ALL disk writes:
```objc
#if TESTING
    NSLog(@"Would write settings to disk now (but no writing during unit tests)");
    if (completionBlock != nil) completionBlock(nil);
    return;  // ← Early return, skips actual disk write
#endif
```

### Fix Applied
1. Removed `TESTING=1` from daemon Debug config (project.pbxproj:4539)
2. Removed `TESTING=1` from daemon Release config (project.pbxproj:4585)
3. Added observability log to SCSettings.m init to prevent future silent failures

### The TESTING flag should ONLY exist in:
- SelfControlTests target (for unit tests) ✅

### Why Second Run Appeared to Work
The blocking mechanisms (hosts file, PF, AppBlocker) work correctly in-memory.
The daemon CAN block apps, but state tracking was broken due to no persistence.

---

## Verification Steps

After rebuilding:

1. **Clean rebuild**:
   ```bash
   xcodebuild clean -project SelfControl.xcodeproj -scheme SelfControl
   xcodebuild -project SelfControl.xcodeproj -scheme SelfControl
   ```

2. **Remove old daemon**:
   ```bash
   sudo launchctl bootout system/org.eyebeam.selfcontrold 2>/dev/null
   sudo rm /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
   sudo rm /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist
   ```

3. **Run safety check twice** - second run should now work

4. **Check logs** - should see "Persistence enabled" instead of "but no writing during unit tests"

---

## Key Files Modified

| File | Change |
|------|--------|
| `SelfControl.xcodeproj/project.pbxproj` | Removed TESTING=1 from daemon Debug/Release |
| `Common/SCSettings.m` | Added observability logging for persistence mode |

---

## Quick Commands

```bash
# Rebuild
xcodebuild -project SelfControl.xcodeproj -scheme SelfControl

# Run app
open build/Release/SelfControl.app

# Stream daemon logs (run FIRST!)
sudo log stream --predicate 'process CONTAINS "self"' --level debug | tee logs.txt

# Check daemon binary timestamp
ls -la /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
```

---

## Previous Issue (RESOLVED): XPC Connection Debugging

### Symptom
Safety check window appears, shows "Starting test block...", then fails with error 4099:
```
Error Domain=NSCocoaErrorDomain Code=4099 "The connection to service named org.eyebeam.selfcontrold was invalidated: Failed to check-in, peer may have been unloaded"
```

### KEY FINDING: Daemon is NOT crashing!
Daemon logs show successful startup:
```
selfcontrold: === DAEMON STARTING ===
selfcontrold: Step 1 - Sentry initialized
selfcontrold: Step 2 - Daemon singleton created
selfcontrold: Step 3 - Starting daemon...
selfcontrold: start() - XPC listener resumed
selfcontrold: start() - Block check complete
selfcontrold: start() - Inactivity timer started
selfcontrold: start() - Hosts file watcher started
selfcontrold: Step 3 - Daemon started
selfcontrold: === RUNNING FOREVER ===
```

**The daemon runs fine!** Issue is the XPC connection from app to daemon.

### Verified OK (not the problem):
| Check | Result |
|-------|--------|
| `get-task-allow` entitlement on daemon | NOT present (fixed) |
| `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` | Set to NO |
| MachServices in daemon plist | Correctly configured |
| App sandbox | NOT sandboxed |
| App Team ID | `L5YX8CH3F5` - MATCHES daemon requirement |

### Current Hypothesis
The XPC connection is failing on the **app side** before reaching the daemon.
NO "NEW CONNECTION ATTEMPT" logs appear in daemon - connection never arrives.

### Logging Added (ready for testing)
| File | What's logged |
|------|---------------|
| `Daemon/DaemonMain.m` | Startup steps |
| `Daemon/SCDaemon.m` | `start()` method steps |
| `Daemon/SCDaemon.m` | `shouldAcceptNewConnection:` - connection attempts |
| `Common/SCXPCClient.m` | `connectToHelperTool` - app-side connection |

### How to Test
```bash
# Terminal 1: Watch logs
log stream --predicate 'process CONTAINS "SelfControl" OR process CONTAINS "selfcontrold"' --level debug

# Then: Run app, trigger Debug > Run Safety Check
```

### What to Look For in Logs
1. `SCXPCClient: === connectToHelperTool CALLED ===` - App attempting connection
2. `SCXPCClient: Connection resumed!` - App thinks connection is ready
3. `selfcontrold: === NEW CONNECTION ATTEMPT ===` - Daemon received connection
4. `selfcontrold: === CONNECTION ACCEPTED ===` - Daemon accepted it

If #1-2 appear but #3 doesn't - connection is lost between app and daemon.
If #3 appears but not #4 - code signing validation is rejecting the app.

---

## Previous Issue (RESOLVED): Daemon Code Signature Invalid

This issue was **FIXED** by setting `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` in project.pbxproj for the daemon target. The daemon no longer has `get-task-allow` and starts successfully.

### Verification Commands
```bash
# Verify daemon doesn't have get-task-allow (should only show application-identifier)
codesign -d --entitlements :- /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold

# Check daemon is installed
ls -la /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
```

---

## Files Overview

### Created Files

| File | Status | Purpose |
|------|--------|---------|
| `Common/Utility/SCVersionTracker.h` | ✅ Done | Version tracking utilities |
| `Common/Utility/SCVersionTracker.m` | ✅ Done | Stores last tested versions in UserDefaults |
| `Common/SCStartupSafetyCheck.h` | ✅ Done | Safety check coordinator header |
| `Common/SCStartupSafetyCheck.m` | ✅ Done | Safety check implementation (syntax errors fixed) |
| `SCSafetyCheckWindowController.h` | ✅ Done | Window controller header |
| `SCSafetyCheckWindowController.m` | ✅ Done | Programmatic UI (no XIB needed) |

### Modified Files

| File | Change |
|------|--------|
| `SCDurationSlider.m:45` | Added `#ifdef DEBUG` to allow 0.5 min (30s) minimum |
| `AppController.h` | Added `@class SCSafetyCheckWindowController` and property |
| `AppController.m:35-39` | Added imports for SCStartupSafetyCheck and SCSafetyCheckWindowController |
| `AppController.m:439-451` | Added safety check trigger in applicationDidFinishLaunching (inside `#ifdef DEBUG`) |
| `AppController.m:458-484` | Added showSafetyCheckPrompt and runSafetyCheck methods (inside `#ifdef DEBUG`) |
| `AppController.m:856-901` | Added setupDebugMenu with "Run Safety Check..." menu item |
| `SelfControl.xcodeproj/project.pbxproj:4199-4202` | Added `DEBUG=1` to SelfControl app's Debug config |
| `SelfControl.xcodeproj/project.pbxproj:4423` | Added `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` to daemon's Debug config |

---

## Architecture: How Safety Check Works

```
AppController.applicationDidFinishLaunching
    └── [SCStartupSafetyCheck safetyCheckNeeded] (checks version change)
    └── showSafetyCheckPrompt (alert dialog)
    └── runSafetyCheck
        └── SCSafetyCheckWindowController (shows progress UI)
        └── SCStartupSafetyCheck.runWithProgressHandler:completionHandler:
            └── [xpc connectToHelperTool]  <-- CONNECTION ISSUE HERE
            └── [xpc installDaemon:] (SMJobBless)  <-- This succeeds
            └── startTestBlock
                └── [xpc startBlockWithControllingUID:...]  <-- Fails with 4099
```

### XPC Connection Flow (where we're debugging)
| Step | File | Method | Status |
|------|------|--------|--------|
| 1 | `SCXPCClient.m:75` | `connectToHelperTool` | Logging added |
| 2 | `SCXPCClient.m:82` | Create `NSXPCConnection` | Logging added |
| 3 | `SCXPCClient.m:130` | `[connection resume]` | Logging added |
| 4 | `SCDaemon.m:157` | `shouldAcceptNewConnection:` | Logging added |
| 5 | `SCDaemon.m:178` | `SecCodeCheckValidity` | Logging added |

---

## Environment

- **macOS:** 26.1 (25B78) - Tahoe beta
- **Architecture:** Apple Silicon (ARM64)
- **Xcode:** Building Debug configuration
- **Team ID:** L5YX8CH3F5

---

## Build & Test Commands

```bash
# Clean build
xcodebuild clean -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Debug

# Build Debug
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Debug build

# Remove old daemon before testing
sudo launchctl bootout system/org.eyebeam.selfcontrold 2>/dev/null
sudo rm /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
sudo rm /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist

# Run app with logs
/path/to/DerivedData/.../Debug/SelfControl.app/Contents/MacOS/SelfControl 2>&1 | tee /tmp/selfcontrol.log

# Verify daemon entitlements after install
codesign -d --entitlements :- /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
```

---

## For Future Agents

### Current Task: Debug XPC Connection
1. Run the test (see "How to Test" above)
2. Analyze the logs to see where connection fails
3. If connection never reaches daemon, issue is app-side (`SCXPCClient.m`)
4. If daemon rejects connection, check code signing validation in `shouldAcceptNewConnection:`

### Key Files for XPC Debugging
| File | Purpose |
|------|---------|
| `Common/SCXPCClient.m` | App-side XPC connection (logging added) |
| `Daemon/SCDaemon.m` | Daemon XPC listener + connection validation (logging added) |
| `Common/SCStartupSafetyCheck.m` | Safety check orchestration |

### Gemini 3 Pro Analysis Suggestions
From external AI analysis, possible causes:
1. **Race condition** - App connects before daemon's listener is registered with launchd
2. **Connection invalidation** - Handlers firing prematurely
3. **Service name mismatch** - (unlikely, verified correct)

### Test Targets
- Website: `example.com` (IANA reserved, safe to block)
- App: `com.apple.Calculator` (always installed, rarely used)

---

## Reference
- Current debug plan: `/Users/vishaljain/.claude/plans/curried-skipping-map.md`
