//
//  SCWeekScheduleWindowController.m
//  SelfControl
//

#import "SCWeekScheduleWindowController.h"
#import "SCWeekGridView.h"
#import "SCBundleSidebarView.h"
#import "SCCalendarGridView.h"
#import "SCDayScheduleEditorController.h"
#import "SCBundleEditorController.h"
#import "SCMenuBarController.h"
#import "SCUIUtilities.h"
#import "Block Management/SCScheduleManager.h"
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCWeeklySchedule.h"
#import "Common/SCLicenseManager.h"
#import "SCLicenseWindowController.h"

// Feature flag to switch between old grid and new calendar UI
static BOOL const kUseCalendarUI = YES;

@interface SCWeekScheduleWindowController () <SCWeekGridViewDelegate,
                                               SCBundleSidebarViewDelegate,
                                               SCCalendarGridViewDelegate,
                                               SCDayScheduleEditorDelegate,
                                               SCBundleEditorDelegate,
                                               SCMenuBarControllerDelegate>

// UI Elements
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *weekLabel;
@property (nonatomic, strong) NSView *statusView;
@property (nonatomic, strong) NSStackView *statusStackView;
@property (nonatomic, strong) SCWeekGridView *weekGridView;
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) NSButton *addBundleButton;
@property (nonatomic, strong) NSButton *emergencyUnlockButton;
@property (nonatomic, strong) NSButton *commitButton;
@property (nonatomic, strong) NSTextField *commitmentLabel;

// New Calendar UI Elements
@property (nonatomic, strong) SCBundleSidebarView *bundleSidebar;
@property (nonatomic, strong) SCCalendarGridView *calendarGridView;
@property (nonatomic, copy, nullable) NSString *focusedBundleID;  // nil = All-Up state

// Week navigation
@property (nonatomic, strong) NSButton *prevWeekButton;
@property (nonatomic, strong) NSButton *nextWeekButton;
@property (nonatomic, assign) NSInteger currentWeekOffset; // 0 = this week, 1 = next week
@property (nonatomic, assign) NSInteger editingWeekOffset; // Week offset when day editor was opened

// Child controllers
@property (nonatomic, strong, nullable) SCDayScheduleEditorController *dayEditorController;
@property (nonatomic, strong, nullable) SCBundleEditorController *bundleEditorController;
@property (nonatomic, strong, nullable) SCLicenseWindowController *licenseWindowController;

// Flag to prevent redundant reloadData when grid updates schedule
@property (nonatomic, assign) BOOL isUpdatingFromGrid;

@end

@implementation SCWeekScheduleWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1440, 1116);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Fence - Week Schedule";
    window.minSize = NSMakeSize(600, 500);
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
        [self setupMenuBar];
        [self setupNotifications];
        [self reloadData];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    // Apply frosted glass styling
    [SCUIUtilities applyFrostedGlassStyleToWindow:self.window];

    // Create frosted glass background view
    NSVisualEffectView *frostedBackground = [SCUIUtilities createFrostedGlassViewWithFrame:contentView.bounds cornerRadius:16.0];
    frostedBackground.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:frostedBackground positioned:NSWindowBelow relativeTo:nil];

    CGFloat padding = 16;
    CGFloat y = contentView.bounds.size.height - padding;

    // Title
    y -= 30;
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, 200, 24)];
    self.titleLabel.stringValue = @"Fence";
    self.titleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
    self.titleLabel.bezeled = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.autoresizingMask = NSViewMinYMargin; // Stay pinned to top
    [contentView addSubview:self.titleLabel];

    // Week navigation (right side): [< This Week] [Week Label] [Next Week >]
    CGFloat navX = contentView.bounds.size.width - 350 - padding;

    // Previous week button (This Week)
    self.prevWeekButton = [[NSButton alloc] initWithFrame:NSMakeRect(navX, y, 90, 24)];
    self.prevWeekButton.title = @"This Week";
    self.prevWeekButton.bezelStyle = NSBezelStyleRounded;
    self.prevWeekButton.font = [NSFont systemFontOfSize:11];
    self.prevWeekButton.target = self;
    self.prevWeekButton.action = @selector(navigateToPrevWeek:);
    self.prevWeekButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    self.prevWeekButton.enabled = NO; // Disabled when on current week
    [contentView addSubview:self.prevWeekButton];

    // Week label (center of navigation)
    self.weekLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(navX + 95, y, 160, 24)];
    self.weekLabel.alignment = NSTextAlignmentCenter;
    self.weekLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.weekLabel.textColor = [NSColor labelColor];
    self.weekLabel.bezeled = NO;
    self.weekLabel.editable = NO;
    self.weekLabel.drawsBackground = NO;
    self.weekLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [self updateWeekLabel];
    [contentView addSubview:self.weekLabel];

    // Next week button
    self.nextWeekButton = [[NSButton alloc] initWithFrame:NSMakeRect(navX + 260, y, 90, 24)];
    self.nextWeekButton.title = @"Next Week →";
    self.nextWeekButton.bezelStyle = NSBezelStyleRounded;
    self.nextWeekButton.font = [NSFont systemFontOfSize:11];
    self.nextWeekButton.target = self;
    self.nextWeekButton.action = @selector(navigateToNextWeek:);
    self.nextWeekButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [contentView addSubview:self.nextWeekButton];

    // Status view - use semi-transparent background to work with frosted glass
    y -= 55; // 50px height + 5px gap
    self.statusView = [[NSView alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 50)];
    self.statusView.wantsLayer = YES;
    self.statusView.layer.backgroundColor = [[NSColor.whiteColor colorWithAlphaComponent:0.1] CGColor];
    self.statusView.layer.cornerRadius = 8;
    self.statusView.layer.borderWidth = 1.0;
    self.statusView.layer.borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.15].CGColor;
    self.statusView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin; // Stay pinned to top
    [contentView addSubview:self.statusView];

    self.statusStackView = [[NSStackView alloc] initWithFrame:NSMakeRect(12, 8, self.statusView.bounds.size.width - 24, 34)];
    self.statusStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.statusStackView.spacing = 8;
    self.statusStackView.alignment = NSLayoutAttributeCenterY;
    self.statusStackView.distribution = NSStackViewDistributionFill; // Pills size to content
    self.statusStackView.autoresizingMask = NSViewWidthSizable;
    [self.statusView addSubview:self.statusStackView];

    // Main content area - either old grid or new calendar UI
    CGFloat bottomControlsHeight = 85; // Space for buttons at bottom
    CGFloat mainAreaHeight = y - bottomControlsHeight;
    CGFloat sidebarWidth = 180;

    if (kUseCalendarUI) {
        // NEW CALENDAR UI: Sidebar on left + Calendar on right

        // Bundle sidebar
        self.bundleSidebar = [[SCBundleSidebarView alloc] initWithFrame:NSMakeRect(padding, bottomControlsHeight, sidebarWidth, mainAreaHeight)];
        self.bundleSidebar.delegate = self;
        self.bundleSidebar.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
        [contentView addSubview:self.bundleSidebar];

        // Calendar grid (to the right of sidebar)
        CGFloat calendarX = padding + sidebarWidth + padding;
        CGFloat calendarWidth = contentView.bounds.size.width - calendarX - padding;
        self.calendarGridView = [[SCCalendarGridView alloc] initWithFrame:NSMakeRect(calendarX, bottomControlsHeight, calendarWidth, mainAreaHeight)];
        self.calendarGridView.delegate = self;
        self.calendarGridView.showOnlyRemainingDays = YES;
        self.calendarGridView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [contentView addSubview:self.calendarGridView];

    } else {
        // OLD GRID UI: Week grid takes full width
        self.gridScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding, bottomControlsHeight, contentView.bounds.size.width - padding * 2, mainAreaHeight)];
        self.gridScrollView.hasVerticalScroller = YES;
        self.gridScrollView.hasHorizontalScroller = NO;
        self.gridScrollView.autohidesScrollers = YES;
        self.gridScrollView.borderType = NSNoBorder;
        self.gridScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        self.weekGridView = [[SCWeekGridView alloc] initWithFrame:NSMakeRect(0, 0, self.gridScrollView.bounds.size.width, 300)];
        self.weekGridView.delegate = self;
        self.weekGridView.showOnlyRemainingDays = YES;

        self.gridScrollView.documentView = self.weekGridView;
        [contentView addSubview:self.gridScrollView];
    }

    // Bottom buttons - positioned at fixed location above window bottom
    CGFloat buttonY = 45;

    // Add Bundle button (only in old UI, sidebar has its own in new UI)
    if (!kUseCalendarUI) {
        self.addBundleButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, buttonY, 120, 30)];
        self.addBundleButton.title = @"+ Add Bundle";
        self.addBundleButton.bezelStyle = NSBezelStyleRounded;
        self.addBundleButton.target = self;
        self.addBundleButton.action = @selector(addBundleClicked:);
        self.addBundleButton.autoresizingMask = NSViewMaxYMargin;
        [contentView addSubview:self.addBundleButton];
    }

    // Emergency Unlock button (red, next to commit button)
    self.emergencyUnlockButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 150 - 10 - 160, buttonY, 160, 30)];
    self.emergencyUnlockButton.bezelStyle = NSBezelStyleRounded;
    self.emergencyUnlockButton.target = self;
    self.emergencyUnlockButton.action = @selector(emergencyUnlockClicked:);
    self.emergencyUnlockButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; // Stay at bottom-right
    [self updateEmergencyButtonTitle:@"Emergency Unlock (5)"];
    [contentView addSubview:self.emergencyUnlockButton];

    self.commitButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 150, buttonY, 150, 30)];
    self.commitButton.title = @"Commit to Week";
    self.commitButton.bezelStyle = NSBezelStyleRounded;
    self.commitButton.target = self;
    self.commitButton.action = @selector(commitClicked:);
    self.commitButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; // Stay at bottom-right
    [contentView addSubview:self.commitButton];

    // Commitment label - below the commit button
    self.commitmentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 200, buttonY - 20, 200, 20)];
    self.commitmentLabel.alignment = NSTextAlignmentRight;
    self.commitmentLabel.font = [NSFont systemFontOfSize:11];
    self.commitmentLabel.textColor = [NSColor secondaryLabelColor];
    self.commitmentLabel.bezeled = NO;
    self.commitmentLabel.editable = NO;
    self.commitmentLabel.drawsBackground = NO;
    self.commitmentLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; // Stay at bottom-right
    [contentView addSubview:self.commitmentLabel];
}

- (void)setupMenuBar {
    SCMenuBarController *menuBar = [SCMenuBarController sharedController];
    menuBar.delegate = self;
    [menuBar setVisible:YES];
}

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scheduleDidChange:)
                                                 name:SCScheduleManagerDidChangeNotification
                                               object:nil];

    // Observe window resize to update grid layout
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResize:)
                                                 name:NSWindowDidResizeNotification
                                               object:self.window];

    // Observe request to show this window (from test block completion)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showWeekScheduleWindowRequested:)
                                                 name:@"SCShowWeekScheduleWindow"
                                               object:nil];
}

- (void)showWeekScheduleWindowRequested:(NSNotification*)note {
    [self.window makeKeyAndOrderFront:nil];
}

- (void)windowDidResize:(NSNotification *)note {
    // Update grid view height when window resizes (e.g., fullscreen)
    [self reloadData];
}

#pragma mark - Data

- (void)reloadData {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    BOOL isCommitted = [manager isCommittedForWeekOffset:self.currentWeekOffset];

    if (kUseCalendarUI) {
        // NEW CALENDAR UI: Update sidebar and calendar

        // Update sidebar
        self.bundleSidebar.bundles = manager.bundles;
        self.bundleSidebar.selectedBundleID = self.focusedBundleID;
        self.bundleSidebar.isCommitted = isCommitted;
        [self.bundleSidebar reloadData];

        // Update calendar grid
        self.calendarGridView.bundles = manager.bundles;

        // Build schedules dictionary
        NSMutableDictionary *scheduleDict = [NSMutableDictionary dictionary];
        for (SCBlockBundle *bundle in manager.bundles) {
            SCWeeklySchedule *schedule = [manager scheduleForBundleID:bundle.bundleID weekOffset:self.currentWeekOffset];
            if (schedule) {
                scheduleDict[bundle.bundleID] = schedule;
            }
        }
        self.calendarGridView.schedules = scheduleDict;

        self.calendarGridView.focusedBundleID = self.focusedBundleID;
        self.calendarGridView.isCommitted = isCommitted;
        self.calendarGridView.showOnlyRemainingDays = (self.currentWeekOffset == 0);
        self.calendarGridView.weekOffset = self.currentWeekOffset;
        [self.calendarGridView reloadData];

    } else {
        // OLD GRID UI: Update grid with week-specific data
        self.weekGridView.bundles = manager.bundles;
        self.weekGridView.schedules = [manager schedulesForWeekOffset:self.currentWeekOffset];
        self.weekGridView.isCommitted = isCommitted;
        self.weekGridView.showOnlyRemainingDays = (self.currentWeekOffset == 0);
        self.weekGridView.weekOffset = self.currentWeekOffset;
        [self.weekGridView reloadData];
    }

    // Update status (only for current week)
    [self updateStatusLabel];

    // Update commitment UI
    [self updateCommitmentUI];

    // Update week label
    [self updateWeekLabel];

    // Update navigation buttons
    [self updateNavigationButtons];

    // Resize grid to fit content - MUST be at least as tall as scroll view
    // In non-flipped coordinates, a smaller document view pins to BOTTOM (y=0)
    // Making it at least viewport height ensures content appears at top
    CGFloat contentHeight = 30 + manager.bundles.count * 60;
    CGFloat viewportHeight = self.gridScrollView.contentSize.height;
    CGFloat gridHeight = MAX(contentHeight, viewportHeight);

    NSRect gridFrame = self.weekGridView.frame;
    gridFrame.size.width = self.gridScrollView.contentSize.width; // Update width too
    gridFrame.size.height = gridHeight;
    self.weekGridView.frame = gridFrame;
}

- (void)updateStatusLabel {
    // Clear existing pills
    for (NSView *subview in [self.statusStackView.arrangedSubviews copy]) {
        [self.statusStackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }

    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Only show blocking status when committed
    if (![manager isCommittedForWeekOffset:0]) {
        NSTextField *uncommittedLabel = [NSTextField labelWithString:@"No active schedule - do you have the courage to commit?"];
        uncommittedLabel.font = [NSFont systemFontOfSize:12];
        uncommittedLabel.textColor = [NSColor secondaryLabelColor];
        [self.statusStackView addArrangedSubview:uncommittedLabel];
        return;
    }

    if (manager.bundles.count == 0) {
        NSTextField *emptyLabel = [NSTextField labelWithString:@"No bundles configured. Add a bundle to get started."];
        emptyLabel.font = [NSFont systemFontOfSize:12];
        emptyLabel.textColor = [NSColor secondaryLabelColor];
        [self.statusStackView addArrangedSubview:emptyLabel];
        return;
    }

    for (SCBlockBundle *bundle in manager.bundles) {
        BOOL allowed = [manager wouldBundleBeAllowed:bundle.bundleID];
        NSString *statusStr = [manager statusStringForBundleID:bundle.bundleID];

        // Create pill container
        NSView *pill = [[NSView alloc] init];
        pill.wantsLayer = YES;
        pill.layer.cornerRadius = 6;

        // Set background color based on allowed/blocked state
        if (allowed) {
            pill.layer.backgroundColor = [[NSColor systemGreenColor] colorWithAlphaComponent:0.25].CGColor;
            pill.layer.borderColor = [[NSColor systemGreenColor] colorWithAlphaComponent:0.5].CGColor;
        } else {
            pill.layer.backgroundColor = [[NSColor systemRedColor] colorWithAlphaComponent:0.25].CGColor;
            pill.layer.borderColor = [[NSColor systemRedColor] colorWithAlphaComponent:0.5].CGColor;
        }
        pill.layer.borderWidth = 1.0;

        // Create horizontal stack inside pill
        NSStackView *pillStack = [[NSStackView alloc] init];
        pillStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        pillStack.spacing = 4;
        pillStack.edgeInsets = NSEdgeInsetsMake(4, 8, 4, 8);

        // Bundle color indicator (small circle)
        NSView *colorDot = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 8, 8)];
        colorDot.wantsLayer = YES;
        colorDot.layer.cornerRadius = 4;
        colorDot.layer.backgroundColor = bundle.color.CGColor;
        [colorDot setFrameSize:NSMakeSize(8, 8)];

        // Bundle name
        NSTextField *nameLabel = [NSTextField labelWithString:bundle.name];
        nameLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        nameLabel.textColor = [NSColor labelColor];

        // Status text (e.g., "blocked till 5pm" or "allowed till 8pm")
        NSString *statusWord = allowed ? @"allowed" : @"blocked";
        NSString *statusText = [NSString stringWithFormat:@"%@ %@", statusWord, statusStr];
        NSTextField *statusLabel = [NSTextField labelWithString:statusText];
        statusLabel.font = [NSFont systemFontOfSize:11];
        statusLabel.textColor = allowed ? [NSColor systemGreenColor] : [NSColor systemRedColor];

        [pillStack addArrangedSubview:colorDot];
        [pillStack addArrangedSubview:nameLabel];
        [pillStack addArrangedSubview:statusLabel];

        // Add constraints for the color dot
        [colorDot.widthAnchor constraintEqualToConstant:8].active = YES;
        [colorDot.heightAnchor constraintEqualToConstant:8].active = YES;

        pillStack.translatesAutoresizingMaskIntoConstraints = NO;
        [pill addSubview:pillStack];
        [NSLayoutConstraint activateConstraints:@[
            [pillStack.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor],
            [pillStack.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor],
            [pillStack.topAnchor constraintEqualToAnchor:pill.topAnchor],
            [pillStack.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor]
        ]];

        // Prevent pill from stretching - it should only be as wide as its content
        [pill setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [pill setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

        [self.statusStackView addArrangedSubview:pill];
    }

    // Add a flexible spacer at the end to push pills to the left
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.statusStackView addArrangedSubview:spacer];
}

- (void)updateEmergencyButtonTitle:(NSString *)title {
    NSMutableAttributedString *redTitle = [[NSMutableAttributedString alloc] initWithString:title];
    [redTitle addAttribute:NSForegroundColorAttributeName
                     value:[NSColor systemRedColor]
                     range:NSMakeRange(0, redTitle.length)];
    [redTitle addAttribute:NSFontAttributeName
                     value:[NSFont systemFontOfSize:13]
                     range:NSMakeRange(0, redTitle.length)];
    self.emergencyUnlockButton.attributedTitle = redTitle;
}

- (void)updateCommitmentUI {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    BOOL isCommitted = [manager isCommittedForWeekOffset:self.currentWeekOffset];

    // Update emergency unlock button
    NSInteger credits = [manager emergencyUnlockCreditsRemaining];
    [self updateEmergencyButtonTitle:[NSString stringWithFormat:@"Emergency Unlock (%ld)", (long)credits]];
    // Only enabled when committed AND have credits remaining
    self.emergencyUnlockButton.enabled = (isCommitted && credits > 0);

    if (isCommitted) {
        self.commitButton.title = @"Committed ✓";
        self.commitButton.enabled = NO;

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"EEEE";
        NSDate *endDate = [manager commitmentEndDateForWeekOffset:self.currentWeekOffset];
        NSString *endDay = [formatter stringFromDate:endDate];
        self.commitmentLabel.stringValue = [NSString stringWithFormat:@"Until %@", endDay];
        self.commitmentLabel.textColor = [NSColor secondaryLabelColor];
    } else {
        NSString *weekName = (self.currentWeekOffset == 0) ? @"This Week" : @"Next Week";
        self.commitButton.title = [NSString stringWithFormat:@"Commit to %@", weekName];

        // For next week, only allow commit on Sunday
        if (self.currentWeekOffset > 0) {
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSInteger weekday = [calendar component:NSCalendarUnitWeekday fromDate:[NSDate date]];
            BOOL isSunday = (weekday == 1); // 1 = Sunday

            if (!isSunday) {
                self.commitButton.enabled = NO;
                self.commitmentLabel.stringValue = @"Commit available on Sunday";
                self.commitmentLabel.textColor = [NSColor tertiaryLabelColor];
                return;
            }
        }

        self.commitButton.enabled = (manager.bundles.count > 0);
        self.commitmentLabel.stringValue = @"";
    }
}

- (void)updateWeekLabel {
    NSCalendar *calendar = [NSCalendar currentCalendar];

    // Get the Monday of the target week
    NSDate *weekStart = [SCWeeklySchedule startOfCurrentWeek];
    if (self.currentWeekOffset > 0) {
        weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay
                                         value:self.currentWeekOffset * 7
                                        toDate:weekStart
                                       options:0];
    }
    NSDate *weekEnd = [calendar dateByAddingUnit:NSCalendarUnitDay value:6 toDate:weekStart options:0];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MMM d";

    NSString *weekType = (self.currentWeekOffset == 0) ? @"This Week" : @"Next Week";
    self.weekLabel.stringValue = [NSString stringWithFormat:@"%@: %@ - %@",
                                   weekType,
                                   [formatter stringFromDate:weekStart],
                                   [formatter stringFromDate:weekEnd]];
}

#pragma mark - Actions

- (void)addBundleClicked:(id)sender {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    self.bundleEditorController = [[SCBundleEditorController alloc] initForNewBundle];
    self.bundleEditorController.delegate = self;
    self.bundleEditorController.isCommitted = [manager isCommittedForWeekOffset:self.currentWeekOffset];
    [self.bundleEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)navigateToPrevWeek:(id)sender {
    if (self.currentWeekOffset > 0) {
        self.currentWeekOffset--;
        [self updateNavigationButtons];
        [self reloadData];
        [self updateWeekLabel];
    }
}

- (void)navigateToNextWeek:(id)sender {
    self.currentWeekOffset++;
    [self updateNavigationButtons];
    [self reloadData];
    [self updateWeekLabel];
}

- (void)updateNavigationButtons {
    self.prevWeekButton.enabled = (self.currentWeekOffset > 0);
    // For now, only allow navigating to next week (offset 1)
    self.nextWeekButton.enabled = (self.currentWeekOffset < 1);
}

- (void)commitClicked:(id)sender {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    if (manager.bundles.count == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Bundles";
        alert.informativeText = @"Please add at least one bundle before committing.";
        [alert runModal];
        return;
    }

    // Check license FIRST, before showing confirmation dialog
    if (![[SCLicenseManager sharedManager] canCommit]) {
        [self showLicenseModalWithCompletion:^{
            // License now valid, show the confirmation dialog
            [self showCommitConfirmationDialog];
        }];
        return;
    }

    // Trial still valid or license valid - show confirmation dialog
    [self showCommitConfirmationDialog];
}

- (void)showCommitConfirmationDialog {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    NSAlert *alert = [[NSAlert alloc] init];
    NSString *weekName = (self.currentWeekOffset == 0) ? @"This Week" : @"Next Week";
    alert.messageText = [NSString stringWithFormat:@"Commit to %@?", weekName];

    // Get the last day of the target week
    NSArray *days = [manager daysToDisplayForWeekOffset:self.currentWeekOffset];
    NSString *lastDay = @"Sunday"; // Always Sunday for Mon-Sun weeks
    if (days.count > 0) {
        lastDay = [SCWeeklySchedule displayNameForDay:[[days lastObject] integerValue]];
    }

    alert.informativeText = [NSString stringWithFormat:
                             @"Once committed, the schedule is locked and cannot be modified. "
                             @"This commitment lasts until %@.\n\n"
                             @"You will still be able to add apps and websites to bundles.", lastDay];
    [alert addButtonWithTitle:@"Commit"];
    [alert addButtonWithTitle:@"Cancel"];

    NSInteger weekOffset = self.currentWeekOffset;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [manager commitToWeekWithOffset:weekOffset];
            [self reloadData];
        }
    }];
}

#pragma mark - License

- (void)showLicenseModalWithCompletion:(void(^)(void))completion {
    self.licenseWindowController = [[SCLicenseWindowController alloc] init];
    self.licenseWindowController.onLicenseActivated = ^{
        self.licenseWindowController = nil;
        if (completion) {
            completion();
        }
    };
    self.licenseWindowController.onCancel = ^{
        self.licenseWindowController = nil;
        // User cancelled - they can't proceed without a license
    };
    [self.licenseWindowController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)emergencyUnlockClicked:(id)sender {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    NSInteger credits = [manager emergencyUnlockCreditsRemaining];

    if (credits <= 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"No Credits Remaining";
        alert.informativeText = @"You have used all your emergency unlock credits.";
        [alert runModal];
        return;
    }

    // Confirmation dialog
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Use Emergency Unlock?";
    alert.informativeText = [NSString stringWithFormat:
        @"This will immediately end all blocking and use 1 of your %ld remaining emergency unlock%@.\n\n"
        @"This cannot be undone.",
        (long)credits, credits == 1 ? @"" : @"s"];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Unlock"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [self performEmergencyUnlock];
        }
    }];
}

- (void)performEmergencyUnlock {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Get path to emergency.sh in the app bundle or project directory
    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"emergency" ofType:@"sh"];

    // Fallback: check project directory (for development)
    if (!scriptPath) {
        NSString *projectPath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
        scriptPath = [projectPath stringByAppendingPathComponent:@"emergency.sh"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
            // Try one more level up (in case we're in build/Release)
            projectPath = [[projectPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
            scriptPath = [projectPath stringByAppendingPathComponent:@"emergency.sh"];
        }
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Script Not Found";
        alert.informativeText = @"Could not find emergency.sh script.";
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    // Run script with admin privileges using AppleScript
    NSString *appleScriptSource = [NSString stringWithFormat:
        @"do shell script \"/bin/bash '%@'\" with administrator privileges", scriptPath];

    NSDictionary *errorInfo = nil;
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:appleScriptSource];
    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errorInfo];

    if (!result && errorInfo) {
        // User cancelled or error occurred
        NSNumber *errorNumber = errorInfo[NSAppleScriptErrorNumber];
        if (errorNumber && [errorNumber integerValue] == -128) {
            // User cancelled - don't show error, don't use credit
            return;
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Emergency Unlock Failed";
        alert.informativeText = [NSString stringWithFormat:@"Error: %@",
            errorInfo[NSAppleScriptErrorMessage] ?: @"Unknown error"];
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    // Success - use credit
    [manager useEmergencyUnlockCredit];

    // Clear commitment from NSUserDefaults (script clears daemon state, we clear app state)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *allDefaults = [defaults dictionaryRepresentation];
    for (NSString *key in allDefaults.allKeys) {
        if ([key hasPrefix:@"SCWeekCommitment_"] || [key hasPrefix:@"SCWeekSchedules_"]) {
            [defaults removeObjectForKey:key];
        }
    }
    [defaults removeObjectForKey:@"SCIsCommitted"];
    [defaults synchronize];

    // Post notification to refresh UI
    [[NSNotificationCenter defaultCenter] postNotificationName:SCScheduleManagerDidChangeNotification object:nil];

    // Show success message
    NSInteger remaining = [manager emergencyUnlockCreditsRemaining];
    NSAlert *successAlert = [[NSAlert alloc] init];
    successAlert.messageText = @"Emergency Unlock Complete";
    successAlert.informativeText = [NSString stringWithFormat:
        @"All blocking has been removed.\n\nYou have %ld emergency unlock%@ remaining.",
        (long)remaining, remaining == 1 ? @"" : @"s"];
    [successAlert runModal];
}

#pragma mark - Notifications

- (void)scheduleDidChange:(NSNotification *)note {
    // Skip redundant reload when the grid itself triggered the update
    // (the grid already refreshes via handleScheduleUpdate)
    if (self.isUpdatingFromGrid) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
    });
}

#pragma mark - SCWeekGridViewDelegate

- (void)weekGridView:(SCWeekGridView *)gridView didSelectBundle:(SCBlockBundle *)bundle forDay:(SCDayOfWeek)day {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Remember which week we're editing
    self.editingWeekOffset = self.currentWeekOffset;

    // Block opening editor when committed - schedule is locked
    if ([manager isCommittedForWeekOffset:self.editingWeekOffset]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Schedule Locked";
        alert.informativeText = @"You're committed to this week. The schedule cannot be modified.";
        [alert runModal];
        return;
    }

    SCWeeklySchedule *schedule = [manager scheduleForBundleID:bundle.bundleID weekOffset:self.editingWeekOffset];

    if (!schedule) {
        schedule = [manager createScheduleForBundle:bundle weekOffset:self.editingWeekOffset];
    }

    self.dayEditorController = [[SCDayScheduleEditorController alloc] initWithBundle:bundle
                                                                            schedule:schedule
                                                                                 day:day];
    self.dayEditorController.delegate = self;
    self.dayEditorController.isCommitted = NO;  // Will never be YES now since we block above

    [self.dayEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)weekGridView:(SCWeekGridView *)gridView didRequestEditBundle:(SCBlockBundle *)bundle {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    self.bundleEditorController = [[SCBundleEditorController alloc] initWithBundle:bundle];
    self.bundleEditorController.delegate = self;
    self.bundleEditorController.isCommitted = [manager isCommittedForWeekOffset:self.currentWeekOffset];
    [self.bundleEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)weekGridViewDidRequestAddBundle:(SCWeekGridView *)gridView {
    [self addBundleClicked:nil];
}

#pragma mark - SCBundleSidebarViewDelegate

- (void)bundleSidebar:(SCBundleSidebarView *)sidebar didSelectBundle:(nullable SCBlockBundle *)bundle {
    // Update focus state
    self.focusedBundleID = bundle.bundleID;

    // Update calendar grid with new focus
    self.calendarGridView.focusedBundleID = self.focusedBundleID;
    [self.calendarGridView reloadData];
}

- (void)bundleSidebarDidRequestAddBundle:(SCBundleSidebarView *)sidebar {
    [self addBundleClicked:nil];
}

- (void)bundleSidebar:(SCBundleSidebarView *)sidebar didRequestEditBundle:(SCBlockBundle *)bundle {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    self.bundleEditorController = [[SCBundleEditorController alloc] initWithBundle:bundle];
    self.bundleEditorController.delegate = self;
    self.bundleEditorController.isCommitted = [manager isCommittedForWeekOffset:self.currentWeekOffset];
    [self.bundleEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - SCCalendarGridViewDelegate

- (void)calendarGrid:(SCCalendarGridView *)grid didUpdateSchedule:(SCWeeklySchedule *)schedule forBundleID:(NSString *)bundleID {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Capture old schedule for undo
    SCWeeklySchedule *oldSchedule = [manager scheduleForBundleID:bundleID weekOffset:self.currentWeekOffset];
    NSInteger weekOffset = self.currentWeekOffset;

    // Register undo action
    [[grid.undoManager prepareWithInvocationTarget:self] restoreSchedule:oldSchedule
                                                             forBundleID:bundleID
                                                              weekOffset:weekOffset
                                                            calendarGrid:grid];

    // Save the updated schedule to the manager
    // Set flag to prevent redundant reloadData (grid already updated itself)
    self.isUpdatingFromGrid = YES;
    [manager updateSchedule:schedule forWeekOffset:self.currentWeekOffset];
    self.isUpdatingFromGrid = NO;
}

- (void)restoreSchedule:(SCWeeklySchedule *)schedule
            forBundleID:(NSString *)bundleID
             weekOffset:(NSInteger)weekOffset
           calendarGrid:(SCCalendarGridView *)grid {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Capture current state for redo
    SCWeeklySchedule *currentSchedule = [manager scheduleForBundleID:bundleID weekOffset:weekOffset];
    [[grid.undoManager prepareWithInvocationTarget:self] restoreSchedule:currentSchedule
                                                             forBundleID:bundleID
                                                              weekOffset:weekOffset
                                                            calendarGrid:grid];

    // Restore the old schedule
    [manager updateSchedule:schedule forWeekOffset:weekOffset];

    // Refresh the UI
    [self reloadData];
}

- (void)calendarGridDidClickEmptyArea:(SCCalendarGridView *)grid {
    // Clear focus - return to All-Up state
    NSLog(@"[ESC] WindowController: calendarGridDidClickEmptyArea called, clearing focusedBundleID=%@", self.focusedBundleID);
    self.focusedBundleID = nil;
    self.bundleSidebar.selectedBundleID = nil;
    [self.bundleSidebar reloadData];
    self.calendarGridView.focusedBundleID = nil;
    [self.calendarGridView reloadData];
    NSLog(@"[ESC] WindowController: focus cleared");
}

- (void)calendarGrid:(SCCalendarGridView *)grid didRequestEditBundle:(SCBlockBundle *)bundle forDay:(SCDayOfWeek)day {
    // Open the day editor sheet for detailed editing
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    self.editingWeekOffset = self.currentWeekOffset;

    SCWeeklySchedule *schedule = [manager scheduleForBundleID:bundle.bundleID weekOffset:self.editingWeekOffset];
    if (!schedule) {
        schedule = [manager createScheduleForBundle:bundle weekOffset:self.editingWeekOffset];
    }

    self.dayEditorController = [[SCDayScheduleEditorController alloc] initWithBundle:bundle
                                                                            schedule:schedule
                                                                                 day:day];
    self.dayEditorController.delegate = self;
    self.dayEditorController.isCommitted = [manager isCommittedForWeekOffset:self.editingWeekOffset];

    [self.dayEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)calendarGridDidAttemptInteractionWithoutFocus:(SCCalendarGridView *)grid {
    [self showSelectBundleWarning];
}

#pragma mark - Warning UI

- (void)showSelectBundleWarning {
    // Don't show multiple warnings at once
    static BOOL isShowingWarning = NO;
    if (isShowingWarning) return;
    isShowingWarning = YES;

    // Create thin frosted glass toast (like status pills but grey)
    CGFloat toastWidth = 280;
    CGFloat toastHeight = 28;

    NSVisualEffectView *toast = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, toastWidth, toastHeight)];
    toast.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    toast.material = NSVisualEffectMaterialToolTip;  // Lighter, more translucent
    toast.state = NSVisualEffectStateActive;
    toast.wantsLayer = YES;
    toast.layer.cornerRadius = toastHeight / 2;  // Pill shape like status pills

    // Add subtle border for definition (like status pills)
    toast.layer.borderWidth = 1.0;
    toast.layer.borderColor = [[NSColor grayColor] colorWithAlphaComponent:0.3].CGColor;

    // Add shadow for floating effect
    toast.shadow = [[NSShadow alloc] init];
    toast.shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.25];
    toast.shadow.shadowOffset = NSMakeSize(0, -2);
    toast.shadow.shadowBlurRadius = 8;

    toast.alphaValue = 0;

    // Add label with contextual message
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    NSString *message = (manager.bundles.count == 0)
        ? @"To create allow block — create a bundle first"
        : @"To create allow block — select a bundle first";
    NSTextField *label = [NSTextField labelWithString:message];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    label.textColor = [NSColor secondaryLabelColor];
    label.alignment = NSTextAlignmentCenter;
    label.frame = NSMakeRect(0, (toastHeight - 16) / 2, toastWidth, 16);
    [toast addSubview:label];

    // Position toast near top center of calendar grid
    NSRect gridFrame = self.calendarGridView.frame;
    toast.frame = NSMakeRect(
        gridFrame.origin.x + (gridFrame.size.width - toastWidth) / 2,
        gridFrame.origin.y + gridFrame.size.height - 50,
        toastWidth, toastHeight
    );
    [self.calendarGridView.superview addSubview:toast positioned:NSWindowAbove relativeTo:self.calendarGridView];

    // Flash calendar border red
    CALayer *flashLayer = [CALayer layer];
    flashLayer.frame = self.calendarGridView.layer.bounds;
    flashLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    flashLayer.zPosition = 1000;  // Stay on top of grid content
    flashLayer.borderColor = [NSColor systemRedColor].CGColor;
    flashLayer.borderWidth = 2.0;
    flashLayer.cornerRadius = 4.0;
    flashLayer.opacity = 0;
    [self.calendarGridView.layer addSublayer:flashLayer];

    // Animate toast in, hold, then out
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.4;
        toast.animator.alphaValue = 1.0;
        flashLayer.opacity = 0.8;
    } completionHandler:^{
        // Flash out
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.6;
            flashLayer.opacity = 0;
        } completionHandler:nil];

        // Hold then fade out toast
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.3;
                toast.animator.alphaValue = 0;
            } completionHandler:^{
                [toast removeFromSuperview];
                [flashLayer removeFromSuperlayer];
                isShowingWarning = NO;
            }];
        });
    }];
}

#pragma mark - SCDayScheduleEditorDelegate

- (void)dayScheduleEditor:(SCDayScheduleEditorController *)editor
         didSaveSchedule:(SCWeeklySchedule *)schedule
                  forDay:(SCDayOfWeek)day {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    [manager updateSchedule:schedule forWeekOffset:self.editingWeekOffset];
    self.dayEditorController = nil;
}

- (void)dayScheduleEditorDidCancel:(SCDayScheduleEditorController *)editor {
    self.dayEditorController = nil;
}

#pragma mark - SCBundleEditorDelegate

- (void)bundleEditor:(SCBundleEditorController *)editor didSaveBundle:(SCBlockBundle *)bundle {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    if (editor.isNewBundle) {
        [manager addBundle:bundle];
    } else {
        [manager updateBundle:bundle];
    }

    self.bundleEditorController = nil;
}

- (void)bundleEditorDidCancel:(SCBundleEditorController *)editor {
    self.bundleEditorController = nil;
}

- (void)bundleEditor:(SCBundleEditorController *)editor didDeleteBundle:(SCBlockBundle *)bundle {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    [manager removeBundleWithID:bundle.bundleID];
    self.bundleEditorController = nil;
}

#pragma mark - SCMenuBarControllerDelegate

- (void)menuBarControllerDidRequestOpenApp:(SCMenuBarController *)controller {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Keyboard Handling

- (void)cancelOperation:(id)sender {
    // Escape key - progressive: first clear selection, then clear focus
    BOOL hasSel = [self.calendarGridView hasSelectedBlock];
    NSLog(@"[ESC] WindowController.cancelOperation: hasSel=%d focusedBundle=%@ firstResp=%@",
          hasSel, self.focusedBundleID, self.window.firstResponder);
    if (hasSel) {
        NSLog(@"[ESC] WindowController: clearing all selections");
        [self.calendarGridView clearAllSelections];
    } else if (self.focusedBundleID) {
        NSLog(@"[ESC] WindowController: clearing focus");
        [self calendarGridDidClickEmptyArea:self.calendarGridView];
    } else {
        NSLog(@"[ESC] WindowController: UNHANDLED - no selection, no focus!");
    }
}

@end
