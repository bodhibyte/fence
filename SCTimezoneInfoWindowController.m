//
//  SCTimezoneInfoWindowController.m
//  SelfControl
//

#import "SCTimezoneInfoWindowController.h"

#pragma mark - SCTimezoneInfoContentView (Private)

// Custom content view that handles Cmd+Q to quit even when sheet is modal
@interface SCTimezoneInfoContentView : NSView
@end

@implementation SCTimezoneInfoContentView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags flags = [event modifierFlags];
    NSString *chars = [[event charactersIgnoringModifiers] lowercaseString];

    BOOL cmdPressed = (flags & NSEventModifierFlagCommand) != 0;
    BOOL shiftPressed = (flags & NSEventModifierFlagShift) != 0;

    // Cmd+Q = Quit (close sheet first, then terminate to avoid bonk)
    if (cmdPressed && !shiftPressed && [chars isEqualToString:@"q"]) {
        NSWindow *sheet = self.window;
        NSWindow *parent = sheet.sheetParent;
        if (parent) {
            [parent endSheet:sheet];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
        return YES;
    }

    // ESC = Close sheet
    if (event.keyCode == 53) { // ESC key
        NSWindow *sheet = self.window;
        NSWindow *parent = sheet.sheetParent;
        if (parent) {
            [parent endSheet:sheet];
        }
        return YES;
    }

    return [super performKeyEquivalent:event];
}

@end

#pragma mark - SCTimezoneInfoWindowController

@interface SCTimezoneInfoWindowController ()
@property (nonatomic, strong) NSButton *okButton;
@property (nonatomic, strong) id clickOutsideMonitor;
@end

@implementation SCTimezoneInfoWindowController

+ (void)showAsSheetForWindow:(NSWindow *)parentWindow {
    SCTimezoneInfoWindowController *controller = [[SCTimezoneInfoWindowController alloc] init];
    [parentWindow beginSheet:controller.window completionHandler:^(NSModalResponse returnCode) {
        [controller removeClickOutsideMonitor];
    }];
    [controller setupClickOutsideMonitor];
}

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 400, 310);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Timezone Information";

    // Use custom content view that handles Cmd+Q
    SCTimezoneInfoContentView *customContentView = [[SCTimezoneInfoContentView alloc] initWithFrame:frame];
    window.contentView = customContentView;

    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    CGFloat padding = 20;
    CGFloat y = contentView.bounds.size.height - padding;

    // Title
    y -= 28;
    NSTextField *titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 24)];
    titleLabel.stringValue = @"Planning to Travel?";
    titleLabel.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.bezeled = NO;
    titleLabel.editable = NO;
    titleLabel.drawsBackground = NO;
    [contentView addSubview:titleLabel];

    // Explanation text
    y -= 16;
    NSString *infoText = @"Block schedules are locked to your Mac's current timezone at the moment you commit. "
        @"This prevents bypassing blocks by changing your system timezone.\n\n"
        @"If you're traveling to a different timezone, you have two options:";

    NSTextField *explainLabel = [NSTextField wrappingLabelWithString:infoText];
    explainLabel.frame = NSMakeRect(padding, y - 70, contentView.bounds.size.width - padding * 2, 70);
    explainLabel.font = [NSFont systemFontOfSize:13];
    explainLabel.textColor = [NSColor labelColor];
    [contentView addSubview:explainLabel];
    y -= 80;

    // Option 1
    y -= 10;
    NSTextField *option1Title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 18)];
    option1Title.stringValue = @"Option 1: Adjust your block times manually";
    option1Title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    option1Title.textColor = [NSColor labelColor];
    option1Title.bezeled = NO;
    option1Title.editable = NO;
    option1Title.drawsBackground = NO;
    [contentView addSubview:option1Title];

    y -= 20;
    NSTextField *option1Detail = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 16, y, contentView.bounds.size.width - padding * 2 - 16, 18)];
    option1Detail.stringValue = @"e.g., add +3 hours if the destination is 3 hours ahead";
    option1Detail.font = [NSFont systemFontOfSize:12];
    option1Detail.textColor = [NSColor secondaryLabelColor];
    option1Detail.bezeled = NO;
    option1Detail.editable = NO;
    option1Detail.drawsBackground = NO;
    [contentView addSubview:option1Detail];

    // Option 2
    y -= 28;
    NSTextField *option2Title = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 18)];
    option2Title.stringValue = @"Option 2: Change your Mac's timezone before committing";
    option2Title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    option2Title.textColor = [NSColor labelColor];
    option2Title.bezeled = NO;
    option2Title.editable = NO;
    option2Title.drawsBackground = NO;
    [contentView addSubview:option2Title];

    y -= 20;
    NSTextField *option2Detail = [[NSTextField alloc] initWithFrame:NSMakeRect(padding + 16, y, contentView.bounds.size.width - padding * 2 - 16, 18)];
    option2Detail.stringValue = @"Set it to your destination timezone in System Settings";
    option2Detail.font = [NSFont systemFontOfSize:12];
    option2Detail.textColor = [NSColor secondaryLabelColor];
    option2Detail.bezeled = NO;
    option2Detail.editable = NO;
    option2Detail.drawsBackground = NO;
    [contentView addSubview:option2Detail];

    // Happy Travels sign-off
    y -= 28;
    NSTextField *signOff = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, contentView.bounds.size.width - padding * 2, 18)];
    signOff.stringValue = @"Happy Travels!";
    signOff.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    signOff.textColor = [NSColor secondaryLabelColor];
    signOff.bezeled = NO;
    signOff.editable = NO;
    signOff.drawsBackground = NO;
    [contentView addSubview:signOff];

    // OK button at bottom
    self.okButton = [[NSButton alloc] initWithFrame:NSMakeRect(contentView.bounds.size.width - padding - 80, padding, 80, 30)];
    self.okButton.title = @"Got It";
    self.okButton.bezelStyle = NSBezelStyleRounded;
    self.okButton.keyEquivalent = @"\r"; // Enter key
    self.okButton.target = self;
    self.okButton.action = @selector(okClicked:);
    [contentView addSubview:self.okButton];
}

- (void)setupClickOutsideMonitor {
    __weak typeof(self) weakSelf = self;
    self.clickOutsideMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
        NSWindow *sheet = weakSelf.window;
        NSPoint windowLocation = [event locationInWindow];

        // Check if click is outside the sheet
        if (event.window == sheet.sheetParent) {
            NSWindow *parent = sheet.sheetParent;
            if (parent) {
                [parent endSheet:sheet];
            }
        }
        return event;
    }];
}

- (void)removeClickOutsideMonitor {
    if (self.clickOutsideMonitor) {
        [NSEvent removeMonitor:self.clickOutsideMonitor];
        self.clickOutsideMonitor = nil;
    }
}

- (void)okClicked:(id)sender {
    NSWindow *sheet = self.window;
    NSWindow *parent = sheet.sheetParent;
    if (parent) {
        [parent endSheet:sheet];
    }
}

@end
