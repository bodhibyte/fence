//
//  SCLicenseManager.h
//  SelfControl
//
//  Manages trial tracking, license validation, and Keychain storage for Fence licensing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCLicenseStatus) {
    SCLicenseStatusTrial,           // Still in trial period (< 2 commits)
    SCLicenseStatusTrialExpired,    // Trial over, no valid license
    SCLicenseStatusValid,           // Valid license stored in Keychain
    SCLicenseStatusInvalid          // License present but invalid signature
};

@interface SCLicenseManager : NSObject

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Trial Tracking

/// Number of commits made so far (stored in UserDefaults)
- (NSInteger)commitCount;

/// Call after a successful commit to increment the counter
- (void)recordCommit;

/// Returns YES if commitCount >= 2 (trial exhausted)
- (BOOL)isTrialExpired;

/// Date of first app launch (for reference, not used in trial logic)
@property (nonatomic, readonly, nullable) NSDate *firstLaunchDate;

#pragma mark - License Status

/// Main check for commit flow: returns YES if trial valid OR license valid
- (BOOL)canCommit;

/// Returns current license status
- (SCLicenseStatus)currentStatus;

#pragma mark - License Validation & Activation

/// Validates a license code format and HMAC signature (does not store)
/// @param code The full license code (e.g., "FENCE-xxxxx...")
/// @param error Output parameter for validation errors
/// @return YES if the code is valid
- (BOOL)validateLicenseCode:(NSString *)code error:(NSError *_Nullable *_Nullable)error;

/// Validates and stores the license code in Keychain
/// @param code The full license code
/// @param error Output parameter for errors
/// @return YES if successfully validated and stored
- (BOOL)activateLicenseCode:(NSString *)code error:(NSError *_Nullable *_Nullable)error;

/// Retrieves the email from the currently stored license (if any)
/// @return The email address from the license payload, or nil if no valid license
- (nullable NSString *)storedLicenseEmail;

/// Returns the stored license code from Keychain (if any)
- (nullable NSString *)storedLicenseCode;

#pragma mark - Debug/Testing

/// Clears the stored license from Keychain (for testing)
- (void)clearStoredLicense;

/// Resets commit count to 0 (for testing)
- (void)resetTrialState;

@end

NS_ASSUME_NONNULL_END
