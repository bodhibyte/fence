//
//  SCDayScheduleEditorController.m
//  SelfControl
//

#import "SCDayScheduleEditorController.h"

// Constants for timeline view
static const CGFloat kTimelineHeight = 300.0;
static const CGFloat kTimelineWidth = 60.0;
static const CGFloat kSnapMinutes = 15.0;
static const CGFloat kHandleHeight = 8.0;

#pragma mark - SCTimelineView (Private)

@interface SCTimelineView : NSView

@property (nonatomic, strong) NSMutableArray<SCTimeRange *> *allowedWindows;
@property (nonatomic, strong) NSColor *bundleColor;
@property (nonatomic, assign) BOOL isCommitted;
@property (nonatomic, copy, nullable) void (^onWindowsChanged)(void);

// Drag state
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSInteger draggingWindowIndex;
@property (nonatomic, assign) BOOL draggingStartHandle;
@property (nonatomic, assign) BOOL draggingEndHandle;
@property (nonatomic, assign) CGFloat dragStartY;
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

    // Resize handles
    [[NSColor whiteColor] setFill];

    // Top handle
    NSRect topHandle = NSMakeRect(windowRect.origin.x + windowRect.size.width/2 - 15,
                                   startY + 2, 30, kHandleHeight);
    [[NSBezierPath bezierPathWithRoundedRect:topHandle xRadius:2 yRadius:2] fill];

    // Bottom handle
    NSRect bottomHandle = NSMakeRect(windowRect.origin.x + windowRect.size.width/2 - 15,
                                      endY - kHandleHeight - 2, 30, kHandleHeight);
    [[NSBezierPath bezierPathWithRoundedRect:bottomHandle xRadius:2 yRadius:2] fill];

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

    // Check if clicking on existing window handle
    for (NSInteger i = self.allowedWindows.count - 1; i >= 0; i--) {
        SCTimeRange *window = self.allowedWindows[i];
        CGFloat startY = [self yFromMinutes:[window startMinutes]];
        CGFloat endY = [self yFromMinutes:[window endMinutes]];

        // Check top handle
        NSRect topHandle = NSMakeRect(35, startY, self.bounds.size.width - 40, kHandleHeight + 4);
        if (NSPointInRect(point, topHandle)) {
            self.isDragging = YES;
            self.draggingWindowIndex = i;
            self.draggingStartHandle = YES;
            self.draggingEndHandle = NO;
            self.originalDragRange = [window copy];
            return;
        }

        // Check bottom handle
        NSRect bottomHandle = NSMakeRect(35, endY - kHandleHeight - 4, self.bounds.size.width - 40, kHandleHeight + 4);
        if (NSPointInRect(point, bottomHandle)) {
            self.isDragging = YES;
            self.draggingWindowIndex = i;
            self.draggingStartHandle = NO;
            self.draggingEndHandle = YES;
            self.originalDragRange = [window copy];
            return;
        }

        // Check if clicking inside window (to move)
        NSRect windowRect = NSMakeRect(35, startY, self.bounds.size.width - 40, endY - startY);
        if (NSPointInRect(point, windowRect)) {
            // For now, just select - could add move functionality
            return;
        }
    }

    // Clicking on empty space - create new window
    if (!self.isCommitted) {
        NSInteger minutes = [self snapToGrid:[self minutesFromY:point.y]];
        SCTimeRange *newWindow = [SCTimeRange rangeWithStart:[self timeStringFromMinutes:minutes]
                                                         end:[self timeStringFromMinutes:minutes + 60]];
        [self.allowedWindows addObject:newWindow];
        self.isDragging = YES;
        self.draggingWindowIndex = self.allowedWindows.count - 1;
        self.draggingStartHandle = NO;
        self.draggingEndHandle = YES;
        self.dragStartY = point.y;

        [self setNeedsDisplay:YES];
        if (self.onWindowsChanged) self.onWindowsChanged();
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.isDragging || self.draggingWindowIndex < 0) return;

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger minutes = [self snapToGrid:[self minutesFromY:point.y]];
    minutes = MAX(0, MIN(24 * 60 - 1, minutes));

    SCTimeRange *window = self.allowedWindows[self.draggingWindowIndex];

    if (self.draggingStartHandle) {
        // Moving start time
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
    } else if (self.draggingEndHandle) {
        // Moving end time
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
    }

    [self setNeedsDisplay:YES];
    if (self.onWindowsChanged) self.onWindowsChanged();
}

- (void)mouseUp:(NSEvent *)event {
    self.isDragging = NO;
    self.draggingWindowIndex = -1;
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
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 280, 24)];
    self.titleLabel.stringValue = [NSString stringWithFormat:@"%@ - %@",
                                    self.bundle.name,
                                    [SCWeeklySchedule displayNameForDay:self.day]];
    self.titleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
    self.titleLabel.bezeled = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.drawsBackground = NO;
    [contentView addSubview:self.titleLabel];

    // Presets dropdown
    y -= 35;
    NSTextField *presetsLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 60, 20)];
    presetsLabel.stringValue = @"Presets:";
    presetsLabel.font = [NSFont systemFontOfSize:12];
    presetsLabel.bezeled = NO;
    presetsLabel.editable = NO;
    presetsLabel.drawsBackground = NO;
    [contentView addSubview:presetsLabel];

    self.presetsButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(75, y - 2, 200, 24) pullsDown:YES];
    [self.presetsButton addItemWithTitle:@"Apply Preset..."];
    [self.presetsButton addItemWithTitle:@"Work Hours (9am-5pm)"];
    [self.presetsButton addItemWithTitle:@"Extended Work (8am-8pm)"];
    [self.presetsButton addItemWithTitle:@"Waking Hours (7am-11pm)"];
    [self.presetsButton addItemWithTitle:@"All Day (always allowed)"];
    [self.presetsButton addItemWithTitle:@"Clear All (always blocked)"];
    self.presetsButton.target = self;
    self.presetsButton.action = @selector(presetSelected:);
    [contentView addSubview:self.presetsButton];

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

    self.timelineView.wantsLayer = YES;
    self.timelineView.layer.cornerRadius = 8;
    self.timelineView.layer.masksToBounds = YES;
    [contentView addSubview:self.timelineView];

    // Copy from dropdown
    y -= 35;
    NSTextField *copyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 70, 20)];
    copyLabel.stringValue = @"Copy from:";
    copyLabel.font = [NSFont systemFontOfSize:11];
    copyLabel.bezeled = NO;
    copyLabel.editable = NO;
    copyLabel.drawsBackground = NO;
    [contentView addSubview:copyLabel];

    self.duplicateFromDayButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(85, y - 2, 100, 22) pullsDown:YES];
    [self.duplicateFromDayButton addItemWithTitle:@"Select..."];
    for (SCDayOfWeek d = SCDayOfWeekSunday; d <= SCDayOfWeekSaturday; d++) {
        if (d != self.day) {
            [self.duplicateFromDayButton addItemWithTitle:[SCWeeklySchedule shortNameForDay:d]];
        }
    }
    self.duplicateFromDayButton.target = self;
    self.duplicateFromDayButton.action = @selector(copyFromSelected:);
    self.duplicateFromDayButton.font = [NSFont systemFontOfSize:11];
    [contentView addSubview:self.duplicateFromDayButton];

    // Apply to dropdown
    NSTextField *applyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(190, y, 50, 20)];
    applyLabel.stringValue = @"Apply to:";
    applyLabel.font = [NSFont systemFontOfSize:11];
    applyLabel.bezeled = NO;
    applyLabel.editable = NO;
    applyLabel.drawsBackground = NO;
    [contentView addSubview:applyLabel];

    self.applyToButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(240, y - 2, 50, 22) pullsDown:YES];
    [self.applyToButton addItemWithTitle:@"..."];
    [self.applyToButton addItemWithTitle:@"All"];
    [self.applyToButton addItemWithTitle:@"Weekdays"];
    [self.applyToButton addItemWithTitle:@"Weekend"];
    self.applyToButton.target = self;
    self.applyToButton.action = @selector(applyToSelected:);
    self.applyToButton.font = [NSFont systemFontOfSize:11];
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

#pragma mark - Sheet Presentation

- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
               completionHandler:(void (^)(NSModalResponse))handler {
    [parentWindow beginSheet:self.window completionHandler:handler];
}

@end
