//
//  SCTimeRange.m
//  SelfControl
//

#import "SCTimeRange.h"

@implementation SCTimeRange

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _startTime = @"00:00";
        _endTime = @"23:59";
    }
    return self;
}

+ (instancetype)rangeWithStart:(NSString *)start end:(NSString *)end {
    SCTimeRange *range = [[SCTimeRange alloc] init];
    range.startTime = start;
    range.endTime = end;
    return range;
}

+ (nullable instancetype)rangeFromDictionary:(NSDictionary *)dict {
    if (!dict[@"startTime"] || !dict[@"endTime"]) {
        return nil;
    }
    return [self rangeWithStart:dict[@"startTime"] end:dict[@"endTime"]];
}

- (NSDictionary *)toDictionary {
    return @{
        @"startTime": self.startTime ?: @"00:00",
        @"endTime": self.endTime ?: @"23:59"
    };
}

#pragma mark - Time Calculations

- (NSInteger)startMinutes {
    return [self minutesFromTimeString:self.startTime];
}

- (NSInteger)endMinutes {
    return [self minutesFromTimeString:self.endTime];
}

- (NSInteger)minutesFromTimeString:(NSString *)timeString {
    NSArray *components = [timeString componentsSeparatedByString:@":"];
    if (components.count != 2) return 0;

    NSInteger hours = [components[0] integerValue];
    NSInteger minutes = [components[1] integerValue];
    return hours * 60 + minutes;
}

- (NSInteger)durationMinutes {
    NSInteger start = [self startMinutes];
    NSInteger end = [self endMinutes];
    if (end >= start) {
        return end - start;
    }
    // Handles overnight (e.g., 23:00 - 06:00) - though we split these
    return (24 * 60 - start) + end;
}

- (BOOL)containsTimeInMinutes:(NSInteger)minutes {
    NSInteger start = [self startMinutes];
    NSInteger end = [self endMinutes];

    // Normal case: start <= end
    if (start <= end) {
        return minutes >= start && minutes <= end;
    }
    // Overnight case (shouldn't happen with split ranges, but handle it)
    return minutes >= start || minutes <= end;
}

- (BOOL)containsCurrentTime {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                               fromDate:[NSDate date]];
    NSInteger currentMinutes = components.hour * 60 + components.minute;
    return [self containsTimeInMinutes:currentMinutes];
}

#pragma mark - Display

- (NSString *)displayString {
    return [NSString stringWithFormat:@"%@ - %@", self.startTime, self.endTime];
}

- (NSString *)displayString12Hour {
    return [NSString stringWithFormat:@"%@ - %@",
            [self format12Hour:self.startTime],
            [self format12Hour:self.endTime]];
}

- (NSString *)format12Hour:(NSString *)time24 {
    NSInteger minutes = [self minutesFromTimeString:time24];

    // Handle 24:00 (end of day midnight) explicitly
    if (minutes == 24 * 60) {
        return @"12:00am";
    }

    NSInteger hours = minutes / 60;
    NSInteger mins = minutes % 60;

    NSString *period = (hours < 12) ? @"am" : @"pm";
    if (hours == 0) hours = 12;
    else if (hours > 12) hours -= 12;

    // Always include minutes for consistent width (prevents jitter during drag)
    return [NSString stringWithFormat:@"%ld:%02ld%@", (long)hours, (long)mins, period];
}

- (BOOL)isValid {
    NSInteger start = [self startMinutes];
    NSInteger end = [self endMinutes];

    // Times must be in valid range (0-1439 for start, 0-1440 for end)
    // End can be 1440 (24:00) to represent end of day
    if (start < 0 || start > 24 * 60 - 1) return NO;
    if (end < 0 || end > 24 * 60) return NO;

    // End must be after start (we don't allow overnight in single range)
    return end >= start;
}

#pragma mark - Presets

+ (instancetype)workHours {
    return [self rangeWithStart:@"09:00" end:@"17:00"];
}

+ (instancetype)extendedWork {
    return [self rangeWithStart:@"08:00" end:@"20:00"];
}

+ (instancetype)wakingHours {
    return [self rangeWithStart:@"07:00" end:@"23:00"];
}

+ (instancetype)allDay {
    return [self rangeWithStart:@"00:00" end:@"24:00"];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    SCTimeRange *copy = [[SCTimeRange allocWithZone:zone] init];
    copy.startTime = [self.startTime copy];
    copy.endTime = [self.endTime copy];
    return copy;
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.startTime forKey:@"startTime"];
    [coder encodeObject:self.endTime forKey:@"endTime"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _startTime = [coder decodeObjectOfClass:[NSString class] forKey:@"startTime"];
        _endTime = [coder decodeObjectOfClass:[NSString class] forKey:@"endTime"];
    }
    return self;
}

#pragma mark - Equality

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[SCTimeRange class]]) return NO;

    SCTimeRange *other = (SCTimeRange *)object;
    return [self.startTime isEqualToString:other.startTime] &&
           [self.endTime isEqualToString:other.endTime];
}

- (NSUInteger)hash {
    return [self.startTime hash] ^ [self.endTime hash];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<SCTimeRange: %@>", [self displayString12Hour]];
}

@end
