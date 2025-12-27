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

+ (BOOL)clearExistingBlockingRules {
#ifdef DEBUG
    NSLog(@"DEBUG: Clearing existing blocking rules...");

    // Build the shell script to clear all blocking rules
    // This needs to run with admin privileges
    NSString *script = @""
        // Clear PF firewall rules
        "pfctl -a org.eyebeam -F all 2>/dev/null; "
        // Clear hosts file entries
        "sed -i '' '/# BEGIN SELFCONTROL BLOCK/,/# END SELFCONTROL BLOCK/d' /etc/hosts; "
        // Flush DNS cache
        "dscacheutil -flushcache; "
        "killall -HUP mDNSResponder 2>/dev/null; "
        "echo 'done'";

    // Use AppleScript to run the command with admin privileges
    NSString *appleScript = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges", script];

    NSDictionary *errorDict = nil;
    NSAppleScript *scriptObject = [[NSAppleScript alloc] initWithSource:appleScript];
    NSAppleEventDescriptor *result = [scriptObject executeAndReturnError:&errorDict];

    if (errorDict) {
        NSLog(@"DEBUG: Failed to clear blocking rules: %@", errorDict);
        return NO;
    }

    NSLog(@"DEBUG: Successfully cleared blocking rules. Result: %@", [result stringValue]);
    return YES;
#else
    // No-op in release builds
    NSLog(@"WARNING: Attempted to clear blocking rules in release build - ignored");
    return NO;
#endif
}

@end
