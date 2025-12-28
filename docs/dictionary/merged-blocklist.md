# Merged Blocklist

<!-- KEYWORDS: merged, blocklist, combine, entries, deduplicate, segment, union -->

**Also known as:** Combined Blocklist, Unified Blocklist

---

## Brief Definition

The combined, deduplicated list of entries from all active bundles in a segment.

---

## Detailed Definition

When multiple bundles are active in a [Segment](segment.md), their entries (websites and apps) are merged into a single blocklist. This merged blocklist is what actually gets blocked during that time period.

**Example:**
```
Segment 10:00-12:00, Active Bundles: [A, B]

Bundle A entries: facebook.com, twitter.com
Bundle B entries: twitter.com, reddit.com, app:com.apple.Terminal

Merged Blocklist: facebook.com, twitter.com, reddit.com, app:com.apple.Terminal
                  (twitter.com deduplicated)
```

---

## Context/Trigger

- Created at commit time for each Segment
- Written to disk as `.selfcontrol` file in schedules directory
- Referenced by segment ID when launchd triggers the block

---

## Code Locations

| File | Purpose |
|------|---------|
| `Block Management/SCScheduleLaunchdBridge.m` | `writeMergedBlocklistForBundles:segmentID:error:` |
| `Block Management/SCScheduleLaunchdBridge.m` | Merge logic in `installJobForSegmentWithBundles:` |

---

## Storage Format

```
~/Library/Application Support/SelfControl/Schedules/{segmentID}.selfcontrol

Contents (plist):
{
    "Blocklist": ["facebook.com", "twitter.com", "app:com.bundle.id"],
    "BlockAsWhitelist": false
}
```

---

## Call Stack

```mermaid
graph TD
    A[Segment created with activeBundles] --> B[writeMergedBlocklistForBundles:segmentID:error:]
    B --> C[Create NSMutableOrderedSet for deduplication]
    C --> D[For each bundle in activeBundles]
    D --> E[Add bundle.entries to set]
    E --> F[Write to {segmentID}.selfcontrol file]
    F --> G[Return file URL]

    subgraph "At Execution Time"
        H[launchd triggers with --schedule-id] --> I[Daemon reads registered schedule]
        I --> J[Apply merged blocklist]
    end

    style A fill:#e1f5fe
    style J fill:#c8e6c9
```

---

## Related Terms

- [Segment](segment.md) - Each segment has one merged blocklist
- [Entry](entry.md) - Individual items in the blocklist
- [Bundle](bundle.md) - Source of entries to merge
- [Pre-Authorized Schedule](pre-authorized-schedule.md) - Contains the merged blocklist

---

## Anti-definitions (What this is NOT)

- **NOT** a single bundle's entries - combines multiple bundles
- **NOT** created by the user - computed from segment's active bundles
- **NOT** stored in user preferences - stored in Schedules directory as separate file

---

## Code Example

```objc
- (NSURL *)writeMergedBlocklistForBundles:(NSArray<SCBlockBundle *> *)bundles
                                segmentID:(NSString *)segmentID
                                    error:(NSError **)error {
    // Merge all entries from all bundles, deduplicating
    NSMutableOrderedSet *mergedEntries = [NSMutableOrderedSet orderedSet];
    for (SCBlockBundle *bundle in bundles) {
        [mergedEntries addObjectsFromArray:bundle.entries];
    }

    // Write to file
    NSURL *fileURL = [[SCScheduleLaunchdBridge schedulesDirectory]
                      URLByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.selfcontrol", segmentID]];

    NSDictionary *blockInfo = @{
        @"Blocklist": mergedEntries.array,
        @"BlockAsWhitelist": @NO
    };

    // ... write to disk
}
```
