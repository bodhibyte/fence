//
//  SCWeekScheduleWindowController.h
//  SelfControl
//
//  Main window controller for the weekly schedule view.
//  Shows the week grid, current status, and controls for bundles and commitment.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCWeekScheduleWindowController : NSWindowController

/// Show the week schedule window
- (void)showWindow:(nullable id)sender;

/// Reload all data
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
