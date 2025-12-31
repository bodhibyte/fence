//
//  SCTestBlockWindowController.m
//  SelfControl
//
//  Window controller for the "Try Test Block" onboarding feature.
//  Creates UI programmatically (no XIB needed).
//

#import "SCTestBlockWindowController.h"
#import "SCXPCClient.h"
#import "SCSettings.h"
#import "SCUIUtilities.h"
#import "SCVersionTracker.h"

typedef NS_ENUM(NSInteger, SCTestBlockState) {
    SCTestBlockStateSetup,      // User is setting up the test
    SCTestBlockStateActive,     // Test block is running
    SCTestBlockStateComplete    // Test finished
};

@interface SCTestBlockWindowController () <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, assign) SCTestBlockState currentState;

// Data
@property (nonatomic, strong) NSMutableArray<NSString*>* blocklist;
@property (nonatomic, assign) NSTimeInterval selectedDuration;
@property (nonatomic, strong) NSDate* blockEndDate;
@property (nonatomic, strong) NSTimer* updateTimer;

// Setup view elements
@property (nonatomic, strong) NSView* setupView;
@property (nonatomic, strong) NSSlider* durationSlider;
@property (nonatomic, strong) NSTextField* durationLabel;
@property (nonatomic, strong) NSTextField* websiteField;
@property (nonatomic, strong) NSButton* addWebsiteButton;
@property (nonatomic, strong) NSButton* addAppButton;
@property (nonatomic, strong) NSScrollView* blocklistScrollView;
@property (nonatomic, strong) NSTableView* blocklistTableView;
@property (nonatomic, strong) NSButton* startButton;

// Active view elements
@property (nonatomic, strong) NSView* activeView;
@property (nonatomic, strong) NSTextField* timerLabel;
@property (nonatomic, strong) NSProgressIndicator* progressBar;
@property (nonatomic, strong) NSTextField* blockingListLabel;
@property (nonatomic, strong) NSTextField* hintLabel;
@property (nonatomic, strong) NSButton* stopButton;

// Complete view elements
@property (nonatomic, strong) NSView* completeView;
@property (nonatomic, strong) NSTextField* successLabel;
@property (nonatomic, strong) NSButton* doneButton;

@end

@implementation SCTestBlockWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 450, 520);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Try Test Block";

    self = [super initWithWindow:window];
    if (self) {
        _blocklist = [NSMutableArray array];
        _selectedDuration = 60; // Default: 1 minute
        _currentState = SCTestBlockStateSetup;
        [self setupUI];
    }
    return self;
}

- (void)dealloc {
    [self.updateTimer invalidate];
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView* contentView = self.window.contentView;
    contentView.wantsLayer = YES;

    // Set solid dark background (don't use frosted glass for sheet-style window)
    self.window.backgroundColor = [NSColor windowBackgroundColor];

    [self setupSetupView];
    [self setupActiveView];
    [self setupCompleteView];

    [self updateViewVisibility];
    [self.window center];
}

- (void)setupSetupView {
    NSView* contentView = self.window.contentView;
    CGFloat width = contentView.frame.size.width;
    CGFloat height = contentView.frame.size.height;

    self.setupView = [[NSView alloc] initWithFrame:contentView.bounds];
    [contentView addSubview:self.setupView];

    CGFloat y = height - 40;
    CGFloat padding = 20;

    // Title
    NSTextField* titleLabel = [self createLabelWithText:@"Try Test Block" fontSize:20 bold:YES];
    titleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 26);
    [self.setupView addSubview:titleLabel];
    y -= 28;

    // Subtitle
    NSTextField* subtitleLabel = [self createLabelWithText:@"Test blocking without committing to a schedule" fontSize:12 bold:NO];
    subtitleLabel.textColor = [NSColor secondaryLabelColor];
    subtitleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 18);
    [self.setupView addSubview:subtitleLabel];
    y -= 35;

    // Duration section
    NSTextField* durationTitleLabel = [self createLabelWithText:@"Duration" fontSize:14 bold:YES];
    durationTitleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 20);
    [self.setupView addSubview:durationTitleLabel];
    y -= 30;

    self.durationSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(padding, y, width - 2*padding - 80, 20)];
    self.durationSlider.minValue = 0;
    self.durationSlider.maxValue = 3;
    self.durationSlider.numberOfTickMarks = 4;
    self.durationSlider.allowsTickMarkValuesOnly = YES;
    self.durationSlider.integerValue = 1; // Default to 1 minute
    self.durationSlider.target = self;
    self.durationSlider.action = @selector(durationChanged:);
    [self.setupView addSubview:self.durationSlider];

    self.durationLabel = [self createLabelWithText:@"1 minute" fontSize:13 bold:NO];
    self.durationLabel.frame = NSMakeRect(width - padding - 70, y, 70, 20);
    self.durationLabel.alignment = NSTextAlignmentRight;
    [self.setupView addSubview:self.durationLabel];
    y -= 15;

    // Tick labels
    NSArray* tickLabels = @[@"30s", @"1m", @"2m", @"5m"];
    CGFloat sliderWidth = width - 2*padding - 80;
    for (NSInteger i = 0; i < tickLabels.count; i++) {
        CGFloat tickX = padding + (sliderWidth * i / 3.0) - 12;
        NSTextField* tickLabel = [self createLabelWithText:tickLabels[i] fontSize:10 bold:NO];
        tickLabel.textColor = [NSColor tertiaryLabelColor];
        tickLabel.frame = NSMakeRect(tickX, y, 30, 14);
        tickLabel.alignment = NSTextAlignmentCenter;
        [self.setupView addSubview:tickLabel];
    }
    y -= 30;

    // Websites section
    NSTextField* websitesTitleLabel = [self createLabelWithText:@"Websites" fontSize:14 bold:YES];
    websitesTitleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 20);
    [self.setupView addSubview:websitesTitleLabel];
    y -= 28;

    self.websiteField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width - 2*padding - 60, 24)];
    self.websiteField.placeholderString = @"facebook.com";
    [self.setupView addSubview:self.websiteField];

    self.addWebsiteButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - padding - 50, y, 50, 24)];
    self.addWebsiteButton.bezelStyle = NSBezelStyleRounded;
    self.addWebsiteButton.title = @"Add";
    self.addWebsiteButton.target = self;
    self.addWebsiteButton.action = @selector(addWebsiteClicked:);
    [self.setupView addSubview:self.addWebsiteButton];
    y -= 35;

    // Apps section
    NSTextField* appsTitleLabel = [self createLabelWithText:@"Apps" fontSize:14 bold:YES];
    appsTitleLabel.frame = NSMakeRect(padding, y, 100, 20);
    [self.setupView addSubview:appsTitleLabel];

    self.addAppButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - padding - 80, y - 2, 80, 24)];
    self.addAppButton.bezelStyle = NSBezelStyleRounded;
    self.addAppButton.title = @"Add App";
    self.addAppButton.target = self;
    self.addAppButton.action = @selector(addAppClicked:);
    [self.setupView addSubview:self.addAppButton];
    y -= 35;

    // Blocklist table
    NSTextField* blocklistTitleLabel = [self createLabelWithText:@"Will be blocked:" fontSize:13 bold:NO];
    blocklistTitleLabel.textColor = [NSColor secondaryLabelColor];
    blocklistTitleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 18);
    [self.setupView addSubview:blocklistTitleLabel];
    y -= 25;

    CGFloat tableHeight = 120;
    self.blocklistScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(padding, y - tableHeight + 18, width - 2*padding, tableHeight)];
    self.blocklistScrollView.hasVerticalScroller = YES;
    self.blocklistScrollView.borderType = NSBezelBorder;

    self.blocklistTableView = [[NSTableView alloc] initWithFrame:self.blocklistScrollView.bounds];
    self.blocklistTableView.dataSource = self;
    self.blocklistTableView.delegate = self;
    self.blocklistTableView.headerView = nil;
    self.blocklistTableView.rowHeight = 24;

    NSTableColumn* typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.width = 40;
    [self.blocklistTableView addTableColumn:typeColumn];

    NSTableColumn* nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.width = width - 2*padding - 80;
    [self.blocklistTableView addTableColumn:nameColumn];

    NSTableColumn* removeColumn = [[NSTableColumn alloc] initWithIdentifier:@"remove"];
    removeColumn.width = 30;
    [self.blocklistTableView addTableColumn:removeColumn];

    self.blocklistScrollView.documentView = self.blocklistTableView;
    [self.setupView addSubview:self.blocklistScrollView];
    y = y - tableHeight - 10;

    // Buttons at bottom
    CGFloat buttonY = 20;

    self.startButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - padding - 130, buttonY, 130, 32)];
    self.startButton.bezelStyle = NSBezelStyleRounded;
    self.startButton.title = @"Start Test Block";
    self.startButton.target = self;
    self.startButton.action = @selector(startTestClicked:);
    self.startButton.keyEquivalent = @"\r";
    [self.setupView addSubview:self.startButton];

    [self updateStartButtonState];
}

- (void)setupActiveView {
    NSView* contentView = self.window.contentView;
    CGFloat width = contentView.frame.size.width;
    CGFloat height = contentView.frame.size.height;

    self.activeView = [[NSView alloc] initWithFrame:contentView.bounds];
    self.activeView.hidden = YES;
    [contentView addSubview:self.activeView];

    CGFloat y = height - 60;
    CGFloat padding = 20;

    // Title
    NSTextField* titleLabel = [self createLabelWithText:@"Test Block Active" fontSize:20 bold:YES];
    titleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 26);
    titleLabel.alignment = NSTextAlignmentCenter;
    [self.activeView addSubview:titleLabel];
    y -= 60;

    // Timer
    self.timerLabel = [self createLabelWithText:@"0:00" fontSize:48 bold:YES];
    self.timerLabel.frame = NSMakeRect(padding, y, width - 2*padding, 60);
    self.timerLabel.alignment = NSTextAlignmentCenter;
    [self.activeView addSubview:self.timerLabel];
    y -= 30;

    // "remaining" label
    NSTextField* remainingLabel = [self createLabelWithText:@"remaining" fontSize:14 bold:NO];
    remainingLabel.textColor = [NSColor secondaryLabelColor];
    remainingLabel.frame = NSMakeRect(padding, y, width - 2*padding, 20);
    remainingLabel.alignment = NSTextAlignmentCenter;
    [self.activeView addSubview:remainingLabel];
    y -= 40;

    // Progress bar
    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding + 40, y, width - 2*padding - 80, 8)];
    self.progressBar.style = NSProgressIndicatorStyleBar;
    self.progressBar.indeterminate = NO;
    self.progressBar.minValue = 0;
    self.progressBar.maxValue = 100;
    [self.activeView addSubview:self.progressBar];
    y -= 50;

    // Currently blocking label
    NSTextField* blockingTitleLabel = [self createLabelWithText:@"Currently blocking:" fontSize:14 bold:YES];
    blockingTitleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 20);
    [self.activeView addSubview:blockingTitleLabel];
    y -= 25;

    self.blockingListLabel = [self createLabelWithText:@"" fontSize:13 bold:NO];
    self.blockingListLabel.frame = NSMakeRect(padding + 10, y - 60, width - 2*padding - 20, 80);
    self.blockingListLabel.maximumNumberOfLines = 5;
    [self.activeView addSubview:self.blockingListLabel];
    y -= 100;

    // Hint label (italic style using secondary color)
    self.hintLabel = [self createLabelWithText:@"This is a test - you can stop anytime" fontSize:12 bold:NO];
    self.hintLabel.textColor = [NSColor secondaryLabelColor];
    self.hintLabel.frame = NSMakeRect(padding, y, width - 2*padding, 18);
    self.hintLabel.alignment = NSTextAlignmentCenter;
    [self.activeView addSubview:self.hintLabel];

    // Stop button
    self.stopButton = [[NSButton alloc] initWithFrame:NSMakeRect((width - 100) / 2, 30, 100, 36)];
    self.stopButton.bezelStyle = NSBezelStyleRounded;
    self.stopButton.title = @"Stop Test";
    self.stopButton.target = self;
    self.stopButton.action = @selector(stopTestClicked:);
    [self.activeView addSubview:self.stopButton];
}

- (void)setupCompleteView {
    NSView* contentView = self.window.contentView;
    CGFloat width = contentView.frame.size.width;
    CGFloat height = contentView.frame.size.height;

    self.completeView = [[NSView alloc] initWithFrame:contentView.bounds];
    self.completeView.hidden = YES;
    [contentView addSubview:self.completeView];

    CGFloat y = height - 100;
    CGFloat padding = 20;

    // Title
    NSTextField* titleLabel = [self createLabelWithText:@"Test Complete!" fontSize:24 bold:YES];
    titleLabel.frame = NSMakeRect(padding, y, width - 2*padding, 32);
    titleLabel.alignment = NSTextAlignmentCenter;
    [self.completeView addSubview:titleLabel];
    y -= 60;

    // Success message
    self.successLabel = [self createLabelWithText:@"Blocking worked correctly!" fontSize:16 bold:NO];
    self.successLabel.frame = NSMakeRect(padding, y, width - 2*padding, 24);
    self.successLabel.alignment = NSTextAlignmentCenter;
    [self.completeView addSubview:self.successLabel];
    y -= 40;

    // Description
    NSTextField* descLabel = [self createLabelWithText:@"The sites and apps you added were\nsuccessfully blocked during the test." fontSize:14 bold:NO];
    descLabel.textColor = [NSColor secondaryLabelColor];
    descLabel.frame = NSMakeRect(padding, y - 20, width - 2*padding, 50);
    descLabel.alignment = NSTextAlignmentCenter;
    descLabel.maximumNumberOfLines = 3;
    [self.completeView addSubview:descLabel];
    y -= 80;

    // Ready prompt
    NSTextField* readyLabel = [self createLabelWithText:@"Ready to set up your real schedule?" fontSize:14 bold:NO];
    readyLabel.frame = NSMakeRect(padding, y, width - 2*padding, 20);
    readyLabel.alignment = NSTextAlignmentCenter;
    [self.completeView addSubview:readyLabel];

    // Done button
    self.doneButton = [[NSButton alloc] initWithFrame:NSMakeRect((width - 100) / 2, 40, 100, 36)];
    self.doneButton.bezelStyle = NSBezelStyleRounded;
    self.doneButton.title = @"Done";
    self.doneButton.target = self;
    self.doneButton.action = @selector(doneClicked:);
    self.doneButton.keyEquivalent = @"\r";
    [self.completeView addSubview:self.doneButton];
}

- (NSTextField*)createLabelWithText:(NSString*)text fontSize:(CGFloat)fontSize bold:(BOOL)bold {
    NSTextField* label = [[NSTextField alloc] init];
    label.stringValue = text;
    label.bezeled = NO;
    label.editable = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    if (bold) {
        label.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
    } else {
        label.font = [NSFont systemFontOfSize:fontSize];
    }
    return label;
}

- (void)updateViewVisibility {
    self.setupView.hidden = (self.currentState != SCTestBlockStateSetup);
    self.activeView.hidden = (self.currentState != SCTestBlockStateActive);
    self.completeView.hidden = (self.currentState != SCTestBlockStateComplete);
}

- (void)updateStartButtonState {
    self.startButton.enabled = (self.blocklist.count > 0);
}

#pragma mark - Actions

- (void)durationChanged:(id)sender {
    NSArray* durations = @[@30, @60, @120, @300];
    NSArray* labels = @[@"30 seconds", @"1 minute", @"2 minutes", @"5 minutes"];

    NSInteger index = self.durationSlider.integerValue;
    if (index >= 0 && index < durations.count) {
        self.selectedDuration = [durations[index] doubleValue];
        self.durationLabel.stringValue = labels[index];
    }
}

- (void)addWebsiteClicked:(id)sender {
    NSString* website = [self.websiteField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (website.length == 0) {
        return;
    }

    // Basic validation - remove protocol if present
    if ([website hasPrefix:@"http://"]) {
        website = [website substringFromIndex:7];
    } else if ([website hasPrefix:@"https://"]) {
        website = [website substringFromIndex:8];
    }

    // Remove trailing slashes and paths
    NSRange slashRange = [website rangeOfString:@"/"];
    if (slashRange.location != NSNotFound) {
        website = [website substringToIndex:slashRange.location];
    }

    if (website.length > 0 && ![self.blocklist containsObject:website]) {
        [self.blocklist addObject:website];
        [self.blocklistTableView reloadData];
        [self updateStartButtonState];
    }

    self.websiteField.stringValue = @"";
}

- (void)addAppClicked:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"app"];
    panel.directoryURL = [NSURL fileURLWithPath:@"/Applications"];
    panel.message = @"Select an app to block during the test";

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString* appPath = panel.URL.path;
            NSBundle* appBundle = [NSBundle bundleWithPath:appPath];
            NSString* bundleId = appBundle.bundleIdentifier;

            if (bundleId) {
                NSString* entry = [NSString stringWithFormat:@"app:%@", bundleId];
                if (![self.blocklist containsObject:entry]) {
                    [self.blocklist addObject:entry];
                    [self.blocklistTableView reloadData];
                    [self updateStartButtonState];
                }
            } else {
                NSAlert* alert = [[NSAlert alloc] init];
                alert.messageText = @"Invalid App";
                alert.informativeText = @"Could not determine the bundle identifier for this app.";
                [alert runModal];
            }
        }
    }];
}

- (void)removeEntryAtIndex:(NSInteger)index {
    if (index >= 0 && index < self.blocklist.count) {
        [self.blocklist removeObjectAtIndex:index];
        [self.blocklistTableView reloadData];
        [self updateStartButtonState];
    }
}

- (void)startTestClicked:(id)sender {
    if (self.blocklist.count == 0) {
        return;
    }

    // Calculate end date
    self.blockEndDate = [NSDate dateWithTimeIntervalSinceNow:self.selectedDuration];

    // Build block settings with IsTestBlock=YES
    NSDictionary* blockSettings = @{
        @"IsTestBlock": @YES,
        @"ClearCaches": @NO,
        @"AllowLocalNetworks": @YES,
        @"EvaluateCommonSubdomains": @NO,
        @"IncludeLinkedDomains": @NO,
        @"BlockSoundShouldPlay": @NO,
        @"EnableErrorReporting": @NO
    };

    // Disable UI during start
    self.startButton.enabled = NO;
    self.startButton.title = @"Starting...";

    SCXPCClient* xpc = [[SCXPCClient alloc] init];

    // First install daemon (may require password)
    [xpc installDaemon:^(NSError* installError) {
        if (installError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.startButton.enabled = YES;
                self.startButton.title = @"Start Test Block";

                // Don't show alert for user cancellation
                if (installError.code != 1) {
                    NSAlert* alert = [[NSAlert alloc] init];
                    alert.messageText = @"Failed to Start";
                    alert.informativeText = installError.localizedDescription ?: @"Could not install the daemon.";
                    [alert runModal];
                }
            });
            return;
        }

        // Now start the block
        [xpc startBlockWithControllingUID:getuid()
                                blocklist:self.blocklist
                              isAllowlist:NO
                                  endDate:self.blockEndDate
                            blockSettings:blockSettings
                                    reply:^(NSError* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    self.startButton.enabled = YES;
                    self.startButton.title = @"Start Test Block";

                    NSAlert* alert = [[NSAlert alloc] init];
                    alert.messageText = @"Failed to Start";
                    alert.informativeText = error.localizedDescription ?: @"Could not start the test block.";
                    [alert runModal];
                } else {
                    [self transitionToActiveState];
                }
            });
        }];
    }];
}

- (void)stopTestClicked:(id)sender {
    self.stopButton.enabled = NO;
    self.stopButton.title = @"Stopping...";

    SCXPCClient* xpc = [[SCXPCClient alloc] init];
    [xpc stopTestBlock:^(NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.updateTimer invalidate];
            self.updateTimer = nil;

            if (error) {
                self.stopButton.enabled = YES;
                self.stopButton.title = @"Stop Test";

                NSAlert* alert = [[NSAlert alloc] init];
                alert.messageText = @"Failed to Stop";
                alert.informativeText = error.localizedDescription ?: @"Could not stop the test block.";
                [alert runModal];
            } else {
                [self transitionToCompleteState];
            }
        });
    }];
}

- (void)cancelClicked:(id)sender {
    if (self.completionHandler) {
        self.completionHandler(NO);
    }
    [self.window close];
}

- (void)doneClicked:(id)sender {
    // Mark that user has completed a test block
    [SCVersionTracker markTestBlockCompleted];

    if (self.completionHandler) {
        self.completionHandler(YES);
    }
    [self.window close];
}

#pragma mark - State Transitions

- (void)transitionToActiveState {
    self.currentState = SCTestBlockStateActive;
    [self updateViewVisibility];

    // Keep window focused after block starts
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Update blocking list label
    NSMutableArray* displayItems = [NSMutableArray array];
    for (NSString* entry in self.blocklist) {
        if ([entry hasPrefix:@"app:"]) {
            NSString* bundleId = [entry substringFromIndex:4];
            NSString* appName = [self appNameForBundleId:bundleId] ?: bundleId;
            [displayItems addObject:[NSString stringWithFormat:@"  %@", appName]];
        } else {
            [displayItems addObject:[NSString stringWithFormat:@"  %@", entry]];
        }
    }
    self.blockingListLabel.stringValue = [displayItems componentsJoinedByString:@"\n"];

    // Start update timer
    [self updateTimerDisplay];
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        target:self
                                                      selector:@selector(timerTick:)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)transitionToCompleteState {
    self.currentState = SCTestBlockStateComplete;
    [self updateViewVisibility];
}

#pragma mark - Timer

- (void)timerTick:(NSTimer*)timer {
    [self updateTimerDisplay];

    // Check if block expired
    if ([[NSDate date] compare:self.blockEndDate] != NSOrderedAscending) {
        [timer invalidate];
        self.updateTimer = nil;

        [self transitionToCompleteState];

        // Bring window to front after delay (refreshUserInterface shows week schedule first)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.window makeKeyAndOrderFront:nil];
            [self.window orderFrontRegardless];
        });
    }
}

- (void)updateTimerDisplay {
    NSTimeInterval remaining = [self.blockEndDate timeIntervalSinceNow];
    if (remaining < 0) remaining = 0;

    NSInteger minutes = (NSInteger)(remaining / 60);
    NSInteger seconds = (NSInteger)remaining % 60;
    self.timerLabel.stringValue = [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];

    // Update progress bar
    CGFloat progress = 100.0 * (1.0 - (remaining / self.selectedDuration));
    self.progressBar.doubleValue = progress;
}

#pragma mark - Helpers

- (NSString*)appNameForBundleId:(NSString*)bundleId {
    NSString* path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId];
    if (path) {
        return [[NSFileManager defaultManager] displayNameAtPath:path];
    }
    return nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    return self.blocklist.count;
}

#pragma mark - NSTableViewDelegate

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    NSString* identifier = tableColumn.identifier;
    NSString* entry = self.blocklist[row];
    BOOL isApp = [entry hasPrefix:@"app:"];

    if ([identifier isEqualToString:@"type"]) {
        NSTextField* cell = [tableView makeViewWithIdentifier:@"TypeCell" owner:self];
        if (!cell) {
            cell = [[NSTextField alloc] init];
            cell.identifier = @"TypeCell";
            cell.bezeled = NO;
            cell.editable = NO;
            cell.drawsBackground = NO;
            cell.font = [NSFont systemFontOfSize:11];
            cell.textColor = [NSColor tertiaryLabelColor];
        }
        cell.stringValue = isApp ? @"(app)" : @"(web)";
        return cell;
    }

    if ([identifier isEqualToString:@"name"]) {
        NSTextField* cell = [tableView makeViewWithIdentifier:@"NameCell" owner:self];
        if (!cell) {
            cell = [[NSTextField alloc] init];
            cell.identifier = @"NameCell";
            cell.bezeled = NO;
            cell.editable = NO;
            cell.drawsBackground = NO;
            cell.font = [NSFont systemFontOfSize:13];
        }
        if (isApp) {
            NSString* bundleId = [entry substringFromIndex:4];
            cell.stringValue = [self appNameForBundleId:bundleId] ?: bundleId;
        } else {
            cell.stringValue = entry;
        }
        return cell;
    }

    if ([identifier isEqualToString:@"remove"]) {
        NSButton* button = [tableView makeViewWithIdentifier:@"RemoveButton" owner:self];
        if (!button) {
            button = [[NSButton alloc] init];
            button.identifier = @"RemoveButton";
            button.bezelStyle = NSBezelStyleInline;
            button.bordered = NO;
            button.title = @"x";
            button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        }
        button.tag = row;
        button.target = self;
        button.action = @selector(removeButtonClicked:);
        return button;
    }

    return nil;
}

- (void)removeButtonClicked:(NSButton*)sender {
    [self removeEntryAtIndex:sender.tag];
}

@end
