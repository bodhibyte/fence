# Calendar UI Redesign - Agent Handover Document

## Status: Work in Progress
**Branch:** `feature/calendar-ui-redesign`
**Current State:** Builds but UI not responsive/polished

---

## 1. What We're Building

Redesigning the week schedule UI from a **bundles×days grid** to a **calendar-like 7-day view** where users draw "allow blocks" like scheduling meetings in Google Calendar.

### Before (Old UI)
```
┌─────────────────────────────────────────┐
│  Bundle 1  │ Mon │ Tue │ Wed │ ... │    │
│  Bundle 2  │ [x] │ [x] │     │ ... │    │
│  Bundle 3  │     │ [x] │ [x] │ ... │    │
└─────────────────────────────────────────┘
Click a cell → Opens day editor sheet
```

### After (New Calendar UI)
```
┌──────────┬───────────────────────────────────────┐
│ BUNDLES  │  Mon    Tue    Wed    Thu    Fri  ...│
│ ───────  │  6am ─────────────────────────────── │
│ [Work  ] │       ████                           │
│ [Social] │       ████   ████                    │
│          │ 12pm ─────────────────────────────── │
│ + Add    │                                      │
└──────────┴───────────────────────────────────────┘
Click bundle pill → Focus state (edit that bundle)
Click-drag → Create allow block
```

---

## 2. CRITICAL SAFETY CONSTRAINT

### This is a FRONTEND-ONLY change

**The backend/daemon receives IDENTICAL data regardless of UI:**

```
UI Layer (what we're changing):
├── Bundle pills with selection state
├── Calendar view with allow blocks
├── Focus/All-Up state management
└── Drag/click interactions

    ↓ Same data flows down ↓

Data Layer (NO CHANGES):
├── SCScheduleManager.updateSchedule:forWeekOffset:
├── SCWeeklySchedule, SCBlockBundle, SCTimeRange models
└── commitToWeekWithOffset: → XPC → Daemon

Backend (ZERO CHANGES):
├── SCXPCClient methods unchanged
├── Daemon receives same blocklist arrays
└── Same blockSettings dictionary
```

### What Backend Expects (DO NOT CHANGE)
- `blocklist`: `NSArray<NSString*>` of `"facebook.com"` or `"app:com.bundle.id"`
- `blockSettings`: 8-key dictionary
- `scheduleId`: UUID string
- `endDate`: NSDate
- `controllingUID`: uid_t

**Gemini 3 Pro reviewed and confirmed: HIGH CONFIDENCE this is safe.**

---

## 3. UX Design Decisions (Confirmed by User)

### State Model: Focus vs. All-Up
| State | Description |
|-------|-------------|
| **All-Up** (default) | All bundles visible at 100% opacity, side-by-side lanes |
| **Focus** | Click bundle pill → that bundle 100%, others 20% opacity |
| **Exit Focus** | Click pill again OR click empty calendar area |

### Visual Style
- **Full window vibrancy** via `NSVisualEffectView` (already implemented via SCUIUtilities)
- **Bundle pills**: Rounded rect (8pt), colored dot on left, 2pt border when selected
- **Allow blocks**: Rounded rect with bundle color, 100%/20% opacity based on focus

### Interactions
| Action | Result |
|--------|--------|
| Click bundle pill | Enter Focus state |
| Click-drag on calendar | Create new allow block (snaps to 15min) |
| Click existing block | Select it (shows resize handles) |
| Drag block edges | Resize duration |
| Drag block middle | Move to different time |
| Double-click block | Open day editor sheet |
| Delete/Backspace | Delete selected block |
| Cmd+Z | Undo (NOT YET IMPLEMENTED) |

### Removed Features
- **NO single-click block creation** (too sensitive, causes misfires)

---

## 4. Files Created

### New View Files
| File | Purpose | Status |
|------|---------|--------|
| `SCBundleSidebarView.h/m` | LHS bundle pills with selection | Created, needs polish |
| `SCCalendarGridView.h/m` | Main calendar with day columns | Created, needs polish |

### Modified Files
| File | Changes |
|------|---------|
| `SCWeekScheduleWindowController.m` | Added conditional UI (`kUseCalendarUI` flag) |

### Feature Flag
```objc
// In SCWeekScheduleWindowController.m line 21
static BOOL const kUseCalendarUI = YES;  // Set to NO to revert to old UI
```

---

## 5. What's Working

- [x] Bundle sidebar renders pills
- [x] Calendar grid renders day columns
- [x] Allow blocks render in lanes
- [x] Click pill toggles focus state
- [x] Drag to create new blocks (basic)
- [x] NOW line for today
- [x] Committed state disables editing
- [x] Data flows to SCScheduleManager correctly

---

## 6. What Needs Fixing

### High Priority
1. **Layout/responsiveness issues** - Views don't resize properly
2. **Block rendering alignment** - Blocks may not align with lanes correctly
3. **Hit testing** - Click detection may be off
4. **Visual polish** - Colors, spacing, hover states need work

### Medium Priority
5. **Undo/redo** - Cmd+Z not wired up
6. **Copy/paste** - Cmd+C/V not implemented
7. **Animations** - Focus state transition should animate (150ms fade)
8. **Right-click menu** - Context menu not implemented

### Low Priority
9. **Keyboard navigation** - Arrow keys to move selection
10. **Accessibility** - VoiceOver support

---

## 7. Key Code Locations

### Sidebar Selection
```objc
// SCBundleSidebarView.m - pillClicked:
- When user clicks a pill, toggles selection
- Calls delegate: bundleSidebar:didSelectBundle:
```

### Focus State
```objc
// SCWeekScheduleWindowController.m
@property (nonatomic, copy, nullable) NSString *focusedBundleID;

// When sidebar selection changes:
- (void)bundleSidebar:(SCBundleSidebarView *)sidebar didSelectBundle:(nullable SCBlockBundle *)bundle {
    self.focusedBundleID = bundle.bundleID;
    self.calendarGridView.focusedBundleID = self.focusedBundleID;
    [self.calendarGridView reloadData];
}
```

### Block Creation (Drag)
```objc
// SCCalendarGridView.m - SCCalendarDayColumn class
// mouseDown: starts drag
// mouseDragged: updates draggingRange
// mouseUp: applies change via onScheduleUpdated callback
```

### Schedule Updates
```objc
// SCCalendarGridView.m → SCWeekScheduleWindowController
- (void)calendarGrid:(SCCalendarGridView *)grid didUpdateSchedule:(SCWeeklySchedule *)schedule forBundleID:(NSString *)bundleID {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    [manager updateSchedule:schedule forWeekOffset:self.currentWeekOffset];
}
```

---

## 8. Data Models (Reference)

### SCTimeRange
```objc
@property NSString *startTime;  // "HH:mm" format
@property NSString *endTime;
- (NSInteger)startMinutes;  // 0-1439
- (NSInteger)endMinutes;
```

### SCWeeklySchedule
```objc
@property NSString *bundleID;
@property NSMutableDictionary *daySchedules;  // day string → NSArray<SCTimeRange>
- (NSArray<SCTimeRange *> *)allowedWindowsForDay:(SCDayOfWeek)day;
- (void)setAllowedWindows:(NSArray *)windows forDay:(SCDayOfWeek)day;
```

### SCDayOfWeek
```objc
SCDayOfWeekSunday = 0,
SCDayOfWeekMonday = 1,
// ... through Saturday = 6
```

---

## 9. Testing Checklist

Before merging:
- [ ] Create allow blocks via drag
- [ ] Resize blocks via edge handles
- [ ] Move blocks via drag
- [ ] Delete blocks (Delete key)
- [ ] Focus state toggles correctly
- [ ] All-Up shows all bundles at 100%
- [ ] Week navigation works
- [ ] Commit flow unchanged (CRITICAL)
- [ ] Committed state locks editing
- [ ] NOW line updates correctly
- [ ] Works with 1 bundle
- [ ] Works with 5+ bundles
- [ ] Window resize works

---

## 10. Rollback Plan

If issues arise, set the feature flag to NO:
```objc
static BOOL const kUseCalendarUI = NO;
```

This reverts to the old SCWeekGridView UI while keeping all new code in place.

---

## 11. Related Documentation

- `/Users/vishaljain/.claude/plans/purring-spinning-raccoon.md` - Full implementation plan
- `SYSTEM_ARCHITECTURE.md` - System overview
- `docs/BLOCKING_MECHANISM.md` - How blocking works

---

*Last updated: December 2024*
