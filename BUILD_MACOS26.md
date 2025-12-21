# Building SelfControl on macOS 26 (Tahoe) / Xcode 16+

This document describes the fixes required to build SelfControl on macOS 26 (Tahoe) with Xcode 16.x. These changes address SDK incompatibilities and build system issues.

## Quick Start (Automated)

Run the setup script to apply all fixes automatically:

```bash
cd /path/to/selfcontrol
./scripts/setup_macos26.sh
```

Then build:
```bash
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Debug build
```

---

## Manual Setup

If you prefer to apply fixes manually or need to understand what changed:

### Step 1: Initialize Git Submodules

The `ArgumentParser` directory is a git submodule that must be initialized:

```bash
git submodule update --init --recursive
```

### Step 2: Install CocoaPods Dependencies

```bash
# Install cocoapods if needed
brew install cocoapods

# Install the localization pruning plugin
/opt/homebrew/opt/ruby/bin/gem install cocoapods-prune-localizations

# Install pods
pod install
```

### Step 3: Add Missing Turkish Localization Files

The Turkish localization is missing two strings files that cause build failures:

```bash
# Copy from German as templates
cp de.lproj/PreferencesGeneralViewController.strings tr.lproj/
cp de.lproj/PreferencesAdvancedViewController.strings tr.lproj/
```

### Step 4: Fix CocoaPods Resource Script Path

CocoaPods generates an incorrect path for MASPreferences resources on macOS. Fix it:

```bash
# Fix the resource path (wrong: .framework/en.lproj, correct: .framework/Resources/en.lproj)
sed -i '' 's|MASPreferences.framework/en.lproj|MASPreferences.framework/Resources/en.lproj|g' \
    "Pods/Target Support Files/Pods-SelfControl/Pods-SelfControl-resources.sh"
```

**Note:** This fix is overwritten by `pod install`. The setup script adds it to the Podfile's `post_install` hook for persistence.

### Step 5: Build

```bash
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Debug build
```

---

## What Was Changed (Details)

### 1. Podfile Changes

**File:** `Podfile`

- Updated `minVersion` from `'10.10'` to `'12.0'`
- **Removed Sentry pod** - incompatible C++ code with macOS 26 SDK:
  - `std::set_terminate` / `std::terminate_handler` missing `#include <exception>`
  - `std::vector<const T>` not allowed in profiling code
  - Sentry 8.x requires Swift which breaks static library linking
- Added `post_install` hook to patch TransformerKit imports:
  ```ruby
  # Fixes for TransformerKit @import statements
  @import Darwin.Availability;   → #import <Availability.h>
  @import Darwin.C.time;         → #include <time.h>
  @import Darwin.C.xlocale;      → #include <xlocale.h>
  @import ObjectiveC.runtime;    → #import <objc/runtime.h>
  ```
- Using MacPass fork of TransformerKit: `https://github.com/MacPass/TransformerKit.git`

### 2. Xcode Project Changes

**File:** `SelfControl.xcodeproj/project.pbxproj`

- Updated `MACOSX_DEPLOYMENT_TARGET` from `10.10` to `12.0` in all build configurations
- Modified 3 shell script build phases to prevent PCH race condition (see below)

### 3. Sentry Removal (Conditional Compilation)

**Files:** `Common/SCSentry.m`, `Common/SCSettings.m`

Added conditional compilation to disable Sentry when not available:

```objc
#if !defined(TESTING) && __has_include(<Sentry/Sentry.h>)
#define SENTRY_ENABLED 1
#import <Sentry/Sentry.h>
#else
#define SENTRY_ENABLED 0
#endif

// Then use: #if SENTRY_ENABLED ... #endif
```

### 4. PCH Race Condition Fix

**Problem:** Three targets (SelfControl, selfcontrol-cli, org.eyebeam.selfcontrold) each have a build script that writes to `version-header.h`. When building in parallel, these scripts race and cause precompiled header invalidation errors:

```
error: File 'version-header.h' has been modified since the precompiled header was built
```

**Solution:** Modified each script to only write if content differs:

**Before:**
```bash
echo "#define SELFCONTROL_VERSION_STRING @\"${MARKETING_VERSION}\"" > "${PROJECT_DIR}/version-header.h"
```

**After:**
```bash
# Only write if content differs to avoid PCH invalidation
NEW="#define SELFCONTROL_VERSION_STRING @\"${MARKETING_VERSION}\""
FILE="${PROJECT_DIR}/version-header.h"
if [ ! -f "$FILE" ] || ! grep -qF "$NEW" "$FILE"; then echo "$NEW" > "$FILE"; fi
```

### 5. Missing Turkish Localization

**Problem:** Build fails looking for:
- `tr.lproj/PreferencesGeneralViewController.strings`
- `tr.lproj/PreferencesAdvancedViewController.strings`

**Solution:** Copy from another language (German) as templates.

### 6. MASPreferences Resource Path

**Problem:** CocoaPods generates incorrect resource path for macOS frameworks:
- Wrong: `.framework/en.lproj/MASPreferencesWindow.nib`
- Correct: `.framework/Resources/en.lproj/MASPreferencesWindow.nib`

**Solution:** Patch the generated script or add to Podfile post_install.

---

## Why Sentry Was Removed

Sentry SDK versions 7.x and 8.x have C++ code incompatible with macOS 26's stricter libc++:

1. **Missing includes:** `std::set_terminate` and `std::terminate_handler` require `#include <exception>` which Sentry doesn't include
2. **Invalid template:** `std::vector<const T>` is not allowed (const elements can't be moved/copied properly)
3. **Swift requirement:** Sentry 8.x requires Swift runtime, which breaks static library linking for CLI tools

The app builds and runs without crash reporting. To re-enable Sentry, wait for a version compatible with macOS 26 SDK.

---

## Troubleshooting

### "Resource not found" error for MASPreferences
Run the setup script again or manually fix the resource path (Step 4).

### PCH invalidation errors
Clear DerivedData and rebuild:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/SelfControl-*
xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl clean build
```

### "Podfile.lock out of sync"
```bash
pod install
./scripts/setup_macos26.sh  # Re-apply fixes
```

### ArgumentParser files not found
```bash
git submodule update --init --recursive
```

---

## Files Modified Summary

| File | Change |
|------|--------|
| `Podfile` | minVersion 12.0, removed Sentry, TransformerKit patches |
| `SelfControl.xcodeproj/project.pbxproj` | Deployment target 12.0, PCH-safe version scripts |
| `Common/SCSentry.m` | Conditional Sentry compilation |
| `Common/SCSettings.m` | Conditional Sentry compilation |
| `tr.lproj/PreferencesGeneralViewController.strings` | Added (copied from de.lproj) |
| `tr.lproj/PreferencesAdvancedViewController.strings` | Added (copied from de.lproj) |
