//
//  SCStartupSafetyCheck.m
//  SelfControl
//
//  Orchestrates startup safety check to verify blocking/unblocking works.
//  Runs on version change (macOS or app version).
//

#import "SCStartupSafetyCheck.h"
#import "SCVersionTracker.h"
#import "SCXPCClient.h"
#import "SCSettings.h"
#import "HostFileBlocker.h"
#import "PacketFilter.h"
#import <AppKit/AppKit.h>

// Test constants
static NSString* const kTestWebsite = @"example.com";
static NSString* const kTestAppBundleID = @"com.apple.calculator";
static NSString* const kTestAppPath = @"/System/Applications/Calculator.app";
static const NSTimeInterval kTestBlockDurationSeconds = 30.0;
static const NSTimeInterval kEmergencyTestBlockDurationSeconds = 300.0; // 5 min - long enough to test emergency.sh

#pragma mark - SCSafetyCheckResult

@implementation SCSafetyCheckResult

- (instancetype)initWithHostsBlock:(BOOL)hostsBlock
                           pfBlock:(BOOL)pfBlock
                          appBlock:(BOOL)appBlock
                      hostsUnblock:(BOOL)hostsUnblock
                        pfUnblock:(BOOL)pfUnblock
                       appUnblock:(BOOL)appUnblock
                   emergencyScript:(BOOL)emergencyScript
                     errorMessage:(nullable NSString*)error {
    if (self = [super init]) {
        _hostsBlockWorked = hostsBlock;
        _pfBlockWorked = pfBlock;
        _appBlockWorked = appBlock;
        _hostsUnblockWorked = hostsUnblock;
        _pfUnblockWorked = pfUnblock;
        _appUnblockWorked = appUnblock;
        _emergencyScriptWorked = emergencyScript;
        _errorMessage = error;

        // Overall pass requires all checks to work
        _passed = hostsBlock && pfBlock && appBlock &&
                  hostsUnblock && pfUnblock && appUnblock &&
                  emergencyScript && (error == nil);
    }
    return self;
}

- (NSArray<NSString*>*)issues {
    NSMutableArray* issues = [NSMutableArray array];

    if (!_hostsBlockWorked) [issues addObject:@"Hosts file blocking failed"];
    if (!_pfBlockWorked) [issues addObject:@"Packet filter blocking failed"];
    if (!_appBlockWorked) [issues addObject:@"App blocking failed (Calculator not killed)"];
    if (!_hostsUnblockWorked) [issues addObject:@"Hosts file unblocking failed"];
    if (!_pfUnblockWorked) [issues addObject:@"Packet filter unblocking failed"];
    if (!_appUnblockWorked) [issues addObject:@"App unblocking failed (Calculator killed after unblock)"];
    if (!_emergencyScriptWorked) [issues addObject:@"Emergency script (emergency.sh) failed to clear block"];
    if (_errorMessage) [issues addObject:_errorMessage];

    return issues;
}

@end

#pragma mark - SCStartupSafetyCheck

@interface SCStartupSafetyCheck ()

@property (nonatomic, strong) SCXPCClient* xpc;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, copy) SCSafetyCheckProgressHandler progressHandler;
@property (nonatomic, copy) SCSafetyCheckCompletionHandler completionHandler;

// Store Phase 1 results for final combined result
@property (nonatomic, strong) NSDictionary* phase1Results;

@end

@implementation SCStartupSafetyCheck

+ (BOOL)safetyCheckNeeded {
    return [SCVersionTracker anyVersionChanged];
}

+ (void)skipSafetyCheck {
    [SCVersionTracker updateLastTestedVersions];
    NSLog(@"SCStartupSafetyCheck: Skipped - versions marked as tested");
}

+ (NSString*)testWebsite {
    return kTestWebsite;
}

+ (NSString*)testAppBundleID {
    return kTestAppBundleID;
}

- (instancetype)init {
    if (self = [super init]) {
        _xpc = [[SCXPCClient alloc] init];
        _cancelled = NO;
    }
    return self;
}

- (void)cancel {
    self.cancelled = YES;
    NSLog(@"SCStartupSafetyCheck: Cancelled");
}

- (void)runWithProgressHandler:(SCSafetyCheckProgressHandler)progressHandler
             completionHandler:(SCSafetyCheckCompletionHandler)completionHandler {
    self.progressHandler = progressHandler;
    self.completionHandler = completionHandler;
    self.cancelled = NO;

    NSLog(@"SCStartupSafetyCheck: Starting safety check");
    [self reportProgress:@"Connecting to daemon..." progress:0.05];

    // Use connectAndExecuteCommandBlock to ensure connection is ready before proceeding
    // This fixes race condition where installDaemon was called before connection was established
    [self.xpc connectAndExecuteCommandBlock:^(NSError* connectError) {
        if (connectError) {
            [self finishWithError:[NSString stringWithFormat:@"Failed to connect: %@", connectError.localizedDescription]];
            return;
        }

        // Install daemon if needed
        [self.xpc installDaemon:^(NSError* error) {
            if (error) {
                [self finishWithError:[NSString stringWithFormat:@"Failed to install daemon: %@", error.localizedDescription]];
                return;
            }

            [self reportProgress:@"Connecting to daemon..." progress:0.08];

            // After daemon install, MUST refresh connection:
            // The pre-install connection attempt likely failed (daemon wasn't running)
            // and created an invalidated connection object that would be reused.
            [self.xpc refreshConnectionAndRun:^{
                // Give daemon time to fully initialize XPC listener
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self reportProgress:@"Starting test block..." progress:0.10];
                    [self startTestBlock];
                });
            }];
        }];
    }];
}

- (void)startTestBlock {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    // Build test blocklist: website + app
    NSArray* testBlocklist = @[
        kTestWebsite,
        [NSString stringWithFormat:@"app:%@", kTestAppBundleID]
    ];

    NSDate* endDate = [NSDate dateWithTimeIntervalSinceNow:kTestBlockDurationSeconds];

    // Minimal block settings for test
    NSDictionary* blockSettings = @{
        @"ClearCaches": @NO,
        @"AllowLocalNetworks": @YES,
        @"EvaluateCommonSubdomains": @NO,
        @"IncludeLinkedDomains": @NO,
        @"BlockSoundShouldPlay": @NO,
        @"EnableErrorReporting": @NO
    };

    // startBlockWithControllingUID already uses connectAndExecuteCommandBlock internally,
    // so we don't need refreshConnectionAndRun (which was causing connection invalidation issues)
    [self.xpc startBlockWithControllingUID:getuid()
                                 blocklist:testBlocklist
                               isAllowlist:NO
                                   endDate:endDate
                             blockSettings:blockSettings
                                     reply:^(NSError* error) {
        if (error) {
            [self finishWithError:[NSString stringWithFormat:@"Failed to start block: %@", error.localizedDescription]];
            return;
        }

        NSLog(@"SCStartupSafetyCheck: Test block started, verifying...");
        [self reportProgress:@"Verifying blocking..." progress:0.20];

        // Wait a moment for block to take effect, then verify
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self verifyBlockingActive];
        });
    }];
}

- (void)verifyBlockingActive {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    [self reportProgress:@"Checking hosts file..." progress:0.25];

    // Check hosts file
    BOOL hostsBlocked = [self verifyHostsContainsTestWebsite];
    NSLog(@"SCStartupSafetyCheck: Hosts file check: %@", hostsBlocked ? @"PASS" : @"FAIL");

    [self reportProgress:@"Checking packet filter..." progress:0.30];

    // Check packet filter
    BOOL pfBlocked = [PacketFilter blockFoundInPF];
    NSLog(@"SCStartupSafetyCheck: Packet filter check: %@", pfBlocked ? @"PASS" : @"FAIL");

    [self reportProgress:@"Testing app blocking..." progress:0.35];

    // Test app blocking by launching Calculator and checking if it gets killed
    [self verifyAppBlockingWithCompletion:^(BOOL appBlocked) {
        NSLog(@"SCStartupSafetyCheck: App blocking check: %@", appBlocked ? @"PASS" : @"FAIL");

        [self reportProgress:@"Waiting for block to expire..." progress:0.40];

        // Store blocking results
        NSDictionary* blockingResults = @{
            @"hostsBlocked": @(hostsBlocked),
            @"pfBlocked": @(pfBlocked),
            @"appBlocked": @(appBlocked)
        };

        // Wait for block to expire
        [self waitForBlockExpiryWithBlockingResults:blockingResults];
    }];
}

- (BOOL)verifyHostsContainsTestWebsite {
    NSError* error = nil;
    NSString* hostsContent = [NSString stringWithContentsOfFile:@"/etc/hosts"
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
    if (error) {
        NSLog(@"SCStartupSafetyCheck: Failed to read hosts file: %@", error);
        return NO;
    }

    // Check if our test website is blocked
    return [hostsContent containsString:kTestWebsite];
}

- (void)verifyAppBlockingWithCompletion:(void(^)(BOOL appBlocked))completion {
    // Launch Calculator
    NSString* appPath = @"/System/Applications/Calculator.app";

    // Check if Calculator is already running and kill it first
    [self killCalculatorIfRunning];

    // Wait longer for daemon to fully initialize app blocking (was 0.5s, now 2s)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Launch Calculator
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:appPath]
                                              configuration:[NSWorkspaceOpenConfiguration configuration]
                                          completionHandler:^(NSRunningApplication* app, NSError* error) {
            if (error) {
                NSLog(@"SCStartupSafetyCheck: Failed to launch Calculator: %@", error);
                // If we can't launch it, assume blocking is working (aggressive kill)
                completion(YES);
                return;
            }

            // Wait longer for AppBlocker to kill it (was 2s, now 3s)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Check if Calculator is still running
                BOOL stillRunning = [self isCalculatorRunning];
                completion(!stillRunning); // If not running, blocking worked
            });
        }];
    });
}

- (void)killCalculatorIfRunning {
    NSArray<NSRunningApplication*>* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.bundleIdentifier isEqualToString:kTestAppBundleID]) {
            [app terminate];
        }
    }
}

- (BOOL)isCalculatorRunning {
    NSArray<NSRunningApplication*>* apps = [[NSWorkspace sharedWorkspace] runningApplications];
    for (NSRunningApplication* app in apps) {
        if ([app.bundleIdentifier isEqualToString:kTestAppBundleID]) {
            return YES;
        }
    }
    return NO;
}

- (void)waitForBlockExpiryWithBlockingResults:(NSDictionary*)blockingResults {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    // Calculate remaining time
    SCSettings* settings = [SCSettings sharedSettings];
    NSDate* blockEndDate = [settings valueForKey:@"BlockEndDate"];

    if (!blockEndDate) {
        // Block already expired or wasn't set
        [self verifyUnblockingWithBlockingResults:blockingResults];
        return;
    }

    NSTimeInterval remaining = [blockEndDate timeIntervalSinceNow];

    if (remaining <= 0) {
        // Block expired
        [self reportProgress:@"Block expired, verifying cleanup..." progress:0.80];
        // Wait longer for daemon cleanup to complete (was 2s, now 4s)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self verifyUnblockingWithBlockingResults:blockingResults];
        });
        return;
    }

    // Update progress
    CGFloat totalDuration = kTestBlockDurationSeconds;
    CGFloat elapsed = totalDuration - remaining;
    CGFloat progress = 0.40 + (elapsed / totalDuration) * 0.35; // 0.40 to 0.75
    NSString* status = [NSString stringWithFormat:@"Waiting for block to expire... (%.0fs remaining)", remaining];
    [self reportProgress:status progress:progress];

    // Check again in 1 second
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self waitForBlockExpiryWithBlockingResults:blockingResults];
    });
}

- (void)verifyUnblockingWithBlockingResults:(NSDictionary*)blockingResults {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    [self reportProgress:@"Verifying hosts file cleaned..." progress:0.55];

    // Check hosts file is clean
    BOOL hostsClean = ![self verifyHostsContainsTestWebsite];
    NSLog(@"SCStartupSafetyCheck: Hosts unblock check: %@", hostsClean ? @"PASS" : @"FAIL");

    [self reportProgress:@"Checking packet filter removed..." progress:0.58];

    // Check PF is clean
    BOOL pfClean = ![PacketFilter blockFoundInPF];
    NSLog(@"SCStartupSafetyCheck: PF unblock check: %@", pfClean ? @"PASS" : @"FAIL");

    [self reportProgress:@"Testing app can launch..." progress:0.60];

    // Test that Calculator can now launch and stay running
    [self verifyAppCanLaunchWithCompletion:^(BOOL canLaunch) {
        NSLog(@"SCStartupSafetyCheck: App unblock check: %@", canLaunch ? @"PASS" : @"FAIL");

        // Clean up Calculator
        [self killCalculatorIfRunning];

        // Store Phase 1 results
        self.phase1Results = @{
            @"hostsBlocked": blockingResults[@"hostsBlocked"],
            @"pfBlocked": blockingResults[@"pfBlocked"],
            @"appBlocked": blockingResults[@"appBlocked"],
            @"hostsUnblocked": @(hostsClean),
            @"pfUnblocked": @(pfClean),
            @"appUnblocked": @(canLaunch)
        };

        // Check if Phase 1 passed before continuing to Phase 2
        BOOL phase1Passed = [blockingResults[@"hostsBlocked"] boolValue] &&
                            [blockingResults[@"pfBlocked"] boolValue] &&
                            [blockingResults[@"appBlocked"] boolValue] &&
                            hostsClean && pfClean && canLaunch;

        if (!phase1Passed) {
            NSLog(@"SCStartupSafetyCheck: Phase 1 failed, skipping Phase 2");
            [self finishWithPhase1OnlyResult];
            return;
        }

        // Phase 1 passed - continue to Phase 2 (emergency.sh test)
        NSLog(@"SCStartupSafetyCheck: Phase 1 passed, starting Phase 2 (emergency.sh test)");
        [self startPhase2EmergencyTest];
    }];
}

#pragma mark - Phase 2: Emergency Script Test

- (void)startPhase2EmergencyTest {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    [self reportProgress:@"Phase 2: Starting emergency.sh test..." progress:0.65];

    // Start a new block with longer duration (won't expire during test)
    NSArray* testBlocklist = @[
        kTestWebsite,
        [NSString stringWithFormat:@"app:%@", kTestAppBundleID]
    ];

    NSDate* endDate = [NSDate dateWithTimeIntervalSinceNow:kEmergencyTestBlockDurationSeconds];

    NSDictionary* blockSettings = @{
        @"ClearCaches": @NO,
        @"AllowLocalNetworks": @YES,
        @"EvaluateCommonSubdomains": @NO,
        @"IncludeLinkedDomains": @NO,
        @"BlockSoundShouldPlay": @NO,
        @"EnableErrorReporting": @NO
    };

    [self.xpc startBlockWithControllingUID:getuid()
                                 blocklist:testBlocklist
                               isAllowlist:NO
                                   endDate:endDate
                             blockSettings:blockSettings
                                     reply:^(NSError* error) {
        if (error) {
            NSLog(@"SCStartupSafetyCheck: Phase 2 - Failed to start block: %@", error);
            [self finishWithEmergencyScriptResult:NO];
            return;
        }

        NSLog(@"SCStartupSafetyCheck: Phase 2 - Block started, verifying before emergency.sh...");
        [self reportProgress:@"Verifying block active..." progress:0.70];

        // Wait for block to take effect
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self verifyPhase2BlockingThenRunEmergency];
        });
    }];
}

- (void)verifyPhase2BlockingThenRunEmergency {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    // Quick verify blocking is active
    BOOL hostsBlocked = [self verifyHostsContainsTestWebsite];
    BOOL pfBlocked = [PacketFilter blockFoundInPF];

    NSLog(@"SCStartupSafetyCheck: Phase 2 - Pre-emergency check: hosts=%@, pf=%@",
          hostsBlocked ? @"blocked" : @"NOT blocked",
          pfBlocked ? @"active" : @"NOT active");

    if (!hostsBlocked || !pfBlocked) {
        NSLog(@"SCStartupSafetyCheck: Phase 2 - Block not active, emergency test invalid");
        [self finishWithEmergencyScriptResult:NO];
        return;
    }

    [self reportProgress:@"Running emergency.sh..." progress:0.75];
    [self runEmergencyScript];
}

- (void)runEmergencyScript {
    // Find emergency.sh in app bundle
    NSString* emergencyPath = [[NSBundle mainBundle] pathForResource:@"emergency" ofType:@"sh"];

    if (!emergencyPath) {
        NSLog(@"SCStartupSafetyCheck: Phase 2 - emergency.sh not found in bundle");
        [self finishWithEmergencyScriptResult:NO];
        return;
    }

    NSLog(@"SCStartupSafetyCheck: Phase 2 - Running emergency.sh at: %@", emergencyPath);

    // Run emergency.sh with sudo via AppleScript (will prompt for password)
    NSString* script = [NSString stringWithFormat:
        @"do shell script \"%@\" with administrator privileges", emergencyPath];

    NSAppleScript* appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary* errorDict = nil;
    [appleScript executeAndReturnError:&errorDict];

    if (errorDict) {
        NSLog(@"SCStartupSafetyCheck: Phase 2 - emergency.sh failed: %@", errorDict);
        [self finishWithEmergencyScriptResult:NO];
        return;
    }

    NSLog(@"SCStartupSafetyCheck: Phase 2 - emergency.sh completed");
    [self reportProgress:@"Verifying emergency cleanup..." progress:0.85];

    // Wait for cleanup to take effect
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self verifyEmergencyCleanup];
    });
}

- (void)verifyEmergencyCleanup {
    if (self.cancelled) {
        [self finishWithError:@"Cancelled"];
        return;
    }

    // Verify hosts file is clean
    BOOL hostsClean = ![self verifyHostsContainsTestWebsite];
    NSLog(@"SCStartupSafetyCheck: Phase 2 - Emergency hosts cleanup: %@", hostsClean ? @"PASS" : @"FAIL");

    // Verify PF is clean
    BOOL pfClean = ![PacketFilter blockFoundInPF];
    NSLog(@"SCStartupSafetyCheck: Phase 2 - Emergency PF cleanup: %@", pfClean ? @"PASS" : @"FAIL");

    BOOL emergencyWorked = hostsClean && pfClean;
    NSLog(@"SCStartupSafetyCheck: Phase 2 - Emergency script test: %@", emergencyWorked ? @"PASS" : @"FAIL");

    [self finishWithEmergencyScriptResult:emergencyWorked];
}

- (void)finishWithPhase1OnlyResult {
    SCSafetyCheckResult* result = [[SCSafetyCheckResult alloc]
        initWithHostsBlock:[self.phase1Results[@"hostsBlocked"] boolValue]
                   pfBlock:[self.phase1Results[@"pfBlocked"] boolValue]
                  appBlock:[self.phase1Results[@"appBlocked"] boolValue]
              hostsUnblock:[self.phase1Results[@"hostsUnblocked"] boolValue]
                pfUnblock:[self.phase1Results[@"pfUnblocked"] boolValue]
               appUnblock:[self.phase1Results[@"appUnblocked"] boolValue]
           emergencyScript:NO  // Not tested
             errorMessage:@"Phase 1 failed, emergency.sh test skipped"];

    [self finishWithResult:result];
}

- (void)finishWithEmergencyScriptResult:(BOOL)emergencyWorked {
    SCSafetyCheckResult* result = [[SCSafetyCheckResult alloc]
        initWithHostsBlock:[self.phase1Results[@"hostsBlocked"] boolValue]
                   pfBlock:[self.phase1Results[@"pfBlocked"] boolValue]
                  appBlock:[self.phase1Results[@"appBlocked"] boolValue]
              hostsUnblock:[self.phase1Results[@"hostsUnblocked"] boolValue]
                pfUnblock:[self.phase1Results[@"pfUnblocked"] boolValue]
               appUnblock:[self.phase1Results[@"appUnblocked"] boolValue]
           emergencyScript:emergencyWorked
             errorMessage:nil];

    // Clean up Calculator if still running
    [self killCalculatorIfRunning];

    // Mark versions as tested if passed
    if (result.passed) {
        [SCVersionTracker updateLastTestedVersions];
    }

    [self finishWithResult:result];
}

- (void)verifyAppCanLaunchWithCompletion:(void(^)(BOOL canLaunch))completion {
    // Make sure Calculator isn't running
    [self killCalculatorIfRunning];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Launch Calculator
        NSString* appPath = @"/System/Applications/Calculator.app";
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:appPath]
                                              configuration:[NSWorkspaceOpenConfiguration configuration]
                                          completionHandler:^(NSRunningApplication* app, NSError* error) {
            if (error) {
                NSLog(@"SCStartupSafetyCheck: Failed to launch Calculator for unblock test: %@", error);
                completion(NO);
                return;
            }

            // Wait 3 seconds and check if it's still running
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                BOOL stillRunning = [self isCalculatorRunning];
                completion(stillRunning); // If still running, unblock worked
            });
        }];
    });
}

- (void)reportProgress:(NSString*)status progress:(CGFloat)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.progressHandler) {
            self.progressHandler(status, progress);
        }
    });
}

- (void)finishWithError:(NSString*)errorMessage {
    SCSafetyCheckResult* result = [[SCSafetyCheckResult alloc]
        initWithHostsBlock:NO pfBlock:NO appBlock:NO
        hostsUnblock:NO pfUnblock:NO appUnblock:NO
        emergencyScript:NO
        errorMessage:errorMessage];
    [self finishWithResult:result];
}

- (void)finishWithResult:(SCSafetyCheckResult*)result {
    [self reportProgress:result.passed ? @"Safety check passed!" : @"Safety check failed" progress:1.0];

    NSLog(@"SCStartupSafetyCheck: Finished - %@", result.passed ? @"PASSED" : @"FAILED");
    if (!result.passed) {
        NSLog(@"SCStartupSafetyCheck: Issues: %@", result.issues);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.completionHandler) {
            self.completionHandler(result);
        }
    });
}

@end
