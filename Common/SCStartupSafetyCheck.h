//
//  SCStartupSafetyCheck.h
//  SelfControl
//
//  Orchestrates startup safety check to verify blocking/unblocking works.
//  DEBUG builds only.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Test result structure
@interface SCSafetyCheckResult : NSObject

@property (nonatomic, readonly) BOOL passed;
@property (nonatomic, readonly) BOOL hostsBlockWorked;
@property (nonatomic, readonly) BOOL pfBlockWorked;
@property (nonatomic, readonly) BOOL appBlockWorked;
@property (nonatomic, readonly) BOOL hostsUnblockWorked;
@property (nonatomic, readonly) BOOL pfUnblockWorked;
@property (nonatomic, readonly) BOOL appUnblockWorked;
@property (nonatomic, readonly, nullable) NSString* errorMessage;
@property (nonatomic, readonly) NSArray<NSString*>* issues;

- (instancetype)initWithHostsBlock:(BOOL)hostsBlock
                           pfBlock:(BOOL)pfBlock
                          appBlock:(BOOL)appBlock
                      hostsUnblock:(BOOL)hostsUnblock
                        pfUnblock:(BOOL)pfUnblock
                       appUnblock:(BOOL)appUnblock
                     errorMessage:(nullable NSString*)error;

@end

// Progress callback
typedef void(^SCSafetyCheckProgressHandler)(NSString* status, CGFloat progress);
typedef void(^SCSafetyCheckCompletionHandler)(SCSafetyCheckResult* result);

@interface SCStartupSafetyCheck : NSObject

// Check if safety test is needed (version changed)
+ (BOOL)safetyCheckNeeded;

// Skip and mark as tested for current versions
+ (void)skipSafetyCheck;

// Run the safety check (async)
- (void)runWithProgressHandler:(SCSafetyCheckProgressHandler)progressHandler
             completionHandler:(SCSafetyCheckCompletionHandler)completionHandler;

// Cancel a running check (if possible)
- (void)cancel;

// Test targets
+ (NSString*)testWebsite;
+ (NSString*)testAppBundleID;

@end

NS_ASSUME_NONNULL_END
