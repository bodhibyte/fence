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

// Opacity for non-focused bundles
static const CGFloat kDimmedOpacity = 0.2;

#pragma mark - SCAllowBlockView (Private)

@interface SCAllowBlockView : NSView

@property (nonatomic, strong) SCTimeRange *timeRange;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, assign) BOOL isDimmed;
@property (nonatomic, assign) BOOL isCommitted;

@end

@implementation SCAllowBlockView

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Background fill
    NSColor *fillColor = self.color;
    if (self.isDimmed) {
        fillColor = [fillColor colorWithAlphaComponent:kDimmedOpacity];
    } else if (self.isSelected) {
        fillColor = [fillColor colorWithAlphaComponent:0.9];
    } else {
        fillColor = [fillColor colorWithAlphaComponent:0.7];
    }

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4];
    [fillColor setFill];
    [path fill];

    // Border
    if (self.isSelected && !self.isCommitted) {
        [[self.color colorWithAlphaComponent:1.0] setStroke];
        path.lineWidth = 2.0;
        [path stroke];
    }

    // Time label if block is tall enough
    if (self.bounds.size.height > 30 && self.timeRange) {
        NSString *label = [self.timeRange displayString12Hour];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9],
            NSForegroundColorAttributeName: self.isDimmed ? [[NSColor labelColor] colorWithAlphaComponent:0.3] : [NSColor labelColor]
        };
        CGFloat textY = self.bounds.size.height - 14;
        [label drawAtPoint:NSMakePoint(4, textY) withAttributes:attrs];
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
@property (nonatomic, assign) CGFloat dragStartY;
@property (nonatomic, assign) NSInteger dragStartMinutes;
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

- (void)reloadBlocks;
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

        for (SCTimeRange *range in windows) {
            CGFloat y = [self yFromMinutes:[range startMinutes]];
            CGFloat height = [self yFromMinutes:[range endMinutes]] - y;

            NSRect blockFrame = NSMakeRect(laneX, y, laneWidth - kLanePadding, height);
            SCAllowBlockView *blockView = [[SCAllowBlockView alloc] initWithFrame:blockFrame];
            blockView.timeRange = range;
            blockView.color = bundle.color;
            blockView.isCommitted = self.isCommitted;

            // Dimmed if not focused bundle (and we have a focused bundle)
            if (self.focusedBundleID && ![bundle.bundleID isEqualToString:self.focusedBundleID]) {
                blockView.isDimmed = YES;
            }

            // Selected state
            if ([bundle.bundleID isEqualToString:self.selectedBundleID]) {
                NSArray *bundleWindows = [schedule allowedWindowsForDay:self.day];
                NSInteger idx = [bundleWindows indexOfObject:range];
                if (idx == self.selectedBlockIndex) {
                    blockView.isSelected = YES;
                }
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

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    if (self.isCommitted) return;
    if (!self.focusedBundleID) {
        // No bundle focused - click goes to empty area handler
        if (self.onEmptyAreaClicked) {
            self.onEmptyAreaClicked();
        }
        return;
    }

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];

    // Check if clicking on an existing block
    for (SCAllowBlockView *blockView in _blockViews) {
        if (NSPointInRect(loc, blockView.frame)) {
            if (event.clickCount == 2) {
                // Double-click: open editor
                SCBlockBundle *bundle = [self bundleForID:self.focusedBundleID];
                if (bundle && self.onBlockDoubleClicked) {
                    self.onBlockDoubleClicked(bundle);
                }
                return;
            }

            // Single click on block - select it and check for resize handles
            self.selectedBundleID = self.focusedBundleID;
            // Find index
            SCWeeklySchedule *schedule = self.schedules[self.focusedBundleID];
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
            self.draggingBundleID = self.focusedBundleID;
            self.draggingRange = [blockView.timeRange copy];
            self.originalDragRange = [blockView.timeRange copy];
            self.dragStartY = loc.y;
            self.dragStartMinutes = [self minutesFromY:loc.y];

            [self reloadBlocks];
            return;
        }
    }

    // Clicking empty area - start creating new block
    self.isCreatingBlock = YES;
    self.isDragging = YES;
    self.draggingBundleID = self.focusedBundleID;

    NSInteger startMinutes = [self snapToGrid:[self minutesFromY:loc.y]];
    self.draggingRange = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:startMinutes]
                                                 end:[self timeStringFromMinutes:startMinutes + 60]];
    self.dragStartY = loc.y;
    self.dragStartMinutes = startMinutes;

    [self reloadBlocks];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.isDragging || self.isCommitted) return;

    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
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

    // Update visual preview (would need to refresh block views with preview)
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
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

- (void)keyDown:(NSEvent *)event {
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
        column.onScheduleUpdated = ^(NSString *bundleID, SCWeeklySchedule *schedule) {
            [weakSelf handleScheduleUpdate:schedule forBundleID:bundleID];
        };
        column.onEmptyAreaClicked = ^{
            if ([weakSelf.delegate respondsToSelector:@selector(calendarGridDidClickEmptyArea:)]) {
                [weakSelf.delegate calendarGridDidClickEmptyArea:weakSelf];
            }
        };
        column.onBlockDoubleClicked = ^(SCBlockBundle *bundle) {
            if ([weakSelf.delegate respondsToSelector:@selector(calendarGrid:didRequestEditBundle:forDay:)]) {
                [weakSelf.delegate calendarGrid:weakSelf didRequestEditBundle:bundle forDay:day];
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

@end
