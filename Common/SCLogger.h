//
//  SCLogger.h
//  SelfControl
//
//  Log export utility for user support
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCLogger : NSObject

// Call on app startup to create ~/.fence/logs/ directory
+ (void)ensureDirectoriesExist;

// Export logs from the last 24 hours for Fence/selfcontrold processes
// Saves to ~/.fence/logs/fence-logs-{timestamp}.txt, reveals in Finder, opens email
+ (void)exportLogsForSupport;

@end

NS_ASSUME_NONNULL_END
