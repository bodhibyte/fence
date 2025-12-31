//
//  SCSafetyCheckWindowController.m
//  SelfControl
//
//  Window controller for the startup safety check UI.
//  Creates UI programmatically (no XIB needed).
//

#import "SCSafetyCheckWindowController.h"
#import "SCStartupSafetyCheck.h"
#import "SCVersionTracker.h"

@interface SCSafetyCheckWindowController ()

@property (nonatomic, strong) SCStartupSafetyCheck* safetyCheck;
@property (nonatomic, assign) BOOL checkInProgress;

// Programmatic UI elements
@property (nonatomic, strong) NSProgressIndicator* progressIndicator;
@property (nonatomic, strong) NSTextField* statusLabel;
@property (nonatomic, strong) NSButton* skipButton;
@property (nonatomic, strong) NSButton* okButton;
@property (nonatomic, strong) NSView* resultsView;
@property (nonatomic, strong) NSTextField* resultTitleLabel;
@property (nonatomic, strong) NSArray<NSTextField*>* resultLabels;

@end

@implementation SCSafetyCheckWindowController

- (instancetype)init {
    // Create window programmatically
    NSRect frame = NSMakeRect(0, 0, 420, 365);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Fence Safety Check";

    self = [super initWithWindow:window];
    if (self) {
        _safetyCheck = nil;
        _checkInProgress = NO;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView* contentView = self.window.contentView;
    CGFloat width = contentView.frame.size.width;
    CGFloat y = contentView.frame.size.height - 40;

    // Title label
    NSTextField* titleLabel = [self createLabelWithText:@"Safety Check" fontSize:18 bold:YES];
    titleLabel.frame = NSMakeRect(20, y, width - 40, 24);
    [contentView addSubview:titleLabel];
    y -= 30;

    // Subtitle
    NSTextField* subtitleLabel = [self createLabelWithText:@"Verifying blocking mechanisms work correctly..." fontSize:12 bold:NO];
    subtitleLabel.textColor = [NSColor secondaryLabelColor];
    subtitleLabel.frame = NSMakeRect(20, y, width - 40, 18);
    [contentView addSubview:subtitleLabel];
    y -= 35;

    // Progress indicator
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, y, width - 40, 20)];
    self.progressIndicator.style = NSProgressIndicatorStyleBar;
    self.progressIndicator.indeterminate = NO;  // Must be NO for determinate progress bar
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 100;
    self.progressIndicator.doubleValue = 0;
    [contentView addSubview:self.progressIndicator];
    y -= 25;

    // Status label
    self.statusLabel = [self createLabelWithText:@"Ready to start..." fontSize:13 bold:NO];
    self.statusLabel.frame = NSMakeRect(20, y, width - 40, 18);
    [contentView addSubview:self.statusLabel];
    y -= 40;

    // Results view (initially hidden)
    self.resultsView = [[NSView alloc] initWithFrame:NSMakeRect(20, 60, width - 40, y - 60)];
    self.resultsView.hidden = YES;
    [contentView addSubview:self.resultsView];

    // Result title
    self.resultTitleLabel = [self createLabelWithText:@"Results" fontSize:16 bold:YES];
    self.resultTitleLabel.frame = NSMakeRect(0, self.resultsView.frame.size.height - 24, width - 40, 24);
    [self.resultsView addSubview:self.resultTitleLabel];

    // Result labels
    NSArray* resultNames = @[
        @"Hosts file blocking",
        @"Packet filter blocking",
        @"App blocking (Calculator)",
        @"Hosts file cleanup",
        @"Packet filter cleanup",
        @"App unblocking",
        @"Emergency script (emergency.sh)"
    ];

    NSMutableArray* labels = [NSMutableArray array];
    CGFloat ry = self.resultsView.frame.size.height - 50;
    for (NSString* name in resultNames) {
        NSTextField* label = [self createLabelWithText:[NSString stringWithFormat:@"\u2022 %@", name] fontSize:13 bold:NO];
        label.frame = NSMakeRect(10, ry, width - 60, 18);
        [self.resultsView addSubview:label];
        [labels addObject:label];
        ry -= 22;
    }
    self.resultLabels = labels;

    // Buttons at bottom
    CGFloat buttonY = 15;
    CGFloat buttonWidth = 90;

    // OK button (initially hidden)
    self.okButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - buttonWidth - 20, buttonY, buttonWidth, 32)];
    self.okButton.bezelStyle = NSBezelStyleRounded;
    self.okButton.title = @"OK";
    self.okButton.target = self;
    self.okButton.action = @selector(okClicked:);
    self.okButton.keyEquivalent = @"\r";
    self.okButton.hidden = YES;
    [contentView addSubview:self.okButton];

    // Skip button
    self.skipButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, buttonY, buttonWidth, 32)];
    self.skipButton.bezelStyle = NSBezelStyleRounded;
    self.skipButton.title = @"Skip";
    self.skipButton.target = self;
    self.skipButton.action = @selector(skipClicked:);
    [contentView addSubview:self.skipButton];

    [self.window center];
}

- (NSTextField*)createLabelWithText:(NSString*)text fontSize:(CGFloat)fontSize bold:(BOOL)bold {
    NSTextField* label = [[NSTextField alloc] init];
    label.stringValue = text;
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.selectable = NO;

    if (bold) {
        label.font = [NSFont boldSystemFontOfSize:fontSize];
    } else {
        label.font = [NSFont systemFontOfSize:fontSize];
    }

    return label;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window setLevel:NSFloatingWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)runSafetyCheck {
    if (self.checkInProgress) {
        NSLog(@"SCSafetyCheckWindowController: Check already in progress");
        return;
    }

    // Reset UI state for fresh run (fixes display bug on re-run)
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Starting safety check...";
    for (NSTextField* label in self.resultLabels) {
        label.textColor = [NSColor labelColor];
    }
    self.resultTitleLabel.textColor = [NSColor labelColor];

    self.checkInProgress = YES;
    self.skipButton.enabled = NO;
    self.skipButton.hidden = NO;
    self.resultsView.hidden = YES;
    self.okButton.hidden = YES;

    self.safetyCheck = [[SCStartupSafetyCheck alloc] init];

    __weak typeof(self) weakSelf = self;

    [self.safetyCheck runWithProgressHandler:^(NSString* status, CGFloat progress) {
        [weakSelf updateProgress:progress status:status];
    } completionHandler:^(SCSafetyCheckResult* result) {
        weakSelf.checkInProgress = NO;
        [weakSelf showResults:result];

        if (weakSelf.completionHandler) {
            weakSelf.completionHandler(result);
        }
    }];
}

- (void)updateProgress:(CGFloat)progress status:(NSString*)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressIndicator.doubleValue = progress * 100;
        self.statusLabel.stringValue = status;

    });
}

- (void)showResults:(SCSafetyCheckResult*)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.resultsView.hidden = NO;
        self.okButton.hidden = NO;
        self.skipButton.hidden = YES;

        if (result.passed) {
            self.resultTitleLabel.stringValue = @"Safety Check Passed";
            self.resultTitleLabel.textColor = [NSColor systemGreenColor];
            self.statusLabel.stringValue = @"All blocking mechanisms verified!";
        } else {
            self.resultTitleLabel.stringValue = @"Safety Check Failed";
            self.resultTitleLabel.textColor = [NSColor systemRedColor];
            self.statusLabel.stringValue = @"Some mechanisms may not work.";
        }

        // Update result labels
        BOOL results[] = {
            result.hostsBlockWorked,
            result.pfBlockWorked,
            result.appBlockWorked,
            result.hostsUnblockWorked,
            result.pfUnblockWorked,
            result.appUnblockWorked,
            result.emergencyScriptWorked
        };

        NSArray* names = @[
            @"Hosts file blocking",
            @"Packet filter blocking",
            @"App blocking (Calculator)",
            @"Hosts file cleanup",
            @"Packet filter cleanup",
            @"App unblocking",
            @"Emergency script (emergency.sh)"
        ];

        for (NSUInteger i = 0; i < self.resultLabels.count && i < 7; i++) {
            NSTextField* label = self.resultLabels[i];
            BOOL passed = results[i];

            if (passed) {
                label.stringValue = [NSString stringWithFormat:@"\u2705 %@", names[i]];
                label.textColor = [NSColor labelColor];
            } else {
                label.stringValue = [NSString stringWithFormat:@"\u274C %@", names[i]];
                label.textColor = [NSColor systemRedColor];
            }
        }

        self.progressIndicator.doubleValue = 100;
    });
}

- (IBAction)skipClicked:(id)sender {
    if (self.checkInProgress) {
        [self.safetyCheck cancel];
    }

    [SCVersionTracker updateLastTestedVersions];

    if (self.skipHandler) {
        self.skipHandler();
    }

    [self.window close];
}

- (IBAction)okClicked:(id)sender {
    [self.window close];
}

- (void)cancelCheck {
    if (self.checkInProgress) {
        [self.safetyCheck cancel];
        self.checkInProgress = NO;
    }
}

@end
