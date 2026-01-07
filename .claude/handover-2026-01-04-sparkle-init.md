# Handover: Sparkle Update System Not Initialized

**Date:** 2026-01-04
**Context:** Sparkle framework included but not working

---

## Summary

Sparkle framework is bundled with the app but **never initialized in code**. Users won't receive automatic updates until this is fixed.

---

## Problem

1. `Sparkle.framework` exists in app bundle at `Contents/Frameworks/`
2. `Info.plist` has correct settings:
   - `SUFeedURL` = `https://usefence.app/appcast.xml`
   - `SUEnableAutomaticChecks` = `true`
3. **BUT** no code initializes `SPUUpdater` or `SPUStandardUpdaterController`
4. No "Check for Updates" menu item exists

---

## Appcast Already Deployed

Version 3.0 appcast is live at `https://usefence.app/appcast.xml`:
- ZIP: `https://usefence.app/updates/Fence-3.0.zip`
- DMG: `https://usefence.app/updates/Fence-3.0.dmg`
- Signature: `cUItZiB67FP9864HRXPU4g61cwTELdcoKwXoJ/SUC/ngQH1Khh2/4RamSIJV8FoV3z/WaShwdR3dLsd1LThaCw==`

---

## Fix Required

### 1. Add Sparkle import to AppController.m

```objc
#import <Sparkle/Sparkle.h>
```

### 2. Add property to AppController interface (in .m or .h)

```objc
@property (nonatomic, strong) SPUStandardUpdaterController *updaterController;
```

### 3. Initialize in applicationDidFinishLaunching:

```objc
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Initialize Sparkle updater
    self.updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                          updaterDelegate:nil
                                                                       userDriverDelegate:nil];

    // ... rest of existing code
}
```

### 4. Add "Check for Updates" to Menu Bar (SCMenuBarController.m)

In `rebuildMenu` method, add after "Show Week Schedule":

```objc
// Check for Updates
NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..."
                                                    action:@selector(checkForUpdates:)
                                             keyEquivalent:@""];
updateItem.target = self;
[self.statusMenu addItem:updateItem];
```

Add the action method:

```objc
- (void)checkForUpdates:(id)sender {
    // Get updater from AppController
    AppController *appController = (AppController *)[NSApp delegate];
    [appController.updaterController checkForUpdates:sender];
}
```

### 5. Expose updaterController in AppController.h

```objc
@class SPUStandardUpdaterController;

@interface AppController : NSObject <NSApplicationDelegate>
@property (nonatomic, strong, readonly) SPUStandardUpdaterController *updaterController;
// ... rest of interface
@end
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `AppController.h` | Add `SPUStandardUpdaterController` property declaration |
| `AppController.m` | Import Sparkle, initialize updater in `applicationDidFinishLaunching:` |
| `SCMenuBarController.m` | Add "Check for Updates" menu item and action |

---

## Testing

1. Build and run new version
2. Check console for Sparkle logs (should see update check)
3. Click "Check for Updates" in menu bar
4. Should show update dialog for v3.0

---

## Version Numbers

- Current deployed app: 1.0.0 (build 500)
- New release: 3.0
- Sparkle compares `sparkle:version` in appcast to `CFBundleVersion` in app

---

## Related Commits This Session

- `cd5a572` - Fix UI staleness after sleep and bundle commit state bugs
- `6106386` - Fix scheduled block transitions failing (ArgumentParser fix)

---

## Build Release Process (for reference)

```bash
# 1. Build release
./scripts/build-release.sh 3.1

# 2. Sign for Sparkle
./Sparkle/bin/sign_update "dist/Fence-3.1.zip"

# 3. Update web/updates/appcast.xml with new version, signature, length

# 4. Copy to fence-web
cp web/updates/appcast.xml ~/fence-web/appcast.xml
cp dist/Fence-3.1.zip ~/fence-web/updates/
cp dist/Fence-3.1.dmg ~/fence-web/updates/

# 5. Deploy
cd ~/fence-web && git add -A && git commit -m "Add Fence 3.1" && git push
```
