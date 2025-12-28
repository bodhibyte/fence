# Bundle

<!-- KEYWORDS: bundle, group, collection, websites, apps, SCBlockBundle, color, name -->

**Also known as:** Block Bundle, Entry Group

---

## Brief Definition

A named group of websites and apps with a color for visual identification.

---

## Detailed Definition

A Bundle (`SCBlockBundle`) is a user-created collection of items to block together. Each bundle has:

- **Name** - User-friendly label (e.g., "Social Media", "Work Distractions")
- **Color** - Visual identification in the week grid
- **Entries** - Array of websites and apps to block
- **Enabled** - Whether the bundle participates in scheduled blocking
- **Bundle ID** - UUID for internal reference

Bundles are the organizational unit for blocking. Users create bundles, add entries to them, and define schedules (Allowed Windows) per bundle per day.

---

## Context/Trigger

- Created via "Add Bundle" in week schedule window
- Edited via `SCBundleEditorController`
- Each bundle has its own schedule (`SCWeeklySchedule`)
- Multiple bundles can be active in the same [Segment](segment.md)

---

## Code Locations

| File | Purpose |
|------|---------|
| `Block Management/SCBlockBundle.h` | Data model |
| `Block Management/SCBlockBundle.m` | Implementation |
| `SCBundleEditorController.h/m` | UI for editing bundles |
| `Block Management/SCScheduleManager.m` | Stores/retrieves bundles |

---

## Data Model

```objc
@interface SCBlockBundle : NSObject <NSCopying, NSSecureCoding>
@property (nonatomic, copy) NSString *bundleID;      // UUID
@property (nonatomic, copy) NSString *name;          // "Social Media"
@property (nonatomic, strong) NSColor *color;        // Visual identifier
@property (nonatomic, strong) NSMutableArray *entries; // ["facebook.com", "app:com.twitter"]
@property (nonatomic, assign) BOOL enabled;          // Participates in blocking?
@end
```

---

## Persistence

```
NSUserDefaults key: "SCScheduleBundles"

[
    {
        "bundleID": "ABC-123-...",
        "name": "Social Media",
        "color": <archived NSColor>,
        "entries": ["facebook.com", "twitter.com"],
        "enabled": true
    },
    ...
]
```

---

## Related Terms

- [Entry](entry.md) - Individual items within a bundle
- [Allowed Window](allowed-window.md) - Schedules are defined per bundle per day
- [Segment](segment.md) - Contains list of active bundles
- [Merged Blocklist](merged-blocklist.md) - Combines entries from multiple bundles

---

## Anti-definitions (What this is NOT)

- **NOT** a macOS app bundle (like `com.apple.Safari`) - that's an [Entry](entry.md)
- **NOT** a time range - bundles contain entries, not schedules
- **NOT** automatically created - user must create and name bundles

---

## Visual Example

```
┌─────────────────────────────────────────────────┐
│ Bundle: "Social Media"  [🟣 Purple]             │
│                                                 │
│ Entries:                                        │
│   • facebook.com                                │
│   • twitter.com                                 │
│   • instagram.com                               │
│   • app:com.tiktok.TikTok                      │
│                                                 │
│ Schedule for Monday:                            │
│   Allowed: 12:00-13:00, 18:00-20:00            │
│   (Blocked rest of day)                         │
└─────────────────────────────────────────────────┘
```
