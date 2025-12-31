//
//  SCVersionTracker.m
//  SelfControl
//
//  Tracks app and OS versions for safety check triggering.
//

#import "SCVersionTracker.h"

static NSString* const kLastTestedAppVersionKey = @"SCSafetyCheck_LastTestedAppVersion";
static NSString* const kLastTestedOSVersionKey = @"SCSafetyCheck_LastTestedOSVersion";
static NSString* const kTestBlockCompletedKey = @"SCTestBlock_Completed";

@implementation SCVersionTracker

+ (NSString*)currentAppVersion {
    NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString* build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    if (version && build) {
        return [NSString stringWithFormat:@"%@ (%@)", version, build];
    } else if (version) {
        return version;
    }
    return @"unknown";
}

+ (NSString*)currentOSVersion {
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)osVersion.majorVersion,
            (long)osVersion.minorVersion,
            (long)osVersion.patchVersion];
}

+ (nullable NSString*)lastTestedAppVersion {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kLastTestedAppVersionKey];
}

+ (nullable NSString*)lastTestedOSVersion {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kLastTestedOSVersionKey];
}

+ (void)updateLastTestedVersions {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[self currentAppVersion] forKey:kLastTestedAppVersionKey];
    [defaults setObject:[self currentOSVersion] forKey:kLastTestedOSVersionKey];
    [defaults synchronize];

    NSLog(@"SCVersionTracker: Updated last tested versions - App: %@, OS: %@",
          [self currentAppVersion], [self currentOSVersion]);
}

+ (BOOL)appVersionChanged {
    NSString* lastTested = [self lastTestedAppVersion];
    if (!lastTested) return YES; // Never tested
    return ![lastTested isEqualToString:[self currentAppVersion]];
}

+ (BOOL)osVersionChanged {
    NSString* lastTested = [self lastTestedOSVersion];
    if (!lastTested) return YES; // Never tested
    return ![lastTested isEqualToString:[self currentOSVersion]];
}

+ (BOOL)anyVersionChanged {
    return [self appVersionChanged] || [self osVersionChanged];
}

+ (void)clearStoredVersions {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kLastTestedAppVersionKey];
    [defaults removeObjectForKey:kLastTestedOSVersionKey];
    [defaults synchronize];

    NSLog(@"SCVersionTracker: Cleared stored versions");
}

+ (BOOL)hasCompletedTestBlock {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTestBlockCompletedKey];
}

+ (void)markTestBlockCompleted {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kTestBlockCompletedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"SCVersionTracker: Marked test block as completed");
}

+ (BOOL)testBlockNeeded {
    return ![self hasCompletedTestBlock];
}

@end
