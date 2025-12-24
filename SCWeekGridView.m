//
//  SCWeekGridView.m
//  SelfControl
//

#import "SCWeekGridView.h"
#import "Block Management/SCScheduleManager.h"

// Layout constants
static const CGFloat kRowHeight = 60.0;
static const CGFloat kHeaderHeight = 30.0;
static const CGFloat kBundleLabelWidth = 120.0;
static const CGFloat kCellPadding = 4.0;
static const CGFloat kTimelineHeight = 48.0;

@interface SCWeekGridView ()

@property (nonatomic, strong, nullable) NSString *highlightedBundleID;
@property (nonatomic, assign) SCDayOfWeek highlightedDay;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) NSPoint lastMousePoint;

// Hover tracking
@property (nonatomic, assign) NSInteger hoveredBundleIndex;
@property (nonatomic, assign) NSInteger hoveredDayIndex;
@property (nonatomic, assign) BOOL isHoveringBundleLabel;

@end

@implementation SCWeekGridView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _showOnlyRemainingDays = YES;
    _weekStartsOnMonday = YES;
    _isCommitted = NO;
    _highlightedDay = -1;
    _hoveredBundleIndex = -1;
    _hoveredDayIndex = -1;
    _isHoveringBundleLabel = NO;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }

    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:(NSTrackingMouseMoved |
                                                              NSTrackingMouseEnteredAndExited |
                                                              NSTrackingActiveInKeyWindow)
                                                       owner:self
                                                    userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

#pragma mark - Data

- (void)reloadData {
    [self setNeedsDisplay:YES];
}

- (nullable SCWeeklySchedule *)scheduleForBundle:(SCBlockBundle *)bundle {
    for (SCWeeklySchedule *schedule in self.schedules) {
        if ([schedule.bundleID isEqualToString:bundle.bundleID]) {
            return schedule;
        }
    }
    return nil;
}

- (NSArray<NSNumber *> *)daysToShow {
    if (self.showOnlyRemainingDays) {
        return [SCWeeklySchedule remainingDaysInWeekStartingMonday:self.weekStartsOnMonday];
    }
    return [SCWeeklySchedule allDaysStartingMonday:self.weekStartsOnMonday];
}

#pragma mark - Layout Calculations

- (CGFloat)cellWidthForDayCount:(NSUInteger)dayCount {
    CGFloat availableWidth = self.bounds.size.width - kBundleLabelWidth;
    return availableWidth / dayCount;
}

- (NSRect)rectForBundleLabel:(NSUInteger)bundleIndex {
    CGFloat y = self.bounds.size.height - kHeaderHeight - (bundleIndex + 1) * kRowHeight;
    return NSMakeRect(0, y, kBundleLabelWidth, kRowHeight);
}

- (NSRect)rectForCell:(NSUInteger)bundleIndex dayIndex:(NSUInteger)dayIndex dayCount:(NSUInteger)dayCount {
    CGFloat cellWidth = [self cellWidthForDayCount:dayCount];
    CGFloat x = kBundleLabelWidth + dayIndex * cellWidth;
    CGFloat y = self.bounds.size.height - kHeaderHeight - (bundleIndex + 1) * kRowHeight;
    return NSMakeRect(x, y, cellWidth, kRowHeight);
}

- (NSRect)rectForDayHeader:(NSUInteger)dayIndex dayCount:(NSUInteger)dayCount {
    CGFloat cellWidth = [self cellWidthForDayCount:dayCount];
    CGFloat x = kBundleLabelWidth + dayIndex * cellWidth;
    CGFloat y = self.bounds.size.height - kHeaderHeight;
    return NSMakeRect(x, y, cellWidth, kHeaderHeight);
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);

    NSArray<NSNumber *> *days = [self daysToShow];
    NSUInteger dayCount = days.count;

    if (dayCount == 0) return;

    // Draw day headers
    [self drawDayHeaders:days];

    // Draw bundle rows
    for (NSUInteger i = 0; i < self.bundles.count; i++) {
        SCBlockBundle *bundle = self.bundles[i];
        SCWeeklySchedule *schedule = [self scheduleForBundle:bundle];

        // Draw bundle label
        [self drawBundleLabel:bundle atIndex:i];

        // Draw cells for each day
        for (NSUInteger j = 0; j < dayCount; j++) {
            SCDayOfWeek day = [days[j] integerValue];
            [self drawCellForBundle:bundle
                           schedule:schedule
                                day:day
                        bundleIndex:i
                           dayIndex:j
                           dayCount:dayCount];
        }
    }

    // Draw grid lines
    [self drawGridLines:days];

    // Draw continuous NOW line across all bundles for today
    [self drawNowLine:days];
}

- (void)drawDayHeaders:(NSArray<NSNumber *> *)days {
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    };

    SCDayOfWeek today = [SCWeeklySchedule today];

    for (NSUInteger i = 0; i < days.count; i++) {
        SCDayOfWeek day = [days[i] integerValue];
        NSRect headerRect = [self rectForDayHeader:i dayCount:days.count];

        // Highlight today
        if (day == today) {
            [[NSColor controlAccentColor] setFill];
            NSRect highlightRect = NSInsetRect(headerRect, 2, 2);
            highlightRect.size.height -= 2;
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:highlightRect xRadius:4 yRadius:4];
            [path fill];

            attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold],
                NSForegroundColorAttributeName: [NSColor whiteColor]
            };
        } else {
            attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
            };
        }

        NSString *dayName = [SCWeeklySchedule shortNameForDay:day];
        NSSize textSize = [dayName sizeWithAttributes:attrs];
        NSPoint textPoint = NSMakePoint(
            headerRect.origin.x + (headerRect.size.width - textSize.width) / 2,
            headerRect.origin.y + (headerRect.size.height - textSize.height) / 2
        );
        [dayName drawAtPoint:textPoint withAttributes:attrs];
    }
}

- (void)drawBundleLabel:(SCBlockBundle *)bundle atIndex:(NSUInteger)index {
    NSRect labelRect = [self rectForBundleLabel:index];

    // Check if this label is hovered
    BOOL isHovered = (self.hoveredBundleIndex == (NSInteger)index && self.isHoveringBundleLabel);

    // Draw hover background
    if (isHovered) {
        NSRect hoverRect = NSInsetRect(labelRect, 4, 4);
        [[[NSColor controlBackgroundColor] blendedColorWithFraction:0.15 ofColor:[NSColor blackColor]] setFill];
        NSBezierPath *hoverPath = [NSBezierPath bezierPathWithRoundedRect:hoverRect xRadius:4 yRadius:4];
        [hoverPath fill];
    }

    // Color indicator
    NSRect colorRect = NSMakeRect(labelRect.origin.x + 8,
                                   labelRect.origin.y + (labelRect.size.height - 12) / 2,
                                   12, 12);
    [bundle.color setFill];
    NSBezierPath *colorPath = [NSBezierPath bezierPathWithOvalInRect:colorRect];
    [colorPath fill];

    // Bundle name
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };

    NSRect textRect = NSMakeRect(colorRect.origin.x + 18,
                                  labelRect.origin.y,
                                  kBundleLabelWidth - 30,
                                  labelRect.size.height);

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineBreakMode = NSLineBreakByTruncatingTail;

    NSMutableDictionary *textAttrs = [attrs mutableCopy];
    textAttrs[NSParagraphStyleAttributeName] = para;

    NSSize textSize = [bundle.name sizeWithAttributes:textAttrs];
    NSPoint textPoint = NSMakePoint(textRect.origin.x,
                                     textRect.origin.y + (textRect.size.height - textSize.height) / 2);
    [bundle.name drawAtPoint:textPoint withAttributes:textAttrs];
}

- (void)drawCellForBundle:(SCBlockBundle *)bundle
                 schedule:(SCWeeklySchedule *)schedule
                      day:(SCDayOfWeek)day
              bundleIndex:(NSUInteger)bundleIndex
                 dayIndex:(NSUInteger)dayIndex
                 dayCount:(NSUInteger)dayCount {

    NSRect cellRect = [self rectForCell:bundleIndex dayIndex:dayIndex dayCount:dayCount];
    NSRect innerRect = NSInsetRect(cellRect, kCellPadding, kCellPadding);

    // Check if this cell is highlighted (for copy/paste)
    BOOL isHighlighted = [self.highlightedBundleID isEqualToString:bundle.bundleID] &&
                         self.highlightedDay == day;

    // Check if this cell is hovered
    BOOL isHovered = (self.hoveredBundleIndex == (NSInteger)bundleIndex &&
                      self.hoveredDayIndex == (NSInteger)dayIndex &&
                      !self.isHoveringBundleLabel);

    // Cell background
    if (isHighlighted) {
        [[NSColor selectedContentBackgroundColor] setFill];
    } else if (isHovered) {
        // Darker background on hover
        [[[NSColor controlBackgroundColor] blendedColorWithFraction:0.15 ofColor:[NSColor blackColor]] setFill];
    } else {
        [[NSColor controlBackgroundColor] setFill];
    }
    NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:innerRect xRadius:6 yRadius:6];
    [bgPath fill];

    // Draw timeline
    [self drawTimelineInRect:innerRect schedule:schedule day:day bundleColor:bundle.color];
}

- (void)drawTimelineInRect:(NSRect)rect
                  schedule:(SCWeeklySchedule *)schedule
                       day:(SCDayOfWeek)day
               bundleColor:(NSColor *)color {

    // Timeline bar area
    CGFloat timelineY = rect.origin.y + (rect.size.height - kTimelineHeight) / 2;
    NSRect timelineRect = NSMakeRect(rect.origin.x + 4, timelineY, rect.size.width - 8, kTimelineHeight);

    // Background (blocked = gray)
    [[NSColor tertiaryLabelColor] setFill];
    NSBezierPath *bgPath = [NSBezierPath bezierPathWithRoundedRect:timelineRect xRadius:4 yRadius:4];
    [bgPath fill];

    if (!schedule) return;

    // Draw allowed windows as colored bars
    NSArray<SCTimeRange *> *windows = [schedule allowedWindowsForDay:day];

    for (SCTimeRange *window in windows) {
        CGFloat startPercent = [window startMinutes] / (24.0 * 60.0);
        CGFloat endPercent = [window endMinutes] / (24.0 * 60.0);

        CGFloat startX = timelineRect.origin.x + startPercent * timelineRect.size.width;
        CGFloat endX = timelineRect.origin.x + endPercent * timelineRect.size.width;

        NSRect windowRect = NSMakeRect(startX, timelineRect.origin.y,
                                        endX - startX, timelineRect.size.height);

        // Use bundle color with some transparency
        [[color colorWithAlphaComponent:0.8] setFill];
        NSBezierPath *windowPath = [NSBezierPath bezierPathWithRoundedRect:windowRect xRadius:2 yRadius:2];
        [windowPath fill];
    }

    // Draw time markers (6am, 12pm, 6pm)
    [[NSColor quaternaryLabelColor] setStroke];
    NSBezierPath *markerPath = [NSBezierPath bezierPath];

    CGFloat markers[] = {0.25, 0.5, 0.75}; // 6am, 12pm, 6pm
    for (int i = 0; i < 3; i++) {
        CGFloat x = timelineRect.origin.x + markers[i] * timelineRect.size.width;
        [markerPath moveToPoint:NSMakePoint(x, timelineRect.origin.y)];
        [markerPath lineToPoint:NSMakePoint(x, timelineRect.origin.y + timelineRect.size.height)];
    }
    [markerPath setLineWidth:0.5];
    [markerPath stroke];

    // NOW line is drawn separately at grid level for continuity across rows
}

- (void)drawNowLine:(NSArray<NSNumber *> *)days {
    // Find if today is visible
    SCDayOfWeek today = [SCWeeklySchedule today];
    NSInteger todayIndex = -1;

    for (NSUInteger i = 0; i < days.count; i++) {
        if ([days[i] integerValue] == today) {
            todayIndex = i;
            break;
        }
    }

    if (todayIndex < 0 || self.bundles.count == 0) return;

    // Calculate current time as percentage of day
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *comps = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:[NSDate date]];
    CGFloat nowPercent = (comps.hour * 60 + comps.minute) / (24.0 * 60.0);

    // Get the X position within today's column
    NSUInteger dayCount = days.count;
    CGFloat cellWidth = [self cellWidthForDayCount:dayCount];
    CGFloat cellX = kBundleLabelWidth + todayIndex * cellWidth;

    // The timeline inside each cell has padding
    CGFloat timelineLeft = cellX + kCellPadding + 4;
    CGFloat timelineWidth = cellWidth - kCellPadding * 2 - 8;
    CGFloat nowX = timelineLeft + nowPercent * timelineWidth;

    // Calculate Y range: from first bundle row to last
    CGFloat topY = self.bounds.size.height - kHeaderHeight;
    CGFloat bottomY = self.bounds.size.height - kHeaderHeight - self.bundles.count * kRowHeight;

    // Draw the continuous red line
    [[NSColor systemRedColor] setStroke];
    NSBezierPath *nowPath = [NSBezierPath bezierPath];
    [nowPath setLineWidth:2.0];
    [nowPath moveToPoint:NSMakePoint(nowX, bottomY)];
    [nowPath lineToPoint:NSMakePoint(nowX, topY)];
    [nowPath stroke];
}

- (void)drawGridLines:(NSArray<NSNumber *> *)days {
    [[NSColor separatorColor] setStroke];
    NSBezierPath *gridPath = [NSBezierPath bezierPath];

    // Horizontal lines
    for (NSUInteger i = 0; i <= self.bundles.count; i++) {
        CGFloat y = self.bounds.size.height - kHeaderHeight - i * kRowHeight;
        [gridPath moveToPoint:NSMakePoint(0, y)];
        [gridPath lineToPoint:NSMakePoint(self.bounds.size.width, y)];
    }

    // Vertical line after bundle labels
    [gridPath moveToPoint:NSMakePoint(kBundleLabelWidth, 0)];
    [gridPath lineToPoint:NSMakePoint(kBundleLabelWidth, self.bounds.size.height)];

    [gridPath setLineWidth:0.5];
    [gridPath stroke];
}

#pragma mark - Mouse Handling

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self updateHoverStateForPoint:point];
}

- (void)mouseExited:(NSEvent *)event {
    self.hoveredBundleIndex = -1;
    self.hoveredDayIndex = -1;
    self.isHoveringBundleLabel = NO;
    [[NSCursor arrowCursor] set];
    [self setNeedsDisplay:YES];
}

- (void)updateHoverStateForPoint:(NSPoint)point {
    NSArray<NSNumber *> *days = [self daysToShow];
    NSUInteger dayCount = days.count;

    NSInteger newBundleIndex = -1;
    NSInteger newDayIndex = -1;
    BOOL newIsHoveringLabel = NO;

    // Check which element is under the mouse
    for (NSUInteger i = 0; i < self.bundles.count; i++) {
        // Check bundle label
        NSRect labelRect = [self rectForBundleLabel:i];
        if (NSPointInRect(point, labelRect)) {
            newBundleIndex = i;
            newIsHoveringLabel = YES;
            break;
        }

        // Check day cells
        for (NSUInteger j = 0; j < dayCount; j++) {
            NSRect cellRect = [self rectForCell:i dayIndex:j dayCount:dayCount];
            if (NSPointInRect(point, cellRect)) {
                newBundleIndex = i;
                newDayIndex = j;
                break;
            }
        }
        if (newBundleIndex >= 0) break;
    }

    // Update state if changed
    if (newBundleIndex != self.hoveredBundleIndex ||
        newDayIndex != self.hoveredDayIndex ||
        newIsHoveringLabel != self.isHoveringBundleLabel) {

        self.hoveredBundleIndex = newBundleIndex;
        self.hoveredDayIndex = newDayIndex;
        self.isHoveringBundleLabel = newIsHoveringLabel;

        // Update cursor
        if (newBundleIndex >= 0) {
            [[NSCursor pointingHandCursor] set];
        } else {
            [[NSCursor arrowCursor] set];
        }

        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSArray<NSNumber *> *days = [self daysToShow];
    NSUInteger dayCount = days.count;

    // Check which cell was clicked
    for (NSUInteger i = 0; i < self.bundles.count; i++) {
        SCBlockBundle *bundle = self.bundles[i];

        // Check bundle label (for editing bundle)
        NSRect labelRect = [self rectForBundleLabel:i];
        if (NSPointInRect(point, labelRect)) {
            [self.delegate weekGridView:self didRequestEditBundle:bundle];
            return;
        }

        // Check day cells
        for (NSUInteger j = 0; j < dayCount; j++) {
            NSRect cellRect = [self rectForCell:i dayIndex:j dayCount:dayCount];
            if (NSPointInRect(point, cellRect)) {
                SCDayOfWeek day = [days[j] integerValue];
                [self.delegate weekGridView:self didSelectBundle:bundle forDay:day];
                return;
            }
        }
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSArray<NSNumber *> *days = [self daysToShow];
    NSUInteger dayCount = days.count;

    // Check which cell was right-clicked
    for (NSUInteger i = 0; i < self.bundles.count; i++) {
        SCBlockBundle *bundle = self.bundles[i];

        for (NSUInteger j = 0; j < dayCount; j++) {
            NSRect cellRect = [self rectForCell:i dayIndex:j dayCount:dayCount];
            if (NSPointInRect(point, cellRect)) {
                SCDayOfWeek day = [days[j] integerValue];
                if ([self.delegate respondsToSelector:@selector(weekGridView:didRightClickBundle:forDay:atPoint:)]) {
                    [self.delegate weekGridView:self didRightClickBundle:bundle forDay:day atPoint:point];
                }
                return;
            }
        }
    }
}

#pragma mark - Highlighting

- (void)highlightCellForBundle:(NSString *)bundleID day:(SCDayOfWeek)day {
    self.highlightedBundleID = bundleID;
    self.highlightedDay = day;
    [self setNeedsDisplay:YES];
}

- (void)clearCellHighlight {
    self.highlightedBundleID = nil;
    self.highlightedDay = -1;
    [self setNeedsDisplay:YES];
}

#pragma mark - Intrinsic Size

- (NSSize)intrinsicContentSize {
    CGFloat height = kHeaderHeight + self.bundles.count * kRowHeight;
    return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

- (BOOL)isFlipped {
    return NO; // Use standard coordinate system (origin at bottom-left)
}

@end
