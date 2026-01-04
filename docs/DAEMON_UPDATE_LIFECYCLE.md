# Daemon Update Lifecycle

This document describes how the privileged daemon (`selfcontrold`) gets updated when the app is updated via Sparkle.

## Overview

The daemon is installed via `SMJobBless` to `/Library/PrivilegedHelperTools/org.eyebeam.selfcontrold`. It only gets updated when the main app explicitly reinstalls it - **not** when launchd jobs fire.

## Update Triggers

```mermaid
flowchart TB
    subgraph Triggers["Daemon Update Triggers"]
        T1[User commits a schedule]
        T2[App launches with active block]
        T3[User starts manual block]
    end

    subgraph NoUpdate["Does NOT Trigger Update"]
        N1[Launchd job fires]
        N2[App launches, no active block]
        N3[CLI executes]
    end

    subgraph Update["Daemon Update Flow"]
        U1[installDaemon: called]
        U2[SMJobRemove - kill old daemon]
        U3[SMJobBless - install new daemon]
        U4[New daemon running ✓]
    end

    T1 --> U1
    T2 --> U1
    T3 --> U1
    U1 --> U2
    U2 --> U3
    U3 --> U4

    N1 -.->|Uses existing daemon| X[No update]
    N2 -.->|Skips version check| X
    N3 -.->|Just XPC call| X
```

## App Launch Flow

```mermaid
flowchart TB
    A[App Launches] --> B{modernBlockIsRunning?}

    B -->|YES| C[Wait 0.5s]
    C --> D[XPC: getVersion]
    D --> E{Compare versions}

    E -->|App > Daemon| F[reinstallDaemon]
    F --> G[SMJobRemove]
    G --> H[SMJobBless]
    H --> I[New daemon installed ✓]

    E -->|App <= Daemon| J[No action needed]

    B -->|NO| K[Skip version check]
    K --> L[Old daemon stays until next commit]

    style F fill:#ff9999
    style I fill:#99ff99
    style L fill:#ffff99
```

## Sparkle Update Scenario

```mermaid
sequenceDiagram
    participant U as User
    participant S as Sparkle
    participant App as Fence.app
    participant D as Daemon

    Note over U,D: Scenario 1: Block is running during update

    U->>S: Check for updates
    S->>S: Download new Fence.app
    S->>App: Relaunch app
    App->>App: modernBlockIsRunning? → YES
    App->>D: XPC: getVersion
    D-->>App: "4.0.1" (old)
    App->>App: 4.0.2 > 4.0.1 → OUTDATED
    App->>D: SMJobRemove (kill old)
    App->>D: SMJobBless (install new)
    Note over D: New daemon v4.0.2 running ✓

    Note over U,D: Scenario 2: No block running during update

    U->>S: Check for updates
    S->>S: Download new Fence.app
    S->>App: Relaunch app
    App->>App: modernBlockIsRunning? → NO
    App->>App: Skip version check
    Note over D: Old daemon stays installed

    Note over U,D: Later: User commits schedule
    U->>App: Click "Commit"
    App->>App: installDaemon: called
    App->>D: SMJobRemove + SMJobBless
    Note over D: New daemon installed ✓
```

## Launchd Job Flow (No Daemon Update)

```mermaid
flowchart TB
    subgraph Launchd["Launchd Job Fires"]
        L1[StartCalendarInterval triggers]
        L2[Execute selfcontrol-cli]
    end

    subgraph CLI["CLI Execution"]
        C1[Parse --schedule-id, --startdate, --enddate]
        C2[Validate dates]
        C3[Connect to daemon via XPC]
        C4[Call startScheduledBlockWithID:]
    end

    subgraph Daemon["Existing Daemon"]
        D1[Receive XPC call]
        D2[Start block with settings from ApprovedSchedules]
    end

    L1 --> L2
    L2 --> C1
    C1 --> C2
    C2 --> C3
    C3 --> D1
    D1 --> D2

    Note1[CLI talks to EXISTING daemon]
    Note2[No SMJobBless called]
    Note3[Daemon version unchanged]

    style Note1 fill:#ffff99
    style Note2 fill:#ffff99
    style Note3 fill:#ffff99
```

## Version Comparison

Both app and daemon use the same version from `version-header.h`:

```c
#define SELFCONTROL_VERSION_STRING @"4.0.2"
```

Comparison logic in `AppController.m`:

```objc
if ([SELFCONTROL_VERSION_STRING compare:daemonVersion options:NSNumericSearch] == NSOrderedDescending) {
    // App version > daemon version → reinstall
    [self reinstallDaemon];
}
```

## Key Files

| File | Purpose |
|------|---------|
| `Common/SCXPCClient.m` | `installDaemon:` method with SMJobBless |
| `AppController.m` | Version check on app launch |
| `version-header.h` | Single source of truth for version |
| `Daemon/SCDaemonXPC.m` | `getVersionWithReply:` implementation |

## Log Messages

When the app launches, look for these log messages:

```
# Block running → version check runs
AppController: Daemon update check - modernBlockIsRunning=YES, appVersion=4.0.2
AppController: Block is running, will check daemon version in 0.5s...
AppController: Daemon version check - daemonVersion=4.0.2, appVersion=4.0.2
AppController: Daemon UP-TO-DATE (4.0.2) - no action needed

# Block running, daemon outdated
AppController: Daemon OUTDATED (4.0.1 < 4.0.2) - reinstalling...

# No block running → skip check
AppController: Daemon update check - modernBlockIsRunning=NO, appVersion=4.0.2
AppController: No block running - skipping daemon version check (will update on next commit)
```

## Summary

| Event | Daemon Updated? | Why |
|-------|-----------------|-----|
| User commits schedule | ✅ Yes | `installDaemon:` called before registering jobs |
| App launches with active block | ✅ Yes | Version check + reinstall if outdated |
| User starts manual block | ✅ Yes | `installDaemon:` called |
| Launchd job fires | ❌ No | CLI just connects to existing daemon |
| App launches, no block | ❌ No | Version check skipped |

**Worst case:** User updates via Sparkle with no active block → old daemon until next commit (typically within a week).

---

*Last updated: January 2026*
