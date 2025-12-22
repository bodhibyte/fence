//
//  SCDebugUtilities.h
//  SelfControl
//
//  Debug mode utilities - only functional in DEBUG builds.
//  In release builds, these methods are no-ops or return safe defaults.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCDebugUtilities : NSObject

/// Returns YES if debug blocking override is currently enabled.
/// Always returns NO in release builds - this is a critical safety feature.
+ (BOOL)isDebugBlockingDisabled;

/// Enable or disable the debug blocking override.
/// No-op in release builds - cannot be enabled in production.
+ (void)setDebugBlockingDisabled:(BOOL)disabled;

/// Returns YES if the current build is a debug build.
+ (BOOL)isDebugBuild;

@end

NS_ASSUME_NONNULL_END
