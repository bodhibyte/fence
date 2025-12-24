# Warmstart: Weekly Commitment UX Implementation

## Session Summary

This session implemented a **new UX for weekly schedule-based blocking** - allowing users to create bundles of apps/websites and set weekly schedules with allowed time windows. This is **UX-only** - no daemon/blocking logic was modified.

## User Requirements

- Week-long commitment (sweet spot for self-employed/PhD users)
- Multiple bundles (Work Apps, Distracting Sites, Gaming) with different schedules
- ALLOW-based model (specify when things ARE allowed, blocked by default)
- Day-level + time window controls (e.g., work apps allowed 9am-9pm on weekdays)
- Copy/template system for quick setup
- Menu bar status indicator
- "Only stricter" rule when committed (can add blocks, can't loosen)
- No escape hatch (hardcore mode)

## New Files Created

### Data Models (`Block Management/`)

| File | Purpose |
|------|---------|
| `SCTimeRange.h/m` | Time window model (e.g., "09:00" to "17:00"). Includes presets like `workHours`, `wakingHours`. |
| `SCBlockBundle.h/m` | Bundle model with `bundleID`, `name`, `color`, `entries[]`. Entries are domains or `app:com.bundle.id`. |
| `SCWeeklySchedule.h/m` | Weekly schedule for one bundle. Dict of day → array of SCTimeRange. Methods like `isAllowedNow`. |
| `SCScheduleManager.h/m` | **App-layer storage** using NSUserDefaults. Manages bundles, schedules, templates, commitment. Does NOT touch daemon/SCSettings. |

### UI Components (root directory)

| File | Purpose |
|------|---------|
| `SCWeekGridView.h/m` | Custom NSView showing week grid (bundles as rows, days as columns). Each cell shows mini 24h timeline. Click cell → opens day editor. |
| `SCDayScheduleEditorController.h/m` | Sheet for editing one day's schedule. Visual 24h timeline with drag-to-create allowed windows. Presets dropdown, copy from/apply to. |
| `SCBundleEditorController.h/m` | Sheet for creating/editing bundles. Name, color picker, add apps (NSOpenPanel) or websites. |
| `SCMenuBarController.h/m` | NSStatusItem showing current blocking status. Green/red/gray dot. Shows bundle statuses and commitment info. |
| `SCWeekScheduleWindowController.h/m` | Main window controller. Shows status bar, week grid, buttons for add bundle/save template/commit. |

## Files Modified

### `AppController.h`
- Added forward declaration: `@class SCWeekScheduleWindowController;`
- Added method: `- (IBAction)showWeekSchedule:(id)sender;`

### `AppController.m`
- Added import: `#import "SCWeekScheduleWindowController.h"`
- Added property: `@property (nonatomic, strong) SCWeekScheduleWindowController* weekScheduleWindowController;`
- Added `showWeekSchedule:` method implementation
- Added menu item in `setupDebugMenu`: "Week Schedule (New UX)..." with `Cmd+Option+W`

## How to Access New UX

1. Build in DEBUG mode
2. Menu: `Debug > Week Schedule (New UX)...` or `Cmd+Option+W`

## Build Errors to Fix

The new files need to be added to the Xcode project. Common issues:

1. **Files not in Xcode project** - Drag new .h/.m files into Xcode project navigator
2. **Missing framework** - `UniformTypeIdentifiers.framework` needed for `UTType` in SCBundleEditorController
3. **Header search paths** - May need to add `Block Management/` to header search paths

### Files to add to Xcode project:

```
Block Management/SCTimeRange.h
Block Management/SCTimeRange.m
Block Management/SCBlockBundle.h
Block Management/SCBlockBundle.m
Block Management/SCWeeklySchedule.h
Block Management/SCWeeklySchedule.m
Block Management/SCScheduleManager.h
Block Management/SCScheduleManager.m
SCWeekGridView.h
SCWeekGridView.m
SCDayScheduleEditorController.h
SCDayScheduleEditorController.m
SCBundleEditorController.h
SCBundleEditorController.m
SCMenuBarController.h
SCMenuBarController.m
SCWeekScheduleWindowController.h
SCWeekScheduleWindowController.m
```

## Architecture Notes

- **UX-only implementation** - Does NOT connect to daemon blocking
- All schedule data stored in `NSUserDefaults` via `SCScheduleManager`
- Existing blocking (`SCSettings`, `BlockManager`, daemon) is untouched
- Debug mode (`Debug > Disable All Blocking`) still works for real blocking
- Menu bar controller starts automatically when week schedule window opens

## Key Design Decisions

1. **ALLOW-based model** - Bundles are blocked 24/7 by default. User adds "allowed windows".
2. **Bundle-first hierarchy** - Rows are bundles, columns are days
3. **15-minute snap** - Time picker snaps to 15-min increments
4. **Only stricter when committed** - Can reduce allowed time, can't expand it
5. **Today-forward view** - Only shows remaining days in week when opened mid-week

## Plan File

Full design plan with mockups: `.claude/plans/splendid-wibbling-creek.md`
