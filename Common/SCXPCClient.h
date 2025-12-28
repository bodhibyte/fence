//
//  SCAppXPC.h
//  SelfControl
//
//  Created by Charlie Stigler on 7/4/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCXPCClient : NSObject

@property (readonly, getter=isConnected) BOOL connected;
@property (atomic, assign, readonly) BOOL connectionIsValid;

- (void)connectToHelperTool;
- (void)forceDisconnect;
- (void)installDaemon:(void(^)(NSError*))callback;
- (void)refreshConnectionAndRun:(void(^)(void))callback;
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock;

- (void)getVersion:(void(^)(NSString* version, NSError* error))reply;
- (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings reply:(void(^)(NSError* error))reply;
- (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist reply:(void(^)(NSError* error))reply;
- (void)updateBlockEndDate:(NSDate*)newEndDate reply:(void(^)(NSError* error))reply;

// Schedule registration methods (for pre-authorized scheduled blocks)
- (void)registerScheduleWithID:(NSString*)scheduleId
                     blocklist:(NSArray<NSString*>*)blocklist
                   isAllowlist:(BOOL)isAllowlist
                 blockSettings:(NSDictionary*)blockSettings
             controllingUID:(uid_t)controllingUID
                         reply:(void(^)(NSError* error))reply;

- (void)startScheduledBlockWithID:(NSString*)scheduleId
                          endDate:(NSDate*)endDate
                            reply:(void(^)(NSError* error))reply;

- (void)unregisterScheduleWithID:(NSString*)scheduleId
                           reply:(void(^)(NSError* error))reply;

- (void)clearAllApprovedSchedules:(void(^)(NSError* error))reply;

- (void)clearBlockForDebug:(void(^)(NSError* error))reply;

@end

NS_ASSUME_NONNULL_END
