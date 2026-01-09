# SuperDimmer DMG Packaging

This folder contains scripts and resources for packaging SuperDimmer into a distributable DMG installer.

## 📦 Quick Start

```bash
# 1. Build the app first
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App
xcodebuild -scheme SuperDimmer -configuration Release build CONFIGURATION_BUILD_DIR=./build/Release

# 2. Create the DMG
cd packaging
chmod +x create-dmg.sh
./create-dmg.sh ../build/Release/SuperDimmer.app

# 3. Find your DMG in packaging/output/
open output/
```

## 📁 Folder Structure

```
packaging/
├── create-dmg.sh       # Main DMG creation script
├── background.png      # DMG window background (optional)
├── README.md           # This file
├── output/             # Generated DMGs go here (git-ignored)
└── resources/          # Additional resources (icons, etc.)
```

## 🛠 Prerequisites

### Required
- macOS 13.0 or later
- Xcode Command Line Tools
- Built SuperDimmer.app

### Optional (for prettier DMGs)
```bash
# Install create-dmg tool for professional-looking DMGs
brew install create-dmg
```

## 📋 Usage

### Basic Usage

```bash
# Create DMG from default build location
./create-dmg.sh

# Create DMG from specific app path
./create-dmg.sh /path/to/SuperDimmer.app
```

### With Code Signing & Notarization

For distribution outside the Mac App Store, you need to sign and notarize the app:

```bash
# 1. First, sign the app with Developer ID
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    /path/to/SuperDimmer.app

# 2. Create the DMG
./create-dmg.sh /path/to/SuperDimmer.app

# 3. Sign the DMG
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
    output/SuperDimmer-vX.X.X.dmg

# 4. Notarize (requires credentials)
export APPLE_ID="your@email.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com
export APPLE_TEAM_ID="XXXXXXXXXX"

NOTARIZE=true ./create-dmg.sh /path/to/SuperDimmer.app
```

## 🎨 Customizing the DMG Appearance

### Background Image

The DMG uses a custom background image for professional appearance. To customize:

1. Create a PNG image at 660x400 pixels
2. Save as `packaging/background.png`
3. Design tips:
   - Use a subtle gradient or pattern
   - Add your app logo
   - Include a visual arrow pointing from app to Applications folder
   - Keep it dark/neutral to match the app aesthetic

### Icon Positions

Edit `create-dmg.sh` to adjust icon positions:

```bash
APP_ICON_X=180      # X position of app icon
APP_ICON_Y=170      # Y position of app icon  
APPS_ICON_X=480     # X position of Applications alias
APPS_ICON_Y=170     # Y position of Applications alias
```

## 🔐 Code Signing Notes

### Why Sign?
- Prevents Gatekeeper warnings ("unidentified developer")
- Required for notarization
- Shows users the app is from a verified developer

### Signing Requirements
1. **Apple Developer Account** ($99/year)
2. **Developer ID Application certificate**
3. **Hardened Runtime** enabled in Xcode

### Checking Signature
```bash
# Verify app signature
codesign -v --verbose /path/to/SuperDimmer.app

# Check signature details
codesign -dv --verbose=4 /path/to/SuperDimmer.app

# Verify DMG signature
codesign -v output/SuperDimmer-vX.X.X.dmg
```

## 🌐 Notarization Notes

### What is Notarization?
Apple's notarization service scans your app for malware and issues a "ticket" that Gatekeeper recognizes. Without notarization, users will see scary warnings.

### Requirements
1. App must be signed with Developer ID
2. Hardened Runtime must be enabled
3. Any entitlements must be justified
4. No known malware patterns

### Getting App-Specific Password
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → Security → App-Specific Passwords
3. Generate a new password for "SuperDimmer Notarization"

### Checking Notarization Status
```bash
# Check if app is notarized
spctl -a -v /path/to/SuperDimmer.app

# Check notarization history
xcrun notarytool history \
    --apple-id "your@email.com" \
    --password "xxxx-xxxx-xxxx-xxxx" \
    --team-id "XXXXXXXXXX"
```

## 🐛 Troubleshooting

### "App is damaged" error
This usually means Gatekeeper quarantine. Fix with:
```bash
xattr -cr /path/to/SuperDimmer.app
```

### Notarization fails
Common issues:
- **Invalid signature**: Re-sign with `--options runtime`
- **Missing entitlement justification**: Add NSAppleEventsUsageDescription, etc.
- **Unsigned frameworks**: Sign all embedded frameworks

### DMG window doesn't show custom layout
The hdiutil method may not perfectly apply window settings on all macOS versions. Use `create-dmg` tool for best results:
```bash
brew install create-dmg
```

## 📊 Build Matrix

| macOS Version | Signing | Notarization | Status |
|---------------|---------|--------------|--------|
| 13.0 Ventura  | ✅      | ✅           | Supported |
| 14.0 Sonoma   | ✅      | ✅           | Primary target |
| 15.0 Sequoia  | ✅      | ✅           | Supported |

## 📝 Version History

- **v1.0.0** (Jan 8, 2026): Initial packaging setup

---

*Part of the SuperDimmer project - A smart screen dimmer for macOS*
