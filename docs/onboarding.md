# Onboarding Flow

## Overview

New users go through a safety check and test block flow to verify blocking works on their system before committing to a schedule.

## Flow Diagram

```mermaid
flowchart TD
    A[App Launch] --> B{Safety Check Needed?}

    B -->|Yes: Version changed| C[Show Safety Check Required prompt]
    C --> D[Run Safety Check]
    D --> E{Check Passed?}
    E -->|Yes| F[Show results + OK button]
    E -->|No| G[Show failure details]
    F --> H[User clicks OK]
    H --> I{Test Block Needed?}

    B -->|No| J{Test Block Needed AND<br/>Never Committed?}
    J -->|Yes| I
    J -->|No| K[Normal App Launch]

    I -->|Yes| L[Show Test Block prompt]
    L --> M{User choice}
    M -->|Try Test Block| N[Show Test Block Window]
    M -->|Maybe Later| K

    N --> O[User configures block]
    O --> P[Start Test Block]
    P --> Q[Block runs 30s-5min]
    Q --> R[Block completes]
    R --> S[User clicks Done]
    S --> T[Mark testBlockCompleted = YES]
    T --> K

    G --> U[User clicks OK]
    U --> K
```

## State Variables

| Key | Type | Purpose |
|-----|------|---------|
| `SCSafetyCheck_LastTestedAppVersion` | String | Last app version that passed safety check |
| `SCSafetyCheck_LastTestedOSVersion` | String | Last macOS version that passed safety check |
| `SCTestBlock_Completed` | Bool | User has completed a test block |
| `SCHasEverCommitted` | Bool | User has ever committed to a schedule |

## Skip Conditions

The test block prompt is **skipped** if ANY of these are true:
- User has completed a test block (`SCTestBlock_Completed = YES`)
- User has ever committed to a schedule (`SCHasEverCommitted = YES`)

## Trigger Conditions

### Safety Check Triggers
- App version changed since last safety check
- macOS version changed since last safety check

### Test Block Prompt Triggers
- Safety check just passed, OR
- Safety check not needed but test block never completed AND user never committed

## Key Files

| File | Purpose |
|------|---------|
| `Common/Utility/SCVersionTracker.h/m` | Tracks versions and completion states |
| `Common/SCStartupSafetyCheck.h/m` | Safety check logic |
| `SCSafetyCheckWindowController.h/m` | Safety check UI |
| `SCTestBlockWindowController.h/m` | Test block UI |
| `AppController.m` | Launch flow orchestration |
