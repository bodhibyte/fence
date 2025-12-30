# Licensing System - Handover for Next Agent

> **Last updated:** December 30, 2024
> **Status:** Ready for online licensing implementation

---

## Next Major Task: Online License Activation

**Full plan available at:** `~/.claude/plans/tender-crunching-crystal.md`

### Goals
1. **Device-limited licenses** - Each key activates on max 3 devices
2. **Server-side trial tracking** - Prevent trial reset by reinstalling
3. **Offline fallback** - App still works without internet

### Infrastructure Needed
- Railway or Cloudflare Workers for API
- PostgreSQL or Cloudflare D1 for database
- New endpoints: `/api/activate`, `/api/trial/register`, `/api/trial/status`

### Key Changes Required
- New `SCDeviceIdentifier.h/m` for hardware UUID
- Modify `SCLicenseManager.m` for online activation
- Update `SCLicenseWindowController.m` for device limit UI
- New server endpoints for activation + trial tracking

---

## Previous Issue (Resolved)

**License keys were not being accepted.** Debug logging was added to diagnose.

### Debug Logging Added
Just added debug logging to `SCLicenseManager.m` in `validateLicenseCode:` method:
- Line ~174: Logs when validation starts
- Line ~263-265: Logs provided signature, computed signature, and first 8 chars of secret key
- Line ~268: Logs signature mismatch
- Line ~277: Logs success

**To diagnose:** Rebuild, try to activate a key, then check logs at `~/.fence/logs/` for `[SCLicenseManager]` entries.

### Likely Root Cause
The secret key may not be loading correctly from build settings. Check:
1. `Secrets.xcconfig` exists and contains `LICENSE_SECRET_KEY = <hex string>`
2. Xcode project references `Secrets.xcconfig` in build settings
3. The `STRINGIFY_VALUE(LICENSE_SECRET_KEY)` macro at line ~259 is producing the actual key, not the literal string "PLACEHOLDER_KEY_FOR_DEVELOPMENT"

### Generate Test Key
```bash
node generate-test-license.js
```
This reads the key from `Secrets.xcconfig` and generates a valid FENCE- license.

---

## What Was Just Completed

### Date-Based Trial System (commit `a73c470`)
Replaced commit-based trial (2 commits) with date-based trial:
- Trial expires on **3rd Sunday from install** (~2.5 weeks guaranteed)
- Menu shows "Free Trial (X days left)"
- Emergency unblock no longer affects trial

**Key files changed:**
- `SCLicenseManager.m` - New methods: `calculateTrialExpiryDate`, `trialExpiryDate`, `trialDaysRemaining`
- `SCLicenseManager.h` - Updated interface
- `SCMenuBarController.m` - Updated display
- Removed `recordCommit` calls from `SCWeekScheduleWindowController.m` and `AppController.m`

### Previous Fixes (commit `8b42f36`)
- Fixed Keychain save (added entitlements)
- Consolidated menu to single "Purchase License" item
- Made modal text generic
- Fixed text field to single-line with horizontal scroll
- Added debug menu options: "Reset to Fresh Trial" / "Expire Trial"

---

## Key Files for Licensing

| File | Purpose |
|------|---------|
| `Common/SCLicenseManager.h` | License manager interface |
| `Common/SCLicenseManager.m` | Trial tracking, validation, Keychain storage |
| `SCLicenseWindowController.m` | License activation modal UI |
| `SCMenuBarController.m` | Menu bar trial status display |
| `Secrets.xcconfig` | Contains `LICENSE_SECRET_KEY` (git-ignored) |
| `generate-test-license.js` | Script to generate test license keys |
| `web/functions/api/generate-license.js` | Server-side license generation |
| `web/functions/api/stripe-webhook.js` | Stripe payment → email license |

---

## License Format

```
FENCE-{base64(payload.signature)}

Payload: {"e":"email","t":"std|stu","c":timestamp}
Signature: HMAC-SHA256(payload, SECRET_KEY) as hex
```

---

## Remaining Tasks

1. **Implement online licensing** (see plan at `~/.claude/plans/tender-crunching-crystal.md`)
   - Phase 1: Server setup (Railway/Cloudflare)
   - Phase 2: Client device ID + trial sync
   - Phase 3: Online activation flow
   - Phase 4: Device management UI
2. Deploy server-side functions to Cloudflare Pages
3. Configure Stripe webhook
4. Set environment variables on Cloudflare:
   - `LICENSE_SECRET_KEY`
   - `STRIPE_WEBHOOK_SECRET`
   - `RESEND_API_KEY`

---

## Debug Commands

```bash
# Reset trial to fresh state
defaults delete org.eyebeam.Fence FenceTrialExpiryDate

# Check trial expiry date
defaults read org.eyebeam.Fence FenceTrialExpiryDate

# Delete license from keychain
security delete-generic-password -s "app.usefence.license" -a "license"

# View license in keychain
security find-generic-password -s "app.usefence.license" -a "license" -w

# Generate test license
node generate-test-license.js

# Check recent logs
ls -t ~/.fence/logs/ | head -1 | xargs -I {} grep "SCLicenseManager" ~/.fence/logs/{}
```

---

## Architecture Docs

- `SYSTEM_ARCHITECTURE.md` - Full system architecture
- `docs/BLOCKING_MECHANISM.md` - How blocking works
- `docs/LICENSING_SPEC.md` - Original licensing specification
