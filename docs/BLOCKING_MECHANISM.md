# SelfControl Blocking Mechanism Deep Dive

> **Purpose:** Technical documentation of how blocking works and how to extend it for app blocking

---

## Current Blocking Architecture

### The Two Walls

SelfControl blocks network access using **two independent mechanisms**. This dual-layer approach ensures that bypassing one layer still leaves the other active.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BLOCKING ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Wall 1: DNS Redirect (/etc/hosts)                                     │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  facebook.com  →  0.0.0.0 (goes nowhere)                      │     │
│   │  twitter.com   →  ::      (IPv6 nowhere)                      │     │
│   │                                                                │     │
│   │  How: System checks /etc/hosts BEFORE DNS servers            │     │
│   │  Bypass: Direct IP access (that's why we need Wall 2)        │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                          │
│   Wall 2: Packet Filter (macOS Firewall)                                │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  block return out proto tcp from any to 157.240.1.35         │     │
│   │  block return out proto udp from any to 104.244.42.1         │     │
│   │                                                                │     │
│   │  How: Kernel intercepts packets before they leave            │     │
│   │  Catches: Direct IP access that bypasses DNS                 │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Both?

| Scenario | Wall 1 (hosts) | Wall 2 (PF) |
|----------|---------------|-------------|
| User types facebook.com | ✅ Blocks | (never reached) |
| User uses IP directly | ❌ Bypassed | ✅ Blocks |
| User modifies /etc/hosts | ❌ Removed | ✅ Still blocks |
| User flushes PF rules | ✅ Still blocks | ❌ Removed |

---

## Detailed Blocking Flow

### 1. User Initiates Block

```
User clicks "Start Block"
         │
         ▼
┌─────────────────────────┐
│   AppController.m:234   │
│   addBlock:             │
│   - Validate blocklist  │
│   - Check duration      │
│   - Start bg thread     │
└─────────────────────────┘
         │
         ▼ (background thread)
┌─────────────────────────┐
│   AppController.m:312   │
│   installBlock:         │
│   - Get authorization   │
│   - Create XPC client   │
│   - Call daemon         │
└─────────────────────────┘
```

### 2. Daemon Receives Request

```
XPC Call arrives at daemon
         │
         ▼
┌────────────────────────────────┐
│  SCDaemonBlockMethods.m:89     │
│  startBlock:                   │
│  - Acquire method lock         │
│  - Validate parameters         │
│  - Store in SCSettings         │
└────────────────────────────────┘
         │
         ▼
┌────────────────────────────────┐
│  SCHelperToolUtilities.m:45    │
│  installBlockRulesFromSettings │
│  - Create BlockManager         │
│  - Call prepareToAddBlock      │
│  - Add each entry              │
│  - Finalize block              │
└────────────────────────────────┘
```

### 3. BlockManager Orchestrates

```
BlockManager.m
         │
         ├──► prepareToAddBlock() ──► Clear old entries from /etc/hosts
         │
         ├──► addBlockEntriesFromStrings() ──► For each entry:
         │         │
         │         ├── Parse entry (hostname:port/mask)
         │         ├── If IP: add PF rule
         │         └── If domain:
         │              ├── Resolve to IP(s) via DNS
         │              ├── Add PF rules for each IP
         │              ├── Add hosts file entries
         │              └── Handle subdomains if enabled
         │
         └──► finalizeBlock() ──► Write files, activate PF
```

### 4. Actual System Modifications

**HostFileBlocker.m - DNS Redirect:**
```objc
// Line ~89
- (BOOL)addRuleBlockingDomain:(NSString*)domain {
    // Add IPv4 redirect
    [hostFileContents appendFormat:@"0.0.0.0\t%@\n", domain];
    // Add IPv6 redirect
    [hostFileContents appendFormat:@"::\t%@\n", domain];
}
```

**PacketFilter.m - Firewall Rules:**
```objc
// Line ~67
- (void)addRuleWithIP:(NSString*)ip port:(int)port maskLen:(int)mask {
    if (port == 0) {
        // Block all ports
        [rules appendFormat:@"block return out proto tcp from any to %@\n", ip];
        [rules appendFormat:@"block return out proto udp from any to %@\n", ip];
    } else {
        // Block specific port
        [rules appendFormat:@"block return out proto tcp from any to %@ port %d\n", ip, port];
    }
}
```

### 5. Enforcement Activation

```objc
// PacketFilter.m:~120
- (void)startBlock {
    // Write rules to anchor file
    [rules writeToFile:@"/etc/pf.anchors/org.eyebeam" atomically:YES];

    // Reload packet filter
    NSTask *pfctl = [[NSTask alloc] init];
    pfctl.launchPath = @"/sbin/pfctl";
    pfctl.arguments = @[@"-f", @"/etc/pf.conf"];
    [pfctl launch];
}
```

---

## The Checkup Timer

**Purpose:** Ensure block persists even if user tries to tamper

```
Every 1 second (SCDaemonBlockMethods.m:~200):
┌──────────────────────────────────────────────────────┐
│                    checkupBlock()                     │
├──────────────────────────────────────────────────────┤
│                                                       │
│  1. Check if BlockEndDate has passed                 │
│     └── If yes: Remove block, kill daemon            │
│                                                       │
│  2. Verify /etc/hosts contains SelfControl section   │
│     └── If missing: Restore from .bak                │
│                                                       │
│  3. Verify PF rules are loaded                       │
│     └── If missing: Reload pfctl                     │
│                                                       │
│  4. Check for tampering                              │
│     └── If detected: Set punishment flag             │
│                                                       │
└──────────────────────────────────────────────────────┘
```

---

## App Blocking Implementation

### Overview

SelfControl now supports blocking **applications** in addition to network destinations. Blocked apps are immediately terminated when launched.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    EXTENDED BLOCKING ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Wall 1: DNS Redirect (/etc/hosts) ............ [EXISTING]             │
│                                                                          │
│   Wall 2: Packet Filter (PF Rules) ............. [EXISTING]             │
│                                                                          │
│   Wall 3: App Blocker (Process Control) ........ [IMPLEMENTED]          │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  Process Monitor + Kill (AppBlocker singleton)                │     │
│   │  - Polls running processes every 500ms via libproc            │     │
│   │  - Extracts bundle ID from .app/Contents/Info.plist           │     │
│   │  - Kills matching processes with SIGTERM/SIGKILL              │     │
│   │  - Singleton pattern ensures persistence across method calls  │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Implementation Details

**Key Design Decisions:**

1. **Singleton Pattern:** `[AppBlocker sharedBlocker]` ensures the blocker persists for the daemon's lifetime, independent of BlockManager's lifecycle. This was critical because BlockManager is a local variable that gets deallocated after `finalizeBlock`.

2. **libproc APIs:** Uses `proc_listpids()` and `proc_pidpath()` instead of `NSWorkspace` because the daemon runs as root without a GUI session.

3. **Bundle ID Extraction:** Walks up the executable path to find `.app` bundle, then reads `Info.plist` to get `CFBundleIdentifier`.

**Core Implementation (`Block Management/AppBlocker.m`):**
```objc
+ (instancetype)sharedBlocker {
    static AppBlocker* shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AppBlocker alloc] init];
    });
    return shared;
}

- (NSArray<NSNumber*>*)findAndKillBlockedApps {
    // Get all PIDs via libproc (daemon-safe, no NSWorkspace)
    int numPids = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t* pids = malloc(sizeof(pid_t) * numPids);
    proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pid_t) * numPids);

    for (int i = 0; i < numPids; i++) {
        // Get executable path
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        proc_pidpath(pids[i], pathBuffer, sizeof(pathBuffer));

        // Extract bundle ID from .app/Contents/Info.plist
        NSString* bundleID = [self bundleIDFromExecutablePath:path];

        if ([blockedBundleIDs containsObject:bundleID]) {
            kill(pids[i], SIGTERM);  // Graceful termination
        }
    }
    free(pids);
}
```

### Integration Points

**1. SCBlockEntry.m - App entry parsing:**
```objc
// Parses "app:com.bundle.id" format
+ (SCBlockEntry*)entryFromString:(NSString*)entryString {
    if ([entryString hasPrefix:@"app:"]) {
        SCBlockEntry* entry = [[SCBlockEntry alloc] init];
        entry.appBundleID = [entryString substringFromIndex:4];
        entry.hostname = nil;  // Not a network block
        return entry;
    }
    // ... existing hostname parsing
}

- (BOOL)isAppEntry {
    return self.appBundleID != nil && self.appBundleID.length > 0;
}
```

**2. BlockManager.m - Routes app entries to AppBlocker:**
```objc
// Uses singleton
_appBlocker = [AppBlocker sharedBlocker];

- (void)addBlockEntryFromString:(NSString*)entryString {
    SCBlockEntry* entry = [SCBlockEntry entryFromString:entryString];

    // App entries bypass hostname-related logic
    if ([entry isAppEntry]) {
        [self addBlockEntry:entry];
        return;
    }
    // ... existing subdomain/related entry logic
}

- (void)addBlockEntry:(SCBlockEntry*)entry {
    if ([entry isAppEntry]) {
        [self.appBlocker addBlockedApp:entry.appBundleID];
        return;
    }
    // ... existing network blocking
}

- (void)finalizeBlock {
    // ... existing code
    if (self.appBlocker.blockedBundleIDs.count > 0) {
        [self.appBlocker startMonitoring];
    }
}
```

**3. UI - DomainListWindowController.m:**
```objc
// "Add App" button opens app picker
- (IBAction)addAppToBlocklist:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeApplication];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSBundle* appBundle = [NSBundle bundleWithURL:panel.URL];
            NSString* entry = [NSString stringWithFormat:@"app:%@", appBundle.bundleIdentifier];
            [self.blocklist addObject:entry];
        }
    }];
}
```

### Block Entry Format (Extended)

```
Current format:
  hostname[:port][/masklen]

Extended format:
  hostname[:port][/masklen]    - Network block (existing)
  app:com.bundle.identifier   - App block (new)

Examples:
  facebook.com               - Block facebook.com website
  app:com.apple.Terminal     - Block Terminal.app
  app:com.cursor.Cursor      - Block Cursor IDE
  app:org.antigravity.app    - Block Antigravity
  smtp.gmail.com:25          - Block Gmail SMTP
```

---

## Alternative: Endpoint Security (Option B)

For completeness, here's what Option B would require:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ENDPOINT SECURITY APPROACH                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Requires:                                                               │
│  ✗ System Extension entitlement (com.apple.developer.endpoint-security) │
│  ✗ Notarization with Apple                                              │
│  ✗ User must approve extension in System Preferences                    │
│  ✗ Separate extension bundle embedded in app                            │
│                                                                          │
│  How it works:                                                           │
│  1. Extension registers for ES_EVENT_TYPE_AUTH_EXEC                     │
│  2. When any process tries to launch, extension is called               │
│  3. Extension checks bundle ID against blocklist                        │
│  4. Returns ES_AUTH_RESULT_DENY to prevent launch                       │
│                                                                          │
│  Code sketch:                                                            │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  es_new_client(&client, ^(es_client_t* c, es_message_t* msg) { │     │
│  │      if (msg->event_type == ES_EVENT_TYPE_AUTH_EXEC) {         │     │
│  │          NSString* path = msg->event.exec.target.path;         │     │
│  │          if ([blockedPaths containsObject:path]) {             │     │
│  │              es_respond_auth_result(c, msg,                    │     │
│  │                  ES_AUTH_RESULT_DENY, false);                  │     │
│  │          } else {                                              │     │
│  │              es_respond_auth_result(c, msg,                    │     │
│  │                  ES_AUTH_RESULT_ALLOW, true);                  │     │
│  │          }                                                     │     │
│  │      }                                                         │     │
│  │  });                                                           │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                                                                          │
│  Recommendation: Start with Option A. Migrate to B if users demand.    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Testing App Blocking

### Manual Test Cases

```bash
# 1. Add Terminal to blocklist
#    Entry: app:com.apple.Terminal

# 2. Start block

# 3. Try to open Terminal
open -a Terminal

# Expected: Terminal opens briefly, then closes
# Log should show: "SelfControl: Blocked app com.apple.Terminal (PID xxx)"

# 4. Check that other apps still work
open -a Safari

# Expected: Safari opens normally
```

### Automated Test

```objc
- (void)testAppBlocker {
    AppBlocker* blocker = [[AppBlocker alloc] init];
    [blocker addBlockedApp:@"com.apple.TextEdit"];

    // Launch TextEdit
    [[NSWorkspace sharedWorkspace]
        launchApplication:@"TextEdit"];

    // Wait for launch
    [NSThread sleepForTimeInterval:0.5];

    // Should find and kill it
    NSArray* killed = [blocker findAndKillBlockedApps];

    XCTAssertEqual(killed.count, 1);
    XCTAssertEqualObjects(
        ((NSRunningApplication*)killed[0]).bundleIdentifier,
        @"com.apple.TextEdit"
    );
}
```

---

## Summary: Files Changed

| File | Status | Description |
|------|--------|-------------|
| `Block Management/AppBlocker.h/m` | ✅ Implemented | Singleton process monitor, libproc-based |
| `Block Management/SCBlockEntry.h/m` | ✅ Implemented | `appBundleID` property, `isAppEntry` method |
| `Block Management/BlockManager.m` | ✅ Implemented | Routes app entries, uses singleton |
| `DomainListWindowController.m` | ✅ Implemented | "Add App" button with app picker |
| `Base.lproj/DomainList.xib` | ✅ Implemented | Add App button in UI |

**Implementation Stats:** ~300 lines of new code in AppBlocker, ~50 lines modifications elsewhere

---

## FAQ

**Q: Why not use launchd to prevent app launch?**
A: launchd can't dynamically block apps based on user-defined rules. It's designed for system services.

**Q: Will this slow down the system?**
A: The 500ms polling is lightweight. `runningApplications` is cached by the system.

**Q: What if the user is in the middle of work when app is killed?**
A: Show a notification before the block starts: "These apps will be blocked: Terminal, Cursor..."

**Q: Can users work around this by renaming apps?**
A: Bundle IDs are embedded in the app. Renaming doesn't change the ID. They'd have to modify the app bundle, which breaks code signing.
