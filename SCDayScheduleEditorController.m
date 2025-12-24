//
//  SCDayScheduleEditorController.m
//  SelfControl
//

#import "SCDayScheduleEditorController.h"

// Constants for timeline view
static const CGFloat kTimelineHeight = 300.0;
static const CGFloat kTimelineWidth = 60.0;
static const CGFloat kSnapMinutes = 15.0;
static const CGFloat kEdgeDetectionZone = 10.0; // Pixels near edge for resize detection

#pragma mark - SCTimelineView (Private)

@interface SCTimelineView : NSView

@property (nonatomic, strong) NSMutableArray<SCTimeRange *> *allowedWindows;
@property (nonatomic, strong) NSColor *bundleColor;
@property (nonatomic, assign) BOOL isCommitted;
@property (nonatomic, copy, nullable) void (^onWindowsChanged)(void);
@property (nonatomic, copy, nullable) void (^onRequestTimeInput)(NSInteger suggestedMinutes);

// Drag state
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSInteger draggingWindowIndex;
@property (nonatomic, assign) BOOL draggingStartEdge;
@property (nonatomic, assign) BOOL draggingEndEdge;
@property (nonatomic, assign) BOOL draggingWholeBlock;
@property (nonatomic, assign) CGFloat dragStartY;
@property (nonatomic, assign) NSInteger dragStartMinutes;
@property (nonatomic, strong, nullable) SCTimeRange *originalDragRange;

- (NSInteger)minutesFromY:(CGFloat)y;
- (CGFloat)yFromMinutes:(NSInteger)minutes;
- (NSInteger)snapToGrid:(NSInteger)minutes;

@end

@implementation SCTimelineView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _allowedWindows = [NSMutableArray array];
        _bundleColor = [NSColor systemBlueColor];
        _draggingWindowIndex = -1;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES; // Origin at top (midnight)
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;

    // Background (blocked = dark gray)
    [[NSColor colorWithWhite:0.2 alpha:1.0] setFill];
    NSRectFill(bounds);

    // Hour lines and labels
    [self drawHourMarkers];

    // Draw allowed windows
    for (NSUInteger i = 0; i < self.allowedWindows.count; i++) {
        SCTimeRange *window = self.allowedWindows[i];
        [self drawWindow:window atIndex:i];
    }

    // Draw "now" line
    [self drawNowLine];
}

- (void)drawNowLine {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    NSInteger nowMinutes = comps.hour * 60 + comps.minute;

    CGFloat nowY = [self yFromMinutes:nowMinutes];

    // Draw dotted red line
    [[NSColor systemRedColor] setStroke];
    NSBezierPath *nowPath = [NSBezierPath bezierPath];
    CGFloat dashPattern[] = {4, 4};
    [nowPath setLineDash:dashPattern count:2 phase:0];
    [nowPath setLineWidth:2.0];
    [nowPath moveToPoint:NSMakePoint(30, nowY)];
    [nowPath lineToPoint:NSMakePoint(self.bounds.size.width, nowY)];
    [nowPath stroke];

    // Draw small "NOW" label
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor systemRedColor]
    };
    [@"NOW" drawAtPoint:NSMakePoint(2, nowY - 4) withAttributes:attrs];
}

- (void)drawHourMarkers {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };

    [[NSColor separatorColor] setStroke];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:0.5];

    for (NSInteger hour = 0; hour <= 24; hour++) {
        CGFloat y = [self yFromMinutes:hour * 60];

        // Line
        [path moveToPoint:NSMakePoint(30, y)];
        [path lineToPoint:NSMakePoint(self.bounds.size.width, y)];

        // Label
        NSString *label;
        if (hour == 0 || hour == 24) {
            label = @"12am";
        } else if (hour == 12) {
            label = @"12pm";
        } else if (hour < 12) {
            label = [NSString stringWithFormat:@"%ldam", (long)hour];
        } else {
            label = [NSString stringWithFormat:@"%ldpm", (long)(hour - 12)];
        }

        [label drawAtPoint:NSMakePoint(2, y - 6) withAttributes:attrs];
    }

    [path stroke];
}

- (void)drawWindow:(SCTimeRange *)window atIndex:(NSUInteger)index {
    CGFloat startY = [self yFromMinutes:[window startMinutes]];
    CGFloat endY = [self yFromMinutes:[window endMinutes]];
    CGFloat height = endY - startY;

    NSRect windowRect = NSMakeRect(35, startY, self.bounds.size.width - 40, height);

    // Main fill
    [[self.bundleColor colorWithAlphaComponent:0.7] setFill];
    NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:windowRect xRadius:4 yRadius:4];
    [bgPath fill];

    // Border
    [[self.bundleColor colorWithAlphaComponent:1.0] setStroke];
    [bgPath setLineWidth:1.5];
    [bgPath stroke];

    // Time labels
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };

    NSString *timeLabel = [window displayString12Hour];
    NSSize labelSize = [timeLabel sizeWithAttributes:attrs];
    NSPoint labelPoint = NSMakePoint(windowRect.origin.x + (windowRect.size.width - labelSize.width) / 2,
                                      startY + height/2 - labelSize.height/2);
    [timeLabel drawAtPoint:labelPoint withAttributes:attrs];
}

#pragma mark - Coordinate Conversion

- (NSInteger)minutesFromY:(CGFloat)y {
    CGFloat percent = y / self.bounds.size.height;
    return (NSInteger)(percent * 24 * 60);
}

- (CGFloat)yFromMinutes:(NSInteger)minutes {
    CGFloat percent = minutes / (24.0 * 60.0);
    return percent * self.bounds.size.height;
}

- (NSInteger)snapToGrid:(NSInteger)minutes {
    return ((NSInteger)round(minutes / kSnapMinutes)) * (NSInteger)kSnapMinutes;
}

#pragma mark - Mouse Handling

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    // Check for double-click on empty space to show time picker
    if (event.clickCount == 2 && !self.isCommitted) {
        NSInteger minutes = [self snapToGrid:[self minutesFromY:point.y]];
        // Check if clicking in empty space (not on a window)
        BOOL onWindow = NO;
        for (SCTimeRange *window in self.allowedWindows) {
            CGFloat startY = [self yFromMinutes:[window startMinutes]];
            CGFloat endY = [self yFromMinutes:[window endMinutes]];
            NSRect windowRect = NSMakeRect(35, startY, self.bounds.size.width - 40, endY - startY);
            if (NSPointInRect(point, windowRect)) {
                onWindow = YES;
                break;
            }
        }
        if (!onWindow && self.onRequestTimeInput) {
            self.onRequestTimeInput(minutes);
            return;
        }
    }

    // Check if clicking on existing window
    for (NSInteger i = self.allowedWindows.count - 1; i >= 0; i--) {
        SCTimeRange *window = self.allowedWindows[i];
        CGFloat startY = [self yFromMinutes:[window startMinutes]];
        CGFloat endY = [self yFromMinutes:[window endMinutes]];

        NSRect windowRect = NSMakeRect(35, startY, self.bounds.size.width - 40, endY - startY);
        if (!NSPointInRect(point, windowRect)) continue;

        self.isDragging = YES;
        self.draggingWindowIndex = i;
        self.originalDragRange = [window copy];
        self.dragStartY = point.y;
        self.dragStartMinutes = [self minutesFromY:point.y];

        // Check if near top edge (resize start)
        if (point.y - startY < kEdgeDetectionZone) {
            self.draggingStartEdge = YES;
            self.draggingEndEdge = NO;
            self.draggingWholeBlock = NO;
            return;
        }

        // Check if near bottom edge (resize end)
        if (endY - point.y < kEdgeDetectionZone) {
            self.draggingStartEdge = NO;
            self.draggingEndEdge = YES;
            self.draggingWholeBlock = NO;
            return;
        }

        // Middle of block - drag the whole block
        self.draggingStartEdge = NO;
        self.draggingEndEdge = NO;
        self.draggingWholeBlock = YES;
        return;
    }

    // Single click on empty space - create new window with drag
    if (!self.isCommitted) {
        NSInteger minutes = [self snapToGrid:[self minutesFromY:point.y]];
        SCTimeRange *newWindow = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:minutes]
                                                         end:[self timeStringFromMinutes:minutes + 60]];
        [self.allowedWindows addObject:newWindow];
        self.isDragging = YES;
        self.draggingWindowIndex = self.allowedWindows.count - 1;
        self.draggingStartEdge = NO;
        self.draggingEndEdge = YES;
        self.draggingWholeBlock = NO;
        self.dragStartY = point.y;

        [self setNeedsDisplay:YES];
        if (self.onWindowsChanged) self.onWindowsChanged();
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.isDragging || self.draggingWindowIndex < 0) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger minutes = [self snapToGrid:[self minutesFromY:point.y]];
    minutes = MAX(0, MIN(24 * 60, minutes));

    SCTimeRange *window = self.allowedWindows[self.draggingWindowIndex];

    if (self.draggingStartEdge) {
        // Moving start time (resize from top)
        NSInteger endMinutes = [window endMinutes];
        if (minutes < endMinutes - 15) {
            // Check commitment constraint
            if (self.isCommitted && self.originalDragRange) {
                // Can only make window smaller, not larger
                if (minutes < [self.originalDragRange startMinutes]) {
                    minutes = [self.originalDragRange startMinutes];
                }
            }
            window.startTime = [self timeStringFromMinutes:minutes];
        }
    } else if (self.draggingEndEdge) {
        // Moving end time (resize from bottom)
        NSInteger startMinutes = [window startMinutes];
        if (minutes > startMinutes + 15) {
            // Check commitment constraint
            if (self.isCommitted && self.originalDragRange) {
                // Can only make window smaller, not larger
                if (minutes > [self.originalDragRange endMinutes]) {
                    minutes = [self.originalDragRange endMinutes];
                }
            }
            window.endTime = [self timeStringFromMinutes:minutes];
        }
    } else if (self.draggingWholeBlock) {
        // Moving the whole block
        NSInteger deltaMinutes = minutes - [self snapToGrid:self.dragStartMinutes];
        NSInteger originalStart = [self.originalDragRange startMinutes];
        NSInteger originalEnd = [self.originalDragRange endMinutes];
        NSInteger duration = originalEnd - originalStart;

        NSInteger newStart = originalStart + deltaMinutes;
        NSInteger newEnd = originalEnd + deltaMinutes;

        // Clamp to day bounds
        if (newStart < 0) {
            newStart = 0;
            newEnd = duration;
        }
        if (newEnd > 24 * 60) {
            newEnd = 24 * 60;
            newStart = newEnd - duration;
        }

        // Check commitment constraint - can only move within original bounds
        if (self.isCommitted && self.originalDragRange) {
            // When committed, block can't be moved to allow more time
            // For simplicity, prevent all movement when committed
            return;
        }

        window.startTime = [self timeStringFromMinutes:newStart];
        window.endTime = [self timeStringFromMinutes:newEnd];
    }

    [self setNeedsDisplay:YES];
    if (self.onWindowsChanged) self.onWindowsChanged();
}

- (void)mouseUp:(NSEvent *)event {
    self.isDragging = NO;
    self.draggingWindowIndex = -1;
    self.draggingStartEdge = NO;
    self.draggingEndEdge = NO;
    self.draggingWholeBlock = NO;
    self.originalDragRange = nil;

    // Clean up any zero-duration windows
    NSMutableArray *toRemove = [NSMutableArray array];
    for (SCTimeRange *window in self.allowedWindows) {
        if ([window durationMinutes] < 15) {
            [toRemove addObject:window];
        }
    }
    [self.allowedWindows removeObjectsInArray:toRemove];

    [self setNeedsDisplay:YES];
    if (self.onWindowsChanged) self.onWindowsChanged();
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }

    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                                options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
                                                                  owner:self
                                                               userInfo:nil];
    [self addTrackingArea:trackingArea];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    // Check if near any window edges
    for (SCTimeRange *window in self.allowedWindows) {
        CGFloat startY = [self yFromMinutes:[window startMinutes]];
        CGFloat endY = [self yFromMinutes:[window endMinutes]];

        NSRect windowRect = NSMakeRect(35, startY, self.bounds.size.width - 40, endY - startY);
        if (!NSPointInRect(point, windowRect)) continue;

        // Near top or bottom edge - resize cursor
        if (point.y - startY < kEdgeDetectionZone || endY - point.y < kEdgeDetectionZone) {
            [[NSCursor resizeUpDownCursor] set];
            return;
        }

        // Middle of block - open hand (move) cursor
        [[NSCursor openHandCursor] set];
        return;
    }

    // Not over any window - arrow cursor
    [[NSCursor arrowCursor] set];
}

- (NSString *)timeStringFromMinutes:(NSInteger)minutes {
    NSInteger hours = minutes / 60;
    NSInteger mins = minutes % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)hours, (long)mins];
}

@end

#pragma mark - SCDayScheduleEditorController

@interface SCDayScheduleEditorController ()

@property (nonatomic, strong) SCBlockBundle *bundle;
@property (nonatomic, assign) SCDayOfWeek day;
@property (nonatomic, strong) SCWeeklySchedule *schedule;
@property (nonatomic, strong) SCWeeklySchedule *workingSchedule;

// UI Elements
@property (nonatomic, strong) SCTimelineView *timelineView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSPopUpButton *presetsButton;
@property (nonatomic, strong) NSPopUpButton *duplicateFromDayButton;
@property (nonatomic, strong) NSPopUpButton *applyToButton;
@property (nonatomic, strong) NSButton *deleteWindowButton;
@property (nonatomic, strong) NSButton *doneButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSButton *addTimeBlockButton;
@property (nonatomic, strong) NSPopover *timeInputPopover;
@property (nonatomic, strong) NSDatePicker *startTimePicker;
@property (nonatomic, strong) NSDatePicker *endTimePicker;

@end

@implementation SCDayScheduleEditorController

- (instancetype)initWithBundle:(SCBlockBundle *)bundle
                      schedule:(SCWeeklySchedule *)schedule
                           day:(SCDayOfWeek)day {
    // Create window programmatically
    NSRect frame = NSMakeRect(0, 0, 300, 500);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Edit Day Schedule";

    self = [super initWithWindow:window];
    if (self) {
        _bundle = bundle;
        _day = day;
        _schedule = schedule;
        _workingSchedule = [schedule copy];
        _isCommitted = NO;

        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    CGFloat y = contentView.bounds.size.height - 10;
    CGFloat padding = 12;

    // Title
    y -= 30;
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 200, 24)];
    self.titleLabel.stringValue = [NSString stringWithFormat:@"%@ - %@",
                                    self.bundle.name,
                                    [SCWeeklySchedule displayNameForDay:self.day]];
    self.titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    self.titleLabel.bezeled = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.drawsBackground = NO;
    [contentView addSubview:self.titleLabel];

    // Legend - colored blocks = allowed time
    NSTextField *legendLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 200, y + 4, 80, 16)];
    legendLabel.stringValue = @"■ = Allowed";
    legendLabel.font = [NSFont systemFontOfSize:10];
    legendLabel.textColor = self.bundle.color;
    legendLabel.bezeled = NO;
    legendLabel.editable = NO;
    legendLabel.drawsBackground = NO;
    [contentView addSubview:legendLabel];

    // Presets dropdown
    y -= 35;
    NSTextField *presetsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60, 20)];
    presetsLabel.stringValue = @"Presets:";
    presetsLabel.font = [NSFont systemFontOfSize:12];
    presetsLabel.bezeled = NO;
    presetsLabel.editable = NO;
    presetsLabel.drawsBackground = NO;
    [contentView addSubview:presetsLabel];

    self.presetsButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(75, y - 2, 170, 24) pullsDown:YES];
    [self.presetsButton addItemWithTitle:@"Apply Preset..."];
    [self.presetsButton addItemWithTitle:@"Work Hours (9am-5pm)"];
    [self.presetsButton addItemWithTitle:@"Extended Work (8am-8pm)"];
    [self.presetsButton addItemWithTitle:@"Waking Hours (7am-11pm)"];
    [self.presetsButton addItemWithTitle:@"All Day (always allowed)"];
    [self.presetsButton addItemWithTitle:@"Clear All (always blocked)"];
    self.presetsButton.target = self;
    self.presetsButton.action = @selector(presetSelected:);
    [contentView addSubview:self.presetsButton];

    // Add time block button ("+")
    self.addTimeBlockButton = [[NSButton alloc] initWithFrame:NSMakeRect(250, y - 2, 30, 24)];
    self.addTimeBlockButton.title = @"+";
    self.addTimeBlockButton.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    self.addTimeBlockButton.bezelStyle = NSBezelStyleRounded;
    self.addTimeBlockButton.target = self;
    self.addTimeBlockButton.action = @selector(addTimeBlockClicked:);
    self.addTimeBlockButton.toolTip = @"Add time block with specific times";
    [contentView addSubview:self.addTimeBlockButton];

    // Timeline view
    y -= 320;
    self.timelineView = [[SCTimelineView alloc] initWithFrame:NSMakeRect(padding, y, 276, 300)];
    self.timelineView.bundleColor = self.bundle.color;
    self.timelineView.allowedWindows = [[self.workingSchedule allowedWindowsForDay:self.day] mutableCopy];
    self.timelineView.isCommitted = self.isCommitted;

    __weak typeof(self) weakSelf = self;
    self.timelineView.onWindowsChanged = ^{
        [weakSelf timelineWindowsChanged];
    };
    self.timelineView.onRequestTimeInput = ^(NSInteger suggestedMinutes) {
        [weakSelf showTimeInputPopoverAtMinutes:suggestedMinutes];
    };

    self.timelineView.wantsLayer = YES;
    self.timelineView.layer.cornerRadius = 8;
    self.timelineView.layer.masksToBounds = YES;
    [contentView addSubview:self.timelineView];

    // Copy schedule from another day
    y -= 35;
    NSTextField *copyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 50, 20)];
    copyLabel.stringValue = @"Copy:";
    copyLabel.font = [NSFont systemFontOfSize:11];
    copyLabel.bezeled = NO;
    copyLabel.editable = NO;
    copyLabel.drawsBackground = NO;
    [contentView addSubview:copyLabel];

    self.duplicateFromDayButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(50, y - 2, 80, 22) pullsDown:YES];
    [self.duplicateFromDayButton addItemWithTitle:@"Day..."];
    for (SCDayOfWeek d = SCDayOfWeekSunday; d <= SCDayOfWeekSaturday; d++) {
        if (d != self.day) {
            [self.duplicateFromDayButton addItemWithTitle:[SCWeeklySchedule shortNameForDay:d]];
        }
    }
    self.duplicateFromDayButton.target = self;
    self.duplicateFromDayButton.action = @selector(copyFromSelected:);
    self.duplicateFromDayButton.font = [NSFont systemFontOfSize:11];
    self.duplicateFromDayButton.toolTip = @"Copy schedule from another day";
    [contentView addSubview:self.duplicateFromDayButton];

    // Apply this schedule to other days
    NSTextField *applyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(140, y, 70, 20)];
    applyLabel.stringValue = @"Apply to:";
    applyLabel.font = [NSFont systemFontOfSize:11];
    applyLabel.bezeled = NO;
    applyLabel.editable = NO;
    applyLabel.drawsBackground = NO;
    [contentView addSubview:applyLabel];

    self.applyToButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, y - 2, 85, 22) pullsDown:YES];
    [self.applyToButton addItemWithTitle:@"Days..."];
    [self.applyToButton addItemWithTitle:@"All Days"];
    [self.applyToButton addItemWithTitle:@"Weekdays"];
    [self.applyToButton addItemWithTitle:@"Weekend"];
    self.applyToButton.target = self;
    self.applyToButton.action = @selector(applyToSelected:);
    self.applyToButton.font = [NSFont systemFontOfSize:11];
    self.applyToButton.toolTip = @"Copy this schedule to other days";
    [contentView addSubview:self.applyToButton];

    // Buttons
    y -= 45;
    self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, y, 80, 30)];
    self.cancelButton.title = @"Cancel";
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.target = self;
    self.cancelButton.action = @selector(cancelClicked:);
    [contentView addSubview:self.cancelButton];

    self.doneButton = [[NSButton alloc] initWithFrame:NSMakeRect(200, y, 80, 30)];
    self.doneButton.title = @"Done";
    self.doneButton.bezelStyle = NSBezelStyleRounded;
    self.doneButton.keyEquivalent = @"\r";
    self.doneButton.target = self;
    self.doneButton.action = @selector(doneClicked:);
    [contentView addSubview:self.doneButton];
}

- (void)timelineWindowsChanged {
    // Update working schedule with current windows
    [self.workingSchedule setAllowedWindows:self.timelineView.allowedWindows forDay:self.day];
}

#pragma mark - Actions

- (void)presetSelected:(id)sender {
    NSInteger index = self.presetsButton.indexOfSelectedItem;
    if (index <= 0) return;

    NSArray<SCTimeRange *> *windows = @[];

    switch (index) {
        case 1: // Work Hours
            windows = @[[SCTimeRange workHours]];
            break;
        case 2: // Extended Work
            windows = @[[SCTimeRange extendedWork]];
            break;
        case 3: // Waking Hours
            windows = @[[SCTimeRange wakingHours]];
            break;
        case 4: // All Day
            windows = @[[SCTimeRange allDay]];
            break;
        case 5: // Clear All
            windows = @[];
            break;
    }

    // Check commitment - can only make stricter
    if (self.isCommitted) {
        NSInteger currentTotal = [self.workingSchedule totalAllowedMinutesForDay:self.day];
        NSInteger newTotal = 0;
        for (SCTimeRange *r in windows) {
            newTotal += [r durationMinutes];
        }
        if (newTotal > currentTotal) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Cannot Loosen Schedule";
            alert.informativeText = @"You're committed to this week. You can only make the schedule stricter.";
            [alert runModal];
            return;
        }
    }

    self.timelineView.allowedWindows = [windows mutableCopy];
    [self.timelineView setNeedsDisplay:YES];
    [self timelineWindowsChanged];

    [self.presetsButton selectItemAtIndex:0];
}

- (void)copyFromSelected:(id)sender {
    NSInteger index = self.duplicateFromDayButton.indexOfSelectedItem;
    if (index <= 0) return;

    // Map selection to day
    NSString *dayName = [self.duplicateFromDayButton titleOfSelectedItem];
    SCDayOfWeek sourceDay = SCDayOfWeekSunday;
    for (SCDayOfWeek d = SCDayOfWeekSunday; d <= SCDayOfWeekSaturday; d++) {
        if ([[SCWeeklySchedule shortNameForDay:d] isEqualToString:dayName]) {
            sourceDay = d;
            break;
        }
    }

    NSArray<SCTimeRange *> *sourceWindows = [self.schedule allowedWindowsForDay:sourceDay];

    // Check commitment
    if (self.isCommitted) {
        NSInteger currentTotal = [self.workingSchedule totalAllowedMinutesForDay:self.day];
        NSInteger newTotal = 0;
        for (SCTimeRange *r in sourceWindows) {
            newTotal += [r durationMinutes];
        }
        if (newTotal > currentTotal) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Cannot Loosen Schedule";
            alert.informativeText = @"You're committed to this week. You can only make the schedule stricter.";
            [alert runModal];
            return;
        }
    }

    // Deep copy windows
    NSMutableArray *copiedWindows = [NSMutableArray array];
    for (SCTimeRange *window in sourceWindows) {
        [copiedWindows addObject:[window copy]];
    }

    self.timelineView.allowedWindows = copiedWindows;
    [self.timelineView setNeedsDisplay:YES];
    [self timelineWindowsChanged];

    [self.duplicateFromDayButton selectItemAtIndex:0];
}

- (void)applyToSelected:(id)sender {
    NSInteger index = self.applyToButton.indexOfSelectedItem;
    if (index <= 0) return;

    NSArray<SCTimeRange *> *currentWindows = self.timelineView.allowedWindows;
    NSArray<NSNumber *> *targetDays;

    switch (index) {
        case 1: // All
            targetDays = @[@(SCDayOfWeekSunday), @(SCDayOfWeekMonday), @(SCDayOfWeekTuesday),
                          @(SCDayOfWeekWednesday), @(SCDayOfWeekThursday), @(SCDayOfWeekFriday),
                          @(SCDayOfWeekSaturday)];
            break;
        case 2: // Weekdays
            targetDays = @[@(SCDayOfWeekMonday), @(SCDayOfWeekTuesday), @(SCDayOfWeekWednesday),
                          @(SCDayOfWeekThursday), @(SCDayOfWeekFriday)];
            break;
        case 3: // Weekend
            targetDays = @[@(SCDayOfWeekSaturday), @(SCDayOfWeekSunday)];
            break;
        default:
            return;
    }

    for (NSNumber *dayNum in targetDays) {
        SCDayOfWeek targetDay = [dayNum integerValue];
        NSMutableArray *copiedWindows = [NSMutableArray array];
        for (SCTimeRange *window in currentWindows) {
            [copiedWindows addObject:[window copy]];
        }
        [self.workingSchedule setAllowedWindows:copiedWindows forDay:targetDay];
    }

    [self.applyToButton selectItemAtIndex:0];
}

- (void)doneClicked:(id)sender {
    // Save the current timeline state
    [self timelineWindowsChanged];

    [self.delegate dayScheduleEditor:self didSaveSchedule:self.workingSchedule forDay:self.day];
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

- (void)cancelClicked:(id)sender {
    [self.delegate dayScheduleEditorDidCancel:self];
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];
}

#pragma mark - Time Input Popover

- (void)addTimeBlockClicked:(id)sender {
    if (self.isCommitted) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Add Blocks";
        alert.informativeText = @"You're committed to this week. You cannot add new allowed time blocks.";
        [alert runModal];
        return;
    }
    // Show time picker with default times (next hour to +2 hours)
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:NSCalendarUnitHour fromDate:[NSDate date]];
    NSInteger nextHour = (comps.hour + 1) % 24;
    [self showTimeInputPopoverAtMinutes:nextHour * 60];
}

- (void)showTimeInputPopoverAtMinutes:(NSInteger)suggestedMinutes {
    if (self.timeInputPopover && self.timeInputPopover.isShown) {
        [self.timeInputPopover close];
        return;
    }

    // Create popover content view
    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 140)];

    // Title label
    NSTextField *titleLabel = [NSTextField labelWithString:@"Add Time Block"];
    titleLabel.frame = NSMakeRect(10, 110, 180, 20);
    titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    [contentView addSubview:titleLabel];

    // Start time label
    NSTextField *startLabel = [NSTextField labelWithString:@"Start:"];
    startLabel.frame = NSMakeRect(10, 80, 40, 20);
    startLabel.font = [NSFont systemFontOfSize:12];
    [contentView addSubview:startLabel];

    // Start time picker
    self.startTimePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(55, 78, 130, 24)];
    self.startTimePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.startTimePicker.datePickerElements = NSDatePickerElementFlagHourMinute;
    self.startTimePicker.dateValue = [self dateFromMinutes:suggestedMinutes];
    [contentView addSubview:self.startTimePicker];

    // End time label
    NSTextField *endLabel = [NSTextField labelWithString:@"End:"];
    endLabel.frame = NSMakeRect(10, 50, 40, 20);
    endLabel.font = [NSFont systemFontOfSize:12];
    [contentView addSubview:endLabel];

    // End time picker
    self.endTimePicker = [[NSDatePicker alloc] initWithFrame:NSMakeRect(55, 48, 130, 24)];
    self.endTimePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.endTimePicker.datePickerElements = NSDatePickerElementFlagHourMinute;
    self.endTimePicker.dateValue = [self dateFromMinutes:MIN(suggestedMinutes + 120, 24 * 60)];
    [contentView addSubview:self.endTimePicker];

    // Create button
    NSButton *createButton = [[NSButton alloc] initWithFrame:NSMakeRect(55, 10, 90, 28)];
    createButton.title = @"Create";
    createButton.bezelStyle = NSBezelStyleRounded;
    createButton.target = self;
    createButton.action = @selector(createTimeBlockFromPopover:);
    [contentView addSubview:createButton];

    // Create and configure popover
    self.timeInputPopover = [[NSPopover alloc] init];
    self.timeInputPopover.contentSize = contentView.frame.size;
    self.timeInputPopover.behavior = NSPopoverBehaviorTransient;
    self.timeInputPopover.animates = YES;

    NSViewController *viewController = [[NSViewController alloc] init];
    viewController.view = contentView;
    self.timeInputPopover.contentViewController = viewController;

    // Show relative to add button
    [self.timeInputPopover showRelativeToRect:self.addTimeBlockButton.bounds
                                       ofView:self.addTimeBlockButton
                                preferredEdge:NSRectEdgeMaxY];
}

- (void)createTimeBlockFromPopover:(id)sender {
    NSInteger startMinutes = [self minutesFromDate:self.startTimePicker.dateValue];
    NSInteger endMinutes = [self minutesFromDate:self.endTimePicker.dateValue];

    // Validate
    if (endMinutes <= startMinutes) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid Time Range";
        alert.informativeText = @"End time must be after start time.";
        [alert runModal];
        return;
    }

    if (endMinutes - startMinutes < 15) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Time Range Too Short";
        alert.informativeText = @"Time blocks must be at least 15 minutes.";
        [alert runModal];
        return;
    }

    // Create the time range
    NSString *startStr = [NSString stringWithFormat:@"%02ld:%02ld", (long)(startMinutes / 60), (long)(startMinutes % 60)];
    NSString *endStr = [NSString stringWithFormat:@"%02ld:%02ld", (long)(endMinutes / 60), (long)(endMinutes % 60)];
    SCTimeRange *newWindow = [SCTimeRange rangeWithStart:startStr end:endStr];

    [self.timelineView.allowedWindows addObject:newWindow];
    [self.timelineView setNeedsDisplay:YES];
    [self timelineWindowsChanged];

    [self.timeInputPopover close];
}

- (NSDate *)dateFromMinutes:(NSInteger)minutes {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [[NSDateComponents alloc] init];
    comps.hour = minutes / 60;
    comps.minute = minutes % 60;
    return [calendar dateFromComponents:comps];
}

- (NSInteger)minutesFromDate:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    return comps.hour * 60 + comps.minute;
}

#pragma mark - Sheet Presentation

- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
               completionHandler:(void (^)(NSModalResponse))handler {
    [parentWindow beginSheet:self.window completionHandler:handler];
}

@end
