//
//  SCCalendarGridView.m
//  SelfControl
//

#import "SCCalendarGridView.h"
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCTimeRange.h"

// Layout constants
static const CGFloat kDayHeaderHeight = 40.0;
static const CGFloat kHourLabelWidth = 50.0;
static const CGFloat kTimelineTopPadding = 10.0;
static const CGFloat kSnapMinutes = 15.0;  // Snap to 15-min grid
static const CGFloat kMinBlockDuration = 30.0;  // Minimum 30 min block
static const CGFloat kEdgeDetectionZone = 8.0;  // Pixels for resize detection
static const CGFloat kLanePadding = 2.0;
static const CGFloat kDragThreshold = 5.0;  // Pixels to move before starting drag-to-create

// Opacity for non-focused bundles
static const CGFloat kDimmedOpacity = 0.2;

#pragma mark - SCAllowBlockView (Private)

@interface SCAllowBlockView : NSView

@property (nonatomic, strong) SCTimeRange *timeRange;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, copy) NSString *bundleID;  // Track which bundle owns this block
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) BOOL isDimmed;
@property (nonatomic, assign) BOOL isCommitted;

@end

@implementation SCAllowBlockView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
    }
    return self;
}

- (void)updateLayer {
    [super updateLayer];
    [self updateAppearance];
}

- (void)updateAppearance {
    // Semi-transparent background + border (slightly more solid than status pills)
    CGFloat bgAlpha = 0.4;
    CGFloat borderAlpha = 0.6;

    if (self.isDimmed) {
        bgAlpha = 0.15;
        borderAlpha = 0.3;
    } else if (self.isSelected && !self.isCommitted) {
        bgAlpha = 0.55;
        borderAlpha = 0.85;
    }

    self.layer.backgroundColor = [self.color colorWithAlphaComponent:bgAlpha].CGColor;
    self.layer.borderColor = [self.color colorWithAlphaComponent:borderAlpha].CGColor;
    self.layer.borderWidth = self.isSelected ? 2.0 : 1.0;
}

- (void)setColor:(NSColor *)color {
    _color = color;
    [self updateAppearance];
}

- (void)setIsSelected:(BOOL)isSelected {
    _isSelected = isSelected;
    [self updateAppearance];
}

- (void)setIsDimmed:(BOOL)isDimmed {
    _isDimmed = isDimmed;
    [self updateAppearance];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Time label if block is tall enough (2 lines with dash)
    if (self.bounds.size.height > 30 && self.timeRange) {
        NSColor *textColor = self.isDimmed ?
            [[NSColor labelColor] colorWithAlphaComponent:0.3] :
            [NSColor labelColor];

        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: textColor
        };

        // Format: "2:00am -" on line 1, "10:00pm" on line 2
        NSString *startTime = [NSString stringWithFormat:@"%@ -",
            [self.timeRange format12Hour:self.timeRange.startTime]];
        NSString *endTime = [self.timeRange format12Hour:self.timeRange.endTime];

        CGFloat lineHeight = 14;
        CGFloat textY = self.bounds.size.height - lineHeight - 4;

        [startTime drawAtPoint:NSMakePoint(6, textY) withAttributes:attrs];
        [endTime drawAtPoint:NSMakePoint(6, textY - lineHeight) withAttributes:attrs];
    }
}

@end

#pragma mark - SCCalendarDayColumn (Private)

@interface SCCalendarDayColumn : NSView

@property (nonatomic, assign) SCDayOfWeek day;
@property (nonatomic, copy) NSArray<SCBlockBundle *> *bundles;
@property (nonatomic, copy) NSDictionary<NSString *, SCWeeklySchedule *> *schedules;
@property (nonatomic, copy, nullable) NSString *focusedBundleID;
@property (nonatomic, assign) BOOL isCommitted;
@property (nonatomic, assign) BOOL isToday;
@property (nonatomic, assign) CGFloat timelineHeight;  // Height for 24 hours

// Drag state
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) BOOL isCreatingBlock;
@property (nonatomic, assign) BOOL isResizingTop;
@property (nonatomic, assign) BOOL isResizingBottom;
@property (nonatomic, assign) BOOL isMovingBlock;
@property (nonatomic, assign) BOOL hasPendingEmptyAreaClick;  // Waiting for drag threshold
@property (nonatomic, assign) CGFloat dragStartY;
@property (nonatomic, assign) NSInteger dragStartMinutes;
@property (nonatomic, assign) NSPoint mouseDownPoint;  // For drag threshold detection
@property (nonatomic, strong, nullable) SCTimeRange *draggingRange;
@property (nonatomic, strong, nullable) SCTimeRange *originalDragRange;
@property (nonatomic, copy, nullable) NSString *draggingBundleID;

// Selected block
@property (nonatomic, assign) NSInteger selectedBlockIndex;
@property (nonatomic, copy, nullable) NSString *selectedBundleID;

// Callbacks
@property (nonatomic, copy, nullable) void (^onScheduleUpdated)(NSString *bundleID, SCWeeklySchedule *schedule);
@property (nonatomic, copy, nullable) void (^onEmptyAreaClicked)(void);
@property (nonatomic, copy, nullable) void (^onBlockDoubleClicked)(SCBlockBundle *bundle);
@property (nonatomic, copy, nullable) void (^onNoFocusInteraction)(void);  // Warning when interacting without bundle focus
@property (nonatomic, copy, nullable) void (^onColumnClicked)(void);  // Any click in the column
@property (nonatomic, copy, nullable) void (^onBlockSelected)(void);  // Block was selected (for clearing other selections)

- (void)reloadBlocks;
- (void)clearSelection;
- (CGFloat)yFromMinutes:(NSInteger)minutes;
- (NSInteger)minutesFromY:(CGFloat)y;

@end

@implementation SCCalendarDayColumn {
    NSMutableArray<SCAllowBlockView *> *_blockViews;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _blockViews = [NSMutableArray array];
        _selectedBlockIndex = -1;
        _timelineHeight = frame.size.height;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (BOOL)isFlipped {
    return YES;  // Origin at top = midnight
}

- (CGFloat)yFromMinutes:(NSInteger)minutes {
    // Map 0-1440 minutes to 0-timelineHeight
    return (minutes / 1440.0) * self.timelineHeight;
}

- (NSInteger)minutesFromY:(CGFloat)y {
    // Map y position to minutes (0-1440)
    NSInteger minutes = (NSInteger)((y / self.timelineHeight) * 1440);
    return MAX(0, MIN(1439, minutes));
}

- (NSInteger)snapToGrid:(NSInteger)minutes {
    return (NSInteger)(round(minutes / kSnapMinutes) * kSnapMinutes);
}

- (void)reloadBlocks {
    // Remove old block views
    for (SCAllowBlockView *block in _blockViews) {
        [block removeFromSuperview];
    }
    [_blockViews removeAllObjects];

    if (self.bundles.count == 0) return;

    // Calculate lane width for each bundle
    CGFloat totalWidth = self.bounds.size.width;
    CGFloat laneWidth = (totalWidth - kLanePadding * 2) / self.bundles.count;

    NSInteger laneIndex = 0;
    for (SCBlockBundle *bundle in self.bundles) {
        SCWeeklySchedule *schedule = self.schedules[bundle.bundleID];
        if (!schedule) continue;

        NSArray<SCTimeRange *> *windows = [schedule allowedWindowsForDay:self.day];
        CGFloat laneX = kLanePadding + laneIndex * laneWidth;

        for (NSInteger i = 0; i < (NSInteger)windows.count; i++) {
            SCTimeRange *range = windows[i];

            // Use draggingRange for the block being dragged (live preview)
            BOOL shouldUseDragRange = self.isDragging &&
                [bundle.bundleID isEqualToString:self.draggingBundleID] &&
                i == self.selectedBlockIndex &&
                self.draggingRange != nil;

            if (shouldUseDragRange) {
                NSLog(@"[DRAG] reloadBlocks: USING draggingRange for bundle=%@ idx=%ld", bundle.bundleID, (long)i);
                range = self.draggingRange;
            } else if (self.isDragging) {
                NSLog(@"[DRAG] reloadBlocks: NOT using draggingRange - bundle=%@ (want %@) idx=%ld (want %ld) hasRange=%d",
                      bundle.bundleID, self.draggingBundleID, (long)i, (long)self.selectedBlockIndex, self.draggingRange != nil);
            }

            CGFloat y = [self yFromMinutes:[range startMinutes]];
            CGFloat height = [self yFromMinutes:[range endMinutes]] - y;

            NSRect blockFrame = NSMakeRect(laneX, y, laneWidth - kLanePadding, height);
            SCAllowBlockView *blockView = [[SCAllowBlockView alloc] initWithFrame:blockFrame];
            blockView.timeRange = range;
            blockView.color = bundle.color;
            blockView.bundleID = bundle.bundleID;  // Track which bundle owns this block
            blockView.isCommitted = self.isCommitted;

            // Dimmed if not focused bundle (and we have a focused bundle)
            if (self.focusedBundleID && ![bundle.bundleID isEqualToString:self.focusedBundleID]) {
                blockView.isDimmed = YES;
            }

            // Selected state
            if ([bundle.bundleID isEqualToString:self.selectedBundleID] && i == self.selectedBlockIndex) {
                blockView.isSelected = YES;
            }

            [self addSubview:blockView];
            [_blockViews addObject:blockView];
        }

        laneIndex++;
    }

    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Background - use bounds, not dirtyRect (dirtyRect can have negative origin in scroll views)
    [[NSColor colorWithWhite:0.15 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    // Hour lines
    [[NSColor colorWithWhite:0.25 alpha:1.0] setStroke];
    for (NSInteger hour = 0; hour <= 24; hour++) {
        CGFloat y = [self yFromMinutes:hour * 60];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(0, y)];
        [line lineToPoint:NSMakePoint(self.bounds.size.width, y)];
        line.lineWidth = (hour % 6 == 0) ? 1.0 : 0.5;  // Thicker lines at 6am, 12pm, 6pm
        [line stroke];
    }

    // Right edge separator line (day column divider)
    [[NSColor colorWithWhite:0.3 alpha:1.0] setStroke];
    NSBezierPath *separator = [NSBezierPath bezierPath];
    [separator moveToPoint:NSMakePoint(self.bounds.size.width - 0.5, 0)];
    [separator lineToPoint:NSMakePoint(self.bounds.size.width - 0.5, self.bounds.size.height)];
    separator.lineWidth = 1.0;
    [separator stroke];

    // NOW line (if today)
    if (self.isToday) {
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
        NSInteger nowMinutes = components.hour * 60 + components.minute;
        CGFloat nowY = [self yFromMinutes:nowMinutes];

        [[NSColor systemRedColor] setStroke];
        NSBezierPath *nowLine = [NSBezierPath bezierPath];
        [nowLine moveToPoint:NSMakePoint(0, nowY)];
        [nowLine lineToPoint:NSMakePoint(self.bounds.size.width, nowY)];
        nowLine.lineWidth = 2.0;
        CGFloat pattern[] = {4, 2};
        [nowLine setLineDash:pattern count:2 phase:0];
        [nowLine stroke];
    }
}

- (void)clearSelection {
    self.selectedBlockIndex = -1;
    self.selectedBundleID = nil;
    [self reloadBlocks];
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    // Notify that this column was clicked (for tracking last clicked day)
    if (self.onColumnClicked) {
        self.onColumnClicked();
    }

    if (self.isCommitted) return;

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    // FIRST: Check if clicking on an existing block (allow even in All-Up/no focus state)
    for (SCAllowBlockView *blockView in _blockViews) {
        if (NSPointInRect(loc, blockView.frame)) {
            // Get the bundle this block belongs to
            NSString *blockBundleID = blockView.bundleID;
            if (!blockBundleID) continue;

            if (event.clickCount == 2) {
                // Double-click: open editor for THIS block's bundle
                SCBlockBundle *bundle = [self bundleForID:blockBundleID];
                if (bundle && self.onBlockDoubleClicked) {
                    self.onBlockDoubleClicked(bundle);
                }
                return;
            }

            // Single click on block - clear all other selections first, then select this one
            if (self.onBlockSelected) {
                self.onBlockSelected();  // Parent will clear ALL selections
            }
            self.selectedBundleID = blockBundleID;

            // Find index in this bundle's schedule
            SCWeeklySchedule *schedule = self.schedules[blockBundleID];
            NSArray *windows = [schedule allowedWindowsForDay:self.day];
            self.selectedBlockIndex = [windows indexOfObject:blockView.timeRange];

            // Check if near top or bottom edge for resize
            CGFloat relY = loc.y - blockView.frame.origin.y;
            if (relY < kEdgeDetectionZone) {
                self.isResizingTop = YES;
            } else if (relY > blockView.frame.size.height - kEdgeDetectionZone) {
                self.isResizingBottom = YES;
            } else {
                self.isMovingBlock = YES;
            }

            self.isDragging = YES;
            self.draggingBundleID = blockBundleID;
            self.draggingRange = [blockView.timeRange copy];
            self.originalDragRange = [blockView.timeRange copy];
            self.dragStartY = loc.y;
            self.dragStartMinutes = [self minutesFromY:loc.y];

            NSLog(@"[DRAG] mouseDown on block: isDragging=%d isMoving=%d isResizeTop=%d isResizeBot=%d bundleID=%@ selIdx=%ld",
                  self.isDragging, self.isMovingBlock, self.isResizingTop, self.isResizingBottom,
                  self.draggingBundleID, (long)self.selectedBlockIndex);

            [self reloadBlocks];

            // Tracking loop - captures all drag events, prevents NSScrollView from stealing them
            BOOL didActuallyDrag = NO;
            NSPoint startPoint = loc;

            while (YES) {
                @autoreleasepool {
                    NSEvent *nextEvent = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                                                  untilDate:[NSDate distantFuture]
                                                                     inMode:NSEventTrackingRunLoopMode
                                                                    dequeue:YES];
                    if (!nextEvent) continue;

                    if (nextEvent.type == NSEventTypeLeftMouseUp) {
                        if (didActuallyDrag) {
                            // Real drag - apply changes
                            [self mouseUp:nextEvent];
                        } else {
                            // Simple click - just reset drag state, keep selection
                            self.isDragging = NO;
                            self.isMovingBlock = NO;
                            self.isResizingTop = NO;
                            self.isResizingBottom = NO;
                            self.draggingRange = nil;
                            self.originalDragRange = nil;
                            self.draggingBundleID = nil;
                        }
                        break;
                    } else if (nextEvent.type == NSEventTypeLeftMouseDragged) {
                        // Hysteresis check - ignore jitters
                        NSPoint currentPoint = [self convertPoint:nextEvent.locationInWindow fromView:nil];
                        CGFloat distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y);

                        if (distance > kDragThreshold) {
                            didActuallyDrag = YES;
                            [self mouseDragged:nextEvent];
                        }
                    }
                }
            }
            return;
        }
    }

    // SECOND: Clicking on empty area - requires bundle focus to create blocks
    if (!self.focusedBundleID) {
        // No bundle focused - show warning
        if (self.onNoFocusInteraction) {
            self.onNoFocusInteraction();
        }
        // Make grid view first responder so ESC still works
        [self.window makeFirstResponder:self.superview];
        return;
    }

    // Empty area click with focus - record position for potential drag-to-create
    // (Don't create block yet - wait for drag threshold)
    // Clear selection in other columns when clicking empty area
    if (self.onBlockSelected) {
        self.onBlockSelected();
    }
    self.hasPendingEmptyAreaClick = YES;
    self.mouseDownPoint = loc;
    self.dragStartY = loc.y;
    self.dragStartMinutes = [self snapToGrid:[self minutesFromY:loc.y]];
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.isCommitted) return;

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    NSLog(@"[DRAG] mouseDragged: isDragging=%d isMoving=%d isResizeTop=%d isResizeBot=%d isCreating=%d",
          self.isDragging, self.isMovingBlock, self.isResizingTop, self.isResizingBottom, self.isCreatingBlock);

    // Check if we should start drag-to-create from a pending empty area click
    if (self.hasPendingEmptyAreaClick && !self.isDragging) {
        // Check if mouse has moved past threshold
        CGFloat dx = loc.x - self.mouseDownPoint.x;
        CGFloat dy = loc.y - self.mouseDownPoint.y;
        CGFloat distance = sqrt(dx * dx + dy * dy);

        if (distance >= kDragThreshold) {
            // Start creating new block via drag
            self.hasPendingEmptyAreaClick = NO;
            self.isCreatingBlock = YES;
            self.isDragging = YES;
            self.draggingBundleID = self.focusedBundleID;
            self.draggingRange = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:self.dragStartMinutes]
                                                         end:[self timeStringFromMinutes:self.dragStartMinutes + 60]];
        } else {
            return;  // Not yet past threshold
        }
    }

    if (!self.isDragging) return;

    NSInteger currentMinutes = [self snapToGrid:[self minutesFromY:loc.y]];

    if (self.isCreatingBlock) {
        // Creating new block - adjust end time
        NSInteger start = self.dragStartMinutes;
        NSInteger end = currentMinutes;
        if (end < start) {
            NSInteger temp = start;
            start = end;
            end = temp;
        }
        if (end - start < kMinBlockDuration) {
            end = start + (NSInteger)kMinBlockDuration;
        }
        self.draggingRange = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:start]
                                                     end:[self timeStringFromMinutes:MIN(end, 1440)]];
    } else if (self.isResizingTop) {
        // Resize top edge
        NSInteger newStart = MIN(currentMinutes, [self.originalDragRange endMinutes] - (NSInteger)kMinBlockDuration);
        newStart = MAX(0, newStart);
        self.draggingRange = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:newStart]
                                                     end:self.originalDragRange.endTime];
    } else if (self.isResizingBottom) {
        // Resize bottom edge
        NSInteger newEnd = MAX(currentMinutes, [self.originalDragRange startMinutes] + (NSInteger)kMinBlockDuration);
        newEnd = MIN(1440, newEnd);
        self.draggingRange = [SCTimeRange rangeWithStart:self.originalDragRange.startTime
                                                     end:[self timeStringFromMinutes:newEnd]];
    } else if (self.isMovingBlock) {
        // Move whole block
        NSInteger delta = currentMinutes - self.dragStartMinutes;
        NSInteger newStart = [self.originalDragRange startMinutes] + delta;
        NSInteger newEnd = [self.originalDragRange endMinutes] + delta;

        // Clamp to day boundaries
        if (newStart < 0) {
            newEnd -= newStart;
            newStart = 0;
        }
        if (newEnd > 1440) {
            newStart -= (newEnd - 1440);
            newEnd = 1440;
        }

        self.draggingRange = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:MAX(0, newStart)]
                                                     end:[self timeStringFromMinutes:MIN(1440, newEnd)]];
    }

    // Update visual preview
    NSLog(@"[DRAG] Updating preview: draggingRange=%@-%@ bundleID=%@ selIdx=%ld",
          self.draggingRange.startTime, self.draggingRange.endTime,
          self.draggingBundleID, (long)self.selectedBlockIndex);
    [self reloadBlocks];
}

- (void)mouseUp:(NSEvent *)event {
    // Reset pending empty area click state
    self.hasPendingEmptyAreaClick = NO;

    if (!self.isDragging) return;

    // Apply the change
    if (self.draggingBundleID && self.draggingRange && [self.draggingRange isValid]) {
        SCWeeklySchedule *schedule = [self.schedules[self.draggingBundleID] copy];
        if (!schedule) {
            schedule = [SCWeeklySchedule emptyScheduleForBundleID:self.draggingBundleID];
        }

        NSMutableArray *windows = [[schedule allowedWindowsForDay:self.day] mutableCopy];
        if (!windows) windows = [NSMutableArray array];

        if (self.isCreatingBlock) {
            // Add new block
            [windows addObject:self.draggingRange];
        } else if (self.selectedBlockIndex >= 0 && self.selectedBlockIndex < windows.count) {
            // Update existing block
            [windows replaceObjectAtIndex:self.selectedBlockIndex withObject:self.draggingRange];
        }

        // Merge overlapping blocks
        windows = [[self mergeOverlappingRanges:windows] mutableCopy];

        [schedule setAllowedWindows:windows forDay:self.day];

        if (self.onScheduleUpdated) {
            self.onScheduleUpdated(self.draggingBundleID, schedule);
        }
    }

    // Reset drag state
    self.isDragging = NO;
    self.isCreatingBlock = NO;
    self.isResizingTop = NO;
    self.isResizingBottom = NO;
    self.isMovingBlock = NO;
    self.draggingRange = nil;
    self.originalDragRange = nil;
    self.draggingBundleID = nil;
}

- (void)mouseMoved:(NSEvent *)event {
    if (self.isCommitted) {
        [[NSCursor arrowCursor] set];
        return;
    }

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    // Check if over any block
    for (SCAllowBlockView *blockView in _blockViews) {
        if (NSPointInRect(loc, blockView.frame)) {
            CGFloat relY = loc.y - blockView.frame.origin.y;

            // Near top or bottom edge = resize cursor
            if (relY < kEdgeDetectionZone || relY > blockView.frame.size.height - kEdgeDetectionZone) {
                [[NSCursor resizeUpDownCursor] set];
            } else {
                // Middle of block = grab cursor
                [[NSCursor openHandCursor] set];
            }
            return;
        }
    }

    // Not over a block = arrow cursor
    [[NSCursor arrowCursor] set];
}

- (void)keyDown:(NSEvent *)event {
    // Escape key - progressive: first clear selection, then clear focus
    if (event.keyCode == 53) {  // Escape
        NSLog(@"[ESC] DayColumn: day=%ld selIdx=%ld selBundle=%@ hasCallback=%d",
              (long)self.day, (long)self.selectedBlockIndex, self.selectedBundleID,
              self.onEmptyAreaClicked != nil);
        if (self.selectedBlockIndex >= 0) {
            // First: clear block selection
            NSLog(@"[ESC] DayColumn: clearing selection");
            self.selectedBlockIndex = -1;
            self.selectedBundleID = nil;
            [self reloadBlocks];
        } else if (self.onEmptyAreaClicked) {
            // Second: clear bundle focus
            NSLog(@"[ESC] DayColumn: clearing focus via callback");
            self.onEmptyAreaClicked();
        } else {
            NSLog(@"[ESC] DayColumn: UNHANDLED - no selection, no callback!");
        }
        return;
    }

    if (self.isCommitted) return;

    // Delete key removes selected block
    if (event.keyCode == 51 || event.keyCode == 117) {  // Backspace or Delete
        if (self.selectedBundleID && self.selectedBlockIndex >= 0) {
            SCWeeklySchedule *schedule = [self.schedules[self.selectedBundleID] copy];
            NSMutableArray *windows = [[schedule allowedWindowsForDay:self.day] mutableCopy];
            if (self.selectedBlockIndex < windows.count) {
                [windows removeObjectAtIndex:self.selectedBlockIndex];
                [schedule setAllowedWindows:windows forDay:self.day];

                if (self.onScheduleUpdated) {
                    self.onScheduleUpdated(self.selectedBundleID, schedule);
                }
            }
            self.selectedBlockIndex = -1;
            self.selectedBundleID = nil;
        }
    }
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

#pragma mark - Helpers

- (NSString *)timeStringFromMinutes:(NSInteger)minutes {
    NSInteger hours = minutes / 60;
    NSInteger mins = minutes % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)mins];
}

- (NSArray<SCTimeRange *> *)mergeOverlappingRanges:(NSArray<SCTimeRange *> *)ranges {
    if (ranges.count <= 1) return ranges;

    // Sort by start time
    NSArray *sorted = [ranges sortedArrayUsingComparator:^NSComparisonResult(SCTimeRange *a, SCTimeRange *b) {
        return [@([a startMinutes]) compare:@([b startMinutes])];
    }];

    NSMutableArray *merged = [NSMutableArray array];
    SCTimeRange *current = [sorted.firstObject copy];

    for (NSInteger i = 1; i < sorted.count; i++) {
        SCTimeRange *next = sorted[i];
        if ([next startMinutes] <= [current endMinutes]) {
            // Overlapping - merge
            NSInteger newEnd = MAX([current endMinutes], [next endMinutes]);
            current = [SCTimeRange rangeWithStart:current.startTime
                                              end:[self timeStringFromMinutes:newEnd]];
        } else {
            [merged addObject:current];
            current = [next copy];
        }
    }
    [merged addObject:current];

    return merged;
}

- (nullable SCBlockBundle *)bundleForID:(NSString *)bundleID {
    for (SCBlockBundle *bundle in self.bundles) {
        if ([bundle.bundleID isEqualToString:bundleID]) {
            return bundle;
        }
    }
    return nil;
}

@end

#pragma mark - SCCalendarGridView

@interface SCCalendarGridView ()

@property (nonatomic, strong) NSView *headerContainer;
@property (nonatomic, strong) NSView *hourLabelContainer;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *columnsContainer;
@property (nonatomic, strong) NSMutableArray<SCCalendarDayColumn *> *dayColumns;
@property (nonatomic, strong) NSMutableArray<NSTextField *> *dayLabels;

// Copy/paste state
@property (nonatomic, strong, nullable) SCTimeRange *copiedBlock;
@property (nonatomic, copy, nullable) NSString *copiedBundleID;
@property (nonatomic, assign) SCDayOfWeek lastClickedDay;

@end

@implementation SCCalendarGridView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _bundles = @[];
        _schedules = @{};
        _dayColumns = [NSMutableArray array];
        _dayLabels = [NSMutableArray array];
        _undoManager = [[NSUndoManager alloc] init];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.wantsLayer = YES;

    CGFloat availableWidth = self.bounds.size.width - kHourLabelWidth;

    // Header container for day labels
    self.headerContainer = [[NSView alloc] initWithFrame:NSMakeRect(kHourLabelWidth, self.bounds.size.height - kDayHeaderHeight, availableWidth, kDayHeaderHeight)];
    self.headerContainer.wantsLayer = YES;
    self.headerContainer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self addSubview:self.headerContainer];

    // Hour labels on the left
    CGFloat timelineHeight = self.bounds.size.height - kDayHeaderHeight - kTimelineTopPadding;
    self.hourLabelContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kHourLabelWidth, timelineHeight)];
    self.hourLabelContainer.wantsLayer = YES;
    self.hourLabelContainer.autoresizingMask = NSViewHeightSizable;
    [self addSubview:self.hourLabelContainer];

    // Scroll view for day columns
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(kHourLabelWidth, 0, availableWidth, timelineHeight)];
    self.scrollView.hasVerticalScroller = NO;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.columnsContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, availableWidth, timelineHeight)];
    self.columnsContainer.wantsLayer = YES;
    self.scrollView.documentView = self.columnsContainer;
    [self addSubview:self.scrollView];

    [self setupHourLabels];
}

- (void)setupHourLabels {
    // Remove old labels
    for (NSView *subview in [self.hourLabelContainer.subviews copy]) {
        [subview removeFromSuperview];
    }

    CGFloat timelineHeight = self.hourLabelContainer.bounds.size.height;

    // Create hour labels for key times: 12am, 6am, 12pm, 6pm
    NSArray *hours = @[@0, @6, @12, @18, @24];
    NSArray *labels = @[@"12am", @"6am", @"12pm", @"6pm", @"12am"];

    for (NSInteger i = 0; i < hours.count; i++) {
        NSInteger hour = [hours[i] integerValue];
        CGFloat y = timelineHeight - (hour / 24.0) * timelineHeight - 8;  // Flipped for display

        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(4, y, kHourLabelWidth - 8, 16)];
        label.stringValue = labels[i];
        label.font = [NSFont systemFontOfSize:10];
        label.textColor = [NSColor secondaryLabelColor];
        label.bezeled = NO;
        label.editable = NO;
        label.drawsBackground = NO;
        label.alignment = NSTextAlignmentRight;
        [self.hourLabelContainer addSubview:label];
    }
}

- (void)reloadData {
    // Get days to display
    NSArray<NSNumber *> *days;
    if (self.showOnlyRemainingDays && self.weekOffset == 0) {
        days = [SCWeeklySchedule remainingDaysInWeekStartingMonday:YES];
    } else {
        days = [SCWeeklySchedule allDaysStartingMonday:YES];
    }

    // Remove old day labels and columns
    for (NSTextField *label in self.dayLabels) {
        [label removeFromSuperview];
    }
    [self.dayLabels removeAllObjects];

    for (SCCalendarDayColumn *col in self.dayColumns) {
        [col removeFromSuperview];
    }
    [self.dayColumns removeAllObjects];

    if (days.count == 0) return;

    // Calculate column width
    CGFloat availableWidth = self.headerContainer.bounds.size.width;
    CGFloat columnWidth = availableWidth / days.count;
    CGFloat timelineHeight = self.columnsContainer.bounds.size.height;

    // Determine today's day
    SCDayOfWeek today = [SCWeeklySchedule today];

    // Create day labels and columns
    for (NSInteger i = 0; i < days.count; i++) {
        SCDayOfWeek day = [days[i] integerValue];
        CGFloat x = i * columnWidth;
        BOOL isToday = (day == today && self.weekOffset == 0);

        // Day label in header
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 0, columnWidth, kDayHeaderHeight)];
        label.stringValue = [SCWeeklySchedule shortNameForDay:day];
        label.font = [NSFont systemFontOfSize:13 weight:isToday ? NSFontWeightBold : NSFontWeightMedium];
        label.textColor = isToday ? [NSColor systemBlueColor] : [NSColor labelColor];
        label.bezeled = NO;
        label.editable = NO;
        label.drawsBackground = NO;
        label.alignment = NSTextAlignmentCenter;
        [self.headerContainer addSubview:label];
        [self.dayLabels addObject:label];

        // Day column
        SCCalendarDayColumn *column = [[SCCalendarDayColumn alloc] initWithFrame:NSMakeRect(x, 0, columnWidth, timelineHeight)];
        column.day = day;
        column.bundles = self.bundles;
        column.schedules = self.schedules;
        column.focusedBundleID = self.focusedBundleID;
        column.isCommitted = self.isCommitted;
        column.isToday = isToday;
        column.timelineHeight = timelineHeight;

        // Set callbacks
        __weak typeof(self) weakSelf = self;
        SCDayOfWeek capturedDay = day;  // Capture day for callbacks
        column.onScheduleUpdated = ^(NSString *bundleID, SCWeeklySchedule *schedule) {
            weakSelf.lastClickedDay = capturedDay;
            [weakSelf handleScheduleUpdate:schedule forBundleID:bundleID];
        };
        column.onEmptyAreaClicked = ^{
            weakSelf.lastClickedDay = capturedDay;
            if ([weakSelf.delegate respondsToSelector:@selector(calendarGridDidClickEmptyArea:)]) {
                [weakSelf.delegate calendarGridDidClickEmptyArea:weakSelf];
            }
        };
        column.onBlockDoubleClicked = ^(SCBlockBundle *bundle) {
            weakSelf.lastClickedDay = capturedDay;
            if ([weakSelf.delegate respondsToSelector:@selector(calendarGrid:didRequestEditBundle:forDay:)]) {
                [weakSelf.delegate calendarGrid:weakSelf didRequestEditBundle:bundle forDay:day];
            }
        };
        column.onNoFocusInteraction = ^{
            weakSelf.lastClickedDay = capturedDay;
            if ([weakSelf.delegate respondsToSelector:@selector(calendarGridDidAttemptInteractionWithoutFocus:)]) {
                [weakSelf.delegate calendarGridDidAttemptInteractionWithoutFocus:weakSelf];
            }
        };
        column.onColumnClicked = ^{
            weakSelf.lastClickedDay = capturedDay;
        };
        column.onBlockSelected = ^{
            // Clear selection in ALL columns (single selection only)
            for (SCCalendarDayColumn *col in weakSelf.dayColumns) {
                [col clearSelection];
            }
        };

        [column reloadBlocks];
        [self.columnsContainer addSubview:column];
        [self.dayColumns addObject:column];
    }

    // Update columns container size
    self.columnsContainer.frame = NSMakeRect(0, 0, availableWidth, timelineHeight);
}

- (void)handleScheduleUpdate:(SCWeeklySchedule *)schedule forBundleID:(NSString *)bundleID {
    // Update internal schedules dictionary
    NSMutableDictionary *newSchedules = [self.schedules mutableCopy];
    newSchedules[bundleID] = schedule;
    self.schedules = newSchedules;

    // Reload affected columns
    for (SCCalendarDayColumn *column in self.dayColumns) {
        column.schedules = self.schedules;
        [column reloadBlocks];
    }

    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(calendarGrid:didUpdateSchedule:forBundleID:)]) {
        [self.delegate calendarGrid:self didUpdateSchedule:schedule forBundleID:bundleID];
    }
}

- (void)setFocusedBundleID:(NSString *)focusedBundleID {
    _focusedBundleID = [focusedBundleID copy];
    for (SCCalendarDayColumn *column in self.dayColumns) {
        column.focusedBundleID = _focusedBundleID;
        [column reloadBlocks];
    }
}

- (void)setIsCommitted:(BOOL)isCommitted {
    _isCommitted = isCommitted;
    for (SCCalendarDayColumn *column in self.dayColumns) {
        column.isCommitted = isCommitted;
        [column reloadBlocks];
    }
}

- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID {
    return self.schedules[bundleID];
}

- (nullable SCBlockBundle *)bundleForID:(NSString *)bundleID {
    for (SCBlockBundle *bundle in self.bundles) {
        if ([bundle.bundleID isEqualToString:bundleID]) {
            return bundle;
        }
    }
    return nil;
}

#pragma mark - Keyboard Handling

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *chars = [[event charactersIgnoringModifiers] lowercaseString];
    BOOL cmdPressed = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) != 0;

    // Cmd+Shift+Z = Redo
    if (cmdPressed && shiftPressed && [chars isEqualToString:@"z"]) {
        if ([self.undoManager canRedo]) {
            [self.undoManager redo];
            return YES;
        }
    }

    // Cmd+Z = Undo
    if (cmdPressed && !shiftPressed && [chars isEqualToString:@"z"]) {
        if ([self.undoManager canUndo]) {
            [self.undoManager undo];
            return YES;
        }
    }

    // Cmd+C = Copy selected block
    if (cmdPressed && !shiftPressed && [chars isEqualToString:@"c"]) {
        // Find the selected block from any day column
        for (SCCalendarDayColumn *column in self.dayColumns) {
            if (column.selectedBundleID && column.selectedBlockIndex >= 0) {
                SCWeeklySchedule *schedule = self.schedules[column.selectedBundleID];
                NSArray *windows = [schedule allowedWindowsForDay:column.day];
                if (column.selectedBlockIndex < (NSInteger)windows.count) {
                    self.copiedBlock = [windows[column.selectedBlockIndex] copy];
                    self.copiedBundleID = column.selectedBundleID;
                    return YES;
                }
            }
        }
    }

    // Cmd+V = Paste block to focused bundle on last clicked day
    if (cmdPressed && !shiftPressed && [chars isEqualToString:@"v"]) {
        if (self.copiedBlock && self.focusedBundleID) {
            // Paste to the last clicked day column
            for (SCCalendarDayColumn *column in self.dayColumns) {
                if (column.day == self.lastClickedDay) {
                    SCWeeklySchedule *schedule = [self.schedules[self.focusedBundleID] copy];
                    if (!schedule) {
                        schedule = [SCWeeklySchedule emptyScheduleForBundleID:self.focusedBundleID];
                    }

                    NSMutableArray *windows = [[schedule allowedWindowsForDay:column.day] mutableCopy];
                    if (!windows) windows = [NSMutableArray array];

                    // Add copied block
                    [windows addObject:[self.copiedBlock copy]];
                    [schedule setAllowedWindows:windows forDay:column.day];

                    if (column.onScheduleUpdated) {
                        column.onScheduleUpdated(self.focusedBundleID, schedule);
                    }
                    return YES;
                }
            }
        }
    }

    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    // Escape key - progressive: first clear selection, THEN clear focus
    if (event.keyCode == 53) {  // Escape key
        BOOL hasSel = [self hasSelectedBlock];
        NSLog(@"[ESC] GridView: hasSel=%d focusedBundle=%@ firstResp=%@",
              hasSel, self.focusedBundleID, self.window.firstResponder);
        if (hasSel) {
            NSLog(@"[ESC] GridView: clearing all selections");
            [self clearAllSelections];
        } else if (self.focusedBundleID) {
            NSLog(@"[ESC] GridView: clearing focus");
            [self.delegate calendarGridDidClickEmptyArea:self];
        } else {
            NSLog(@"[ESC] GridView: UNHANDLED - no selection, no focus!");
        }
        return;
    }

    [super keyDown:event];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)hasSelectedBlock {
    for (SCCalendarDayColumn *column in self.dayColumns) {
        if (column.selectedBlockIndex >= 0) {
            return YES;
        }
    }
    return NO;
}

- (void)clearAllSelections {
    for (SCCalendarDayColumn *column in self.dayColumns) {
        [column clearSelection];
    }
}

@end
