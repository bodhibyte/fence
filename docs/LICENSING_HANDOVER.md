# Licensing System - WIP Handover

> **Status:** Work in progress. Core implementation done, some bugs remain.

---

## What Was Implemented

### New Files Created

| File | Purpose |
|------|---------|
| `Common/SCLicenseManager.h` | License manager singleton header |
| `Common/SCLicenseManager.m` | Trial tracking (UserDefaults), Keychain storage, HMAC-SHA256 validation |
| `SCLicenseWindowController.h` | License activation modal header |
| `SCLicenseWindowController.m` | Programmatic UI for license entry (no XIB) |
| `web/functions/api/generate-license.js` | Server-side license code generation |
| `web/functions/api/stripe-webhook.js` | Stripe webhook handler → emails license |
| `Secrets.xcconfig` | Contains `LICENSE_SECRET_KEY` (git-ignored) |
| `docs/LICENSING_SPEC.md` | Original specification document |

### Files Modified

| File | Changes |
|------|---------|
| `SCWeekScheduleWindowController.m` | Added license check BEFORE commit confirmation dialog (lines 489-511), added `showLicenseModalWithCompletion:` helper |
| `AppController.m` | Added license check before `installBlock` (lines 129-158), added `showLicenseModalWithCompletion:` helper |
| `SCMenuBarController.m` | Added trial status display, "Purchase License...", "Enter License Key..." menu items |
| `.gitignore` | Added `Secrets.xcconfig` |

---

## How It Works

### Trial Logic
- User gets **2 free commits** (stored in `UserDefaults` key `FenceCommitCount`)
- On **3rd commit attempt** → license modal appears
- `SCLicenseManager.canCommit` returns `YES` if trial valid OR license valid

### License Code Format
```
FENCE-{base64(payload.signature)}

Payload: {"e":"email","t":"std|stu","c":timestamp}
Signature: HMAC-SHA256(payload, SECRET_KEY) as hex
```

### Storage
- **Trial count:** `UserDefaults` → `FenceCommitCount` (domain: `org.eyebeam.Fence`)
- **License code:** Keychain → service `app.usefence.license`, account `license`, iCloud-synced

### Secret Key
- Stored in `Secrets.xcconfig` (git-ignored, not in repo)
- Generate with: `openssl rand -hex 32`
- Accessed via preprocessor macro `LICENSE_SECRET_KEY`
- Same key must be in app (Secrets.xcconfig) and server (Cloudflare env var)

---

## What's Working

✅ Trial counting logic (`commitCount`, `isTrialExpired`)
✅ License modal appears when trial expired and user clicks "Commit to Week"
✅ Menu bar shows "Trial Expired" in red when `FenceCommitCount >= 2`
✅ Menu bar shows "Free Trial (X commits left)" when in trial
✅ "Purchase License..." and "Enter License Key..." menu items
✅ License validation (HMAC-SHA256 signature check)
✅ Debug logging in `SCLicenseManager` for troubleshooting

---

## What's Broken / Needs Fixing

### 1. Keychain Save Failing
**Symptom:** "Failed to save license. Please try again." error
**Location:** `SCLicenseManager.m` → `storeLicenseInKeychain:` (line ~301)
**Debug:** Add `NSLog` for `OSStatus` return value from `SecItemAdd`
**Possible causes:**
- Keychain entitlements missing
- iCloud Keychain sync issue
- App sandbox restrictions

### 2. Menu Bar UX Simplification Needed
**Current:** Shows both "Purchase License..." and "Enter License Key..."
**Wanted:** Just "Purchase License..." that opens the license modal
**Location:** `SCMenuBarController.m` → `rebuildMenu` (lines ~186-199)
**Fix:** Remove "Enter License Key..." item, make "Purchase License..." call `enterLicenseClicked:` instead of opening URL

### 3. License Modal Text Too Specific
**Current:** "Your free trial has ended. Enter your license key to continue using Fence."
**Wanted:** Generic text like "To use Fence forever, purchase a license."
**Location:** `SCLicenseWindowController.m` → `setupUI` (line ~58)

### 4. Text Field Placeholder Formatting
**Symptom:** "FENCE-XXXXXXXXXXXX..." looks weird in the text field
**Location:** `SCLicenseWindowController.m` → `setupUI` (line ~73)
**Fix:** Change placeholder or use regular system font

---

## How to Test

### Set Trial State
```bash
# Set to expired (0 commits left)
defaults write org.eyebeam.Fence FenceCommitCount -int 2

# Set to fresh trial (2 commits left)
defaults write org.eyebeam.Fence FenceCommitCount -int 0

# Check current value
defaults read org.eyebeam.Fence FenceCommitCount
```

### Clear License from Keychain
```bash
security delete-generic-password -s "app.usefence.license" -a "license"
```

### Generate Test License Key
Use the server-side function or create a local script with your secret key:
```bash
# See web/functions/api/generate-license.js for the algorithm
# You'll need your SECRET_KEY from Secrets.xcconfig
```

---

## Key Code Locations

### License Check Flow (Week Schedule)
```
SCWeekScheduleWindowController.m:489 → commitClicked:
  └── SCLicenseManager.m:109 → canCommit
      └── SCLicenseManager.m:100 → isTrialExpired
      └── SCLicenseManager.m:116 → currentStatus
```

### License Modal Display
```
SCWeekScheduleWindowController.m:546 → showLicenseModalWithCompletion:
  └── SCLicenseWindowController.m:26 → init
  └── SCLicenseWindowController.m:136 → beginSheetModalForWindow:
```

### License Activation
```
SCLicenseWindowController.m:152 → activateClicked:
  └── SCLicenseManager.m:213 → activateLicenseCode:error:
      └── SCLicenseManager.m:139 → validateLicenseCode:error:
      └── SCLicenseManager.m:301 → storeLicenseInKeychain: ← FAILING
```

### Menu Bar Trial Status
```
SCMenuBarController.m:155 → rebuildMenu (license status section)
```

---

## Server-Side (Not Yet Deployed)

### Cloudflare Environment Variables Needed
```
LICENSE_SECRET_KEY=[same key as in Secrets.xcconfig]
STRIPE_WEBHOOK_SECRET=[from Stripe dashboard]
RESEND_API_KEY=[existing]
```

### Stripe Webhook Setup
1. Stripe Dashboard → Developers → Webhooks
2. Add endpoint: `https://usefence.app/api/stripe-webhook`
3. Select event: `checkout.session.completed`

---

## Debug Logs

Logs are in `SCLicenseManager.m`. Look for `[SCLicenseManager]` prefix:
```
[SCLicenseManager] commitCount = X (key: FenceCommitCount)
[SCLicenseManager] isTrialExpired = YES/NO
[SCLicenseManager] currentStatus = SCLicenseStatusTrial/TrialExpired/Valid/Invalid
```

To view: Use Xcode console or `Report Bug` → check `~/.fence/logs/`

---

*Last updated: December 30, 2024*
