//
//  SCSafetyCheckWindowController.h
//  SelfControl
//
//  Window controller for the startup safety check UI.
//  Creates UI programmatically (no XIB needed).
//

#import <Cocoa/Cocoa.h>

@class SCSafetyCheckResult;

NS_ASSUME_NONNULL_BEGIN

@interface SCSafetyCheckWindowController : NSWindowController

// Callbacks
@property (nonatomic, copy, nullable) void(^skipHandler)(void);
@property (nonatomic, copy, nullable) void(^completionHandler)(SCSafetyCheckResult* result);

// Actions
- (IBAction)skipClicked:(id)sender;
- (IBAction)okClicked:(id)sender;

// Control methods
- (void)runSafetyCheck;
- (void)cancelCheck;
- (void)updateProgress:(CGFloat)progress status:(NSString*)status;
- (void)showResults:(SCSafetyCheckResult*)result;

@end

NS_ASSUME_NONNULL_END
