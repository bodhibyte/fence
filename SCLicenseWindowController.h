//
//  SCLicenseWindowController.h
//  SelfControl
//
//  Modal sheet for license activation when trial has expired.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCLicenseWindowController : NSWindowController

/// Called when a valid license is activated successfully
@property (nonatomic, copy, nullable) void (^onLicenseActivated)(void);

/// Called when the user cancels (closes without activating)
@property (nonatomic, copy, nullable) void (^onCancel)(void);

/// Present as a sheet on the given parent window
- (void)beginSheetModalForWindow:(NSWindow *)parentWindow
               completionHandler:(void (^_Nullable)(NSModalResponse))handler;

@end

NS_ASSUME_NONNULL_END
