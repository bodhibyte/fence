//
//  SCScheduleManager.m
//  SelfControl
//

#import "SCScheduleManager.h"

NSNotificationName const SCScheduleManagerDidChangeNotification = @"SCScheduleManagerDidChangeNotification";

// NSUserDefaults keys (app-layer only, not in SCSettings)
static NSString * const kBundlesKey = @"SCScheduleBundles";
static NSString * const kSchedulesKey = @"SCWeeklySchedules";
static NSString * const kWeekSchedulesPrefix = @"SCWeekSchedules_"; // + week key (e.g., "2024-12-23")
static NSString * const kWeekCommitmentPrefix = @"SCWeekCommitment_"; // + week key
static NSString * const kCommitmentEndDateKey = @"SCCommitmentEndDate";
static NSString * const kIsCommittedKey = @"SCIsCommitted";

@interface SCScheduleManager ()

@property (nonatomic, strong) NSMutableArray<SCBlockBundle *> *mutableBundles;
@property (nonatomic, strong) NSMutableArray<SCWeeklySchedule *> *mutableSchedules;
// Cache for week-specific schedules: weekKey -> array of schedules
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<SCWeeklySchedule *> *> *weekSchedulesCache;

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
        _weekSchedulesCache = [NSMutableDictionary dictionary];
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

#pragma mark - Week Settings

- (NSArray<NSNumber *> *)daysToDisplay {
    return [self daysToDisplayForWeekOffset:0];
}

- (NSArray<NSNumber *> *)daysToDisplayForWeekOffset:(NSInteger)weekOffset {
    if (weekOffset == 0) {
        // Current week - show remaining days from today
        return [SCWeeklySchedule remainingDaysInWeekStartingMonday:YES];
    } else {
        // Future weeks - show all days
        return [SCWeeklySchedule allDaysStartingMonday:YES];
    }
}

- (NSArray<NSNumber *> *)allDaysInOrder {
    return [SCWeeklySchedule allDaysStartingMonday:YES];
}

#pragma mark - Multi-Week Schedules

- (NSString *)weekKeyForOffset:(NSInteger)weekOffset {
    NSDate *weekStart;
    if (weekOffset == 0) {
        weekStart = [SCWeeklySchedule startOfCurrentWeek];
    } else {
        NSCalendar *calendar = [NSCalendar currentCalendar];
        weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay
                                         value:weekOffset * 7
                                        toDate:[SCWeeklySchedule startOfCurrentWeek]
                                       options:0];
    }
    return [SCWeeklySchedule weekKeyForDate:weekStart];
}

- (NSArray<SCWeeklySchedule *> *)schedulesForWeekOffset:(NSInteger)weekOffset {
    NSString *weekKey = [self weekKeyForOffset:weekOffset];

    // Check cache first
    if (self.weekSchedulesCache[weekKey]) {
        return [self.weekSchedulesCache[weekKey] copy];
    }

    // Load from NSUserDefaults
    NSString *storageKey = [kWeekSchedulesPrefix stringByAppendingString:weekKey];
    NSArray *scheduleDicts = [[NSUserDefaults standardUserDefaults] objectForKey:storageKey];

    NSMutableArray<SCWeeklySchedule *> *schedules = [NSMutableArray array];
    for (NSDictionary *dict in scheduleDicts) {
        SCWeeklySchedule *schedule = [SCWeeklySchedule scheduleFromDictionary:dict];
        if (schedule) {
            [schedules addObject:schedule];
        }
    }

    // Cache the result
    self.weekSchedulesCache[weekKey] = schedules;

    return [schedules copy];
}

- (nullable SCWeeklySchedule *)scheduleForBundleID:(NSString *)bundleID weekOffset:(NSInteger)weekOffset {
    NSArray<SCWeeklySchedule *> *schedules = [self schedulesForWeekOffset:weekOffset];
    for (SCWeeklySchedule *schedule in schedules) {
        if ([schedule.bundleID isEqualToString:bundleID]) {
            return schedule;
        }
    }
    return nil;
}

- (void)updateSchedule:(SCWeeklySchedule *)schedule forWeekOffset:(NSInteger)weekOffset {
    // Check commitment constraint
    if ([self isCommittedForWeekOffset:weekOffset]) {
        SCWeeklySchedule *oldSchedule = [self scheduleForBundleID:schedule.bundleID weekOffset:weekOffset];
        if (oldSchedule) {
            for (SCDayOfWeek day = SCDayOfWeekSunday; day <= SCDayOfWeekSaturday; day++) {
                if ([self changeWouldLoosenSchedule:oldSchedule toSchedule:schedule forDay:day]) {
                    NSLog(@"Rejecting schedule change that would loosen restrictions while committed");
                    return;
                }
            }
        }
    }

    NSString *weekKey = [self weekKeyForOffset:weekOffset];

    // Ensure cache is loaded
    [self schedulesForWeekOffset:weekOffset];

    NSMutableArray<SCWeeklySchedule *> *schedules = self.weekSchedulesCache[weekKey];
    if (!schedules) {
        schedules = [NSMutableArray array];
        self.weekSchedulesCache[weekKey] = schedules;
    }

    // Find and update or add
    NSInteger index = NSNotFound;
    for (NSUInteger i = 0; i < schedules.count; i++) {
        if ([schedules[i].bundleID isEqualToString:schedule.bundleID]) {
            index = i;
            break;
        }
    }

    if (index != NSNotFound) {
        schedules[index] = schedule;
    } else {
        [schedules addObject:schedule];
    }

    // Save to NSUserDefaults
    [self saveSchedulesForWeekOffset:weekOffset];
    [self postChangeNotification];
}

- (SCWeeklySchedule *)createScheduleForBundle:(SCBlockBundle *)bundle weekOffset:(NSInteger)weekOffset {
    SCWeeklySchedule *schedule = [SCWeeklySchedule emptyScheduleForBundleID:bundle.bundleID];

    NSString *weekKey = [self weekKeyForOffset:weekOffset];

    // Ensure cache exists
    if (!self.weekSchedulesCache[weekKey]) {
        self.weekSchedulesCache[weekKey] = [NSMutableArray array];
    }

    [self.weekSchedulesCache[weekKey] addObject:schedule];
    [self saveSchedulesForWeekOffset:weekOffset];

    return schedule;
}

- (void)saveSchedulesForWeekOffset:(NSInteger)weekOffset {
    NSString *weekKey = [self weekKeyForOffset:weekOffset];
    NSString *storageKey = [kWeekSchedulesPrefix stringByAppendingString:weekKey];

    NSMutableArray *scheduleDicts = [NSMutableArray array];
    for (SCWeeklySchedule *schedule in self.weekSchedulesCache[weekKey]) {
        [scheduleDicts addObject:[schedule toDictionary]];
    }

    [[NSUserDefaults standardUserDefaults] setObject:scheduleDicts forKey:storageKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Commitment

- (BOOL)isCommitted {
    return [self isCommittedForWeekOffset:0];
}

- (nullable NSDate *)commitmentEndDate {
    return [self commitmentEndDateForWeekOffset:0];
}

- (BOOL)isCommittedForWeekOffset:(NSInteger)weekOffset {
    NSDate *endDate = [self commitmentEndDateForWeekOffset:weekOffset];
    if (!endDate) return NO;
    return [endDate timeIntervalSinceNow] > 0;
}

- (nullable NSDate *)commitmentEndDateForWeekOffset:(NSInteger)weekOffset {
    NSString *weekKey = [self weekKeyForOffset:weekOffset];
    NSString *storageKey = [kWeekCommitmentPrefix stringByAppendingString:weekKey];
    return [[NSUserDefaults standardUserDefaults] objectForKey:storageKey];
}

- (void)commitToWeek {
    [self commitToWeekWithOffset:0];
}

- (void)commitToWeekWithOffset:(NSInteger)weekOffset {
    NSCalendar *calendar = [NSCalendar currentCalendar];

    // Get the Monday of the target week
    NSDate *weekStart;
    if (weekOffset == 0) {
        weekStart = [SCWeeklySchedule startOfCurrentWeek];
    } else {
        weekStart = [calendar dateByAddingUnit:NSCalendarUnitDay
                                         value:weekOffset * 7
                                        toDate:[SCWeeklySchedule startOfCurrentWeek]
                                       options:0];
    }

    // Week ends on Sunday (6 days after Monday) at 23:59:59
    NSDate *endOfWeek = [calendar dateByAddingUnit:NSCalendarUnitDay value:6 toDate:weekStart options:0];
    // Move to end of day
    NSDateComponents *endOfDayComponents = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                       fromDate:endOfWeek];
    endOfDayComponents.hour = 23;
    endOfDayComponents.minute = 59;
    endOfDayComponents.second = 59;
    endOfWeek = [calendar dateFromComponents:endOfDayComponents];

    // Store with week-specific key
    NSString *weekKey = [self weekKeyForOffset:weekOffset];
    NSString *storageKey = [kWeekCommitmentPrefix stringByAppendingString:weekKey];
    [[NSUserDefaults standardUserDefaults] setObject:endOfWeek forKey:storageKey];
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
