# Licensing System - Current Implementation

> **Source of Truth:** This document reflects the ACTUAL implementation as of January 2026.
>
> **Note:** `LICENSING_SPEC.md` and `LICENSING_HANDOVER.md` are outdated and should be considered historical references only.

---

## Documentation Status

| Document | Status | Issue |
|----------|--------|-------|
| `LICENSING_SPEC.md` | **Outdated** | Describes commit-based trial (2 commits); actual is date-based |
| `LICENSING_HANDOVER.md` | **Partially Outdated** | Says online activation "not yet implemented" but it IS implemented |
| `LICENSING_CURRENT.md` | **Current** | This document - reflects actual code |

---

## Overview

Fence uses a **date-based trial** with **server-synchronized state** and **iCloud license storage**.

| Component | Implementation |
|-----------|----------------|
| Trial | Expires Saturday midnight before 3rd Sunday from install (~2.5 weeks) |
| Storage | iCloud key-value store (primary) + UserDefaults (backup) |
| Server | Railway API at `fence-api-cli-production.up.railway.app` |
| Device ID | SHA256 hash of IOPlatformUUID |

---

## App Startup Flow

```mermaid
sequenceDiagram
    participant App as AppController
    participant LM as SCLicenseManager
    participant UD as UserDefaults
    participant IC as iCloud KV Store
    participant API as Railway API

    Note over App: App launches

    App->>LM: [SCLicenseManager sharedManager]

    activate LM
    LM->>LM: init
    LM->>UD: Check FenceFirstLaunchDate

    alt First launch ever
        LM->>UD: Set FenceFirstLaunchDate = now
        LM->>LM: calculateTrialExpiryDate
        LM->>UD: Set FenceTrialExpiryDate
    end

    LM->>LM: setupAPISession (bypass proxy)
    deactivate LM

    Note over App: Async: Trial Sync

    App->>LM: syncTrialStatusWithCompletion:
    activate LM
    LM->>LM: Get deviceIdentifier (SHA256 of UUID)
    LM->>API: POST /api/trial/check<br/>{ deviceId: "..." }

    alt Server responds
        API-->>LM: { expiresAt, daysRemaining }
        LM->>UD: Update FenceTrialExpiryDate<br/>(if server says earlier)
        LM->>UD: Cache in FenceCachedServerTrialExpiry
    else Network fails
        LM->>UD: Use cached FenceTrialExpiryDate
    end
    deactivate LM

    Note over App: Async: License Recovery

    App->>LM: attemptLicenseRecoveryWithCompletion:
    activate LM
    LM->>IC: Check for existing license

    alt No local license
        LM->>API: GET /api/recover?deviceId=...
        alt Server has license for device
            API-->>LM: { licenseCode: "FENCE-..." }
            LM->>IC: Store recovered license
            LM->>UD: Backup to UserDefaults
        end
    end
    deactivate LM

    Note over App: App ready for user interaction
```

---

## License Status vs Commit Permission

There are **two different checks** with different logic:

| Method | Purpose | Logic |
|--------|---------|-------|
| `currentStatus` | Display status (menu, UI) | License checked FIRST, takes priority over trial |
| `canCommit` | Guard commit action | Short-circuits if trial active (doesn't distinguish licensed vs trial) |

### Status Display Flow (currentStatus)

```mermaid
flowchart TB
    subgraph Check["SCLicenseManager.currentStatus"]
        A[Start]
        B[retrieveLicenseFromStorage]
        C{Valid license<br/>in storage?}
        D{isTrialExpired?}
    end

    subgraph Result["Status"]
        R1[SCLicenseStatusValid<br/>Menu: hidden trial info]
        R2[SCLicenseStatusTrial<br/>Menu: 'Free Trial X days']
        R3[SCLicenseStatusTrialExpired<br/>Menu: 'Trial Expired']
        R4[SCLicenseStatusInvalid<br/>Menu: 'Trial Expired']
    end

    A --> B
    B --> C
    C -->|Yes| R1
    C -->|No| D
    D -->|No| R2
    D -->|Yes, no code| R3
    D -->|Yes, invalid code| R4

    style R1 fill:#90EE90
    style R2 fill:#87CEEB
    style R3 fill:#FFB6C1
    style R4 fill:#FFB6C1
```

**Key Point:** If you enter a license during trial, `currentStatus` immediately returns `SCLicenseStatusValid` and the menu shows you as licensed (hides trial info + "Enter License" option).

### Commit Permission Flow (canCommit)

```mermaid
flowchart TB
    subgraph Trigger["User Action"]
        A[User clicks Commit]
    end

    subgraph Check["SCLicenseManager.canCommit"]
        B{isTrialExpired?}
        C[currentStatus]
        D{status == Valid?}
    end

    subgraph Result["Outcome"]
        R1[Allow commit]
        R2[Show license modal]
    end

    A --> B
    B -->|No - Trial active| R1
    B -->|Yes - Trial expired| C
    C --> D
    D -->|Yes| R1
    D -->|No| R2

    style R1 fill:#90EE90
    style R2 fill:#FFB6C1
```

**Note:** `canCommit` short-circuits if trial is active. This is fine because both trial users and licensed users can commit - the distinction only matters for display purposes.

---

## Trial Expiry Calculation

```mermaid
flowchart LR
    subgraph Input["Install Date"]
        I1[firstLaunchDate]
        I2[Current weekday<br/>Sunday=1...Saturday=7]
    end

    subgraph Calc["calculateTrialExpiryDate"]
        C1[Days until next Sunday]
        C2[Add 13 days<br/>2 more full weeks]
        C3[Set time to 23:59:59]
    end

    subgraph Output["Result"]
        O1[Saturday midnight<br/>before 3rd Sunday]
        O2[~14-20 days<br/>depending on install day]
    end

    I1 --> C1
    I2 --> C1
    C1 --> C2
    C2 --> C3
    C3 --> O1
    O1 --> O2
```

**Example:**
- Install on Monday → Trial = 19 days
- Install on Sunday → Trial = 20 days
- Install on Saturday → Trial = 14 days

---

## License Validation Flow

```mermaid
flowchart TB
    subgraph Input["License Code"]
        L1["FENCE-{base64(payload.signature)}"]
    end

    subgraph Local["Local Validation (validateLicenseCode:)"]
        V1{Starts with FENCE-?}
        V2[Base64 decode<br/>standard + URL-safe]
        V3{Valid base64?}
        V4[Split by last '.']
        V5{Has payload + sig?}
        V6[Parse JSON payload]
        V7{Has e, t, c fields?}
        V8[Compute HMAC-SHA256<br/>using SECRET_KEY]
        V9{Signatures match?}
    end

    subgraph Online["Online Activation (activateLicenseOnline:)"]
        O1[POST /api/activate<br/>licenseCode + deviceId]
        O2{Response?}
        O3[200: Store in iCloud]
        O4[409: Already used]
        O5[404: Not in database]
        O6[Network error:<br/>Offline fallback]
    end

    subgraph Storage["Storage"]
        S1[iCloud KV Store<br/>FenceLicenseCode]
        S2[UserDefaults backup<br/>FenceLicenseCode]
    end

    L1 --> V1
    V1 -->|No| X1[Reject]
    V1 -->|Yes| V2
    V2 --> V3
    V3 -->|No| X1
    V3 -->|Yes| V4
    V4 --> V5
    V5 -->|No| X1
    V5 -->|Yes| V6
    V6 --> V7
    V7 -->|No| X1
    V7 -->|Yes| V8
    V8 --> V9
    V9 -->|No| X1
    V9 -->|Yes| O1

    O1 --> O2
    O2 -->|200| O3
    O2 -->|409| O4
    O2 -->|404| O5
    O2 -->|Error| O6

    O3 --> S1
    O3 --> S2
    O6 --> S1
    O6 --> S2

    style X1 fill:#FFB6C1
    style O3 fill:#90EE90
    style O6 fill:#FFE4B5
```

---

## License Retrieval Fallback Chain

```mermaid
flowchart TB
    subgraph Check["retrieveLicenseFromStorage"]
        A[Start retrieval]
        B[Try iCloud KV Store]
        C{Found in iCloud?}
        D[Try UserDefaults]
        E{Found locally?}
        F[Validate signature]
        G{Valid?}
        H[Sync local → iCloud]
    end

    subgraph Result["Outcome"]
        R1[Return valid license]
        R2[Return nil]
    end

    A --> B
    B --> C
    C -->|Yes| F
    C -->|No| D
    D --> E
    E -->|Yes| F
    E -->|No| R2
    F --> G
    G -->|Yes| H
    G -->|No| R2
    H --> R1

    style R1 fill:#90EE90
    style R2 fill:#FFB6C1
```

---

## Key Code References

### Trial Logic

| File | Method | Lines | Purpose |
|------|--------|-------|---------|
| `Common/SCLicenseManager.m` | `ensureFirstLaunchDate` | 94-102 | Sets first launch date |
| `Common/SCLicenseManager.m` | `calculateTrialExpiryDate` | 106-128 | 3rd Sunday calculation |
| `Common/SCLicenseManager.m` | `trialExpiryDate` | 130-139 | Gets/caches expiry |
| `Common/SCLicenseManager.m` | `isTrialExpired` | 141-147 | Checks expiry |
| `Common/SCLicenseManager.m` | `trialDaysRemaining` | 149-158 | Days remaining |
| `Common/SCLicenseManager.m` | `canCommit` | 162-167 | Main commit guard |

### License Validation

| File | Method | Lines | Purpose |
|------|--------|-------|---------|
| `Common/SCLicenseManager.m` | `validateLicenseCode:error:` | 195-303 | Local HMAC validation |
| `Common/SCLicenseManager.m` | `activateLicenseOnline:completion:` | 460-549 | Server activation |
| `Common/SCLicenseManager.m` | `storeLicenseIniCloud:` | 374-390 | iCloud storage |
| `Common/SCLicenseManager.m` | `retrieveLicenseFromStorage` | 392-426 | iCloud + local retrieval |

### Server Sync

| File | Method | Lines | Purpose |
|------|--------|-------|---------|
| `Common/SCLicenseManager.m` | `syncTrialStatusWithCompletion:` | 553-616 | Trial sync with server |
| `Common/SCLicenseManager.m` | `attemptLicenseRecoveryWithCompletion:` | 620-703 | License recovery |
| `Common/SCDeviceIdentifier.m` | `+deviceIdentifier` | 14-34 | SHA256 of hardware UUID |

### Startup Hooks

| File | Location | Lines | Hook |
|------|----------|-------|------|
| `AppController.m` | awakeFromNib or init | 463-466 | `syncTrialStatusWithCompletion:` |
| `AppController.m` | awakeFromNib or init | 468-475 | `attemptLicenseRecoveryWithCompletion:` |
| `AppController.m` | commit action | 134-143 | `canCommit` guard |

### UI Integration

| File | Method | Lines | Purpose |
|------|--------|-------|---------|
| `SCLicenseWindowController.m` | `activateClicked:` | 206-242 | Activation button |
| `SCMenuBarController.m` | Trial status display | 185-208 | Menu bar status |
| `SCWeekScheduleWindowController.m` | Commit guard | 687-697 | Pre-commit license check |

---

## UserDefaults Keys

| Key | Type | Purpose |
|-----|------|---------|
| `FenceFirstLaunchDate` | NSDate | When app first launched |
| `FenceTrialExpiryDate` | NSDate | Calculated local expiry |
| `FenceCachedServerTrialExpiry` | NSDate | Server-synced expiry |
| `FenceLicenseCode` | NSString | License backup (also in iCloud) |

---

## Server Endpoints

**Base URL:** `https://fence-api-cli-production.up.railway.app`

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/trial/check` | POST | Sync trial status by device ID |
| `/api/activate` | POST | Activate license (marks as used) |
| `/api/recover` | GET | Recover license by device ID |

---

## Storage Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iCloud KV Store                         │
│                    (NSUbiquitousKeyValueStore)                  │
│                                                                 │
│  FenceLicenseCode = "FENCE-..."                                │
│  ─────────────────────────────────────────────────────────────  │
│  Syncs across all user's devices with same Apple ID             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Fallback
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        UserDefaults                             │
│                                                                 │
│  FenceFirstLaunchDate = <NSDate>                               │
│  FenceTrialExpiryDate = <NSDate>                               │
│  FenceCachedServerTrialExpiry = <NSDate>                       │
│  FenceLicenseCode = "FENCE-..." (backup)                       │
│  ─────────────────────────────────────────────────────────────  │
│  Device-local, survives reinstalls                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Server sync
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Railway API Server                         │
│                                                                 │
│  - Tracks which licenses are activated                          │
│  - Tracks trial expiry by device ID                             │
│  - Can recover licenses if local storage fails                  │
└─────────────────────────────────────────────────────────────────┘
```

**Note:** The implementation has moved AWAY from Keychain to iCloud key-value storage. Old documentation mentioning Keychain is outdated.

---

## Debug Commands

```bash
# Reset trial to fresh state
defaults delete org.eyebeam.Fence FenceTrialExpiryDate
defaults delete org.eyebeam.Fence FenceFirstLaunchDate

# Check trial expiry
defaults read org.eyebeam.Fence FenceTrialExpiryDate

# Check first launch date
defaults read org.eyebeam.Fence FenceFirstLaunchDate

# Delete local license backup
defaults delete org.eyebeam.Fence FenceLicenseCode

# Generate test license
node generate-test-license.js
```

---

*Last updated: January 2026*
