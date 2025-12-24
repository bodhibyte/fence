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

#pragma mark - Schedules

/// All weekly schedules (one per bundle)
@property (nonatomic, readonly) NSArray<SCWeeklySchedule *> *schedules;

/// Gets schedule for a specific bundle
- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID;

/// Updates schedule for a bundle
- (void)updateSchedule:(SCWeeklySchedule *)schedule;

/// Creates an empty schedule for a new bundle
- (SCWeeklySchedule *)createScheduleForBundle:(SCBlockBundle *)bundle;

#pragma mark - Templates

/// Saves current week setup as the default template
- (void)saveCurrentAsDefaultTemplate;

/// Loads the default template (called at week rollover)
- (void)loadDefaultTemplate;

/// Checks if a default template exists
- (BOOL)hasDefaultTemplate;

/// Clears the default template
- (void)clearDefaultTemplate;

#pragma mark - Week Settings

/// Whether week starts on Monday (YES) or Sunday (NO)
@property (nonatomic, assign) BOOL weekStartsOnMonday;

/// Returns days to display based on current day and week start preference
- (NSArray<NSNumber *> *)daysToDisplay;

/// Returns all days in order based on week start preference
- (NSArray<NSNumber *> *)allDaysInOrder;

#pragma mark - Commitment

/// Whether there's an active commitment
@property (nonatomic, readonly) BOOL isCommitted;

/// End date of current commitment (nil if not committed)
@property (nonatomic, readonly, nullable) NSDate *commitmentEndDate;

/// Commits to the current week schedule (locks it)
/// In UX-only mode, this just sets the flag without affecting blocking
- (void)commitToWeek;

/// Checks if a change would make the schedule looser (not allowed when committed)
- (BOOL)changeWouldLoosenSchedule:(SCWeeklySchedule *)oldSchedule
                     toSchedule:(SCWeeklySchedule *)newSchedule
                         forDay:(SCDayOfWeek)day;

/// Clears commitment (for testing/debug only)
- (void)clearCommitmentForDebug;

#pragma mark - Status Display (UX Only)

/// Returns what the status WOULD be if blocking were active
/// This is for UX display only - does not affect actual blocking
- (NSDictionary<NSString *, NSDictionary *> *)currentStatusForDisplay;

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

@end

NS_ASSUME_NONNULL_END
