//
//  SCMenuBarController.m
//  SelfControl
//

#import "SCMenuBarController.h"
#import "Block Management/SCScheduleManager.h"
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCWeeklySchedule.h"

@interface SCMenuBarController ()

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSTimer *updateTimer;

@end

@implementation SCMenuBarController

+ (instancetype)sharedController {
    static SCMenuBarController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SCMenuBarController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isVisible = NO;

        // Listen for schedule changes
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(scheduleDidChange:)
                                                     name:SCScheduleManagerDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.updateTimer invalidate];
}

#pragma mark - Visibility

- (void)setVisible:(BOOL)visible {
    if (_isVisible == visible) return;

    _isVisible = visible;

    if (visible) {
        [self createStatusItem];
        [self startUpdateTimer];
    } else {
        [self removeStatusItem];
        [self stopUpdateTimer];
    }
}

- (void)createStatusItem {
    if (self.statusItem) return;

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    // Set up button
    self.statusItem.button.image = [self statusImage];
    self.statusItem.button.imagePosition = NSImageLeft;

    // Create menu
    [self rebuildMenu];

    self.statusItem.menu = self.statusMenu;
}

- (void)removeStatusItem {
    if (self.statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
        self.statusItem = nil;
    }
}

#pragma mark - Menu Building

- (void)rebuildMenu {
    self.statusMenu = [[NSMenu alloc] init];

    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Header with current time
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"h:mma EEEE";
    NSString *timeStr = [[formatter stringFromDate:[NSDate date]] lowercaseString];

    NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"NOW (%@)", timeStr]
                                                        action:nil
                                                 keyEquivalent:@""];
    headerItem.enabled = NO;
    [self.statusMenu addItem:headerItem];

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    // Bundle statuses
    for (SCBlockBundle *bundle in manager.bundles) {
        BOOL allowed = [manager wouldBundleBeAllowed:bundle.bundleID];
        NSString *statusStr = [manager statusStringForBundleID:bundle.bundleID];

        NSString *icon = allowed ? @"✅" : @"🔒";
        NSString *title = [NSString stringWithFormat:@"%@ %@", icon, bundle.name];

        NSMenuItem *bundleItem = [[NSMenuItem alloc] initWithTitle:title
                                                            action:nil
                                                     keyEquivalent:@""];

        // Add status as attributed subtitle
        NSMutableAttributedString *attrTitle = [[NSMutableAttributedString alloc] initWithString:title];
        [attrTitle appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];

        NSDictionary *subtitleAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        };
        NSAttributedString *subtitle = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"     %@", statusStr]
                                                                       attributes:subtitleAttrs];
        [attrTitle appendAttributedString:subtitle];

        bundleItem.attributedTitle = attrTitle;
        bundleItem.enabled = NO;

        [self.statusMenu addItem:bundleItem];
    }

    if (manager.bundles.count == 0) {
        NSMenuItem *noBundlesItem = [[NSMenuItem alloc] initWithTitle:@"No bundles configured"
                                                               action:nil
                                                        keyEquivalent:@""];
        noBundlesItem.enabled = NO;
        [self.statusMenu addItem:noBundlesItem];
    }

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    // Commitment info
    if (manager.isCommitted) {
        NSDateFormatter *endFormatter = [[NSDateFormatter alloc] init];
        endFormatter.dateFormat = @"EEEE";
        NSString *endDay = [endFormatter stringFromDate:manager.commitmentEndDate];

        NSMenuItem *commitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Committed until %@", endDay]
                                                            action:nil
                                                     keyEquivalent:@""];
        commitItem.enabled = NO;
        [self.statusMenu addItem:commitItem];
    } else {
        NSMenuItem *noCommitItem = [[NSMenuItem alloc] initWithTitle:@"No active commitment"
                                                              action:nil
                                                       keyEquivalent:@""];
        noCommitItem.enabled = NO;
        [self.statusMenu addItem:noCommitItem];
    }

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    // Open SelfControl
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open SelfControl"
                                                      action:@selector(openAppClicked:)
                                               keyEquivalent:@""];
    openItem.target = self;
    [self.statusMenu addItem:openItem];
}

- (NSImage *)statusImage {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Determine state
    BOOL hasActiveBlocking = NO;
    BOOL allAllowed = YES;

    for (SCBlockBundle *bundle in manager.bundles) {
        if (![manager wouldBundleBeAllowed:bundle.bundleID]) {
            hasActiveBlocking = YES;
            allAllowed = NO;
        }
    }

    // Create appropriate icon
    NSImage *image;

    if (manager.bundles.count == 0 || !manager.isCommitted) {
        // Gray circle - no commitment
        image = [self circleImageWithColor:[NSColor tertiaryLabelColor]];
    } else if (allAllowed) {
        // Green - all allowed
        image = [self circleImageWithColor:[NSColor systemGreenColor]];
    } else {
        // Red - something is blocked
        image = [self circleImageWithColor:[NSColor systemRedColor]];
    }

    [image setTemplate:NO];
    return image;
}

- (NSImage *)circleImageWithColor:(NSColor *)color {
    CGFloat size = 16;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];

    [image lockFocus];
    [color setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2, 2, size - 4, size - 4)];
    [path fill];
    [image unlockFocus];

    return image;
}

#pragma mark - Update

- (void)updateStatus {
    if (!self.statusItem) return;

    self.statusItem.button.image = [self statusImage];
    [self rebuildMenu];
}

- (void)startUpdateTimer {
    [self.updateTimer invalidate];

    // Update every minute
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                        target:self
                                                      selector:@selector(timerFired:)
                                                      userInfo:nil
                                                       repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
}

- (void)stopUpdateTimer {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (void)timerFired:(NSTimer *)timer {
    [self updateStatus];
}

#pragma mark - Notifications

- (void)scheduleDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateStatus];
    });
}

#pragma mark - Actions

- (void)openAppClicked:(id)sender {
    [self.delegate menuBarControllerDidRequestOpenApp:self];
}

@end
