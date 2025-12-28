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

    // Only show bundle status pills when committed (like week schedule window)
    if (manager.isCommitted) {
        for (SCBlockBundle *bundle in manager.bundles) {
            BOOL allowed = [manager wouldBundleBeAllowed:bundle.bundleID];
            NSString *statusStr = [manager statusStringForBundleID:bundle.bundleID];
            NSString *statusWord = allowed ? @"allowed" : @"blocked";
            NSColor *statusColor = allowed ? [NSColor systemGreenColor] : [NSColor systemRedColor];

            // Format: "● noise allowed till 8:16pm"
            NSString *fullText = [NSString stringWithFormat:@"● %@ %@ %@", bundle.name, statusWord, statusStr];

            NSMenuItem *bundleItem = [[NSMenuItem alloc] initWithTitle:fullText
                                                                action:nil
                                                         keyEquivalent:@""];

            // Create attributed string with colored text
            NSMutableAttributedString *attrTitle = [[NSMutableAttributedString alloc] initWithString:fullText];
            [attrTitle addAttribute:NSForegroundColorAttributeName value:statusColor range:NSMakeRange(0, fullText.length)];
            [attrTitle addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:13] range:NSMakeRange(0, fullText.length)];

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
    }

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

    // Show Week Schedule
    NSMenuItem *scheduleItem = [[NSMenuItem alloc] initWithTitle:@"Show Week Schedule"
                                                          action:@selector(showScheduleClicked:)
                                                   keyEquivalent:@""];
    scheduleItem.target = self;
    [self.statusMenu addItem:scheduleItem];

    // View Blocklist - only when committed
    if (manager.isCommitted) {
        NSString *blocklistTitle = [self blocklistMenuTitle];
        NSMenuItem *blocklistItem = [[NSMenuItem alloc] initWithTitle:blocklistTitle
                                                               action:@selector(showBlocklistClicked:)
                                                        keyEquivalent:@""];
        blocklistItem.target = self;
        [self.statusMenu addItem:blocklistItem];
    }

#ifdef DEBUG
    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    // Debug submenu
    NSMenuItem *debugItem = [[NSMenuItem alloc] initWithTitle:@"Debug Options"
                                                       action:nil
                                                keyEquivalent:@""];
    NSMenu *debugMenu = [[NSMenu alloc] init];

    NSMenuItem *disableBlockingItem = [[NSMenuItem alloc] initWithTitle:@"Disable All Blocking"
                                                                 action:@selector(debugDisableBlocking:)
                                                          keyEquivalent:@""];
    disableBlockingItem.target = self;
    [debugMenu addItem:disableBlockingItem];

    NSMenuItem *resetCreditsItem = [[NSMenuItem alloc] initWithTitle:@"Reset Emergency Credits"
                                                              action:@selector(debugResetCredits:)
                                                       keyEquivalent:@""];
    resetCreditsItem.target = self;
    [debugMenu addItem:resetCreditsItem];

    debugItem.submenu = debugMenu;
    [self.statusMenu addItem:debugItem];
#endif

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    // Quit
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Fence"
                                                      action:@selector(quitClicked:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [self.statusMenu addItem:quitItem];
}

- (NSString *)blocklistMenuTitle {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    NSInteger siteCount = 0;
    NSInteger appCount = 0;

    // Count entries from bundles currently blocking (not in allowed window)
    for (SCBlockBundle *bundle in manager.bundles) {
        if ([manager wouldBundleBeAllowed:bundle.bundleID]) {
            continue; // Skip bundles in allowed window
        }
        for (id entry in bundle.entries) {
            if ([entry isKindOfClass:[NSString class]]) {
                NSString *entryStr = (NSString *)entry;
                if ([entryStr hasPrefix:@"app:"]) {
                    appCount++;
                } else {
                    siteCount++;
                }
            }
        }
    }

    return [NSString stringWithFormat:@"View Blocklist (%ld sites, %ld apps)", (long)siteCount, (long)appCount];
}

- (NSImage *)statusImage {
    // Load the fence image as a template (macOS will handle light/dark mode)
    NSImage *image = [NSImage imageNamed:@"MenuBarFence"];
    [image setTemplate:YES];
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
    self.statusItem.menu = self.statusMenu;
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

- (void)showScheduleClicked:(id)sender {
    if (self.onShowSchedule) {
        self.onShowSchedule();
    } else {
        [self.delegate menuBarControllerDidRequestOpenApp:self];
    }
}

- (void)showBlocklistClicked:(id)sender {
    if (self.onShowBlocklist) {
        self.onShowBlocklist();
    }
}

- (void)quitClicked:(id)sender {
    [NSApp terminate:nil];
}

#ifdef DEBUG
- (void)debugDisableBlocking:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCDebugDisableBlockingRequested" object:nil];
}

- (void)debugResetCredits:(id)sender {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SCDebugResetCreditsRequested" object:nil];
}
#endif

@end
