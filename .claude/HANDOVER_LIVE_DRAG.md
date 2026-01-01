# Handover: Live Drag & Click-to-Select Bug

## Current State

**What works:**
- Live drag/resize of blocks in calendar grid (move, stretch, shrink)
- Selection clears when clicking on different day
- ESC key handling

**What's broken:**
- Single-click to select a block doesn't work
- User clicks a block, selection appears briefly, then disappears on mouseUp
- This prevents using Delete key to remove blocks (need selection first)

---

## Recent Commit Context

**Commit:** `WIP: Live drag with tracking loop - click-to-select still broken`

### Why we added the tracking loop

The `SCCalendarDayColumn` views are inside an `NSScrollView`. When dragging, the scroll view was intercepting mouse events - only ONE `mouseDragged:` event was reaching the day column, then silence.

**Fix:** Added a modal tracking loop in `mouseDown:` that explicitly captures all mouse events until `mouseUp`:

```objc
// SCCalendarGridView.m, inside SCCalendarDayColumn.mouseDown:, line ~386
while (YES) {
    @autoreleasepool {
        NSEvent *nextEvent = [self.window nextEventMatchingMask:...];
        // ... process drag/up events
    }
}
```

### What we tried to fix click-to-select

1. **Track `didActuallyDrag`** - Only call `mouseUp:` if mouse moved past threshold
2. **Reset drag state manually** - If no drag, reset flags without calling `mouseUp:`
3. **Hysteresis threshold** - Ignore movements < `kDragThreshold` (5px)

**But it still doesn't work.** Selection disappears on click release.

---

## Where to Add Debug Logs

### 1. Inside the tracking loop (SCCalendarGridView.m:390-425)

```objc
// After line 398 (mouseUp received)
NSLog(@"[DEBUG] Tracking loop: mouseUp received, didActuallyDrag=%d", didActuallyDrag);

// After line 418 (threshold check)
NSLog(@"[DEBUG] Tracking loop: drag distance=%.1f, threshold=%.1f, didActuallyDrag=%d",
      distance, kDragThreshold, didActuallyDrag);
```

### 2. In reloadBlocks (SCCalendarGridView.m:~230)

Check if selection state is being preserved:
```objc
NSLog(@"[DEBUG] reloadBlocks: selectedBlockIndex=%ld selectedBundleID=%@",
      (long)self.selectedBlockIndex, self.selectedBundleID);
```

### 3. In onBlockSelected callback (SCCalendarGridView.m:~840)

This clears ALL selections - might be called unexpectedly:
```objc
column.onBlockSelected = ^{
    NSLog(@"[DEBUG] onBlockSelected callback fired - clearing all selections");
    for (SCCalendarDayColumn *col in weakSelf.dayColumns) {
        [col clearSelection];
    }
};
```

---

## Key Files & Functions

| File | Function | Purpose |
|------|----------|---------|
| `SCCalendarGridView.m` | `SCCalendarDayColumn.mouseDown:` (line ~315) | Block click handling, tracking loop |
| `SCCalendarGridView.m` | `SCCalendarDayColumn.mouseUp:` (line ~530) | Applies drag changes, resets state |
| `SCCalendarGridView.m` | `SCCalendarDayColumn.reloadBlocks` (line ~206) | Renders blocks, applies selection highlight |
| `SCCalendarGridView.m` | `onBlockSelected` callback (line ~840) | Clears selections across all columns |
| `SCCalendarGridView.m` | `onScheduleUpdated` callback (line ~800) | Called after drag, triggers data reload |

---

## Hypothesis: What Might Be Wrong

1. **`onBlockSelected` is clearing selection at wrong time**
   - In mouseDown, we call `onBlockSelected()` BEFORE setting selection
   - But this clears the current column's selection too
   - Then we set selection again... but something might be undoing it

2. **Schedule update triggering unwanted reload**
   - Even without drag, something might call `onScheduleUpdated`
   - This triggers `handleScheduleUpdate` → `reloadData` → clears state?

3. **Tracking loop state reset not complete**
   - We reset `isDragging`, `isMovingBlock`, etc.
   - But maybe we're also resetting `selectedBlockIndex` somewhere?

---

## Test Procedure

1. Add logs to locations above
2. Run app, single-click a block
3. Check Console.app for `[DEBUG]` logs
4. Look for:
   - Is `onBlockSelected` callback firing multiple times?
   - What is `selectedBlockIndex` before/after reloadBlocks?
   - Is `onScheduleUpdated` being called even without drag?

---

## Selection State Variables

In `SCCalendarDayColumn`:
- `selectedBlockIndex` - Index of selected block (-1 if none)
- `selectedBundleID` - Bundle ID of selected block (nil if none)

In drag state:
- `isDragging` - Currently in drag operation
- `isMovingBlock` / `isResizingTop` / `isResizingBottom` - Drag mode
- `draggingRange` - Current drag position
- `draggingBundleID` - Bundle being dragged

**Selection should persist independently of drag state.**
