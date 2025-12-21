#!/bin/bash
#
# SelfControl macOS 26 (Tahoe) Build Setup Script
#
# This script applies all necessary fixes to build SelfControl on macOS 26
# with Xcode 16.x. Run this after cloning the repository.
#
# Usage: ./scripts/setup_macos26.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=== SelfControl macOS 26 Build Setup ==="
echo ""

# Step 1: Initialize git submodules
echo "[1/5] Initializing git submodules..."
if [ ! -f "ArgumentParser/ArgumentParser/XPMArgumentSignature.m" ]; then
    git submodule update --init --recursive
    echo "      Submodules initialized."
else
    echo "      Submodules already initialized."
fi

# Step 2: Check for CocoaPods
echo "[2/5] Checking CocoaPods..."
if ! command -v pod &> /dev/null; then
    echo "      CocoaPods not found. Install with: brew install cocoapods"
    exit 1
fi

# Check for localization plugin
if ! pod plugins installed 2>/dev/null | grep -q "cocoapods-prune-localizations"; then
    echo "      Installing cocoapods-prune-localizations plugin..."
    /opt/homebrew/opt/ruby/bin/gem install cocoapods-prune-localizations 2>/dev/null || \
        gem install cocoapods-prune-localizations
fi
echo "      CocoaPods ready."

# Step 3: Add missing Turkish localization files
echo "[3/5] Fixing Turkish localization..."
if [ ! -f "tr.lproj/PreferencesGeneralViewController.strings" ]; then
    cp de.lproj/PreferencesGeneralViewController.strings tr.lproj/
    echo "      Added PreferencesGeneralViewController.strings"
fi
if [ ! -f "tr.lproj/PreferencesAdvancedViewController.strings" ]; then
    cp de.lproj/PreferencesAdvancedViewController.strings tr.lproj/
    echo "      Added PreferencesAdvancedViewController.strings"
fi
echo "      Turkish localization complete."

# Step 4: Run pod install
echo "[4/5] Installing CocoaPods dependencies..."
pod install --silent
echo "      Pods installed."

# Step 5: Fix MASPreferences resource path in pods script
echo "[5/5] Fixing CocoaPods resource paths..."
RESOURCE_SCRIPT="Pods/Target Support Files/Pods-SelfControl/Pods-SelfControl-resources.sh"
if [ -f "$RESOURCE_SCRIPT" ]; then
    # Fix the incorrect framework resource path
    sed -i '' 's|MASPreferences.framework/en.lproj|MASPreferences.framework/Resources/en.lproj|g' "$RESOURCE_SCRIPT"
    echo "      Resource paths fixed."
else
    echo "      Warning: Resource script not found. Run 'pod install' first."
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To build SelfControl:"
echo ""
echo "  xcodebuild -workspace SelfControl.xcworkspace -scheme SelfControl -configuration Debug build"
echo ""
echo "Or open in Xcode:"
echo ""
echo "  open SelfControl.xcworkspace"
echo ""
echo "Note: If you run 'pod install' again, re-run this script to reapply fixes."
