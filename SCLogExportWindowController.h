//
//  SCLogExportWindowController.h
//  SelfControl
//
//  Window controller for the log export loading indicator.
//  Shows a progress indicator while logs are being captured.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCLogExportWindowController : NSWindowController

/// Returns the shared instance (singleton)
+ (instancetype)sharedController;

/// Shows the loading window and starts the progress animation
- (void)show;

/// Stops the animation and closes the window
- (void)close;

@end

NS_ASSUME_NONNULL_END
