# SelfControl Development Setup

## Prerequisites

- macOS (modern version)
- Xcode with command-line tools
- Homebrew

## Step 1: Install CocoaPods

```bash
brew install cocoapods
```

## Step 2: Install the Localization Plugin

The Podfile requires `cocoapods-prune-localizations`. This must be installed to the **same Ruby** that CocoaPods uses.

First, find where Homebrew's Ruby gem is:
```bash
# CocoaPods uses Homebrew's keg-only Ruby
/opt/homebrew/opt/ruby/bin/gem install cocoapods-prune-localizations
```

### Troubleshooting: Ruby Version Mismatch

If you upgraded Ruby via Homebrew and get errors like:
```
Could not find 'ffi' (>= 1.15.0) among X total gem(s)
```

Reinstall CocoaPods to rebuild gems against the new Ruby:
```bash
brew reinstall cocoapods
```

Then reinstall the plugin:
```bash
/opt/homebrew/opt/ruby/bin/gem install cocoapods-prune-localizations
```

## Step 3: Install Dependencies

```bash
cd /path/to/selfcontrol
pod install
```

This creates:
- `selfcontrol.xcworkspace` - **use this to open the project**
- `Pods/` directory with dependencies

## Step 4: Open in Xcode

```bash
open selfcontrol.xcworkspace
```

**Important:** Open `.xcworkspace`, NOT `.xcodeproj`

## Step 5: Code Signing

You'll likely hit code signing errors on first build. For each target:

1. Select the target in Xcode
2. Go to **Signing & Capabilities** tab
3. Select your personal Apple Developer team (free tier works)

Targets that need signing:
- SelfControl
- selfcontrold (daemon)
- selfcontrol-cli
- SelfControl Killer
- SCKillerHelper

## Step 6: Update Code Signing Requirements (CRITICAL)

If you're building with your own Apple Developer certificate, you **must** update the code signing requirements in several files. The app uses SMJobBless to install a privileged helper, which requires the signing certificates to match specific requirements.

### Find Your Team ID

Your Team ID is visible in Xcode under Signing & Capabilities, or run:
```bash
security find-identity -v -p codesigning | grep "Apple Development"
```
The Team ID is the 10-character string in parentheses (e.g., `L5YX8CH3F5`).

### Files to Update

Replace the original Team ID (`EG6ZYP3AQH`) with your Team ID in these files:

#### 1. `Info.plist` - SMPrivilegedExecutables (line ~61)
#### 2. `Daemon/selfcontrold-Info.plist` - SMAuthorizedClients (line ~55)
#### 3. `selfcontrol-cli-Info.plist` - SMPrivilegedExecutables (line ~56)
#### 4. `Daemon/SCDaemon.m` - Runtime validation (line ~162)
#### 5. `SelfControl.xcodeproj/project.pbxproj` - DEVELOPMENT_TEAM entries

**Quick find-and-replace:**
```bash
# Replace Team ID in all files (change YOUR_TEAM_ID to your actual Team ID)
find . -name "*.plist" -o -name "*.m" -o -name "project.pbxproj" | \
  xargs sed -i '' 's/EG6ZYP3AQH/YOUR_TEAM_ID/g'
```

### Add Apple Development Certificate Support

The default code signing requirements only allow Mac App Store or Developer ID certificates. For local development with "Apple Development" certificates, you need to add the Apple Development OID (`1.2.840.113635.100.6.1.12`).

In the same 4 files above, update the certificate requirements from:
```
certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
```

To:
```
certificate leaf[field.1.2.840.113635.100.6.1.9] /* exists */ or certificate leaf[field.1.2.840.113635.100.6.1.12] /* exists */ or certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */
```

**Certificate OIDs explained:**
- `1.2.840.113635.100.6.1.9` = Mac App Store
- `1.2.840.113635.100.6.1.12` = Apple Development (for local builds)
- `1.2.840.113635.100.6.1.13` = Developer ID Application

### Remove Old Helper (if previously installed)

If you've run SelfControl before with a different signing, remove the old helper:
```bash
sudo rm -f /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold
sudo rm -f /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist
```

Then do a clean build in Xcode (⇧⌘K).

## Step 7: Build and Run

1. Select **SelfControl** scheme (top left)
2. Press **Cmd+B** to build
3. Press **Cmd+R** to run

## Safe Testing Tips

- **Always test with short blocks** (1-2 minutes)
- **Block harmless sites** like `example.com`
- **Build SelfControl Killer too** - it's your emergency escape
- **Keep admin password handy** - needed to remove stuck blocks

## What Gets Installed When You Start a Block

| Component | Location |
|-----------|----------|
| Daemon binary | `/Library/PrivilegedHelperTools/org.eyebeam.selfcontrold` |
| Daemon config | `/Library/LaunchDaemons/org.eyebeam.selfcontrold.plist` |
| Settings | `/usr/local/etc/.{hash}.plist` |
| Firewall rules | `/etc/pf.anchors/org.eyebeam` |
| Hosts entries | `/etc/hosts` (between SELFCONTROL markers) |

## Uninstalling (Clean Slate)

```bash
# Remove the app
sudo rm -rf /Applications/SelfControl.app

# Stop and remove the daemon
sudo launchctl unload /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist 2>/dev/null
sudo rm -f /Library/LaunchDaemons/org.eyebeam.selfcontrold.plist
sudo rm -f /Library/PrivilegedHelperTools/org.eyebeam.selfcontrold

# Clear any existing blocks
sudo rm -f /etc/SelfControl* /etc/pf.anchors/org.eyebeam

# Remove settings (filename is SHA1 hashed)
sudo rm -f /usr/local/etc/.*.plist

# Flush DNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## Removing Licensing Logic (For Forks)

If you're forking this project and want to remove the licensing/trial system entirely, follow these steps:

### Option 1: Always Return Licensed (Simplest)

Edit `Common/SCLicenseManager.m` and modify two methods:

```objc
// Around line 162
- (BOOL)canCommit {
    return YES;  // Always allow commits
}

// Around line 169
- (SCLicenseStatus)currentStatus {
    return SCLicenseStatusValid;  // Always report as licensed
}
```

This leaves all the licensing code in place but makes it a no-op.

### Option 2: Full Removal (Clean)

#### Files to Delete
```bash
rm Common/SCLicenseManager.h
rm Common/SCLicenseManager.m
rm Common/SCDeviceIdentifier.h
rm Common/SCDeviceIdentifier.m
rm SCLicenseWindowController.h
rm SCLicenseWindowController.m
rm docs/LICENSING_CURRENT.md
rm generate-test-license.js
rm Secrets.xcconfig  # If it exists
```

#### Files to Modify

**1. `AppController.m`**
- Remove `#import "Common/SCLicenseManager.h"`
- Remove `syncTrialStatusWithCompletion:` call (~line 463-466)
- Remove `attemptLicenseRecoveryWithCompletion:` call (~line 468-475)
- Remove license check before commit (~line 134-143)
- Remove `showLicenseModalWithCompletion:` method

**2. `SCMenuBarController.m`**
- Remove `#import "Common/SCLicenseManager.h"`
- Remove trial status display in menu (~lines 185-208)
- Remove "Enter License" menu item (~lines 230-238)
- Remove debug menu items for trial reset/expire
- Remove `enterLicenseClicked:` and `showLicenseWindowWithParent:` methods

**3. `SCWeekScheduleWindowController.m`**
- Remove `#import "Common/SCLicenseManager.h"`
- Remove `canCommit` check before commit (~line 687-697)
- Remove `showLicenseModalWithCompletion:` method

**4. `SelfControl.xcodeproj/project.pbxproj`**
- Remove references to deleted files (or just remove from Xcode UI)

### Server Components (If Removing Online Licensing)

The licensing server is separate from the main app. If you don't need it:

```bash
rm -rf server/  # Railway API server code
```

The server endpoints (not needed if licensing removed):
- `POST /api/trial/check` - Trial sync
- `POST /api/activate` - License activation
- `GET /api/recover` - License recovery

### Licensing Documentation

Current licensing implementation is documented in:
- `docs/LICENSING_CURRENT.md` - Full flow diagrams and code references

### Build Settings

If using Option 1, you may still need a `Secrets.xcconfig` with a placeholder:
```
LICENSE_SECRET_KEY = placeholder_not_used
```

Or add to your build settings directly in Xcode.
