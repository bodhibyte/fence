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

## Step 6: Build and Run

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
