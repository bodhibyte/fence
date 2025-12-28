//
//  SCDaemon.m
//  SelfControl
//
//  Created by Charlie Stigler on 5/28/20.
//

#import "SCDaemon.h"
#import "SCDaemonProtocol.h"
#import "SCDaemonXPC.h"
#import "SCDaemonBlockMethods.h"
#import "SCFileWatcher.h"
#import "SCScheduleManager.h"
#import "SCSettings.h"
#import "SCMiscUtilities.h"
#include <pwd.h>

static NSString* serviceName = @"org.eyebeam.selfcontrold";
float const INACTIVITY_LIMIT_SECS = 60 * 2; // 2 minutes

@interface NSXPCConnection(PrivateAuditToken)

// This property exists, but it's private. Make it available:
@property (nonatomic, readonly) audit_token_t auditToken;

@end

@interface SCDaemon () <NSXPCListenerDelegate>

@property (nonatomic, strong, readwrite) NSXPCListener* listener;
@property (strong, readwrite) NSTimer* checkupTimer;
@property (strong, readwrite) NSTimer* inactivityTimer;
@property (nonatomic, strong, readwrite) NSDate* lastActivityDate;

@property (nonatomic, strong) SCFileWatcher* hostsFileWatcher;

@end

@implementation SCDaemon

+ (instancetype)sharedDaemon {
    static SCDaemon* daemon = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        daemon = [SCDaemon new];
    });
    return daemon;
}

- (id) init {
    _listener = [[NSXPCListener alloc] initWithMachServiceName: serviceName];
    _listener.delegate = self;
    
    return self;
}

- (void)start {
    NSLog(@"selfcontrold: start() - Resuming XPC listener...");
    [self.listener resume];
    NSLog(@"selfcontrold: start() - XPC listener resumed");

    // if there's any evidence of a block (i.e. an official one running,
    // OR just block remnants remaining in hosts), we should start
    // running checkup regularly so the block gets found/removed
    // at the proper time.
    // we do NOT run checkup if there's no block, because it can result
    // in the daemon actually unloading itself before the app has a chance
    // to start the block
    NSLog(@"selfcontrold: start() - Checking for existing block...");
    if ([SCBlockUtilities anyBlockIsRunning] || [SCBlockUtilities blockRulesFoundOnSystem]) {
        NSLog(@"selfcontrold: start() - Block found, starting checkup timer");
        [self startCheckupTimer];
    }
    NSLog(@"selfcontrold: start() - Block check complete");

    // Check for missed scheduled blocks (e.g., after reboot during scheduled window)
    NSLog(@"selfcontrold: start() - Checking for missed scheduled blocks...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self startMissedBlockIfNeeded];
    });

    NSLog(@"selfcontrold: start() - Starting inactivity timer...");
    [self startInactivityTimer];
    [self resetInactivityTimer];
    NSLog(@"selfcontrold: start() - Inactivity timer started");

    NSLog(@"selfcontrold: start() - Starting hosts file watcher...");
    self.hostsFileWatcher = [SCFileWatcher watcherWithFile: @"/etc/hosts" block:^(NSError * _Nonnull error) {
        if ([SCBlockUtilities anyBlockIsRunning]) {
            NSLog(@"INFO: hosts file changed, checking block integrity");
            [SCDaemonBlockMethods checkBlockIntegrity];
        }
    }];
    NSLog(@"selfcontrold: start() - Hosts file watcher started");
}

- (void)startCheckupTimer {
    // this method must always be called on the main thread, so the timer will work properly
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self startCheckupTimer];
        });
        return;
    }

    // if the timer's already running, don't stress it!
    if (self.checkupTimer != nil) {
        return;
    }
    
    self.checkupTimer = [NSTimer scheduledTimerWithTimeInterval: 1 repeats: YES block:^(NSTimer * _Nonnull timer) {
       [SCDaemonBlockMethods checkupBlock];
    }];

    // run the first checkup immediately!
    [SCDaemonBlockMethods checkupBlock];
}
- (void)stopCheckupTimer {
    if (self.checkupTimer == nil) {
        return;
    }
    
    [self.checkupTimer invalidate];
    self.checkupTimer = nil;
}


- (void)startInactivityTimer {
    // Daemon now runs permanently after first install for:
    // 1. Scheduled blocks (no password prompts for each segment)
    // 2. Jailbreak resistance (KeepAlive=true restarts if killed)
    // 3. Reboot persistence (RunAtLoad=true auto-starts)
    // Resource usage is negligible (~5-10MB, zero CPU when idle)
}
- (void)resetInactivityTimer {
    self.lastActivityDate = [NSDate date];
}

- (void)dealloc {
    if (self.checkupTimer) {
        [self.checkupTimer invalidate];
        self.checkupTimer = nil;
    }
    if (self.inactivityTimer) {
        [self.inactivityTimer invalidate];
        self.inactivityTimer = nil;
    }
    if (self.hostsFileWatcher) {
        [self.hostsFileWatcher stopWatching];
        self.hostsFileWatcher = nil;
    }
}

#pragma mark - Missed Block Recovery

/// Checks if we're inside a scheduled block window but no block is running.
/// If so, starts the block immediately. Called on daemon startup to recover
/// from missed launchd triggers (e.g., after reboot during scheduled block).
- (void)startMissedBlockIfNeeded {
    // Debug logging to file (NSLog doesn't show in system log for daemons)
    NSMutableString *debugLog = [NSMutableString string];
    [debugLog appendFormat:@"\n=== startMissedBlockIfNeeded %@ ===\n", [NSDate date]];
    [debugLog appendFormat:@"euid: %d\n", geteuid()];

    NSLog(@"SCDaemon: Checking for missed scheduled blocks...");

    // Don't check if a block is already running
    BOOL blockRunning = [SCBlockUtilities anyBlockIsRunning];
    [debugLog appendFormat:@"blockAlreadyRunning: %d\n", blockRunning];
    if (blockRunning) {
        [debugLog appendString:@"EXIT: Block already running\n"];
        [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SCDaemon: Block already running, skipping missed block check");
        return;
    }

    // Use ApprovedSchedules + launchd jobs instead of recalculating
    // This works because:
    // 1. ApprovedSchedules is in daemon's own settings (readable as root)
    // 2. Launchd jobs contain the timing info (start time, end date)
    // 3. We just need to find which approved segment should be active NOW

    SCSettings *settings = [SCSettings sharedSettings];
    NSDictionary *approvedSchedules = [settings valueForKey:@"ApprovedSchedules"];
    [debugLog appendFormat:@"approvedSchedules count: %lu\n", (unsigned long)approvedSchedules.count];

    if (approvedSchedules.count == 0) {
        [debugLog appendString:@"EXIT: No approved schedules\n"];
        [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SCDaemon: No approved schedules found");
        return;
    }

    // Get console user's home directory to find launchd jobs
    uid_t consoleUID = [SCMiscUtilities consoleUserUID];
    [debugLog appendFormat:@"consoleUID: %d\n", consoleUID];
    if (consoleUID == 0) {
        [debugLog appendString:@"EXIT: No console user\n"];
        [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SCDaemon: No console user found");
        return;
    }

    // Find user's LaunchAgents directory
    struct passwd *pw = getpwuid(consoleUID);
    if (!pw) {
        [debugLog appendString:@"EXIT: Could not get user home dir\n"];
        [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SCDaemon: Could not get home directory for user %d", consoleUID);
        return;
    }
    NSString *homeDir = [NSString stringWithUTF8String:pw->pw_dir];
    NSString *launchAgentsDir = [homeDir stringByAppendingPathComponent:@"Library/LaunchAgents"];
    [debugLog appendFormat:@"launchAgentsDir: %@\n", launchAgentsDir];

    // Find all SelfControl schedule jobs
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:launchAgentsDir error:nil];
    NSString *jobPrefix = @"org.eyebeam.selfcontrol.schedule.merged-";

    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *nowComponents = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute)
                                                  fromDate:now];
    // NSCalendar weekday: 1=Sunday, 2=Monday, ... 7=Saturday
    // launchd weekday: 0=Sunday, 1=Monday, ... 6=Saturday
    NSInteger nowWeekday = nowComponents.weekday - 1;
    NSInteger nowMinutes = nowComponents.hour * 60 + nowComponents.minute;
    [debugLog appendFormat:@"now: %@ (weekday=%ld, minutes=%ld)\n", now, (long)nowWeekday, (long)nowMinutes];

    NSString *activeSegmentID = nil;
    NSDate *activeEndDate = nil;
    NSInteger activeStartMinutes = -1;  // Track start time for "most recent" comparison

    for (NSString *file in files) {
        if (![file hasPrefix:jobPrefix]) continue;

        NSString *jobPath = [launchAgentsDir stringByAppendingPathComponent:file];
        NSDictionary *jobPlist = [NSDictionary dictionaryWithContentsOfFile:jobPath];
        if (!jobPlist) continue;

        // Extract segment ID from label: org.eyebeam.selfcontrol.schedule.merged-{UUID}.{day}.{time}
        NSString *label = jobPlist[@"Label"];
        NSArray *parts = [label componentsSeparatedByString:@".merged-"];
        if (parts.count < 2) continue;

        NSString *remainder = parts[1]; // {UUID}.{day}.{time}
        NSArray *remainderParts = [remainder componentsSeparatedByString:@"."];
        if (remainderParts.count < 3) continue;

        NSString *segmentID = remainderParts[0];

        // Check if this segment is in ApprovedSchedules
        if (!approvedSchedules[segmentID]) {
            [debugLog appendFormat:@"Skipping job %@ - not in ApprovedSchedules\n", segmentID];
            continue;
        }

        // Get start time from StartCalendarInterval
        NSDictionary *startInterval = jobPlist[@"StartCalendarInterval"];
        if (!startInterval) continue;

        NSInteger jobWeekday = [startInterval[@"Weekday"] integerValue];
        NSInteger jobHour = [startInterval[@"Hour"] integerValue];
        NSInteger jobMinute = [startInterval[@"Minute"] integerValue];
        NSInteger jobStartMinutes = jobHour * 60 + jobMinute;

        // Get end date from ProgramArguments
        NSArray *args = jobPlist[@"ProgramArguments"];
        NSDate *endDate = nil;
        for (NSString *arg in args) {
            if ([arg hasPrefix:@"--enddate="]) {
                NSString *endDateStr = [arg substringFromIndex:10];
                NSISO8601DateFormatter *isoFormatter = [[NSISO8601DateFormatter alloc] init];
                endDate = [isoFormatter dateFromString:endDateStr];
                break;
            }
        }

        if (!endDate) continue;

        [debugLog appendFormat:@"Job %@: weekday=%ld, start=%ld, end=%@\n",
                  segmentID, (long)jobWeekday, (long)jobStartMinutes, endDate];

        // Check if this segment is active NOW
        // Active if: same weekday, started in past (or same time), ends in future
        BOOL sameWeekday = (jobWeekday == nowWeekday);
        BOOL startedOrNow = (jobStartMinutes <= nowMinutes);
        BOOL endsInFuture = ([endDate timeIntervalSinceNow] > 0);

        [debugLog appendFormat:@"  sameWeekday=%d, startedOrNow=%d, endsInFuture=%d\n",
                  sameWeekday, startedOrNow, endsInFuture];

        if (sameWeekday && startedOrNow && endsInFuture) {
            // This segment should be active!
            // If multiple match, pick the one that started most recently
            if (activeSegmentID == nil || jobStartMinutes > activeStartMinutes) {
                activeSegmentID = segmentID;
                activeEndDate = endDate;
                activeStartMinutes = jobStartMinutes;
                [debugLog appendFormat:@"  -> CANDIDATE: %@ (starts at %ld)\n", segmentID, (long)jobStartMinutes];
            }
        }
    }

    if (!activeSegmentID) {
        [debugLog appendString:@"EXIT: No active segment found\n"];
        [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"SCDaemon: No approved segment is active right now");
        return;
    }

    [debugLog appendFormat:@"MATCH: Starting approved segment %@ until %@\n", activeSegmentID, activeEndDate];
    [debugLog writeToFile:@"/tmp/selfcontrol_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSLog(@"SCDaemon: Found missed block! Approved segment %@ should be active (ends: %@)",
          activeSegmentID, activeEndDate);

    // Start the block using the approved schedule
    NSDictionary *schedule = approvedSchedules[activeSegmentID];
    NSArray *blocklist = schedule[@"blocklist"];
    BOOL isAllowlist = [schedule[@"isAllowlist"] boolValue];
    NSDictionary *blockSettings = schedule[@"blockSettings"];
    uid_t controllingUID = [schedule[@"controllingUID"] unsignedIntValue];

    [debugLog appendFormat:@"Starting block with %lu entries\n", (unsigned long)blocklist.count];

    [SCDaemonBlockMethods startBlockWithControllingUID:controllingUID
                                             blocklist:blocklist
                                           isAllowlist:isAllowlist
                                               endDate:activeEndDate
                                         blockSettings:blockSettings
                                         authorization:nil
                                                 reply:^(NSError *error) {
        if (error) {
            NSLog(@"SCDaemon: Failed to start approved segment %@: %@", activeSegmentID, error);
        } else {
            NSLog(@"SCDaemon: Successfully started approved segment %@", activeSegmentID);
        }
    }];
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    NSLog(@"selfcontrold: === NEW CONNECTION ATTEMPT ===");
    NSLog(@"selfcontrold: Connection from: %@", newConnection);

    // There is a potential security issue / race condition with matching based on PID, so we use the (technically private) auditToken instead
    audit_token_t auditToken = newConnection.auditToken;
    NSDictionary* guestAttributes = @{
        (id)kSecGuestAttributeAudit: [NSData dataWithBytes: &auditToken length: sizeof(audit_token_t)]
    };
    SecCodeRef guest;
    OSStatus copyStatus = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef _Nullable)(guestAttributes), kSecCSDefaultFlags, &guest);
    NSLog(@"selfcontrold: SecCodeCopyGuestWithAttributes status = %d", (int)copyStatus);
    if (copyStatus != errSecSuccess) {
        NSLog(@"selfcontrold: REJECTED - Failed to get guest code ref");
        return NO;
    }
    
    SecRequirementRef isSelfControlApp;
    // versions before 4.0 didn't have hardened code signing, so aren't trustworthy to talk to the daemon
    // (plus the daemon didn't exist before 4.0 so there's really no reason they should want to run it!)
    SecRequirementCreateWithString(CFSTR("anchor apple generic and (identifier \"org.eyebeam.SelfControl\" or identifier \"org.eyebeam.selfcontrol-cli\") and info [CFBundleVersion] >= \"407\" and (certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate leaf[field.1.2.840.113635.100.6.1.12] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */) and certificate leaf[subject.OU] = L5YX8CH3F5"), kSecCSDefaultFlags, &isSelfControlApp);
    OSStatus clientValidityStatus = SecCodeCheckValidity(guest, kSecCSDefaultFlags, isSelfControlApp);
    NSLog(@"selfcontrold: SecCodeCheckValidity status = %d", (int)clientValidityStatus);

    CFRelease(guest);
    CFRelease(isSelfControlApp);

    if (clientValidityStatus) {
        NSError* error = [NSError errorWithDomain: NSOSStatusErrorDomain code: clientValidityStatus userInfo: nil];
        NSLog(@"selfcontrold: REJECTED - Invalid client signing (status %d). Error: %@", (int)clientValidityStatus, error);
        [SCSentry captureError: error];
        return NO;
    }

    NSLog(@"selfcontrold: Client validated! Setting up exported interface...");
    SCDaemonXPC* scdXPC = [[SCDaemonXPC alloc] init];
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol: @protocol(SCDaemonProtocol)];
    newConnection.exportedObject = scdXPC;

    [newConnection resume];

    NSLog(@"selfcontrold: === CONNECTION ACCEPTED ===");
    [SCSentry addBreadcrumb: @"Daemon accepted new connection" category: @"daemon"];

    return YES;
}

@end
