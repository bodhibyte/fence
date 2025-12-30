//
//  SCLicenseManager.h
//  SelfControl
//
//  Manages trial tracking, license validation, and Keychain storage for Fence licensing.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCLicenseStatus) {
    SCLicenseStatusTrial,           // Still in trial period (before expiry date)
    SCLicenseStatusTrialExpired,    // Trial over, no valid license
    SCLicenseStatusValid,           // Valid license stored in Keychain
    SCLicenseStatusInvalid          // License present but invalid signature
};

@interface SCLicenseManager : NSObject

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Trial Tracking (Date-Based)

/// Returns the trial expiry date (3rd Sunday from first launch)
/// Calculates and stores on first access
- (NSDate *)trialExpiryDate;

/// Returns the number of days remaining in trial (0 if expired)
- (NSInteger)trialDaysRemaining;

/// Returns YES if current date >= expiry date
- (BOOL)isTrialExpired;

/// Date of first app launch
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

#pragma mark - Online Activation (Server-Side Validation)

/// Activates a license online - validates with server and marks key as used.
/// @param code The license code to activate
/// @param completion Called with success status and optional error message
- (void)activateLicenseOnline:(NSString *)code
                   completion:(void(^)(BOOL success, NSString *_Nullable errorMessage))completion;

#pragma mark - Trial Sync (Server-Side Tracking)

/// Syncs trial status with server on app launch.
/// This prevents trial reset by reinstalling the app.
/// @param completion Called with days remaining (-1 if offline/error, uses cached)
- (void)syncTrialStatusWithCompletion:(void(^)(NSInteger daysRemaining))completion;

#pragma mark - Debug/Testing

/// Clears the stored license from Keychain (for testing)
- (void)clearStoredLicense;

/// Resets trial to fresh state (recalculates 3rd Sunday from today)
- (void)resetTrialState;

/// Expires trial immediately (sets expiry to today)
- (void)expireTrialState;

@end

NS_ASSUME_NONNULL_END
