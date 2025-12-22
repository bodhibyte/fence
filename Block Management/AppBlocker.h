//
//  AppBlocker.h
//  SelfControl
//
//  Monitors running applications and terminates blocked apps.
//  Uses low-level libproc APIs to work in daemon context (no NSWorkspace).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppBlocker : NSObject

/// Set of bundle IDs to block (e.g., "com.apple.Terminal")
@property (nonatomic, readonly) NSSet<NSString*>* blockedBundleIDs;

/// Whether the blocker is currently monitoring
@property (nonatomic, readonly) BOOL isMonitoring;

/// Add an app bundle ID to the blocklist
- (void)addBlockedApp:(NSString*)bundleID;

/// Remove an app from the blocklist
- (void)removeBlockedApp:(NSString*)bundleID;

/// Start monitoring and killing blocked apps (poll every 500ms)
- (void)startMonitoring;

/// Stop monitoring
- (void)stopMonitoring;

/// Immediately scan and kill any running blocked apps
/// @return Array of PIDs (as NSNumber) that were terminated
- (NSArray<NSNumber*>*)findAndKillBlockedApps;

/// Clear all blocked apps (used when block ends)
- (void)clearAllBlockedApps;

@end

NS_ASSUME_NONNULL_END
