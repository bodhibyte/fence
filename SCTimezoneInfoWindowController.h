//
//  SCTimezoneInfoWindowController.h
//  SelfControl
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Modal dialog explaining timezone behavior for travelers
@interface SCTimezoneInfoWindowController : NSWindowController

/// Show the timezone info dialog as a sheet attached to the parent window
/// @param parentWindow The window to attach the sheet to
+ (void)showAsSheetForWindow:(NSWindow *)parentWindow;

@end

NS_ASSUME_NONNULL_END
