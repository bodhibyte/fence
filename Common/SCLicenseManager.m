//
//  SCLicenseManager.m
//  SelfControl
//
//  Manages trial tracking, license validation, and Keychain storage for Fence licensing.
//

#import "SCLicenseManager.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>

#pragma mark - UserDefaults Keys

static NSString * const kFirstLaunchDateKey = @"FenceFirstLaunchDate";
static NSString * const kCommitCountKey = @"FenceCommitCount";

#pragma mark - Keychain Constants

static NSString * const kKeychainService = @"app.usefence.license";
static NSString * const kKeychainAccount = @"license";

#pragma mark - License Validation Constants

static NSString * const kLicensePrefix = @"FENCE-";

// The secret key is injected via build settings (Secrets.xcconfig)
// This allows the key to be kept out of source control
#ifndef LICENSE_SECRET_KEY
#define LICENSE_SECRET_KEY PLACEHOLDER_KEY_FOR_DEVELOPMENT
#endif

// Stringify macro to convert preprocessor definition to NSString
#define STRINGIFY(x) @#x
#define STRINGIFY_VALUE(x) STRINGIFY(x)

#pragma mark - Error Domain

NSString * const SCLicenseErrorDomain = @"SCLicenseError";

typedef NS_ENUM(NSInteger, SCLicenseErrorCode) {
    SCLicenseErrorInvalidFormat = 1,
    SCLicenseErrorInvalidEncoding = 2,
    SCLicenseErrorInvalidStructure = 3,
    SCLicenseErrorInvalidSignature = 4,
    SCLicenseErrorKeychainFailure = 5,
    SCLicenseErrorInvalidPayload = 6
};

#pragma mark - Implementation

@interface SCLicenseManager ()
@property (nonatomic, strong) NSDate *firstLaunchDate;
@end

@implementation SCLicenseManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static SCLicenseManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SCLicenseManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self ensureFirstLaunchDate];
    }
    return self;
}

- (void)ensureFirstLaunchDate {
    NSDate *storedDate = [[NSUserDefaults standardUserDefaults] objectForKey:kFirstLaunchDateKey];
    if (!storedDate) {
        storedDate = [NSDate date];
        [[NSUserDefaults standardUserDefaults] setObject:storedDate forKey:kFirstLaunchDateKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    _firstLaunchDate = storedDate;
}

#pragma mark - Trial Tracking

- (NSInteger)commitCount {
    NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:kCommitCountKey];
    NSLog(@"[SCLicenseManager] commitCount = %ld (key: %@)", (long)count, kCommitCountKey);
    return count;
}

- (void)recordCommit {
    NSInteger count = [self commitCount];
    [[NSUserDefaults standardUserDefaults] setInteger:count + 1 forKey:kCommitCountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (BOOL)isTrialExpired {
    NSInteger count = [self commitCount];
    BOOL expired = count >= 2;
    NSLog(@"[SCLicenseManager] isTrialExpired = %@ (count=%ld, threshold=2)", expired ? @"YES" : @"NO", (long)count);
    return expired;
}

#pragma mark - License Status

- (BOOL)canCommit {
    if (![self isTrialExpired]) {
        return YES;  // Still in trial
    }
    return [self currentStatus] == SCLicenseStatusValid;
}

- (SCLicenseStatus)currentStatus {
    if (![self isTrialExpired]) {
        NSLog(@"[SCLicenseManager] currentStatus = SCLicenseStatusTrial (trial not expired)");
        return SCLicenseStatusTrial;
    }

    NSString *storedCode = [self retrieveLicenseFromKeychain];
    if (!storedCode) {
        NSLog(@"[SCLicenseManager] currentStatus = SCLicenseStatusTrialExpired (no stored code)");
        return SCLicenseStatusTrialExpired;
    }

    if ([self validateLicenseCode:storedCode error:nil]) {
        NSLog(@"[SCLicenseManager] currentStatus = SCLicenseStatusValid (valid license)");
        return SCLicenseStatusValid;
    }

    NSLog(@"[SCLicenseManager] currentStatus = SCLicenseStatusInvalid (invalid license)");
    return SCLicenseStatusInvalid;
}

#pragma mark - License Validation

- (BOOL)validateLicenseCode:(NSString *)code error:(NSError **)error {
    // Must start with "FENCE-"
    if (![code hasPrefix:kLicensePrefix]) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license format. Code must start with FENCE-."}];
        }
        return NO;
    }

    // Extract the base64-encoded part
    NSString *encoded = [code substringFromIndex:kLicensePrefix.length];

    // Decode from base64
    // Handle base64url encoding (replace - with + and _ with /)
    NSString *base64Standard = [[encoded stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                stringByReplacingOccurrencesOfString:@"_" withString:@"/"];

    // Add padding if necessary
    NSInteger padLength = (4 - (base64Standard.length % 4)) % 4;
    NSString *paddedBase64 = [base64Standard stringByPaddingToLength:base64Standard.length + padLength
                                                          withString:@"="
                                                     startingAtIndex:0];

    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:paddedBase64 options:0];
    if (!decoded) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidEncoding
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license encoding."}];
        }
        return NO;
    }

    NSString *decodedStr = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    if (!decodedStr) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidEncoding
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license data."}];
        }
        return NO;
    }

    // Split into payload and signature by last "." separator
    NSRange lastDotRange = [decodedStr rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDotRange.location == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidStructure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license structure."}];
        }
        return NO;
    }

    NSString *payloadStr = [decodedStr substringToIndex:lastDotRange.location];
    NSString *providedSignature = [decodedStr substringFromIndex:lastDotRange.location + 1];

    // Verify the payload is valid JSON
    NSData *payloadData = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonError];
    if (!payload || jsonError) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidPayload
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license payload."}];
        }
        return NO;
    }

    // Verify required fields exist
    if (!payload[@"e"] || !payload[@"t"] || !payload[@"c"]) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidPayload
                                     userInfo:@{NSLocalizedDescriptionKey: @"License missing required fields."}];
        }
        return NO;
    }

    // Compute HMAC signature
    NSString *secretKey = STRINGIFY_VALUE(LICENSE_SECRET_KEY);
    NSString *computedSignature = [self hmacSHA256:payloadStr withKey:secretKey];

    // Compare signatures (case-insensitive hex comparison)
    if (![computedSignature.lowercaseString isEqualToString:providedSignature.lowercaseString]) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorInvalidSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid license signature."}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)activateLicenseCode:(NSString *)code error:(NSError **)error {
    // First validate the code
    if (![self validateLicenseCode:code error:error]) {
        return NO;
    }

    // Store in Keychain
    BOOL stored = [self storeLicenseInKeychain:code];
    if (!stored) {
        if (error) {
            *error = [NSError errorWithDomain:SCLicenseErrorDomain
                                         code:SCLicenseErrorKeychainFailure
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to save license. Please try again."}];
        }
        return NO;
    }

    return YES;
}

- (NSString *)storedLicenseEmail {
    NSString *code = [self retrieveLicenseFromKeychain];
    if (!code) return nil;

    // Validate first to ensure it's still valid
    if (![self validateLicenseCode:code error:nil]) {
        return nil;
    }

    // Extract payload and parse email
    NSDictionary *payload = [self extractPayloadFromCode:code];
    return payload[@"e"];
}

- (NSString *)storedLicenseCode {
    return [self retrieveLicenseFromKeychain];
}

- (NSDictionary *)extractPayloadFromCode:(NSString *)code {
    if (![code hasPrefix:kLicensePrefix]) return nil;

    NSString *encoded = [code substringFromIndex:kLicensePrefix.length];

    // Handle base64url encoding
    NSString *base64Standard = [[encoded stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                stringByReplacingOccurrencesOfString:@"_" withString:@"/"];

    NSInteger padLength = (4 - (base64Standard.length % 4)) % 4;
    NSString *paddedBase64 = [base64Standard stringByPaddingToLength:base64Standard.length + padLength
                                                          withString:@"="
                                                     startingAtIndex:0];

    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:paddedBase64 options:0];
    if (!decoded) return nil;

    NSString *decodedStr = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    if (!decodedStr) return nil;

    NSRange lastDotRange = [decodedStr rangeOfString:@"." options:NSBackwardsSearch];
    if (lastDotRange.location == NSNotFound) return nil;

    NSString *payloadStr = [decodedStr substringToIndex:lastDotRange.location];
    NSData *payloadData = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];

    return [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];
}

#pragma mark - Keychain Operations

- (BOOL)storeLicenseInKeychain:(NSString *)code {
    // Delete existing first
    [self deleteLicenseFromKeychain];

    NSData *codeData = [code dataUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecValueData: codeData,
        (__bridge id)kSecAttrSynchronizable: @YES,  // iCloud Keychain sync
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
    };

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);

    if (status != errSecSuccess) {
        CFStringRef errorMessage = SecCopyErrorMessageString(status, NULL);
        NSLog(@"[SCLicenseManager] Failed to store license in Keychain: %d (%@)",
              (int)status, (__bridge NSString *)errorMessage);
        if (errorMessage) CFRelease(errorMessage);
    }

    return status == errSecSuccess;
}

- (NSString *)retrieveLicenseFromKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrSynchronizable: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };

    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&dataRef);

    if (status == errSecSuccess && dataRef) {
        NSData *data = (__bridge_transfer NSData *)dataRef;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }

    return nil;
}

- (void)deleteLicenseFromKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrSynchronizable: @YES
    };

    SecItemDelete((__bridge CFDictionaryRef)query);
}

#pragma mark - Crypto

- (NSString *)hmacSHA256:(NSString *)data withKey:(NSString *)key {
    const char *cKey = [key cStringUsingEncoding:NSUTF8StringEncoding];
    const char *cData = [data cStringUsingEncoding:NSUTF8StringEncoding];

    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), hmac);

    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", hmac[i]];
    }

    return result;
}

#pragma mark - Debug/Testing

- (void)clearStoredLicense {
    [self deleteLicenseFromKeychain];
}

- (void)resetTrialState {
    // Clear commit count and first launch date
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCommitCountKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kFirstLaunchDateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self ensureFirstLaunchDate];

    // Clear license from keychain
    [self deleteLicenseFromKeychain];

    NSLog(@"[SCLicenseManager] Trial state reset (commit count cleared, license removed)");
}

- (void)expireTrialState {
    // Set commit count to threshold (2) to expire trial
    [[NSUserDefaults standardUserDefaults] setInteger:2 forKey:kCommitCountKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Clear license from keychain
    [self deleteLicenseFromKeychain];

    NSLog(@"[SCLicenseManager] Trial expired (commit count set to 2, license removed)");
}

@end
