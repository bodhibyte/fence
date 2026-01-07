# Schedule Job Lifecycle

This document describes the complete lifecycle of scheduled blocking jobs, from user input to cleanup.

> **Note:** For timezone handling and travel scenarios, see [TIMEZONE_HANDLING.md](TIMEZONE_HANDLING.md).
>
> **Note:** For daemon timers, persistence, and sleep/wake behavior, see [DAEMON_LIFECYCLE.md](DAEMON_LIFECYCLE.md).

## Overview Diagram

```mermaid
flowchart TB
    subgraph UI["User Interface"]
        A[User defines bundles & schedules]
        B[User clicks 'Commit Week']
    end

    subgraph Commit["Commit Flow (SCScheduleManager)"]
        C[commitToWeekWithOffset:]
        D[Cleanup stale jobs<br/>endDate in past]
        E[Calculate merged segments]
        F[Generate unique segmentID<br/>per segment]
    end

    subgraph Registration["Job Registration"]
        G[Register in ApprovedSchedules<br/>via XPC to daemon]
        H[Create launchd plist<br/>with startDate + endDate]
        I[Load job via launchctl]
    end

    subgraph Storage["Persisted State"]
        J[(ApprovedSchedules<br/>in daemon settings<br/>/usr/local/etc/.hash.plist)]
        K[(Launchd Plist<br/>~/Library/LaunchAgents/<br/>org.eyebeam...merged-UUID...plist)]
    end

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    F --> H
    G --> J
    H --> I
    I --> K
```

## Job Firing Paths

There are **three paths** that can trigger a scheduled block:

| Path | Trigger | Use Case |
|------|---------|----------|
| **Path 1** | launchd fires at scheduled time | Normal operation |
| **Path 2** | Daemon startup | Reboot during scheduled window |
| **Path 3** | Periodic daemon sweep (1 min) | Sleep/wake, launchd failures, background permission disabled |

```mermaid
flowchart TB
    subgraph Trigger["Job Trigger"]
        T1[launchd fires at<br/>StartCalendarInterval<br/>day + time]
        T2[System reboot<br/>during scheduled block]
        T3[Daemon sweep timer<br/>fires every 1 minute]
    end

    subgraph Path1["Path 1: Launchd → CLI → Daemon"]
        P1A[launchd executes CLI:<br/>selfcontrol-cli start<br/>--schedule-id=UUID<br/>--startdate=...<br/>--enddate=...]
        P1B{CLI: Parse dates<br/>from args}
        P1C{now < startDate?}
        P1D{now > endDate?}
        P1E[XPC: cleanupStaleSchedule]
        P1F[XPC: startScheduledBlockWithID]
        P1G[Skip - future week]
    end

    subgraph Path2["Path 2: Daemon Startup Recovery"]
        P2A[Daemon starts:<br/>startMissedBlockIfNeeded]
        P2B[Scan plist files in<br/>~/Library/LaunchAgents/]
        P2C[Parse startDate + endDate<br/>from plist ProgramArguments]
        P2D{now < startDate?}
        P2E{now > endDate?}
        P2F[cleanupStaleScheduleWithID]
        P2G[SCDaemonBlockMethods<br/>startBlock directly]
        P2H[Skip - future week]
    end

    subgraph Path3["Path 3: Periodic Daemon Sweep"]
        P3A[scheduleCheckTimer fires<br/>every 60 seconds]
        P3B[startMissedBlockIfNeeded]
        P3C{Block already<br/>running?}
        P3D[Exit early]
        P3E[Same as Path 2:<br/>Scan + validate + start]
    end

    subgraph Daemon["Daemon Block Execution"]
        D1[Lookup ApprovedSchedules<br/>by segmentID]
        D2[Extract blocklist +<br/>block settings]
        D3[SCDaemonBlockMethods<br/>startBlockWithControllingUID]
        D4[Install PF rules<br/>+ /etc/hosts<br/>+ AppBlocker]
        D5[Start checkup timer<br/>1-second interval]
    end

    T1 --> P1A
    P1A --> P1B
    P1B --> P1C
    P1C -->|Yes| P1G
    P1C -->|No| P1D
    P1D -->|Yes| P1E
    P1D -->|No| P1F
    P1E --> Cleanup
    P1F --> D1

    T2 --> P2A
    P2A --> P2B
    P2B --> P2C
    P2C --> P2D
    P2D -->|Yes| P2H
    P2D -->|No| P2E
    P2E -->|Yes| P2F
    P2E -->|No| P2G
    P2F --> Cleanup
    P2G --> D4

    T3 --> P3A
    P3A --> P3B
    P3B --> P3C
    P3C -->|Yes| P3D
    P3C -->|No| P3E
    P3E --> D4

    D1 --> D2
    D2 --> D3
    D3 --> D4
    D4 --> D5
```

### Path 3: Why Periodic Sweep?

The 1-minute periodic sweep exists as a **backup mechanism** for cases where launchd (Path 1) fails:

| Scenario | launchd Behavior | Path 3 Saves the Day |
|----------|------------------|----------------------|
| **Sleep/wake** | May not fire jobs during sleep | Sweep catches it within 60s of wake |
| **Background permission disabled** | Jobs not loaded | Sweep bypasses launchd entirely |
| **launchd edge cases** | Rare timing issues | Sweep provides redundancy |

**Race condition safety:** The sweep always checks `anyBlockIsRunning` first. If launchd already started the block, the sweep exits early. Both paths can fire — only one will actually start the block.

## Block Lifecycle & Expiration

```mermaid
flowchart TB
    subgraph Active["Active Block"]
        A1[Block running<br/>BlockIsRunning = YES]
        A2[Checkup timer<br/>every 1 second]
        A3{Block expired?<br/>now > endDate}
        A4{Block tampered?<br/>rules missing}
        A5[Re-add rules<br/>checkBlockIntegrity]
    end

    subgraph End["Block End"]
        E1[removeBlock]
        E2[Clear PF rules]
        E3[Restore /etc/hosts]
        E4[Stop AppBlocker]
        E5[BlockIsRunning = NO]
        E6[Stop checkup timer]
    end

    A1 --> A2
    A2 --> A3
    A3 -->|No| A4
    A4 -->|Yes| A5
    A5 --> A2
    A4 -->|No| A2
    A3 -->|Yes| E1
    E1 --> E2
    E2 --> E3
    E3 --> E4
    E4 --> E5
    E5 --> E6
```

## Cleanup Mechanisms

There are **two types of cleanup** for different scenarios:

| Cleanup Type | Purpose | What it clears |
|--------------|---------|----------------|
| `cleanupStaleScheduleWithID:` | Remove expired **job definition** | launchd plist + ApprovedSchedules entry |
| `clearExpiredBlockWithReply:` | Remove expired **blocking rules** | PF rules + /etc/hosts + AppBlocker + BlockIsRunning flag |

### Job Cleanup (cleanupStaleScheduleWithID)

Used when a scheduled job's `endDate` has passed - removes the job definition.

```mermaid
flowchart TB
    subgraph Triggers["Job Cleanup Triggers"]
        T1[CLI detects<br/>job endDate passed]
        T2[Daemon startup detects<br/>job endDate passed]
        T3[Commit flow detects<br/>stale jobs]
    end

    subgraph Cleanup["cleanupStaleScheduleWithID:"]
        C1[Remove from<br/>ApprovedSchedules]
        C2[Find plist matching<br/>merged-UUID pattern]
        C3[launchctl bootout<br/>unload job]
        C4[Delete plist file]
    end

    subgraph Result["Result"]
        R1[Job no longer fires]
        R2[ApprovedSchedules<br/>entry removed]
        R3[Resources freed]
    end

    T1 --> Cleanup
    T2 --> Cleanup
    T3 --> Cleanup

    C1 --> C2
    C2 --> C3
    C3 --> C4
    C4 --> R1
    C4 --> R2
    C4 --> R3
```

### Block Cleanup (clearExpiredBlockWithReply)

Used when an active block has expired but wasn't cleared (e.g., after sleep/wake when checkup timer couldn't run).

```mermaid
flowchart TB
    subgraph Trigger["Block Cleanup Trigger"]
        T1[CLI detects:<br/>anyBlockIsRunning=YES<br/>AND currentBlockIsExpired=YES]
    end

    subgraph Cleanup["clearExpiredBlockWithReply:"]
        C1[Verify block is<br/>actually expired]
        C2[Clear PF firewall rules]
        C3[Restore /etc/hosts]
        C4[Stop AppBlocker]
        C5[Set BlockIsRunning=NO]
        C6[Send config notification]
    end

    subgraph Result["Result"]
        R1[Blocking infrastructure<br/>removed]
        R2[New block can<br/>start cleanly]
    end

    T1 --> C1
    C1 --> C2
    C2 --> C3
    C3 --> C4
    C4 --> C5
    C5 --> C6
    C6 --> R1
    C6 --> R2
```

**Sleep/Wake Scenario:**
1. Block runs from 9:00-10:00
2. User closes laptop at 9:30 (sleep)
3. At 10:00, block should expire, but checkup timer is suspended
4. At 11:00, next scheduled block tries to start
5. CLI detects: `anyBlockIsRunning=YES` but `currentBlockIsExpired=YES`
6. CLI calls `clearExpiredBlock` to clear stale blocking rules
7. New block starts successfully

## Data Structures

### Launchd Plist (Job Definition)

```
~/Library/LaunchAgents/org.eyebeam.selfcontrol.schedule.merged-{UUID}.{day}.{time}.plist
```

```xml
<dict>
    <key>Label</key>
    <string>org.eyebeam.selfcontrol.schedule.merged-550e8400-e29b-41d4.tuesday.0930</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Applications/SelfControl.app/Contents/MacOS/selfcontrol-cli</string>
        <string>start</string>
        <string>--schedule-id=550e8400-e29b-41d4</string>
        <string>--startdate=2026-01-06T09:30:00Z</string>
        <string>--enddate=2026-01-06T17:00:00Z</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>2</integer>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>30</integer>
    </dict>

    <key>RunAtLoad</key><false/>
</dict>
```

### ApprovedSchedules Entry

```
/usr/local/etc/.{hash}.plist → ApprovedSchedules dictionary
```

```objc
ApprovedSchedules[@"550e8400-e29b-41d4"] = @{
    @"blocklist": @[@"facebook.com", @"app:com.apple.Terminal"],
    @"isAllowlist": @NO,
    @"blockSettings": @{
        @"ClearCaches": @YES,
        @"AllowLocalNetworks": @NO
    },
    @"controllingUID": @501,
    @"registeredAt": <NSDate>
};
```

## Validation Logic

```mermaid
flowchart LR
    subgraph Input["Job Fires"]
        I1[startDate]
        I2[endDate]
        I3[now = current time]
    end

    subgraph Check["Validation"]
        C1{now < startDate?}
        C2{now > endDate?}
    end

    subgraph Action["Action"]
        A1[SKIP<br/>Future week<br/>Don't cleanup]
        A2[CLEANUP<br/>Expired job<br/>Remove everything]
        A3[EXECUTE<br/>Valid job<br/>Start block]
    end

    I1 --> C1
    I2 --> C2
    I3 --> C1
    I3 --> C2

    C1 -->|Yes| A1
    C1 -->|No| C2
    C2 -->|Yes| A2
    C2 -->|No| A3
```

## Multi-Week Commit Scenario (Sunday)

```mermaid
sequenceDiagram
    participant U as User
    participant SM as SCScheduleManager
    participant LB as LaunchdBridge
    participant D as Daemon
    participant L as Launchd

    Note over U: It's Sunday Jan 5

    U->>SM: Commit This Week
    SM->>SM: Cleanup stale jobs (none)
    SM->>LB: Create segments for This Week
    LB->>D: Register ApprovedSchedules[UUID-A]
    LB->>L: Install job UUID-A<br/>Sunday 2pm-6pm<br/>startDate=Jan 5 2pm<br/>endDate=Jan 5 6pm

    U->>SM: Commit Next Week
    SM->>SM: Cleanup stale jobs (none - This Week still valid)
    SM->>LB: Create segments for Next Week
    LB->>D: Register ApprovedSchedules[UUID-B]
    LB->>L: Install job UUID-B<br/>Sunday 2pm-6pm<br/>startDate=Jan 12 2pm<br/>endDate=Jan 12 6pm

    Note over L: Sunday Jan 5, 2pm arrives

    L->>L: Fire UUID-A job
    L->>L: Fire UUID-B job (same day/time!)

    Note over L: UUID-A: startDate=Jan 5 ✓
    Note over L: UUID-B: startDate=Jan 12 ✗ (future)

    L-->>D: UUID-A proceeds → Block starts
    L-->>D: UUID-B skips (now < startDate)
```

## Key Files

| File | Purpose |
|------|---------|
| `Block Management/SCScheduleManager.m` | Commit flow, segment calculation, cleanup orchestration |
| `Block Management/SCScheduleLaunchdBridge.m` | Plist creation with startDate/endDate |
| `cli-main.m` | CLI arg parsing, validation, expired block detection, XPC calls |
| `Daemon/SCDaemon.m` | Startup recovery, cleanup helper, **1-minute schedule sweep timer** |
| `Daemon/SCDaemonXPC.m` | XPC handlers for start block + cleanup + clearExpiredBlock |
| `Daemon/SCDaemonBlockMethods.m` | Actual block execution, checkup timer |

---

*Last updated: January 2026*
