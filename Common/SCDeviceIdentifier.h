//
//  SCDeviceIdentifier.h
//  SelfControl
//
//  Generates a stable, privacy-preserving device identifier for license tracking.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCDeviceIdentifier : NSObject

/// Returns a SHA256 hash of the hardware UUID.
/// This identifier is stable across app reinstalls but privacy-preserving.
+ (NSString *)deviceIdentifier;

@end

NS_ASSUME_NONNULL_END
