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
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];

    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }

    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow)
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

    // Draw "Add Bundle" row if not too many bundles
    if (self.bundles.count < 8) {
        [self drawAddBundleRow];
    }

    // Draw grid lines
    [self drawGridLines:days];
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

    // Check if this cell is highlighted
    BOOL isHighlighted = [self.highlightedBundleID isEqualToString:bundle.bundleID] &&
                         self.highlightedDay == day;

    // Cell background
    if (isHighlighted) {
        [[NSColor selectedContentBackgroundColor] setFill];
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
}

- (void)drawAddBundleRow {
    NSUInteger bundleCount = self.bundles.count;
    CGFloat y = self.bounds.size.height - kHeaderHeight - (bundleCount + 1) * kRowHeight;
    NSRect rowRect = NSMakeRect(0, y, self.bounds.size.width, kRowHeight);

    // Draw "+" button area
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:24 weight:NSFontWeightLight],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };

    NSString *plusSign = @"+";
    NSSize textSize = [plusSign sizeWithAttributes:attrs];
    NSPoint textPoint = NSMakePoint(
        (kBundleLabelWidth - textSize.width) / 2,
        rowRect.origin.y + (rowRect.size.height - textSize.height) / 2
    );
    [plusSign drawAtPoint:textPoint withAttributes:attrs];

    // Label
    NSDictionary *labelAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]
    };
    NSString *label = @"Add Bundle";
    NSSize labelSize = [label sizeWithAttributes:labelAttrs];
    NSPoint labelPoint = NSMakePoint(
        textPoint.x + textSize.width + 4,
        rowRect.origin.y + (rowRect.size.height - labelSize.height) / 2
    );
    [label drawAtPoint:labelPoint withAttributes:labelAttrs];
}

- (void)drawGridLines:(NSArray<NSNumber *> *)days {
    [[NSColor separatorColor] setStroke];
    NSBezierPath *gridPath = [NSBezierPath bezierPath];

    // Horizontal lines
    for (NSUInteger i = 0; i <= self.bundles.count + 1; i++) {
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

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];

    NSArray<NSNumber *> *days = [self daysToShow];
    NSUInteger dayCount = days.count;

    // Check if clicked on "Add Bundle" row
    if (self.bundles.count < 8) {
        CGFloat addRowY = self.bounds.size.height - kHeaderHeight - (self.bundles.count + 1) * kRowHeight;
        NSRect addRowRect = NSMakeRect(0, addRowY, kBundleLabelWidth, kRowHeight);
        if (NSPointInRect(point, addRowRect)) {
            [self.delegate weekGridViewDidRequestAddBundle:self];
            return;
        }
    }

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
    CGFloat height = kHeaderHeight + (self.bundles.count + 1) * kRowHeight;
    return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

- (BOOL)isFlipped {
    return NO; // Use standard coordinate system (origin at bottom-left)
}

@end
