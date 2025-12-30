# Fence Licensing System - Implementation Specification

> **For AI Agents:** This document contains everything needed to implement the licensing system. Read fully before starting.

---

## Overview

Fence is a macOS app (Objective-C) that blocks apps/websites on a schedule. Users get a 2-week free trial, then must purchase a license ($49 regular, $5 student) to continue using the app.

**Key Principle:** The app's brand is "a lock you can't pick" - the licensing must follow this. Hard block, no workarounds, no nag screens.

---

## Trial Logic

### Rules
- User gets **2 free commits** (2 weeks of use)
- On **3rd commit attempt** → hard block, require license
- Cannot dismiss the license modal without entering valid code or quitting app

### Why Commit-Based (not Calendar)
- Prevents weird state: active block schedule but expired trial
- Clean cutoff: if you can't commit week 3, your week 2 blocks expire naturally
- User understands: "I used my 2 free weeks"

### State Tracking
```
UserDefaults keys:
- "firstLaunchDate": Date    // When app first launched
- "commitCount": Integer     // Number of successful commits (starts at 0)
```

### Flow
```
User clicks "Commit" button
        │
        ▼
Check commitCount >= 2?
        │
        ├── NO ──► Allow commit, increment commitCount
        │
        └── YES ──► Check valid license in Keychain
                        │
                        ├── Valid ──► Allow commit
                        │
                        └── Invalid/Missing ──► Show license modal (hard block)
```

---

## License Code Format

### Structure
```
FENCE-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

Where X = base64url encoded (payload + signature)
```

### Payload (JSON, minified)
```json
{
  "e": "user@email.com",
  "t": "std",
  "c": 1704067200
}
```

| Field | Description |
|-------|-------------|
| `e` | Customer email (from Stripe) |
| `t` | License type: `"std"` (standard $49) or `"stu"` (student $5) |
| `c` | Created timestamp (Unix seconds) |

### Signature
```
signature = HMAC-SHA256(payload_json_string, SECRET_KEY)
```

### Full Code Construction
```
code = "FENCE-" + base64url(payload_json + "." + signature_hex)
```

### Example
```
Payload: {"e":"test@university.edu","t":"stu","c":1704067200}
Secret:  your-secret-key-here
Result:  FENCE-eyJlIjoidGVzdEB1bml2ZXJzaXR5LmVkdSIsInQiOiJzdHUiLCJjIjoxNzA0MDY3MjAwfS5hYmNkZWYxMjM0NTY...
```

---

## Storage

### Location: macOS Keychain (iCloud-synced)

```objc
// Keychain item attributes
kSecClass:            kSecClassGenericPassword
kSecAttrService:      "app.usefence.license"
kSecAttrAccount:      "license"
kSecAttrSynchronizable: kCFBooleanTrue  // Enables iCloud Keychain sync
kSecValueData:        [license code as UTF-8 data]
```

### Why Keychain
1. Survives app updates (Sparkle)
2. Survives app reinstalls
3. Syncs to user's other Macs via iCloud Keychain
4. Secure storage (encrypted)
5. Standard macOS practice

### iCloud Keychain Sync Behavior
- If user has iCloud Keychain ON: License syncs to all their Macs automatically
- If user has iCloud Keychain OFF: License only on that Mac
- Different Apple ID = different Keychain = code not present

### User Messaging
When license is activated, show:
> "License activated! If you have iCloud Keychain enabled, this license will sync to your other Macs. If not, email support@usefence.app for help activating on another Mac."

---

## App-Side Implementation (Objective-C)

### New Files to Create

#### `Common/SCLicenseManager.h`
```objc
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SCLicenseStatus) {
    SCLicenseStatusTrial,           // Still in trial period
    SCLicenseStatusTrialExpired,    // Trial over, no license
    SCLicenseStatusValid,           // Valid license found
    SCLicenseStatusInvalid          // License present but invalid
};

@interface SCLicenseManager : NSObject

+ (instancetype)sharedManager;

// Trial tracking
- (void)recordCommit;              // Call after successful commit
- (NSInteger)commitCount;          // Number of commits so far
- (BOOL)isTrialExpired;            // commitCount >= 2

// License management
- (SCLicenseStatus)currentStatus;
- (BOOL)validateLicenseCode:(NSString *)code error:(NSError **)error;
- (BOOL)activateLicenseCode:(NSString *)code error:(NSError **)error;
- (NSString *)storedLicenseEmail;  // Returns email from stored license, or nil

// For commit flow
- (BOOL)canCommit;                 // YES if trial valid OR license valid

@end
```

#### `Common/SCLicenseManager.m`
```objc
#import "SCLicenseManager.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>

static NSString * const kFirstLaunchDateKey = @"firstLaunchDate";
static NSString * const kCommitCountKey = @"commitCount";
static NSString * const kKeychainService = @"app.usefence.license";
static NSString * const kKeychainAccount = @"license";

// IMPORTANT: This is the PUBLIC verification key
// The PRIVATE signing key stays on the server only
static NSString * const kLicensePublicKey = @"YOUR_PUBLIC_KEY_HERE";

@implementation SCLicenseManager

+ (instancetype)sharedManager {
    static SCLicenseManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[SCLicenseManager alloc] init];
        [shared ensureFirstLaunchDate];
    });
    return shared;
}

- (void)ensureFirstLaunchDate {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kFirstLaunchDateKey]) {
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kFirstLaunchDateKey];
    }
}

#pragma mark - Trial Tracking

- (NSInteger)commitCount {
    return [[NSUserDefaults standardUserDefaults] integerForKey:kCommitCountKey];
}

- (void)recordCommit {
    NSInteger count = [self commitCount];
    [[NSUserDefaults standardUserDefaults] setInteger:count + 1 forKey:kCommitCountKey];
}

- (BOOL)isTrialExpired {
    return [self commitCount] >= 2;
}

#pragma mark - License Validation

- (BOOL)canCommit {
    if (![self isTrialExpired]) {
        return YES;  // Still in trial
    }
    return [self currentStatus] == SCLicenseStatusValid;
}

- (SCLicenseStatus)currentStatus {
    if (![self isTrialExpired]) {
        return SCLicenseStatusTrial;
    }

    NSString *storedCode = [self retrieveLicenseFromKeychain];
    if (!storedCode) {
        return SCLicenseStatusTrialExpired;
    }

    if ([self validateLicenseCode:storedCode error:nil]) {
        return SCLicenseStatusValid;
    }

    return SCLicenseStatusInvalid;
}

- (BOOL)validateLicenseCode:(NSString *)code error:(NSError **)error {
    // Must start with "FENCE-"
    if (![code hasPrefix:@"FENCE-"]) {
        if (error) *error = [NSError errorWithDomain:@"SCLicense" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid license format"}];
        return NO;
    }

    NSString *encoded = [code substringFromIndex:6];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (!decoded) {
        if (error) *error = [NSError errorWithDomain:@"SCLicense" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid license encoding"}];
        return NO;
    }

    NSString *decodedStr = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    NSArray *parts = [decodedStr componentsSeparatedByString:@"."];
    if (parts.count != 2) {
        if (error) *error = [NSError errorWithDomain:@"SCLicense" code:3
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid license structure"}];
        return NO;
    }

    NSString *payloadStr = parts[0];
    NSString *providedSignature = parts[1];

    // Verify HMAC signature
    NSString *computedSignature = [self hmacSHA256:payloadStr withKey:kLicensePublicKey];

    if (![computedSignature isEqualToString:providedSignature]) {
        if (error) *error = [NSError errorWithDomain:@"SCLicense" code:4
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid license signature"}];
        return NO;
    }

    return YES;
}

- (BOOL)activateLicenseCode:(NSString *)code error:(NSError **)error {
    if (![self validateLicenseCode:code error:error]) {
        return NO;
    }

    return [self storeLicenseInKeychain:code];
}

- (NSString *)storedLicenseEmail {
    NSString *code = [self retrieveLicenseFromKeychain];
    if (!code) return nil;

    // Decode and extract email
    NSString *encoded = [code substringFromIndex:6];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    NSString *decodedStr = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
    NSString *payloadStr = [decodedStr componentsSeparatedByString:@"."][0];

    NSData *payloadData = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil];

    return payload[@"e"];
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
        (__bridge id)kSecAttrSynchronizable: @YES  // iCloud Keychain sync
    };

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

- (NSString *)retrieveLicenseFromKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecAttrSynchronizable: @YES
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

@end
```

#### `UI/SCLicenseWindowController.h`
```objc
#import <Cocoa/Cocoa.h>

@interface SCLicenseWindowController : NSWindowController

@property (nonatomic, copy) void (^onLicenseActivated)(void);
@property (nonatomic, copy) void (^onCancel)(void);

- (void)showAsSheet:(NSWindow *)parentWindow;

@end
```

#### `UI/SCLicenseWindowController.m`
```objc
#import "SCLicenseWindowController.h"
#import "SCLicenseManager.h"

@interface SCLicenseWindowController ()
@property (weak) IBOutlet NSTextField *licenseCodeField;
@property (weak) IBOutlet NSTextField *errorLabel;
@property (weak) IBOutlet NSButton *activateButton;
@property (weak) IBOutlet NSProgressIndicator *spinner;
@end

@implementation SCLicenseWindowController

- (instancetype)init {
    return [super initWithWindowNibName:@"SCLicenseWindowController"];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.errorLabel.stringValue = @"";
}

- (void)showAsSheet:(NSWindow *)parentWindow {
    [parentWindow beginSheet:self.window completionHandler:nil];
}

- (IBAction)activateLicense:(id)sender {
    NSString *code = [self.licenseCodeField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (code.length == 0) {
        self.errorLabel.stringValue = @"Please enter a license code.";
        return;
    }

    self.activateButton.enabled = NO;
    [self.spinner startAnimation:nil];
    self.errorLabel.stringValue = @"";

    NSError *error = nil;
    BOOL success = [[SCLicenseManager sharedManager] activateLicenseCode:code error:&error];

    [self.spinner stopAnimation:nil];
    self.activateButton.enabled = YES;

    if (success) {
        [self.window.sheetParent endSheet:self.window];
        if (self.onLicenseActivated) {
            self.onLicenseActivated();
        }
    } else {
        self.errorLabel.stringValue = error.localizedDescription ?: @"Invalid license code.";
    }
}

- (IBAction)purchaseLicense:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://usefence.app/#pricing"]];
}

- (IBAction)cancel:(id)sender {
    [self.window.sheetParent endSheet:self.window];
    if (self.onCancel) {
        self.onCancel();
    }
}

@end
```

### Files to Modify

#### In `AppController.m` or wherever commit is triggered:

```objc
#import "SCLicenseManager.h"
#import "SCLicenseWindowController.h"

// Before allowing commit:
- (IBAction)commitSchedule:(id)sender {
    if (![[SCLicenseManager sharedManager] canCommit]) {
        // Show license modal
        SCLicenseWindowController *licenseWC = [[SCLicenseWindowController alloc] init];
        licenseWC.onLicenseActivated = ^{
            // License now valid, proceed with commit
            [self performCommit];
            [[SCLicenseManager sharedManager] recordCommit];
        };
        licenseWC.onCancel = ^{
            // User cancelled, do nothing (they can't proceed)
        };
        [licenseWC showAsSheet:self.window];
        return;
    }

    // Trial still valid or license valid
    [self performCommit];
    [[SCLicenseManager sharedManager] recordCommit];
}
```

---

## Server-Side Implementation (Cloudflare Workers)

### Environment Variables Required
```
RESEND_API_KEY=re_xxxx           # Already have this
LICENSE_SECRET_KEY=xxxx          # Generate: openssl rand -hex 32
STRIPE_WEBHOOK_SECRET=whsec_xxx  # From Stripe webhook settings
```

### `web/functions/api/generate-license.js`
```javascript
// Internal function - called by stripe-webhook, not exposed directly

export function generateLicenseCode(email, type, secretKey) {
  const payload = JSON.stringify({
    e: email,
    t: type,  // "std" or "stu"
    c: Math.floor(Date.now() / 1000)
  });

  // Create HMAC signature
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secretKey);
  const payloadData = encoder.encode(payload);

  // Use Web Crypto API
  return crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  ).then(key => {
    return crypto.subtle.sign('HMAC', key, payloadData);
  }).then(signature => {
    const sigHex = Array.from(new Uint8Array(signature))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    const combined = payload + '.' + sigHex;
    const encoded = btoa(combined);

    return 'FENCE-' + encoded;
  });
}
```

### `web/functions/api/stripe-webhook.js`
```javascript
import { generateLicenseCode } from './generate-license.js';

export async function onRequestPost(context) {
  const { request, env } = context;

  // Verify Stripe signature
  const signature = request.headers.get('stripe-signature');
  const body = await request.text();

  // TODO: Verify webhook signature with env.STRIPE_WEBHOOK_SECRET
  // For now, parse the event
  const event = JSON.parse(body);

  if (event.type !== 'checkout.session.completed') {
    return new Response(JSON.stringify({ received: true }), { status: 200 });
  }

  const session = event.data.object;
  const customerEmail = session.customer_details?.email;

  if (!customerEmail) {
    console.error('No customer email in session');
    return new Response(JSON.stringify({ error: 'No email' }), { status: 400 });
  }

  // Determine license type based on amount
  const amount = session.amount_total;  // in cents
  const licenseType = amount <= 500 ? 'stu' : 'std';  // $5 or less = student

  // Generate license
  const licenseCode = await generateLicenseCode(
    customerEmail,
    licenseType,
    env.LICENSE_SECRET_KEY
  );

  // Send email via Resend
  const emailResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Fence <noreply@usefence.app>',
      to: customerEmail,
      subject: 'Your Fence License Key',
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
          <h1 style="font-size: 24px; font-weight: normal; color: #1a1a1a; margin-bottom: 24px;">Thanks for purchasing Fence!</h1>

          <p style="color: #5c5c5c; font-size: 16px; line-height: 1.6; margin-bottom: 24px;">
            Here's your license key. Enter it in the app when prompted:
          </p>

          <div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin-bottom: 24px;">
            <code style="font-size: 14px; word-break: break-all; color: #1a1a1a;">${licenseCode}</code>
          </div>

          <p style="color: #5c5c5c; font-size: 14px; line-height: 1.6;">
            <strong>Note:</strong> If you have iCloud Keychain enabled, this license will automatically sync to your other Macs.
            If not, and you need to activate on another Mac, email support@usefence.app.
          </p>

          <p style="color: #999; font-size: 13px; margin-top: 40px;">
            Questions? Reply to this email or reach out at support@usefence.app
          </p>
        </div>
      `,
    }),
  });

  if (!emailResponse.ok) {
    console.error('Failed to send email:', await emailResponse.text());
  }

  return new Response(JSON.stringify({ received: true }), { status: 200 });
}
```

---

## Stripe Webhook Setup

1. Go to Stripe Dashboard → Developers → Webhooks
2. Add endpoint: `https://usefence.app/api/stripe-webhook`
3. Select event: `checkout.session.completed`
4. Copy the webhook signing secret → add to Cloudflare env as `STRIPE_WEBHOOK_SECRET`

---

## Security Notes

### Secret Key Management
- `LICENSE_SECRET_KEY`: Only on server (Cloudflare env var). Never in app.
- App uses the SAME key for verification (HMAC is symmetric)
- **Important**: The key in the app binary can be extracted. This is acceptable for indie software. Determined pirates will always crack. Focus on honest users.

### What This Prevents
- Casual sharing: Code tied to email, looks sketchy to share
- Random guessing: HMAC signature required
- Trivial cracks: Need to patch binary

### What This Doesn't Prevent
- Determined reverse engineering (acceptable)
- Key extraction from binary (acceptable)
- Someone patching the canCommit check (acceptable)

**Philosophy**: Make it easy to buy, annoying to crack. Don't punish paying customers with complex DRM.

---

## Testing Checklist

- [ ] Fresh install: firstLaunchDate set correctly
- [ ] Commit 1: Works, commitCount = 1
- [ ] Commit 2: Works, commitCount = 2
- [ ] Commit 3: Blocked, license modal appears
- [ ] Invalid code: Error shown, can't dismiss
- [ ] Valid code: Stored in Keychain, commit proceeds
- [ ] App restart: License still valid from Keychain
- [ ] Sparkle update: License persists
- [ ] iCloud Keychain: License syncs to other Mac (manual test)

---

## Files Summary

### Create
```
Common/SCLicenseManager.h
Common/SCLicenseManager.m
UI/SCLicenseWindowController.h
UI/SCLicenseWindowController.m
UI/SCLicenseWindowController.xib
web/functions/api/generate-license.js
web/functions/api/stripe-webhook.js
```

### Modify
```
AppController.m (or wherever commit is triggered)
```

### Environment Variables (Cloudflare)
```
RESEND_API_KEY=[your-resend-api-key]
LICENSE_SECRET_KEY=[generate with: openssl rand -hex 32]
STRIPE_WEBHOOK_SECRET=[from Stripe dashboard]
```

---

*Last updated: December 2024*
