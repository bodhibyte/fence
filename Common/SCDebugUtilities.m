//
//  SCDebugUtilities.m
//  SelfControl
//
//  Debug mode utilities - only functional in DEBUG builds.
//

#import "SCDebugUtilities.h"
#import "SCSettings.h"

// Key for storing debug blocking state
static NSString* const kDebugBlockingDisabledKey = @"DebugBlockingDisabled";

@implementation SCDebugUtilities

+ (BOOL)isDebugBuild {
#ifdef DEBUG
    return YES;
#else
    return NO;
#endif
}

+ (BOOL)isDebugBlockingDisabled {
#ifdef DEBUG
    // In debug builds, check the setting
    SCSettings* settings = [SCSettings sharedSettings];
    return [settings boolForKey:kDebugBlockingDisabledKey];
#else
    // In release builds, ALWAYS return NO
    // This is a critical safety feature - blocking can never be disabled in production
    return NO;
#endif
}

+ (void)setDebugBlockingDisabled:(BOOL)disabled {
#ifdef DEBUG
    // Only allow setting in debug builds
    SCSettings* settings = [SCSettings sharedSettings];
    [settings setValue:@(disabled) forKey:kDebugBlockingDisabledKey];
    [settings synchronizeSettings];

    NSLog(@"DEBUG: Blocking %@ via debug override",
          disabled ? @"DISABLED" : @"ENABLED");
#else
    // No-op in release builds - log warning for visibility
    NSLog(@"WARNING: Attempted to set debug blocking in release build - ignored");
#endif
}

@end
