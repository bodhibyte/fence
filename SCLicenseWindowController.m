//
//  SCLicenseWindowController.m
//  SelfControl
//
//  Modal sheet for license activation when trial has expired.
//

#import "SCLicenseWindowController.h"
#import "Common/SCLicenseManager.h"

#pragma mark - SCLicenseContentView (Private)

// Custom content view that handles Cmd+Q to quit even when sheet is modal
@interface SCLicenseContentView : NSView
@end

@implementation SCLicenseContentView

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

    return [super performKeyEquivalent:event];
}

@end

#pragma mark - SCLicenseWindowController

@interface SCLicenseWindowController () <NSWindowDelegate>

@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *messageLabel;
@property (nonatomic, strong) NSTextField *licenseCodeField;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) NSButton *activateButton;
@property (nonatomic, strong) NSButton *purchaseButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic, strong) NSProgressIndicator *spinner;

@end

@implementation SCLicenseWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 450, 280);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"License Required";

    // Use custom content view that handles Cmd+Q
    SCLicenseContentView *customContentView = [[SCLicenseContentView alloc] initWithFrame:frame];
    window.contentView = customContentView;

    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    CGFloat padding = 24;
    CGFloat width = contentView.bounds.size.width - (padding * 2);
    CGFloat y = contentView.bounds.size.height - padding;

    // Title
    y -= 28;
    self.titleLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width, 28)];
    self.titleLabel.stringValue = @"License Required";
    self.titleLabel.font = [NSFont boldSystemFontOfSize:18];
    self.titleLabel.bezeled = NO;
    self.titleLabel.editable = NO;
    self.titleLabel.selectable = NO;
    self.titleLabel.drawsBackground = NO;
    self.titleLabel.alignment = NSTextAlignmentCenter;
    [contentView addSubview:self.titleLabel];

    // Message
    y -= 50;
    self.messageLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width, 40)];
    self.messageLabel.stringValue = @"Enter your license key to unlock Fence, or purchase a license below.";
    self.messageLabel.font = [NSFont systemFontOfSize:13];
    self.messageLabel.bezeled = NO;
    self.messageLabel.editable = NO;
    self.messageLabel.selectable = NO;
    self.messageLabel.drawsBackground = NO;
    self.messageLabel.alignment = NSTextAlignmentCenter;
    self.messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.messageLabel.usesSingleLineMode = NO;
    [contentView addSubview:self.messageLabel];

    // License code field label
    y -= 30;
    NSTextField *fieldLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width, 18)];
    fieldLabel.stringValue = @"License Key:";
    fieldLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    fieldLabel.bezeled = NO;
    fieldLabel.editable = NO;
    fieldLabel.selectable = NO;
    fieldLabel.drawsBackground = NO;
    fieldLabel.textColor = [NSColor secondaryLabelColor];
    [contentView addSubview:fieldLabel];

    // License code text field (single-line with horizontal scroll)
    y -= 28;
    self.licenseCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width, 24)];
    self.licenseCodeField.placeholderString = @"FENCE-XXXXXXXXXXXXXXXXXXXXXXXX";
    self.licenseCodeField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.licenseCodeField.bezelStyle = NSTextFieldRoundedBezel;
    self.licenseCodeField.usesSingleLineMode = YES;
    self.licenseCodeField.cell.scrollable = YES;
    self.licenseCodeField.cell.wraps = NO;
    self.licenseCodeField.lineBreakMode = NSLineBreakByClipping;
    [contentView addSubview:self.licenseCodeField];

    // Error label
    y -= 22;
    self.errorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, y, width, 18)];
    self.errorLabel.stringValue = @"";
    self.errorLabel.font = [NSFont systemFontOfSize:11];
    self.errorLabel.textColor = [NSColor systemRedColor];
    self.errorLabel.bezeled = NO;
    self.errorLabel.editable = NO;
    self.errorLabel.selectable = NO;
    self.errorLabel.drawsBackground = NO;
    [contentView addSubview:self.errorLabel];

    // Spinner (next to error label, hidden initially)
    self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding + width - 20, y, 16, 16)];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.displayedWhenStopped = NO;
    [contentView addSubview:self.spinner];

    // Button row
    y = padding;
    CGFloat buttonWidth = 120;
    CGFloat buttonHeight = 32;
    CGFloat buttonSpacing = 12;

    // Cancel button (left)
    self.cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(padding, y, buttonWidth, buttonHeight)];
    self.cancelButton.title = @"Cancel";
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.target = self;
    self.cancelButton.action = @selector(cancelClicked:);
    [contentView addSubview:self.cancelButton];

    // Purchase button (middle)
    CGFloat purchaseX = (contentView.bounds.size.width - buttonWidth) / 2;
    self.purchaseButton = [[NSButton alloc] initWithFrame:NSMakeRect(purchaseX, y, buttonWidth, buttonHeight)];
    self.purchaseButton.title = @"Purchase";
    self.purchaseButton.bezelStyle = NSBezelStyleRounded;
    self.purchaseButton.target = self;
    self.purchaseButton.action = @selector(purchaseClicked:);
    [contentView addSubview:self.purchaseButton];

    // Activate button (right, primary)
    CGFloat activateX = contentView.bounds.size.width - padding - buttonWidth;
    self.activateButton = [[NSButton alloc] initWithFrame:NSMakeRect(activateX, y, buttonWidth, buttonHeight)];
    self.activateButton.title = @"Activate";
    self.activateButton.bezelStyle = NSBezelStyleRounded;
    self.activateButton.keyEquivalent = @"\r";  // Default button (Enter)
    self.activateButton.target = self;
    self.activateButton.action = @selector(activateClicked:);
    [contentView addSubview:self.activateButton];
}

#pragma mark - Sheet Presentation

- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
               completionHandler:(void (^)(NSModalResponse))handler {
    [parentWindow beginSheet:self.window completionHandler:^(NSModalResponse response) {
        if (handler) {
            handler(response);
        }
    }];
}

#pragma mark - Actions

- (void)activateClicked:(id)sender {
    NSString *code = [self.licenseCodeField.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (code.length == 0) {
        self.errorLabel.stringValue = @"Please enter a license code.";
        return;
    }

    // Clear previous error and show activating state
    self.errorLabel.stringValue = @"Activating...";
    self.errorLabel.textColor = [NSColor secondaryLabelColor];
    self.activateButton.enabled = NO;
    self.licenseCodeField.enabled = NO;
    [self.spinner startAnimation:nil];

    // Attempt online activation (async)
    [[SCLicenseManager sharedManager] activateLicenseOnline:code completion:^(BOOL success, NSString *errorMessage) {
        [self.spinner stopAnimation:nil];
        self.activateButton.enabled = YES;
        self.licenseCodeField.enabled = YES;

        if (success) {
            // Close the sheet
            [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];

            // Call the success callback
            if (self.onLicenseActivated) {
                self.onLicenseActivated();
            }
        } else {
            // Show error (reset to red color)
            self.errorLabel.textColor = [NSColor systemRedColor];
            self.errorLabel.stringValue = errorMessage ?: @"Activation failed. Please try again.";
        }
    }];
}

- (void)purchaseClicked:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://usefence.app/#pricing"]];
}

- (void)cancelClicked:(id)sender {
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseCancel];

    if (self.onCancel) {
        self.onCancel();
    }
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    // Allow closing, treat as cancel
    if (self.onCancel) {
        self.onCancel();
    }
    return YES;
}

@end
