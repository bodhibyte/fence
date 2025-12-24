//
//  SCTimeRange.h
//  SelfControl
//
//  Represents a time range within a day (e.g., 9:00am - 5:00pm)
//  Used for defining allowed windows in weekly schedules.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCTimeRange : NSObject <NSCopying, NSSecureCoding>

/// Start time in 24h format "HH:mm" (e.g., "09:00")
@property (nonatomic, copy) NSString *startTime;

/// End time in 24h format "HH:mm" (e.g., "17:00", or "23:59" for end-of-day)
@property (nonatomic, copy) NSString *endTime;

/// Creates a time range from start to end times
+ (instancetype)rangeWithStart:(NSString *)start end:(NSString *)end;

/// Creates a time range from a dictionary (for persistence)
+ (nullable instancetype)rangeFromDictionary:(NSDictionary *)dict;

/// Converts to dictionary for persistence
- (NSDictionary *)toDictionary;

/// Returns start time as minutes from midnight (0-1439)
- (NSInteger)startMinutes;

/// Returns end time as minutes from midnight (0-1439)
- (NSInteger)endMinutes;

/// Returns duration in minutes
- (NSInteger)durationMinutes;

/// Checks if a given time (minutes from midnight) falls within this range
- (BOOL)containsTimeInMinutes:(NSInteger)minutes;

/// Checks if the current time falls within this range
- (BOOL)containsCurrentTime;

/// Returns human-readable description (e.g., "9:00am - 5:00pm")
- (NSString *)displayString;

/// Returns human-readable description with 12h format
- (NSString *)displayString12Hour;

/// Validates the time range (start < end, valid times)
- (BOOL)isValid;

/// Common presets
+ (instancetype)workHours;       // 9:00 - 17:00
+ (instancetype)extendedWork;    // 8:00 - 20:00
+ (instancetype)wakingHours;     // 7:00 - 23:00
+ (instancetype)allDay;          // 0:00 - 23:59

@end

NS_ASSUME_NONNULL_END
