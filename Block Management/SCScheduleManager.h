//
//  SCScheduleManager.h
//  SelfControl
//
//  Manages bundles and weekly schedules at the app layer (NSUserDefaults).
//  This is purely for UX - does NOT connect to the daemon blocking logic.
//  Designed for safe UX testing without affecting actual blocking.
//

#import <Foundation/Foundation.h>
#import "SCBlockBundle.h"
#import "SCWeeklySchedule.h"
#import "SCTimeRange.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted when bundles or schedules change
extern NSNotificationName const SCScheduleManagerDidChangeNotification;

@interface SCScheduleManager : NSObject

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Bundles

/// All configured bundles
@property (nonatomic, readonly) NSArray<SCBlockBundle *> *bundles;

/// Adds a new bundle
- (void)addBundle:(SCBlockBundle *)bundle;

/// Removes a bundle by ID
- (void)removeBundleWithID:(NSString *)bundleID;

/// Updates an existing bundle
- (void)updateBundle:(SCBlockBundle *)bundle;

/// Gets a bundle by ID
- (nullable SCBlockBundle *)bundleWithID:(NSString *)bundleID;

/// Reorders bundles
- (void)reorderBundles:(NSArray<SCBlockBundle *> *)bundles;

#pragma mark - Week Settings

/// Returns remaining days in current week (always Mon-Sun)
- (NSArray<NSNumber *> *)daysToDisplay;

/// Returns remaining days for a specific week offset (0 = this week, 1 = next week)
- (NSArray<NSNumber *> *)daysToDisplayForWeekOffset:(NSInteger)weekOffset;

/// Returns all days in order (always Mon-Sun)
- (NSArray<NSNumber *> *)allDaysInOrder;

#pragma mark - Multi-Week Schedules

/// Gets all schedules for a specific week offset (0 = current, 1 = next)
- (NSArray<SCWeeklySchedule *> *)schedulesForWeekOffset:(NSInteger)weekOffset;

/// Gets schedule for a specific bundle and week offset
- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID weekOffset:(NSInteger)weekOffset;

/// Updates schedule for a specific week offset
- (void)updateSchedule:(SCWeeklySchedule *)schedule forWeekOffset:(NSInteger)weekOffset;

/// Creates an empty schedule for a bundle at a specific week offset
- (SCWeeklySchedule *)createScheduleForBundle:(SCBlockBundle *)bundle weekOffset:(NSInteger)weekOffset;

#pragma mark - Commitment

/// Whether the current week has an active commitment
@property (nonatomic, readonly) BOOL isCommitted;

/// End date of current week's commitment (nil if not committed)
@property (nonatomic, readonly, nullable) NSDate *commitmentEndDate;

/// Checks if a specific week offset is committed
- (BOOL)isCommittedForWeekOffset:(NSInteger)weekOffset;

/// Gets commitment end date for a specific week offset
- (nullable NSDate *)commitmentEndDateForWeekOffset:(NSInteger)weekOffset;

/// Commits to a specific week (0 = current, 1 = next)
- (void)commitToWeekWithOffset:(NSInteger)weekOffset;

/// Legacy method - commits to current week
- (void)commitToWeek;

/// Checks if a change would make the schedule looser (not allowed when committed)
- (BOOL)changeWouldLoosenSchedule:(SCWeeklySchedule *)oldSchedule
                     toSchedule:(SCWeeklySchedule *)newSchedule
                         forDay:(SCDayOfWeek)day;

/// Clears commitment (for testing/debug only)
- (void)clearCommitmentForDebug;

/// Cleans up expired commitments and their launchd jobs
/// Called on app launch and periodically
- (void)cleanupExpiredCommitments;

#pragma mark - Status Display (UX Only)

/// Returns status string for a specific bundle
- (NSString *)statusStringForBundleID:(NSString *)bundleID;

/// Checks if a bundle WOULD be allowed right now (for display)
- (BOOL)wouldBundleBeAllowed:(NSString *)bundleID;

#pragma mark - Persistence

/// Saves all data to NSUserDefaults
- (void)save;

/// Reloads data from NSUserDefaults
- (void)reload;

/// Clears all data (for testing)
- (void)clearAllData;

#pragma mark - Emergency Unlock Credits

/// Returns the number of emergency unlock credits remaining (default: 5 for new users)
- (NSInteger)emergencyUnlockCreditsRemaining;

/// Uses one emergency unlock credit. Returns YES if successful, NO if no credits remaining.
- (BOOL)useEmergencyUnlockCredit;

/// Resets emergency unlock credits to 5 (DEBUG only)
- (void)resetEmergencyUnlockCredits;

@end

NS_ASSUME_NONNULL_END
