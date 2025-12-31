//
//  SCTestBlockWindowController.h
//  SelfControl
//
//  Window controller for the "Try Test Block" onboarding feature.
//  Allows users to test blocking without committing to a full schedule.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCTestBlockWindowController : NSWindowController

/// Completion handler called when the test block flow completes
/// @param didComplete YES if the test ran (stopped or expired), NO if cancelled
@property (nonatomic, copy, nullable) void (^completionHandler)(BOOL didComplete);

@end

NS_ASSUME_NONNULL_END
