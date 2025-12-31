//
//  SCVersionTracker.h
//  SelfControl
//
//  Tracks app and OS versions for safety check triggering.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCVersionTracker : NSObject

// Current versions
+ (NSString*)currentAppVersion;
+ (NSString*)currentOSVersion;

// Last tested versions (stored in UserDefaults)
+ (nullable NSString*)lastTestedAppVersion;
+ (nullable NSString*)lastTestedOSVersion;

// Update tracked versions to current
+ (void)updateLastTestedVersions;

// Check if versions changed since last test
+ (BOOL)appVersionChanged;
+ (BOOL)osVersionChanged;
+ (BOOL)anyVersionChanged;

// Clear stored versions (for testing)
+ (void)clearStoredVersions;

// Test block completion tracking
+ (BOOL)hasCompletedTestBlock;
+ (void)markTestBlockCompleted;
+ (BOOL)testBlockNeeded;

@end

NS_ASSUME_NONNULL_END
