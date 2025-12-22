//
//  AppBlocker.m
//  SelfControl
//
//  Monitors running applications and terminates blocked apps.
//  Uses low-level libproc APIs to work in daemon context (no NSWorkspace).
//

#import "AppBlocker.h"
#import "SCSentry.h"
#import "SCDebugUtilities.h"
#import <libproc.h>
#import <signal.h>

// Poll interval in milliseconds
static const uint64_t APP_BLOCK_POLL_INTERVAL_MS = 500;
static const uint64_t APP_BLOCK_POLL_LEEWAY_MS = 50;

@interface AppBlocker ()

@property (nonatomic, strong) NSMutableSet<NSString*>* mutableBlockedBundleIDs;
@property (nonatomic, strong) dispatch_source_t monitorTimer;
@property (nonatomic, strong) NSLock* blockLock;
@property (nonatomic, readwrite) BOOL isMonitoring;

@end

@implementation AppBlocker

+ (instancetype)sharedBlocker {
    static AppBlocker* shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AppBlocker alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _mutableBlockedBundleIDs = [NSMutableSet set];
        _blockLock = [[NSLock alloc] init];
        _isMonitoring = NO;
    }
    return self;
}

- (NSSet<NSString*>*)blockedBundleIDs {
    [self.blockLock lock];
    NSSet* copy = [self.mutableBlockedBundleIDs copy];
    [self.blockLock unlock];
    return copy;
}

- (void)addBlockedApp:(NSString*)bundleID {
    if (!bundleID || bundleID.length == 0) return;

    [self.blockLock lock];
    [self.mutableBlockedBundleIDs addObject:bundleID];
    [self.blockLock unlock];

    NSLog(@"AppBlocker: Added blocked app: %@", bundleID);
}

- (void)removeBlockedApp:(NSString*)bundleID {
    if (!bundleID) return;

    [self.blockLock lock];
    [self.mutableBlockedBundleIDs removeObject:bundleID];
    [self.blockLock unlock];

    NSLog(@"AppBlocker: Removed blocked app: %@", bundleID);
}

- (void)clearAllBlockedApps {
    [self.blockLock lock];
    [self.mutableBlockedBundleIDs removeAllObjects];
    [self.blockLock unlock];

    NSLog(@"AppBlocker: Cleared all blocked apps");
}

- (void)startMonitoring {
    if (self.isMonitoring) return;

    // First kill any currently running blocked apps
    [self findAndKillBlockedApps];

    // Create timer on global queue
    self.monitorTimer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    );

    dispatch_source_set_timer(
        self.monitorTimer,
        dispatch_time(DISPATCH_TIME_NOW, APP_BLOCK_POLL_INTERVAL_MS * NSEC_PER_MSEC),
        APP_BLOCK_POLL_INTERVAL_MS * NSEC_PER_MSEC,
        APP_BLOCK_POLL_LEEWAY_MS * NSEC_PER_MSEC
    );

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.monitorTimer, ^{
        [weakSelf findAndKillBlockedApps];
    });

    dispatch_resume(self.monitorTimer);
    self.isMonitoring = YES;

    NSLog(@"AppBlocker: Started monitoring with %lu blocked apps",
          (unsigned long)self.blockedBundleIDs.count);
}

- (void)stopMonitoring {
    if (!self.isMonitoring) return;

    if (self.monitorTimer) {
        dispatch_source_cancel(self.monitorTimer);
        self.monitorTimer = nil;
    }

    self.isMonitoring = NO;
    NSLog(@"AppBlocker: Stopped monitoring");
}

/// Extract bundle identifier from an executable path by finding the .app bundle
- (NSString*)bundleIDFromExecutablePath:(NSString*)execPath {
    if (!execPath || execPath.length == 0) return nil;

    // Walk up directories to find .app bundle
    NSString* path = execPath;
    while (path.length > 1) {
        if ([path hasSuffix:@".app"]) {
            // Found app bundle, read Info.plist
            NSString* plistPath = [path stringByAppendingPathComponent:@"Contents/Info.plist"];
            NSDictionary* info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            NSString* bundleID = info[@"CFBundleIdentifier"];
            // Debug: log only if this looks like a user app (not system)
            if (bundleID && ![path hasPrefix:@"/System"] && ![path hasPrefix:@"/usr"]) {
                // NSLog(@"AppBlocker: Path %@ -> bundleID %@", path, bundleID);
            }
            return bundleID;
        }
        path = [path stringByDeletingLastPathComponent];
    }
    return nil;
}

/// Find and kill blocked apps using daemon-safe libproc APIs (no NSWorkspace)
- (NSArray<NSNumber*>*)findAndKillBlockedApps {
#ifdef DEBUG
    // Check debug override - if blocking is disabled, don't kill any apps
    if ([SCDebugUtilities isDebugBlockingDisabled]) {
        return @[];
    }
#endif

    NSMutableArray<NSNumber*>* killedPIDs = [NSMutableArray array];

    [self.blockLock lock];
    NSSet<NSString*>* currentBlockedIDs = [self.mutableBlockedBundleIDs copy];
    [self.blockLock unlock];

    if (currentBlockedIDs.count == 0) {
        return @[];
    }

    // Get number of processes
    int numPids = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (numPids <= 0) {
        NSLog(@"AppBlocker: Failed to get process count");
        return @[];
    }

    // Allocate buffer for PIDs
    pid_t* pids = (pid_t*)malloc(sizeof(pid_t) * (size_t)numPids);
    if (!pids) {
        NSLog(@"AppBlocker: Failed to allocate PID buffer");
        return @[];
    }

    // Get actual list of PIDs
    int actualCount = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)(sizeof(pid_t) * (size_t)numPids));
    actualCount = actualCount / (int)sizeof(pid_t);

    NSLog(@"AppBlocker: Polling - checking %d processes against %lu blocked apps: %@",
          actualCount, (unsigned long)currentBlockedIDs.count, currentBlockedIDs);

    for (int i = 0; i < actualCount; i++) {
        pid_t pid = pids[i];
        if (pid == 0) continue;

        // Get executable path for this process
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE];
        int pathLen = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));

        if (pathLen <= 0) continue;

        NSString* execPath = [[NSString alloc] initWithBytes:pathBuffer
                                                      length:(NSUInteger)pathLen
                                                    encoding:NSUTF8StringEncoding];

        // Get bundle ID from executable path
        NSString* bundleID = [self bundleIDFromExecutablePath:execPath];
        if (!bundleID) continue;

        // Log apps that match or might match blocked apps (for debugging)
        for (NSString* blockedID in currentBlockedIDs) {
            if ([bundleID containsString:blockedID] || [blockedID containsString:bundleID]) {
                NSLog(@"AppBlocker: Checking app %@ (PID %d) against blocked %@", bundleID, pid, blockedID);
            }
        }

        // Check if this app should be blocked
        if ([currentBlockedIDs containsObject:bundleID]) {
            // Terminate the process with SIGTERM (graceful)
            int result = kill(pid, SIGTERM);

            if (result == 0) {
                [killedPIDs addObject:@(pid)];
                NSLog(@"AppBlocker: Terminated blocked app %@ (PID %d)", bundleID, pid);

                [SCSentry addBreadcrumb:
                    [NSString stringWithFormat:@"Terminated blocked app: %@", bundleID]
                    category:@"appblocker"];
            } else {
                // Try SIGKILL if SIGTERM failed
                result = kill(pid, SIGKILL);
                if (result == 0) {
                    [killedPIDs addObject:@(pid)];
                    NSLog(@"AppBlocker: Force killed blocked app %@ (PID %d)", bundleID, pid);
                } else {
                    NSLog(@"AppBlocker: Failed to terminate %@ (PID %d), errno=%d",
                          bundleID, pid, errno);
                }
            }
        }
    }

    free(pids);
    return killedPIDs;
}

- (void)dealloc {
    [self stopMonitoring];
}

@end
