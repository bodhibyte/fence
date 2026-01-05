//
//  SCLogExportWindowController.m
//  SelfControl
//
//  Window controller for the log export loading indicator.
//  Creates UI programmatically (no XIB needed).
//

#import "SCLogExportWindowController.h"

#pragma mark - SCLogExportContentView (Private)

// Custom content view that handles Cmd+Q to quit even when window is displayed
@interface SCLogExportContentView : NSView
@end

@implementation SCLogExportContentView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags flags = [event modifierFlags];
    NSString *chars = [[event charactersIgnoringModifiers] lowercaseString];

    BOOL cmdPressed = (flags & NSEventModifierFlagCommand) != 0;
    BOOL shiftPressed = (flags & NSEventModifierFlagShift) != 0;

    // Cmd+Q = Quit (close window first, then terminate to avoid bonk)
    if (cmdPressed && !shiftPressed && [chars isEqualToString:@"q"]) {
        [self.window close];
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
        return YES;
    }

    return [super performKeyEquivalent:event];
}

@end

#pragma mark - SCLogExportWindowController

@interface SCLogExportWindowController ()

@property (nonatomic, strong) NSProgressIndicator *progressIndicator;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *noteLabel;

@end

@implementation SCLogExportWindowController

static SCLogExportWindowController *_sharedController = nil;

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedController = [[SCLogExportWindowController alloc] init];
    });
    return _sharedController;
}

- (instancetype)init {
    // Create window programmatically
    NSRect frame = NSMakeRect(0, 0, 350, 160);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Capturing Logs";

    // Use custom content view that handles Cmd+Q
    SCLogExportContentView *customContentView = [[SCLogExportContentView alloc] initWithFrame:frame];
    window.contentView = customContentView;

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    CGFloat padding = 24;
    CGFloat width = contentView.bounds.size.width - (padding * 2);
    CGFloat y = contentView.bounds.size.height - padding;

    // Title label
    y -= 24;
    self.titleLabel = [self createLabelWithText:@"Capturing Logs..." fontSize:16 bold:YES];
    self.titleLabel.frame = NSMakeRect(padding, y, width, 24);
    self.titleLabel.alignment = NSTextAlignmentCenter;
    [contentView addSubview:self.titleLabel];

    // Progress indicator (indeterminate bar)
    y -= 30;
    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, y, width, 20)];
    self.progressIndicator.style = NSProgressIndicatorStyleBar;
    self.progressIndicator.indeterminate = YES;
    [contentView addSubview:self.progressIndicator];

    // Status label
    y -= 28;
    self.statusLabel = [self createLabelWithText:@"Collecting system logs for support..." fontSize:13 bold:NO];
    self.statusLabel.frame = NSMakeRect(padding, y, width, 20);
    self.statusLabel.alignment = NSTextAlignmentCenter;
    [contentView addSubview:self.statusLabel];

    // Warning note (red text)
    y -= 24;
    self.noteLabel = [self createLabelWithText:@"Note: this can sometimes take a few minutes." fontSize:12 bold:NO];
    self.noteLabel.frame = NSMakeRect(padding, y, width, 18);
    self.noteLabel.alignment = NSTextAlignmentCenter;
    self.noteLabel.textColor = [NSColor systemRedColor];
    [contentView addSubview:self.noteLabel];
}

- (NSTextField *)createLabelWithText:(NSString *)text fontSize:(CGFloat)fontSize bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] init];
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

- (void)show {
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window setLevel:NSFloatingWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
    [self.progressIndicator startAnimation:nil];
}

- (void)close {
    [self.progressIndicator stopAnimation:nil];
    [self.window close];
}

@end
