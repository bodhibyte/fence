//
//  SCWeekScheduleWindowController.m
//  SelfControl
//

#import "SCWeekScheduleWindowController.h"
#import "SCWeekGridView.h"
#import "SCDayScheduleEditorController.h"
#import "SCBundleEditorController.h"
#import "SCMenuBarController.h"
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
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) SCWeekGridView *weekGridView;
@property (nonatomic, strong) NSScrollView *gridScrollView;
@property (nonatomic, strong) NSButton *addBundleButton;
@property (nonatomic, strong) NSButton *saveTemplateButton;
@property (nonatomic, strong) NSButton *commitButton;
@property (nonatomic, strong) NSTextField *commitmentLabel;

// Child controllers
@property (nonatomic, strong, nullable) SCDayScheduleEditorController *dayEditorController;
@property (nonatomic, strong, nullable) SCBundleEditorController *bundleEditorController;

@end

@implementation SCWeekScheduleWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 700, 550);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SelfControl - Week Schedule";
    window.minSize = NSMakeSize(500, 400);

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
    [contentView addSubview:self.titleLabel];

    // Week label (right side)
    self.weekLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - 200 - padding, y, 200, 24)];
    self.weekLabel.alignment = NSTextAlignmentRight;
    self.weekLabel.font = [NSFont systemFontOfSize:14];
    self.weekLabel.textColor = [NSColor secondaryLabelColor];
    self.weekLabel.bezeled = NO;
    self.weekLabel.editable = NO;
    self.weekLabel.drawsBackground = NO;
    self.weekLabel.autoresizingMask = NSViewMinXMargin;
    [self updateWeekLabel];
    [contentView addSubview:self.weekLabel];

    // Status view
    y -= 60;
    self.statusView = [[NSView alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 50)];
    self.statusView.wantsLayer = YES;
    self.statusView.layer.backgroundColor = [[NSColor controlBackgroundColor] CGColor];
    self.statusView.layer.cornerRadius = 8;
    self.statusView.autoresizingMask = NSViewWidthSizable;
    [contentView addSubview:self.statusView];

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 10, self.statusView.bounds.size.width - 24, 30)];
    self.statusLabel.font = [NSFont systemFontOfSize:13];
    self.statusLabel.bezeled = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.autoresizingMask = NSViewWidthSizable;
    [self.statusView addSubview:self.statusLabel];

    // Week grid
    y -= 280;
    self.gridScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 270)];
    self.gridScrollView.hasVerticalScroller = YES;
    self.gridScrollView.hasHorizontalScroller = NO;
    self.gridScrollView.autohidesScrollers = YES;
    self.gridScrollView.borderType = NSBezelBorder;
    self.gridScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.weekGridView = [[SCWeekGridView alloc] initWithFrame:NSMakeRect(0, 0, self.gridScrollView.bounds.size.width, 300)];
    self.weekGridView.delegate = self;
    self.weekGridView.weekStartsOnMonday = [SCScheduleManager sharedManager].weekStartsOnMonday;
    self.weekGridView.showOnlyRemainingDays = YES;

    self.gridScrollView.documentView = self.weekGridView;
    [contentView addSubview:self.gridScrollView];

    // Bottom buttons
    y -= 50;

    self.addBundleButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, y, 120, 30)];
    self.addBundleButton.title = @"+ Add Bundle";
    self.addBundleButton.bezelStyle = NSBezelStyleRounded;
    self.addBundleButton.target = self;
    self.addBundleButton.action = @selector(addBundleClicked:);
    [contentView addSubview:self.addBundleButton];

    self.saveTemplateButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding + 130, y, 140, 30)];
    self.saveTemplateButton.title = @"Save as Default";
    self.saveTemplateButton.bezelStyle = NSBezelStyleRounded;
    self.saveTemplateButton.target = self;
    self.saveTemplateButton.action = @selector(saveTemplateClicked:);
    [contentView addSubview:self.saveTemplateButton];

    self.commitButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 150, y, 150, 30)];
    self.commitButton.title = @"Commit to Week";
    self.commitButton.bezelStyle = NSBezelStyleRounded;
    self.commitButton.target = self;
    self.commitButton.action = @selector(commitClicked:);
    self.commitButton.autoresizingMask = NSViewMinXMargin;
    [contentView addSubview:self.commitButton];

    // Commitment label
    y -= 25;
    self.commitmentLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 200, y, 200, 20)];
    self.commitmentLabel.alignment = NSTextAlignmentRight;
    self.commitmentLabel.font = [NSFont systemFontOfSize:11];
    self.commitmentLabel.textColor = [NSColor secondaryLabelColor];
    self.commitmentLabel.bezeled = NO;
    self.commitmentLabel.editable = NO;
    self.commitmentLabel.drawsBackground = NO;
    self.commitmentLabel.autoresizingMask = NSViewMinXMargin;
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

    // Resize grid to fit content
    CGFloat gridHeight = MAX(300, 30 + (manager.bundles.count + 1) * 60);
    NSRect gridFrame = self.weekGridView.frame;
    gridFrame.size.height = gridHeight;
    self.weekGridView.frame = gridFrame;
}

- (void)updateStatusLabel {
    SCScheduleManager *manager = [SCScheduleManager sharedManager];
    NSMutableString *status = [NSMutableString string];

    if (manager.bundles.count == 0) {
        [status appendString:@"No bundles configured. Add a bundle to get started."];
    } else {
        [status appendString:@"NOW: "];

        for (SCBlockBundle *bundle in manager.bundles) {
            BOOL allowed = [manager wouldBundleBeAllowed:bundle.bundleID];
            NSString *statusStr = [manager statusStringForBundleID:bundle.bundleID];

            if (allowed) {
                [status appendFormat:@"%@ %@ • ", bundle.name, statusStr];
            } else {
                [status appendFormat:@"%@ blocked • ", bundle.name];
            }
        }

        // Remove trailing " • "
        if ([status hasSuffix:@" • "]) {
            [status deleteCharactersInRange:NSMakeRange(status.length - 3, 3)];
        }
    }

    self.statusLabel.stringValue = status;
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
