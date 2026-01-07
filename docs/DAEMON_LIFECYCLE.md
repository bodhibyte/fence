# Daemon Lifecycle

This document describes the lifecycle of the `selfcontrold` daemon, including startup, timers, and persistence behavior.

> **Related:** [SCHEDULE_JOB_LIFECYCLE.md](SCHEDULE_JOB_LIFECYCLE.md) for how scheduled blocks fire.

## Overview

The **selfcontrold** daemon (`org.eyebeam.selfcontrold`) is a privileged root daemon that handles all blocking operations. It runs **permanently** after first install, enabled by `KeepAlive=true` and `RunAtLoad=true`.

## State Diagram

```mermaid
stateDiagram-v2
    [*] --> NotInstalled

    NotInstalled --> Running: SMJobBless (user commits schedule)

    state Running {
        [*] --> Idle

        Idle --> ActiveBlock: Block starts
        ActiveBlock --> Idle: Block expires/cleared

        state Idle {
            note right of Idle
                - Schedule timer (1 min)
                - XPC listener active
                - Hosts file watcher
            end note
        }

        state ActiveBlock {
            note right of ActiveBlock
                - Checkup timer (1 sec)
                - PF rules active
                - /etc/hosts modified
                - AppBlocker (if app entries)
            end note
        }
    }

    Running --> Running: KeepAlive restarts if killed
    Running --> Running: RunAtLoad on reboot
```

## Daemon Startup

### Installation via SMJobBless

The daemon is installed when the user first commits a schedule or starts a block:

```objc
// In SCXPCClient.m
SMJobBless(kSMDomainSystemLaunchd, CFSTR("org.eyebeam.selfcontrold"), ...);
```

**Triggers:**
- User commits a schedule
- User starts a manual block
- App detects outdated daemon version

### Entry Point

```objc
// DaemonMain.m
int main(int argc, const char *argv[]) {
    SCDaemon* daemon = [SCDaemon sharedDaemon];
    [daemon start];  // Initialize all subsystems
    [[NSRunLoop currentRunLoop] run];  // Never returns
    return 0;
}
```

### The `-start` Method

When the daemon starts, it initializes:

1. **XPC Listener** — Accepts connections from the app
2. **Checkup Timer** — Starts only if block is running (1-second interval)
3. **Schedule Check Timer** — Always runs (1-minute interval)
4. **Hosts File Watcher** — Detects tampering during active blocks

```objc
- (void)start {
    [self.listener resume];

    if ([SCBlockUtilities anyBlockIsRunning]) {
        [self startCheckupTimer];
    }

    // Immediate check for missed blocks (e.g., after reboot)
    [self startMissedBlockIfNeeded];

    // Periodic sweep for missed scheduled blocks
    self.scheduleCheckTimer = [NSTimer scheduledTimerWithTimeInterval: 60 ...];
}
```

## Timer Architecture

### Summary

| Timer | Interval | Purpose | When Active |
|-------|----------|---------|-------------|
| **Checkup Timer** | 1 second | Verify block integrity, expire blocks | Only during active block |
| **Schedule Check Timer** | 60 seconds | Catch missed scheduled blocks | Always |
| **Inactivity Timer** | N/A | Previously used for daemon exit | **DISABLED** |

### Checkup Timer (1-second)

Runs only when a block is active. Every second:

1. **Block expired?** → Remove block, stop timer
2. **No block flag but rules exist?** → Clean up remnants
3. **Block active?** → Every 15 seconds, verify integrity:
   - PF rules intact
   - /etc/hosts entries exist
   - AppBlocker running (if needed)
   - If compromised: re-add all rules

```objc
self.checkupTimer = [NSTimer scheduledTimerWithTimeInterval: 1
                                                    repeats: YES
                                                      block:^(NSTimer * _Nonnull timer) {
    [SCDaemonBlockMethods checkupBlock];
}];
```

### Schedule Check Timer (1-minute)

Runs permanently. Every minute, calls `startMissedBlockIfNeeded` which:

1. Checks if block already running (exit early if so)
2. Scans `~/Library/LaunchAgents` for schedule job plists
3. For each job, extracts start time and end date
4. If a job should be active NOW but no block is running → starts the block

**Purpose:** Catches missed blocks due to:
- launchd not firing during sleep
- System booting after scheduled start time
- Background permission being disabled

```objc
self.scheduleCheckTimer = [NSTimer scheduledTimerWithTimeInterval: 60
                                                          repeats: YES
                                                            block:^(NSTimer * _Nonnull timer) {
    [self startMissedBlockIfNeeded];
}];
```

### Inactivity Timer (DISABLED)

The daemon previously had an inactivity timeout that would exit after 2 minutes of inactivity. This is now **disabled** — the daemon runs permanently.

```objc
float const INACTIVITY_LIMIT_SECS = 60 * 2; // No longer used

- (void)startInactivityTimer {
    // Daemon now runs permanently for:
    // 1. Scheduled blocks (no password prompts)
    // 2. Jailbreak resistance (KeepAlive restarts if killed)
    // 3. Resource usage is negligible
}
```

## Persistence & KeepAlive

### Launchd Configuration

```xml
<!-- org.eyebeam.selfcontrold.plist -->
<dict>
    <key>Label</key>
    <string>org.eyebeam.selfcontrold</string>

    <key>RunAtLoad</key>
    <true/>              <!-- Start on boot -->

    <key>KeepAlive</key>
    <true/>              <!-- Restart if killed -->

    <key>MachServices</key>
    <dict>
        <key>org.eyebeam.selfcontrold</key>
        <true/>          <!-- XPC service name -->
    </dict>
</dict>
```

### Behavior

| Scenario | Result |
|----------|--------|
| System boot | Daemon starts (`RunAtLoad=true`) |
| Daemon crashes | launchd restarts it (`KeepAlive=true`) |
| User kills daemon | launchd restarts it |
| Daemon exits cleanly | launchd restarts it |

This is **intentional for tamper resistance**. Users cannot circumvent blocking by killing the daemon.

## Timer Interaction

```
Boot/Install
    │
    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Daemon -start method                                                    │
│   • XPC listener resumed                                                │
│   • Schedule check timer starts (1 min)                                 │
│   • Check for missed blocks                                             │
│   • Start checkup timer IF block already running                        │
└─────────────────────────────────────────────────────────────────────────┘
    │
    │  No block running:
    │  ┌─────────────────────────────────────────────────────────────────┐
    │  │ Schedule timer fires every 60s                                  │
    │  │   → startMissedBlockIfNeeded                                    │
    │  │   → Scans ApprovedSchedules + launchd jobs                      │
    │  │   → Starts block if missed                                      │
    │  └─────────────────────────────────────────────────────────────────┘
    │
    │  Block starts:
    │  ┌─────────────────────────────────────────────────────────────────┐
    │  │ Checkup timer starts (1 sec)                                    │
    │  │   → checkupBlock every second                                   │
    │  │   → Integrity check every 15s                                   │
    │  │   → Expires block when endDate passes                           │
    │  └─────────────────────────────────────────────────────────────────┘
    │
    │  Block expires:
    │  ┌─────────────────────────────────────────────────────────────────┐
    │  │ Checkup timer stops                                             │
    │  │ Schedule timer continues (next segment may fire)                │
    │  └─────────────────────────────────────────────────────────────────┘
    │
    ▼
   (daemon runs forever)
```

## Resource Usage

The daemon is designed to be lightweight:

| Resource | Usage |
|----------|-------|
| Memory | ~5-10 MB |
| CPU (idle) | 0% |
| CPU (schedule sweep) | < 5ms every 60 seconds |
| CPU (active block) | < 1ms every second |

## Key Files

| File | Purpose |
|------|---------|
| `Daemon/SCDaemon.m` | Main daemon class, timers, lifecycle |
| `Daemon/SCDaemon.h` | Header |
| `Daemon/DaemonMain.m` | Entry point |
| `Daemon/SCDaemonBlockMethods.m` | Block operations, checkup logic |
| `Daemon/SCDaemonXPC.m` | XPC interface handlers |
| `Daemon/org.eyebeam.selfcontrold.plist` | launchd configuration |

---

*Last updated: January 2026*
