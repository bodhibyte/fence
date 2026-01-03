# Handover Document: Code Signing & License Storage Issues

## Current Issue

When using Xcode's "Direct Distribution" (Product → Archive → Distribute App → Direct Distribution), the codesign fails with:

```
codesign command failed:
.../Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop: replacing existing signature
.../Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop: A timestamp was expected but was not found.
```

**The Sparkle framework's `fileop` binary is missing a timestamp in its signature**, which causes Xcode's distribution pipeline to fail.

## Background Context

### What Was Fixed in Previous Session

1. **EPOLICY Error (163)** - The app wouldn't launch with `open` command after building with `build-release.sh`. Error: "Launchd job spawn failed"

2. **Root Cause**: Adding `--entitlements` flag to codesign with Developer ID signing caused EPOLICY because:
   - Entitlements need authorization via provisioning profile
   - Developer ID distribution doesn't typically embed provisioning profiles
   - The `keychain-access-groups` entitlement wasn't available for Developer ID

3. **Solution Implemented**: Switched license storage from Keychain to iCloud Key-Value Storage (`NSUbiquitousKeyValueStore`):
   - No entitlements needed
   - Syncs across Macs via iCloud
   - Local `NSUserDefaults` backup for offline fallback

### Recent Commit to Understand

**Commit `4631da0`**: "Switch license storage from Keychain to iCloud key-value storage"

Changes:
- `Common/SCLicenseManager.m`: Replaced `SecItemAdd`/`SecItemCopyMatching` with `NSUbiquitousKeyValueStore`
- `scripts/build-release.sh`: Removed `--entitlements` flag

## Key Files

| File | Purpose |
|------|---------|
| `scripts/build-release.sh` | Release build script - signs all components with Developer ID |
| `Common/SCLicenseManager.m` | License storage/retrieval using iCloud key-value storage |
| `SelfControl.entitlements` | Entitlements file (currently has keychain-access-groups, but not used) |
| `Podfile` | Contains Sparkle dependency |

## The Current Sparkle Timestamp Issue

The Sparkle framework (used for auto-updates) contains pre-signed binaries. When Xcode tries to re-sign for distribution:

1. It finds `fileop` binary inside `Autoupdate.app`
2. The existing signature lacks a timestamp
3. Xcode's codesign expects a timestamp and fails

### Potential Solutions to Investigate

1. **Update Sparkle** - Newer versions may have properly timestamped signatures
   ```bash
   pod update Sparkle
   ```

2. **Re-sign Sparkle manually** before archive - The `build-release.sh` already does this:
   ```bash
   codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$binary"
   ```

3. **Use pre-built Sparkle XCFramework** instead of CocoaPods version

4. **Check Sparkle version**:
   ```bash
   grep -A2 "Sparkle" Podfile.lock
   ```

## Debug Strategy

### First Place to Add Debug Logs

The issue is at the Xcode/codesign level, not in app code. To debug:

1. **Check current Sparkle signing**:
   ```bash
   codesign -dvvv /path/to/Fence.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop
   ```
   Look for "Timestamp=" line - if missing, that's the problem.

2. **Check build-release.sh signing** - It should add timestamps with `--timestamp` flag

3. **Compare working vs failing**:
   - `build-release.sh` works (manual re-signing with timestamps)
   - Xcode Direct Distribution fails (expects timestamps already present)

### Why build-release.sh Works

The script forcefully re-signs ALL binaries including Sparkle internals with `--timestamp`:
```bash
codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$binary"
```

Xcode's distribution expects binaries to already have valid timestamps and may not re-sign everything the same way.

## Working Build Command

```bash
./scripts/build-release.sh 2.4
```

This produces a working, notarized DMG at `dist/Fence-2.4.dmg`.

## iCloud Capability Required

The app needs iCloud "Key-value storage" capability enabled in Xcode:
- Signing & Capabilities → + Capability → iCloud → Key-value storage ✓

## Quick Test Commands

```bash
# Build release
./scripts/build-release.sh 2.4

# Test launch
open /Applications/Fence.app

# Check signature
codesign -dvvv /Applications/Fence.app

# Check Sparkle signature
codesign -dvvv "/Applications/Fence.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
```

## Summary

- **License storage**: Fixed - now uses iCloud key-value storage
- **build-release.sh**: Works - manually signs everything with timestamps
- **Xcode Direct Distribution**: Fails on Sparkle timestamp - needs investigation
- **Recommendation**: Either fix Sparkle signing or continue using `build-release.sh`
