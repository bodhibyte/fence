# Entry

<!-- KEYWORDS: entry, domain, website, app, bundle ID, blocklist, SCBlockEntry -->

**Also known as:** Blocklist Entry, Blocked Item

---

## Brief Definition

A single blocked item - either a website domain or an app bundle identifier.

---

## Detailed Definition

An Entry is one item in a [Bundle](bundle.md)'s blocklist. There are two types:

| Type | Format | Example |
|------|--------|---------|
| Website | `domain.com` | `facebook.com`, `reddit.com` |
| App | `app:com.bundle.id` | `app:com.apple.Terminal`, `app:com.cursor.Cursor` |

Entries are stored as strings in a bundle's `entries` array. The `SCBlockEntry` class parses entries and provides helper methods.

---

## Context/Trigger

- Added via Bundle Editor or domain list UI
- Apps added via file picker (selecting .app file)
- Combined into [Merged Blocklist](merged-blocklist.md) at commit time

---

## Code Locations

| File | Purpose |
|------|---------|
| `Block Management/SCBlockEntry.h` | Entry parsing and helpers |
| `Block Management/SCBlockEntry.m` | Implementation |
| `DomainListWindowController.m` | UI for adding entries |

---

## Data Model

```objc
@interface SCBlockEntry : NSObject
@property (nonatomic, copy, readonly) NSString *rawEntry;
@property (nonatomic, copy, readonly, nullable) NSString *appBundleID;  // nil for websites
@property (nonatomic, readonly) BOOL isAppEntry;

+ (instancetype)entryWithString:(NSString *)string;
@end
```

---

## Parsing Logic

```objc
// Website entry
SCBlockEntry *web = [SCBlockEntry entryWithString:@"facebook.com"];
web.isAppEntry  // NO
web.rawEntry    // "facebook.com"
web.appBundleID // nil

// App entry
SCBlockEntry *app = [SCBlockEntry entryWithString:@"app:com.apple.Terminal"];
app.isAppEntry  // YES
app.rawEntry    // "app:com.apple.Terminal"
app.appBundleID // "com.apple.Terminal"
```

---

## Related Terms

- [Bundle](bundle.md) - Contains entries
- [Merged Blocklist](merged-blocklist.md) - Combined entries from active bundles

---

## Anti-definitions (What this is NOT)

- **NOT** a time range - entries are what gets blocked, not when
- **NOT** the same as a [Bundle](bundle.md) - entries are items INSIDE a bundle
- **NOT** a blocking rule - entries are just identifiers; blocking logic is elsewhere

---

## Blocking Mechanism

| Entry Type | How Blocked |
|------------|-------------|
| Website | `/etc/hosts` redirect + PF firewall rules |
| App | Process polling every 500ms, killed if running |

---

## UI Display

```
┌─────────────────────────────────────────┐
│ Entries:                                │
│   🌐 facebook.com                       │  ← Website (blue icon)
│   🌐 twitter.com                        │
│   📱 Terminal (com.apple.Terminal)      │  ← App (purple icon)
│   📱 Cursor (com.cursor.Cursor)         │
└─────────────────────────────────────────┘
```
