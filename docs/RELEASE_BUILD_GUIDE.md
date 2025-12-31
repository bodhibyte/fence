# Release Build Guide

This document describes how to build, sign, notarize, and distribute Fence.app (formerly SelfControl).

## Prerequisites

1. **Xcode** installed with command-line tools
2. **Developer ID Application certificate** from Apple Developer portal
3. **App-specific password** for notarization (from appleid.apple.com)
4. **CocoaPods** installed (`gem install cocoapods`)
5. **create-dmg** installed (`brew install create-dmg`)

## One-Time Setup

### 1. Install Dependencies

```bash
pod install
```

### 2. Store Notarization Credentials

Generate an app-specific password at https://appleid.apple.com → Sign-In & Security → App-Specific Passwords.

Then store it in your keychain:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

## Building a Release

```bash
./scripts/build-release.sh 1.0
```

This script:
1. Builds the Release configuration using the workspace
2. Signs all nested components with Developer ID + hardened runtime
3. Creates a ZIP and submits for notarization
4. Staples the notarization ticket
5. Creates and notarizes a DMG
6. Outputs both DMG and ZIP to `dist/`

## Hurdles We Overcame

### Issue 1: Empty MacOS Folder in Release Build

**Symptom:** Release build created an app bundle with empty `Contents/MacOS/` folder.

**Root Cause:** The build was using `-project SelfControl.xcodeproj` instead of `-workspace SelfControl.xcworkspace`. With CocoaPods, you MUST use the workspace so that pod dependencies are built first.

**Fix:** Changed build command to:
```bash
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl ...
```

### Issue 2: Linker Error - library 'Pods-SCKillerHelper' not found

**Symptom:** `ld: library 'Pods-SCKillerHelper' not found`

**Root Cause:** Same as above - using project instead of workspace meant pod targets weren't being built.

**Fix:** Use `-workspace` instead of `-project`.

### Issue 3: Notarization Credential Error (HTTP 401)

**Symptom:** `HTTP status code: 401. Invalid credentials.`

**Root Cause:** The keychain item `AC_PASSWORD` didn't exist, and we were using the old credential syntax.

**Fix:**
1. Generate app-specific password from appleid.apple.com
2. Store using `xcrun notarytool store-credentials "AC_PASSWORD" ...`
3. Use `--keychain-profile "AC_PASSWORD"` (not `--password "@keychain:..."`)

### Issue 4: Notarization Rejected - Invalid Signatures

**Symptom:** Notarization status "Invalid" with errors about nested binaries not signed with Developer ID.

**Root Cause:** `codesign --deep` doesn't properly sign nested frameworks/helpers for notarization. Each binary needs:
- Developer ID signature (not development certificate)
- Hardened runtime (`--options runtime`)
- Secure timestamp (`--timestamp`)
- No `com.apple.security.get-task-allow` entitlement

**Affected Components:**
- `Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop`
- `Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate`
- `Contents/Library/LaunchServices/org.eyebeam.selfcontrold`

**Fix:** Sign each component individually, from deepest to outermost:
```bash
# Sign Sparkle internals
codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app"

# Sign Sparkle framework
codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework"

# Sign daemon
codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp \
    "$APP_PATH/Contents/Library/LaunchServices/org.eyebeam.selfcontrold"

# Sign main app last
codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$APP_PATH"
```

## Sparkle Updates

After building, generate the Sparkle signature for your appcast:

```bash
./Sparkle/bin/sign_update "dist/Fence-1.0.zip"
```

## Troubleshooting

### Check Notarization Log

If notarization fails, get the detailed log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"
```

### Verify Signatures

```bash
codesign --verify --deep --strict --verbose=2 Fence.app
```

### Check Entitlements

```bash
codesign -d --entitlements - Fence.app
```
