//
//  SCDeviceIdentifier.m
//  SelfControl
//
//  Generates a stable, privacy-preserving device identifier for license tracking.
//

#import "SCDeviceIdentifier.h"
#import <IOKit/IOKitLib.h>
#import <CommonCrypto/CommonDigest.h>

@implementation SCDeviceIdentifier

+ (NSString *)deviceIdentifier {
    static NSString *cachedIdentifier = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        NSString *hardwareUUID = [self hardwareUUID];
        if (hardwareUUID) {
            cachedIdentifier = [self sha256Hash:hardwareUUID];
        } else {
            // Fallback: use a random UUID stored in user defaults
            NSString *fallbackKey = @"FenceDeviceIdentifierFallback";
            cachedIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:fallbackKey];
            if (!cachedIdentifier) {
                cachedIdentifier = [self sha256Hash:[[NSUUID UUID] UUIDString]];
                [[NSUserDefaults standardUserDefaults] setObject:cachedIdentifier forKey:fallbackKey];
            }
        }
    });

    return cachedIdentifier;
}

+ (NSString *)hardwareUUID {
    io_service_t platformExpert = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPlatformExpertDevice")
    );

    if (!platformExpert) {
        NSLog(@"[SCDeviceIdentifier] Failed to get IOPlatformExpertDevice");
        return nil;
    }

    CFTypeRef uuidRef = IORegistryEntryCreateCFProperty(
        platformExpert,
        CFSTR(kIOPlatformUUIDKey),
        kCFAllocatorDefault,
        0
    );

    IOObjectRelease(platformExpert);

    if (!uuidRef) {
        NSLog(@"[SCDeviceIdentifier] Failed to get platform UUID");
        return nil;
    }

    NSString *uuid = (__bridge_transfer NSString *)uuidRef;
    return uuid;
}

+ (NSString *)sha256Hash:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];

    CC_SHA256(cStr, (CC_LONG)strlen(cStr), hash);

    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", hash[i]];
    }

    return result;
}

@end
