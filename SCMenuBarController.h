//
//  SCMenuBarController.h
//  SelfControl
//
//  Menu bar status item showing current blocking status.
//  Displays which bundles are allowed/blocked and commitment info.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SCMenuBarController;

@protocol SCMenuBarControllerDelegate <NSObject>

/// Called when user clicks "Open SelfControl" in menu
- (void)menuBarControllerDidRequestOpenApp:(SCMenuBarController *)controller;

@end

@interface SCMenuBarController : NSObject

@property (nonatomic, weak, nullable) id<SCMenuBarControllerDelegate> delegate;

/// The status item in the menu bar
@property (nonatomic, strong, readonly) NSStatusItem *statusItem;

/// Whether the menu bar item is visible
@property (nonatomic, assign) BOOL isVisible;

/// Shared instance
+ (instancetype)sharedController;

/// Updates the menu bar display with current status
- (void)updateStatus;

/// Shows/hides the menu bar item
- (void)setVisible:(BOOL)visible;

@end

NS_ASSUME_NONNULL_END
