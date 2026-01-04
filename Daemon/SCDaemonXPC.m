//
//  SCDaemonXPC.m
//  selfcontrold
//
//  Created by Charlie Stigler on 5/30/20.
//

#import "SCDaemonXPC.h"
#import "SCDaemon.h"
#import "SCDaemonBlockMethods.h"
#import "SCXPCAuthorization.h"
#import "SCHelperToolUtilities.h"

@implementation SCDaemonXPC

- (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: startBlockWithControllingUID");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"AUTHORIZATION ACCEPTED for startBlock with authData %@ and command %s", authData, sel_getName(_cmd));
    }

    [SCDaemonBlockMethods startBlockWithControllingUID: controllingUID blocklist: blocklist isAllowlist:isAllowlist endDate: endDate blockSettings:blockSettings authorization: authData reply: reply];
}

- (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: updateBlocklist");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"AUTHORIZATION ACCEPTED for updateBlocklist with authData %@ and command %s", authData, sel_getName(_cmd));
    }
    
    [SCDaemonBlockMethods updateBlocklist: newBlocklist authorization: authData reply: reply];
}

- (void)updateBlockEndDate:(NSDate*)newEndDate authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: updateBlockEndDate");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"AUTHORIZATION ACCEPTED for updateBlockENdDate with authData %@ and command %s", authData, sel_getName(_cmd));
    }
    
    [SCDaemonBlockMethods updateBlockEndDate: newEndDate authorization: authData reply: reply];
}

// Part of the HelperToolProtocol.  Returns the version number of the tool.  Note that never
// requires authorization.
- (void)getVersionWithReply:(void(^)(NSString * version))reply {
    NSLog(@"XPC method called: getVersionWithReply");
    // We specifically don't check for authorization here.  Everyone is always allowed to get
    // the version of the helper tool.
    reply(SELFCONTROL_VERSION_STRING);
}

#pragma mark - Schedule Registration (Pre-Authorization System)

// Register a schedule - stores approved schedule in secure settings
// Note: Authorization is already verified by installDaemon: before this call
// (installDaemon acquires org.eyebeam.SelfControl.startBlock right)
// Skipping redundant checkAuthorization here to avoid double prompt (password + Touch ID)
- (void)registerScheduleWithID:(NSString*)scheduleId
                     blocklist:(NSArray<NSString*>*)blocklist
                   isAllowlist:(BOOL)isAllowlist
                 blockSettings:(NSDictionary*)blockSettings
             controllingUID:(uid_t)controllingUID
                 authorization:(NSData *)authData
                         reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: registerScheduleWithID: %@ (auth verified by installDaemon)", scheduleId);

    // Store the approved schedule in secure settings (root-only file)
    SCSettings* settings = [SCSettings sharedSettings];
    NSMutableDictionary* approvedSchedules = [[settings valueForKey: @"ApprovedSchedules"] mutableCopy];
    if (approvedSchedules == nil) {
        approvedSchedules = [NSMutableDictionary new];
    }

    // Store schedule details keyed by scheduleId
    approvedSchedules[scheduleId] = @{
        @"blocklist": blocklist ?: @[],
        @"isAllowlist": @(isAllowlist),
        @"blockSettings": blockSettings ?: @{},
        @"controllingUID": @(controllingUID),
        @"registeredAt": [NSDate date]
    };

    [settings setValue: approvedSchedules forKey: @"ApprovedSchedules"];
    [settings synchronizeSettings];

    NSLog(@"INFO: Schedule %@ registered successfully", scheduleId);
    reply(nil);
}

// Start a pre-registered schedule - NO authorization required (schedule was pre-approved)
- (void)startScheduledBlockWithID:(NSString*)scheduleId
                          endDate:(NSDate*)endDate
                            reply:(void(^)(NSError* error))reply {
    NSLog(@"=== DAEMON: startScheduledBlockWithID ===");
    NSLog(@"DAEMON: scheduleId = %@", scheduleId);
    NSLog(@"DAEMON: requested endDate = %@", endDate);

    // NO authorization check - we trust the schedule because it was pre-approved
    // and stored in root-only settings file

    // Look up the approved schedule
    SCSettings* settings = [SCSettings sharedSettings];
    NSDictionary* approvedSchedules = [settings valueForKey: @"ApprovedSchedules"];
    NSLog(@"DAEMON: ApprovedSchedules count = %lu", (unsigned long)approvedSchedules.count);
    NSLog(@"DAEMON: ApprovedSchedules keys = %@", [approvedSchedules allKeys]);

    NSDictionary* schedule = approvedSchedules[scheduleId];

    if (schedule == nil) {
        NSLog(@"DAEMON ERROR: Schedule ID %@ NOT FOUND in approved schedules!", scheduleId);
        NSLog(@"DAEMON: Available schedules: %@", approvedSchedules);
        reply([SCErr errorWithCode: 403 subDescription: @"Schedule not registered or unauthorized"]);
        return;
    }

    NSLog(@"DAEMON: Found approved schedule %@", scheduleId);

    // Extract schedule parameters
    NSArray* blocklist = schedule[@"blocklist"];
    BOOL isAllowlist = [schedule[@"isAllowlist"] boolValue];
    NSDictionary* blockSettings = schedule[@"blockSettings"];
    uid_t controllingUID = [schedule[@"controllingUID"] unsignedIntValue];

    NSLog(@"DAEMON: blocklist count = %lu", (unsigned long)blocklist.count);
    NSLog(@"DAEMON: blocklist = %@", blocklist);
    NSLog(@"DAEMON: isAllowlist = %d", isAllowlist);
    NSLog(@"DAEMON: controllingUID = %u", controllingUID);
    NSLog(@"DAEMON: blockSettings = %@", blockSettings);

    if (blocklist.count == 0) {
        NSLog(@"DAEMON WARNING: Blocklist is EMPTY! Block may not do anything.");
    }

    NSLog(@"DAEMON: Calling startBlockWithControllingUID...");

    // Start the block without authorization (it was pre-approved)
    [SCDaemonBlockMethods startBlockWithControllingUID: controllingUID
                                             blocklist: blocklist
                                           isAllowlist: isAllowlist
                                               endDate: endDate
                                         blockSettings: blockSettings
                                         authorization: nil
                                                 reply:^(NSError *error) {
        if (error) {
            NSLog(@"DAEMON ERROR: startBlock failed: %@", error);
        } else {
            NSLog(@"DAEMON: Block started successfully for schedule %@", scheduleId);
        }
        NSLog(@"=== DAEMON: startScheduledBlockWithID COMPLETE ===");
        reply(error);
    }];
}

// Unregister a schedule - requires authorization
- (void)unregisterScheduleWithID:(NSString*)scheduleId
                   authorization:(NSData *)authData
                           reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: unregisterScheduleWithID: %@", scheduleId);

    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: @selector(startBlockWithControllingUID:blocklist:isAllowlist:endDate:blockSettings:authorization:reply:)];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed for unregisterSchedule due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    SCSettings* settings = [SCSettings sharedSettings];
    NSMutableDictionary* approvedSchedules = [[settings valueForKey: @"ApprovedSchedules"] mutableCopy];
    if (approvedSchedules != nil) {
        [approvedSchedules removeObjectForKey: scheduleId];
        [settings setValue: approvedSchedules forKey: @"ApprovedSchedules"];
        [settings synchronizeSettings];
    }

    NSLog(@"INFO: Schedule %@ unregistered successfully", scheduleId);
    reply(nil);
}

- (void)clearAllApprovedSchedulesWithAuthorization:(NSData *)authData
                                             reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: clearAllApprovedSchedules");

    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: @selector(startBlockWithControllingUID:blocklist:isAllowlist:endDate:blockSettings:authorization:reply:)];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed for clearAllApprovedSchedules due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    SCSettings* settings = [SCSettings sharedSettings];
    [settings setValue: nil forKey: @"ApprovedSchedules"];
    [settings synchronizeSettings];

    NSLog(@"INFO: All approved schedules cleared successfully");
    reply(nil);
}

- (void)clearBlockForDebugWithAuthorization:(NSData *)authData
                                      reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: clearBlockForDebug");

#ifdef DEBUG
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: @selector(startBlockWithControllingUID:blocklist:isAllowlist:endDate:blockSettings:authorization:reply:)];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed for clearBlockForDebug due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    NSLog(@"WARNING: Forcibly clearing active block (DEBUG MODE)");
    [SCHelperToolUtilities removeBlock];

    NSLog(@"INFO: Block cleared via debug method");
    reply(nil);
#else
    NSLog(@"ERROR: clearBlockForDebug called in non-DEBUG build - ignoring");
    reply([SCErr errorWithCode: 500 subDescription: @"Debug methods not available in release builds"]);
#endif
}

- (void)isPFBlockActiveWithReply:(void(^)(BOOL active))reply {
    // No authorization needed - this is a read-only query
    // Delegate to SCDaemonBlockMethods which has access to PacketFilter
    [[SCDaemonBlockMethods new] isPFBlockActiveWithReply:reply];
}

- (void)stopTestBlockWithReply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: stopTestBlock");

    // NO authorization required - test blocks are meant to be freely stoppable
    // But we MUST verify this is actually a test block
    SCSettings* settings = [SCSettings sharedSettings];
    BOOL isTestBlock = [[settings valueForKey:@"IsTestBlock"] boolValue];

    if (!isTestBlock) {
        NSLog(@"ERROR: stopTestBlock called but IsTestBlock=NO - refusing to stop");
        reply([SCErr errorWithCode: 401 subDescription: @"Not a test block - cannot stop without emergency unlock"]);
        return;
    }

    [SCDaemonBlockMethods stopTestBlock:reply];
}

- (void)cleanupStaleScheduleWithID:(NSString*)scheduleId
                             reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: cleanupStaleScheduleWithID: %@", scheduleId);

    // NO authorization required - this is cleanup of pre-authorized schedules
    // that have expired (endDate in the past)

    [[SCDaemon sharedDaemon] cleanupStaleScheduleWithID:scheduleId];

    NSLog(@"INFO: Stale schedule %@ cleaned up successfully", scheduleId);
    reply(nil);
}

@end
