//
//  SCWeekScheduleWindowController.m
//  SelfControl
//

#import "SCWeekScheduleWindowController.h"
#import "SCWeekGridView.h"
#import "SCDayScheduleEditorController.h"
#import "SCBundleEditorController.h"
#import "SCMenuBarController.h"
#import "SCUIUtilities.h"
#import "Block Management/SCScheduleManager.h"
#import "Block Management/SCBlockBundle.h"
#import "Block Management/SCWeeklySchedule.h"

@interface SCWeekScheduleWindowController () <SCWeekGridViewDelegate,
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
@property (nonatomic, strong) NSButton *saveTemplateButton;
@property (nonatomic, strong) NSButton *commitButton;
@property (nonatomic, strong) NSTextField *commitmentLabel;
@property (nonatomic, strong) NSSegmentedControl *weekStartControl;

// Child controllers
@property (nonatomic, strong, nullable) SCDayScheduleEditorController *dayEditorController;
@property (nonatomic, strong, nullable) SCBundleEditorController *bundleEditorController;

@end

@implementation SCWeekScheduleWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 900, 700);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SelfControl - Week Schedule";
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
    self.titleLabel.stringValue = @"SelfControl";
    self.titleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightBold];
    self.titleLabel.bezeled = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.autoresizingMask = NSViewMinYMargin; // Stay pinned to top
    [contentView addSubview:self.titleLabel];

    // Week label (right side)
    self.weekLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - 200 - padding, y, 200, 24)];
    self.weekLabel.alignment = NSTextAlignmentRight;
    self.weekLabel.font = [NSFont systemFontOfSize:14];
    self.weekLabel.textColor = [NSColor secondaryLabelColor];
    self.weekLabel.bezeled = NO;
    self.weekLabel.editable = NO;
    self.weekLabel.drawsBackground = NO;
    self.weekLabel.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin; // Stay at top-right
    [self updateWeekLabel];
    [contentView addSubview:self.weekLabel];

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

    // Week grid - position with minimal gap from status bar
    CGFloat bottomControlsHeight = 85; // Space for buttons at bottom
    CGFloat gridHeight = y - bottomControlsHeight;
    self.gridScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding, bottomControlsHeight, contentView.bounds.size.width - padding * 2, gridHeight)];
    self.gridScrollView.hasVerticalScroller = YES;
    self.gridScrollView.hasHorizontalScroller = NO;
    self.gridScrollView.autohidesScrollers = YES;
    self.gridScrollView.borderType = NSNoBorder; // Remove border for cleaner look
    self.gridScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.weekGridView = [[SCWeekGridView alloc] initWithFrame:NSMakeRect(0, 0, self.gridScrollView.bounds.size.width, 300)];
    self.weekGridView.delegate = self;
    self.weekGridView.weekStartsOnMonday = [SCScheduleManager sharedManager].weekStartsOnMonday;
    self.weekGridView.showOnlyRemainingDays = YES;

    self.gridScrollView.documentView = self.weekGridView;
    [contentView addSubview:self.gridScrollView];

    // Bottom buttons - positioned at fixed location above window bottom
    CGFloat buttonY = 45;

    self.addBundleButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, buttonY, 120, 30)];
    self.addBundleButton.title = @"+ Add Bundle";
    self.addBundleButton.bezelStyle = NSBezelStyleRounded;
    self.addBundleButton.target = self;
    self.addBundleButton.action = @selector(addBundleClicked:);
    self.addBundleButton.autoresizingMask = NSViewMaxYMargin; // Stay at bottom
    [contentView addSubview:self.addBundleButton];

    self.saveTemplateButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding + 130, buttonY, 140, 30)];
    self.saveTemplateButton.title = @"Save as Default";
    self.saveTemplateButton.bezelStyle = NSBezelStyleRounded;
    self.saveTemplateButton.target = self;
    self.saveTemplateButton.action = @selector(saveTemplateClicked:);
    self.saveTemplateButton.autoresizingMask = NSViewMaxYMargin; // Stay at bottom
    [contentView addSubview:self.saveTemplateButton];

    self.commitButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 150, buttonY, 150, 30)];
    self.commitButton.title = @"Commit to Week";
    self.commitButton.bezelStyle = NSBezelStyleRounded;
    self.commitButton.target = self;
    self.commitButton.action = @selector(commitClicked:);
    self.commitButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; // Stay at bottom-right
    [contentView addSubview:self.commitButton];

    // Week starts on toggle
    NSTextField *weekStartLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 280, buttonY + 5, 90, 20)];
    weekStartLabel.stringValue = @"Week starts:";
    weekStartLabel.font = [NSFont systemFontOfSize:11];
    weekStartLabel.textColor = [NSColor secondaryLabelColor];
    weekStartLabel.bezeled = NO;
    weekStartLabel.editable = NO;
    weekStartLabel.drawsBackground = NO;
    weekStartLabel.autoresizingMask = NSViewMaxYMargin; // Stay at bottom
    [contentView addSubview:weekStartLabel];

    self.weekStartControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(padding + 370, buttonY + 2, 100, 24)];
    [self.weekStartControl setSegmentCount:2];
    [self.weekStartControl setLabel:@"Sun" forSegment:0];
    [self.weekStartControl setLabel:@"Mon" forSegment:1];
    [self.weekStartControl setWidth:45 forSegment:0];
    [self.weekStartControl setWidth:45 forSegment:1];
    self.weekStartControl.target = self;
    self.weekStartControl.action = @selector(weekStartChanged:);
    self.weekStartControl.selectedSegment = [SCScheduleManager sharedManager].weekStartsOnMonday ? 1 : 0;
    self.weekStartControl.autoresizingMask = NSViewMaxYMargin; // Stay at bottom
    [contentView addSubview:self.weekStartControl];

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
}

- (void)windowDidResize:(NSNotification *)note {
    // Update grid view height when window resizes (e.g., fullscreen)
    [self reloadData];
}

#pragma mark - Data

- (void)reloadData {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    // Update grid
    self.weekGridView.bundles = manager.bundles;
    self.weekGridView.schedules = manager.schedules;
    self.weekGridView.isCommitted = manager.isCommitted;
    self.weekGridView.weekStartsOnMonday = manager.weekStartsOnMonday;
    [self.weekGridView reloadData];

    // Update status
    [self updateStatusLabel];

    // Update commitment UI
    [self updateCommitmentUI];

    // Update week label
    [self updateWeekLabel];

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

        // Status text
        NSString *statusText = allowed ? statusStr : @"blocked";
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

- (void)updateCommitmentUI {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];

    if (manager.isCommitted) {
        self.commitButton.title = @"Committed ✓";
        self.commitButton.enabled = NO;

        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"EEEE";
        NSString *endDay = [formatter stringFromDate:manager.commitmentEndDate];
        self.commitmentLabel.stringValue = [NSString stringWithFormat:@"Until %@", endDay];
    } else {
        self.commitButton.title = @"Commit to Week";
        self.commitButton.enabled = (manager.bundles.count > 0);
        self.commitmentLabel.stringValue = @"";
    }
}

- (void)updateWeekLabel {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];

    // Get start and end of week
    NSDateComponents *weekdayComponents = [calendar components:NSCalendarUnitWeekday fromDate:now];
    NSInteger weekday = weekdayComponents.weekday; // 1 = Sunday

    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    NSInteger daysToStart;
    if (manager.weekStartsOnMonday) {
        daysToStart = (weekday == 1) ? -6 : -(weekday - 2); // Monday start
    } else {
        daysToStart = -(weekday - 1); // Sunday start
    }

    NSDate *weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay value:daysToStart toDate:now options:0];
    NSDate *weekEnd = [calendar dateByAddingUnit:NSCalendarUnitDay value:6 toDate:weekStart options:0];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MMM d";

    self.weekLabel.stringValue = [NSString stringWithFormat:@"Week of %@ - %@",
                                   [formatter stringFromDate:weekStart],
                                   [formatter stringFromDate:weekEnd]];
}

#pragma mark - Actions

- (void)addBundleClicked:(id)sender {
    self.bundleEditorController = [[SCBundleEditorController alloc] initForNewBundle];
    self.bundleEditorController.delegate = self;
    [self.bundleEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)weekStartChanged:(id)sender {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    BOOL startsOnMonday = (self.weekStartControl.selectedSegment == 1);
    manager.weekStartsOnMonday = startsOnMonday;
    [self reloadData];
    [self updateWeekLabel];
}

- (void)saveTemplateClicked:(id)sender {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    [manager saveCurrentAsDefaultTemplate];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Template Saved";
    alert.informativeText = @"Your current schedule has been saved as the default. It will be automatically loaded at the start of each new week.";
    [alert runModal];
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

    // Confirmation
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Commit to This Week?";

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"EEEE";
    NSArray *days = [manager daysToDisplay];
    NSString *lastDay = [SCWeeklySchedule displayNameForDay:[[days lastObject] integerValue]];

    alert.informativeText = [NSString stringWithFormat:
                             @"Once committed, you can only make the schedule stricter (reduce allowed time). "
                             @"This commitment lasts until %@.\n\n"
                             @"This is UX testing mode - actual blocking is not connected yet.", lastDay];
    [alert addButtonWithTitle:@"Commit"];
    [alert addButtonWithTitle:@"Cancel"];

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [manager commitToWeek];
            [self reloadData];
        }
    }];
}

#pragma mark - Notifications

- (void)scheduleDidChange:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
    });
}

#pragma mark - SCWeekGridViewDelegate

- (void)weekGridView:(SCWeekGridView *)gridView didSelectBundle:(SCBlockBundle *)bundle forDay:(SCDayOfWeek)day {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    SCWeeklySchedule *schedule = [manager scheduleForBundleID:bundle.bundleID];

    if (!schedule) {
        schedule = [manager createScheduleForBundle:bundle];
    }

    self.dayEditorController = [[SCDayScheduleEditorController alloc] initWithBundle:bundle
                                                                            schedule:schedule
                                                                                 day:day];
    self.dayEditorController.delegate = self;
    self.dayEditorController.isCommitted = manager.isCommitted;

    [self.dayEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)weekGridView:(SCWeekGridView *)gridView didRequestEditBundle:(SCBlockBundle *)bundle {
    self.bundleEditorController = [[SCBundleEditorController alloc] initWithBundle:bundle];
    self.bundleEditorController.delegate = self;
    [self.bundleEditorController beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)weekGridViewDidRequestAddBundle:(SCWeekGridView *)gridView {
    [self addBundleClicked:nil];
}

#pragma mark - SCDayScheduleEditorDelegate

- (void)dayScheduleEditor:(SCDayScheduleEditorController *)editor
         didSaveSchedule:(SCWeeklySchedule *)schedule
                  forDay:(SCDayOfWeek)day {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    [manager updateSchedule:schedule];
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

@end
