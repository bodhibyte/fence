//
//  SCScheduleManager.m
//  SelfControl
//

#import "SCScheduleManager.h"

NSNotificationName const SCScheduleManagerDidChangeNotification = @"SCScheduleManagerDidChangeNotification";

// NSUserDefaults keys (app-layer only, not in SCSettings)
static NSString * const kBundlesKey = @"SCScheduleBundles";
static NSString * const kSchedulesKey = @"SCWeeklySchedules";
static NSString * const kDefaultTemplateKey = @"SCDefaultWeekTemplate";
static NSString * const kWeekStartsMondayKey = @"SCWeekStartsOnMonday";
static NSString * const kCommitmentEndDateKey = @"SCCommitmentEndDate";
static NSString * const kIsCommittedKey = @"SCIsCommitted";

@interface SCScheduleManager ()

@property (nonatomic, strong) NSMutableArray<SCBlockBundle *> *mutableBundles;
@property (nonatomic, strong) NSMutableArray<SCWeeklySchedule *> *mutableSchedules;

@end

@implementation SCScheduleManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static SCScheduleManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SCScheduleManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableBundles = [NSMutableArray array];
        _mutableSchedules = [NSMutableArray array];
        [self reload];
    }
    return self;
}

#pragma mark - Bundles

- (NSArray<SCBlockBundle *> *)bundles {
    return [self.mutableBundles copy];
}

- (void)addBundle:(SCBlockBundle *)bundle {
    if (!bundle || [self bundleWithID:bundle.bundleID]) {
        return; // Already exists or invalid
    }

    bundle.displayOrder = self.mutableBundles.count;
    [self.mutableBundles addObject:bundle];

    // Create empty schedule for this bundle
    [self createScheduleForBundle:bundle];

    [self save];
    [self postChangeNotification];
}

- (void)removeBundleWithID:(NSString *)bundleID {
    SCBlockBundle *bundle = [self bundleWithID:bundleID];
    if (bundle) {
        [self.mutableBundles removeObject:bundle];

        // Also remove the schedule
        SCWeeklySchedule *schedule = [self scheduleForBundleID:bundleID];
        if (schedule) {
            [self.mutableSchedules removeObject:schedule];
        }

        [self save];
        [self postChangeNotification];
    }
}

- (void)updateBundle:(SCBlockBundle *)bundle {
    NSInteger index = [self indexOfBundleWithID:bundle.bundleID];
    if (index != NSNotFound) {
        self.mutableBundles[index] = bundle;
        [self save];
        [self postChangeNotification];
    }
}

- (nullable SCBlockBundle *)bundleWithID:(NSString *)bundleID {
    for (SCBlockBundle *bundle in self.mutableBundles) {
        if ([bundle.bundleID isEqualToString:bundleID]) {
            return bundle;
        }
    }
    return nil;
}

- (NSInteger)indexOfBundleWithID:(NSString *)bundleID {
    for (NSUInteger i = 0; i < self.mutableBundles.count; i++) {
        if ([self.mutableBundles[i].bundleID isEqualToString:bundleID]) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)reorderBundles:(NSArray<SCBlockBundle *> *)bundles {
    [self.mutableBundles removeAllObjects];
    [self.mutableBundles addObjectsFromArray:bundles];

    // Update display order
    for (NSUInteger i = 0; i < self.mutableBundles.count; i++) {
        self.mutableBundles[i].displayOrder = i;
    }

    [self save];
    [self postChangeNotification];
}

#pragma mark - Schedules

- (NSArray<SCWeeklySchedule *> *)schedules {
    return [self.mutableSchedules copy];
}

- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID {
    for (SCWeeklySchedule *schedule in self.mutableSchedules) {
        if ([schedule.bundleID isEqualToString:bundleID]) {
            return schedule;
        }
    }
    return nil;
}

- (void)updateSchedule:(SCWeeklySchedule *)schedule {
    // Check if this would loosen the schedule when committed
    if (self.isCommitted) {
        SCWeeklySchedule *oldSchedule = [self scheduleForBundleID:schedule.bundleID];
        if (oldSchedule) {
            // Check each day
            for (SCDayOfWeek day = SCDayOfWeekSunday; day <= SCDayOfWeekSaturday; day++) {
                if ([self changeWouldLoosenSchedule:oldSchedule toSchedule:schedule forDay:day]) {
                    NSLog(@"Rejecting schedule change that would loosen restrictions while committed");
                    return;
                }
            }
        }
    }

    NSInteger index = [self indexOfScheduleWithBundleID:schedule.bundleID];
    if (index != NSNotFound) {
        self.mutableSchedules[index] = schedule;
    } else {
        [self.mutableSchedules addObject:schedule];
    }

    [self save];
    [self postChangeNotification];
}

- (SCWeeklySchedule *)createScheduleForBundle:(SCBlockBundle *)bundle {
    SCWeeklySchedule *schedule = [SCWeeklySchedule emptyScheduleForBundleID:bundle.bundleID];
    [self.mutableSchedules addObject:schedule];
    [self save];
    return schedule;
}

- (NSInteger)indexOfScheduleWithBundleID:(NSString *)bundleID {
    for (NSUInteger i = 0; i < self.mutableSchedules.count; i++) {
        if ([self.mutableSchedules[i].bundleID isEqualToString:bundleID]) {
            return i;
        }
    }
    return NSNotFound;
}

#pragma mark - Templates

- (void)saveCurrentAsDefaultTemplate {
    NSMutableArray *bundleDicts = [NSMutableArray array];
    for (SCBlockBundle *bundle in self.mutableBundles) {
        [bundleDicts addObject:[bundle toDictionary]];
    }

    NSMutableArray *scheduleDicts = [NSMutableArray array];
    for (SCWeeklySchedule *schedule in self.mutableSchedules) {
        [scheduleDicts addObject:[schedule toDictionary]];
    }

    NSDictionary *template = @{
        @"bundles": bundleDicts,
        @"schedules": scheduleDicts
    };

    [[NSUserDefaults standardUserDefaults] setObject:template forKey:kDefaultTemplateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)loadDefaultTemplate {
    NSDictionary *template = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultTemplateKey];
    if (!template) return;

    // Clear current data
    [self.mutableBundles removeAllObjects];
    [self.mutableSchedules removeAllObjects];

    // Load bundles
    NSArray *bundleDicts = template[@"bundles"];
    for (NSDictionary *dict in bundleDicts) {
        SCBlockBundle *bundle = [SCBlockBundle bundleFromDictionary:dict];
        if (bundle) {
            [self.mutableBundles addObject:bundle];
        }
    }

    // Load schedules
    NSArray *scheduleDicts = template[@"schedules"];
    for (NSDictionary *dict in scheduleDicts) {
        SCWeeklySchedule *schedule = [SCWeeklySchedule scheduleFromDictionary:dict];
        if (schedule) {
            [self.mutableSchedules addObject:schedule];
        }
    }

    [self save];
    [self postChangeNotification];
}

- (BOOL)hasDefaultTemplate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultTemplateKey] != nil;
}

- (void)clearDefaultTemplate {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultTemplateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Week Settings

- (BOOL)weekStartsOnMonday {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWeekStartsMondayKey];
}

- (void)setWeekStartsOnMonday:(BOOL)weekStartsOnMonday {
    [[NSUserDefaults standardUserDefaults] setBool:weekStartsOnMonday forKey:kWeekStartsMondayKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self postChangeNotification];
}

- (NSArray<NSNumber *> *)daysToDisplay {
    return [SCWeeklySchedule remainingDaysInWeekStartingMonday:self.weekStartsOnMonday];
}

- (NSArray<NSNumber *> *)allDaysInOrder {
    return [SCWeeklySchedule allDaysStartingMonday:self.weekStartsOnMonday];
}

#pragma mark - Commitment

- (BOOL)isCommitted {
    // Check if we have a commitment that hasn't expired
    NSDate *endDate = self.commitmentEndDate;
    if (!endDate) return NO;

    return [endDate timeIntervalSinceNow] > 0;
}

- (nullable NSDate *)commitmentEndDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kCommitmentEndDateKey];
}

- (void)commitToWeek {
    // Calculate end of week based on week start preference
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];

    // Find the end of the current week
    NSDateComponents *components = [calendar components:(NSCalendarUnitYearForWeekOfYear | NSCalendarUnitWeekOfYear)
                                               fromDate:now];

    // Set to end of week (Sunday 23:59:59 or Saturday 23:59:59)
    if (self.weekStartsOnMonday) {
        // Week ends Sunday
        components.weekday = 1; // Sunday
    } else {
        // Week ends Saturday
        components.weekday = 7; // Saturday
    }

    NSDate *endOfWeek = [calendar dateFromComponents:components];

    // Add a day to get to the very end
    endOfWeek = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:endOfWeek options:0];
    // Subtract 1 second to get 23:59:59
    endOfWeek = [endOfWeek dateByAddingTimeInterval:-1];

    [[NSUserDefaults standardUserDefaults] setObject:endOfWeek forKey:kCommitmentEndDateKey];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kIsCommittedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self postChangeNotification];
}

- (BOOL)changeWouldLoosenSchedule:(SCWeeklySchedule *)oldSchedule
                      toSchedule:(SCWeeklySchedule *)newSchedule
                          forDay:(SCDayOfWeek)day {
    NSArray<SCTimeRange *> *oldWindows = [oldSchedule allowedWindowsForDay:day];
    NSArray<SCTimeRange *> *newWindows = [newSchedule allowedWindowsForDay:day];

    // Calculate total allowed minutes
    NSInteger oldTotal = 0;
    for (SCTimeRange *range in oldWindows) {
        oldTotal += [range durationMinutes];
    }

    NSInteger newTotal = 0;
    for (SCTimeRange *range in newWindows) {
        newTotal += [range durationMinutes];
    }

    // If new has MORE allowed time, it's looser
    if (newTotal > oldTotal) {
        return YES;
    }

    // Check if any new window extends beyond old windows
    // (More sophisticated check for partial overlap)
    for (SCTimeRange *newRange in newWindows) {
        BOOL coveredByOld = NO;
        for (SCTimeRange *oldRange in oldWindows) {
            // Check if new range is fully contained within old range
            if ([newRange startMinutes] >= [oldRange startMinutes] &&
                [newRange endMinutes] <= [oldRange endMinutes]) {
                coveredByOld = YES;
                break;
            }
        }
        if (!coveredByOld && newRange.durationMinutes > 0) {
            return YES; // New window not covered by any old window
        }
    }

    return NO;
}

- (void)clearCommitmentForDebug {
#ifdef DEBUG
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCommitmentEndDateKey];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kIsCommittedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self postChangeNotification];
#endif
}

#pragma mark - Status Display

- (NSDictionary<NSString *, NSDictionary *> *)currentStatusForDisplay {
    NSMutableDictionary *status = [NSMutableDictionary dictionary];

    for (SCBlockBundle *bundle in self.mutableBundles) {
        SCWeeklySchedule *schedule = [self scheduleForBundleID:bundle.bundleID];
        BOOL allowed = schedule ? [schedule isAllowedNow] : NO;

        status[bundle.bundleID] = @{
            @"name": bundle.name,
            @"allowed": @(allowed),
            @"statusString": [self statusStringForBundleID:bundle.bundleID],
            @"color": bundle.color ?: [NSColor grayColor]
        };
    }

    return status;
}

- (NSString *)statusStringForBundleID:(NSString *)bundleID {
    SCWeeklySchedule *schedule = [self scheduleForBundleID:bundleID];
    if (!schedule) {
        return @"No schedule";
    }
    return [schedule currentStatusString];
}

- (BOOL)wouldBundleBeAllowed:(NSString *)bundleID {
    SCWeeklySchedule *schedule = [self scheduleForBundleID:bundleID];
    if (!schedule) {
        return NO; // No schedule = blocked by default
    }
    return [schedule isAllowedNow];
}

#pragma mark - Persistence

- (void)save {
    // Save bundles
    NSMutableArray *bundleDicts = [NSMutableArray array];
    for (SCBlockBundle *bundle in self.mutableBundles) {
        [bundleDicts addObject:[bundle toDictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:bundleDicts forKey:kBundlesKey];

    // Save schedules
    NSMutableArray *scheduleDicts = [NSMutableArray array];
    for (SCWeeklySchedule *schedule in self.mutableSchedules) {
        [scheduleDicts addObject:[schedule toDictionary]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:scheduleDicts forKey:kSchedulesKey];

    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)reload {
    [self.mutableBundles removeAllObjects];
    [self.mutableSchedules removeAllObjects];

    // Load bundles
    NSArray *bundleDicts = [[NSUserDefaults standardUserDefaults] objectForKey:kBundlesKey];
    for (NSDictionary *dict in bundleDicts) {
        SCBlockBundle *bundle = [SCBlockBundle bundleFromDictionary:dict];
        if (bundle) {
            [self.mutableBundles addObject:bundle];
        }
    }

    // Sort bundles by display order
    [self.mutableBundles sortUsingComparator:^NSComparisonResult(SCBlockBundle *b1, SCBlockBundle *b2) {
        return [@(b1.displayOrder) compare:@(b2.displayOrder)];
    }];

    // Load schedules
    NSArray *scheduleDicts = [[NSUserDefaults standardUserDefaults] objectForKey:kSchedulesKey];
    for (NSDictionary *dict in scheduleDicts) {
        SCWeeklySchedule *schedule = [SCWeeklySchedule scheduleFromDictionary:dict];
        if (schedule) {
            [self.mutableSchedules addObject:schedule];
        }
    }
}

- (void)clearAllData {
    [self.mutableBundles removeAllObjects];
    [self.mutableSchedules removeAllObjects];

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBundlesKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSchedulesKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCommitmentEndDateKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kIsCommittedKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self postChangeNotification];
}

#pragma mark - Notifications

- (void)postChangeNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:SCScheduleManagerDidChangeNotification
                                                        object:self];
}

@end
