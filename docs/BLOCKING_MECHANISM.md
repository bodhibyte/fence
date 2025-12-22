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

## Adding App Blocking: Design Proposal

### The Gap

Currently SelfControl blocks **network destinations**. It has no concept of **applications**. A blocked app can still:
- Run and perform local operations
- Use local network (127.0.0.1)
- Interact with user

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    EXTENDED BLOCKING ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   Wall 1: DNS Redirect (/etc/hosts) ............ [EXISTING]             │
│                                                                          │
│   Wall 2: Packet Filter (PF Rules) ............. [EXISTING]             │
│                                                                          │
│   Wall 3: App Blocker (Process Control) ........ [NEW]                  │
│   ┌───────────────────────────────────────────────────────────────┐     │
│   │  OPTION A: Process Monitor + Kill                             │     │
│   │  - Poll running processes every 0.5 seconds                   │     │
│   │  - Match against blocked bundle IDs                           │     │
│   │  - Send SIGKILL to matching processes                         │     │
│   │  Pros: Simple, no kernel/SIP issues                           │     │
│   │  Cons: App briefly opens before being killed                  │     │
│   ├───────────────────────────────────────────────────────────────┤     │
│   │  OPTION B: Endpoint Security Framework                        │     │
│   │  - System Extension intercepts process creation               │     │
│   │  - Block before app window appears                            │     │
│   │  Pros: Clean prevention, no flicker                           │     │
│   │  Cons: Requires notarization, entitlements, user approval     │     │
│   └───────────────────────────────────────────────────────────────┘     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Implementation Option A: Process Monitor (Recommended)

**Why:** Simpler, fits existing architecture, no notarization changes needed

**New Files to Create:**

1. **`Block Management/AppBlocker.h`**
```objc
@interface AppBlocker : NSObject

@property (readonly) NSSet<NSString*>* blockedBundleIDs;

- (void)addBlockedApp:(NSString*)bundleID;
- (void)startMonitoring;
- (void)stopMonitoring;
- (NSArray<NSRunningApplication*>*)findAndKillBlockedApps;

@end
```

2. **`Block Management/AppBlocker.m`**
```objc
@implementation AppBlocker {
    NSMutableSet<NSString*>* _blockedBundleIDs;
    dispatch_source_t _monitorTimer;
}

- (void)startMonitoring {
    // Create timer on daemon queue
    _monitorTimer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    );

    // Fire every 500ms
    dispatch_source_set_timer(_monitorTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        500 * NSEC_PER_MSEC,
        50 * NSEC_PER_MSEC
    );

    dispatch_source_set_event_handler(_monitorTimer, ^{
        [self findAndKillBlockedApps];
    });

    dispatch_resume(_monitorTimer);
}

- (NSArray<NSRunningApplication*>*)findAndKillBlockedApps {
    NSMutableArray* killed = [NSMutableArray array];

    for (NSRunningApplication* app in [[NSWorkspace sharedWorkspace] runningApplications]) {
        if ([_blockedBundleIDs containsObject:app.bundleIdentifier]) {
            [app forceTerminate];
            [killed addObject:app];

            // Log the kill
            NSLog(@"SelfControl: Blocked app %@ (PID %d)",
                  app.bundleIdentifier, app.processIdentifier);
        }
    }

    return killed;
}

@end
```

### Integration Points

**1. SCBlockEntry.m - Add app support:**
```objc
// Add new property
@property (nonatomic, strong) NSString* appBundleID;

// New init method
- (instancetype)initWithAppBundleID:(NSString*)bundleID {
    self = [super init];
    if (self) {
        _appBundleID = bundleID;
        _hostname = nil;  // Not a network block
    }
    return self;
}

// Modify parsing to detect app: prefix
- (instancetype)initWithString:(NSString*)entryString {
    if ([entryString hasPrefix:@"app:"]) {
        return [self initWithAppBundleID:
            [entryString substringFromIndex:4]];
    }
    // ... existing hostname parsing
}
```

**2. BlockManager.m - Handle app entries:**
```objc
// Add AppBlocker instance
@property (nonatomic, strong) AppBlocker* appBlocker;

- (void)prepareToAddBlock {
    // ... existing code
    self.appBlocker = [[AppBlocker alloc] init];
}

- (void)addBlockEntry:(SCBlockEntry*)entry {
    if (entry.appBundleID) {
        [self.appBlocker addBlockedApp:entry.appBundleID];
    } else {
        // ... existing network blocking
    }
}

- (void)finalizeBlock {
    // ... existing code
    [self.appBlocker startMonitoring];
}
```

**3. SCDaemonBlockMethods.m - Add to checkup:**
```objc
- (void)checkupBlock {
    // ... existing checkup code

    // Also check app blocking
    AppBlocker* appBlocker = self.blockManager.appBlocker;
    if (appBlocker) {
        [appBlocker findAndKillBlockedApps];
    }
}
```

**4. SCSettings.m - Store app blocklist:**
```objc
// Add new key
NSString* const kActiveAppBlocklist = @"ActiveAppBlocklist";

// In settings dictionary
- (NSArray<NSString*>*)activeAppBlocklist {
    return [self valueForKey:kActiveAppBlocklist];
}
```

**5. UI Changes - DomainListWindowController.m:**
```objc
// Add segmented control: Websites | Apps
// When Apps selected, show app picker

- (IBAction)addAppToBlocklist:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[UTTypeApplication];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];

    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSBundle* appBundle = [NSBundle bundleWithURL:panel.URL];
            NSString* entry = [NSString stringWithFormat:@"app:%@",
                appBundle.bundleIdentifier];
            [self.blocklist addObject:entry];
            [self.blocklistTableView reloadData];
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

## Summary: Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `Block Management/AppBlocker.m/h` | **NEW** | Process monitor + killer |
| `Block Management/SCBlockEntry.m/h` | Modify | Add `appBundleID` property |
| `Block Management/BlockManager.m` | Modify | Integrate AppBlocker |
| `Daemon/SCDaemonBlockMethods.m` | Modify | Add app check to checkup |
| `Common/SCSettings.m` | Modify | Add `ActiveAppBlocklist` |
| `DomainListWindowController.m` | Modify | Add app picker UI |
| `DomainListWindowController.xib` | Modify | Add segmented control |

**Estimated Complexity:** ~500 lines of new code, ~100 lines of modifications

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
