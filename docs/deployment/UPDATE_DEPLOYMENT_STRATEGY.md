# SuperDimmer Update Deployment Strategy
## How to Deploy App Updates to Users

### Version 1.0 | January 8, 2026

---

## 📋 Executive Summary

SuperDimmer uses the **Sparkle framework** for automatic software updates, following the same approach as BetterDisplay, f.lux, and other reference apps. This document covers the complete update deployment workflow from building a new version to delivering it to users.

**Key Technologies:**
- **Sparkle 2.x** - macOS open-source update framework
- **EdDSA (ed25519)** - Cryptographic signing for update integrity
- **Appcast XML** - RSS-based update feed
- **Cloudflare Pages** - Website + update hosting (already set up)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SuperDimmer Update System                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────┐         ┌─────────────────┐        ┌─────────────┐   │
│   │   Developer     │         │  GitHub/        │        │  User's Mac │   │
│   │   Machine       │         │  Cloudflare     │        │             │   │
│   │                 │         │                 │        │             │   │
│   │  1. Build app   │         │                 │        │ 4. Sparkle  │   │
│   │  2. Sign with   │────────▶│  appcast.xml    │◀───────│    checks   │   │
│   │     EdDSA key   │         │  + DMG/ZIP      │        │    feed     │   │
│   │  3. Generate    │         │  files          │        │             │   │
│   │     appcast     │         │                 │        │ 5. Download │   │
│   │  4. Upload      │         │                 │        │    & update │   │
│   └─────────────────┘         └─────────────────┘        └─────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔑 Part 1: Initial Setup (One-Time)

### 1.1 Add Sparkle to Your Project

**Option A: Swift Package Manager (Recommended)**

In Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/sparkle-project/Sparkle`
3. Select version `2.6.0` or later
4. Add `Sparkle` to SuperDimmer target

**Option B: Manual Framework Embed**
- Download from https://github.com/sparkle-project/Sparkle/releases
- Drag `Sparkle.framework` to your project's Frameworks folder
- Ensure "Embed & Sign" is selected in build settings

### 1.2 Generate EdDSA Signing Keys

```bash
# Navigate to Sparkle tools (after SPM adds it)
cd ~/Library/Developer/Xcode/DerivedData/SuperDimmer-*/SourcePackages/artifacts/sparkle/Sparkle/bin

# OR download standalone Sparkle release and use included tools:
cd /path/to/Sparkle-2.6.0/bin

# Generate the key pair - saves to Keychain, prints public key
./generate_keys
```

**Output example:**
```
A key has been generated and saved in your keychain. Add the `SUPublicEDKey` key to
the Info.plist of each app for which you intend to use Sparkle for distributing
updates. It should appear like this:

    <key>SUPublicEDKey</key>
    <string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>
```

**IMPORTANT: Backup your private key!**
```bash
# Export private key to secure backup file
./generate_keys -x ~/SuperDimmer-sparkle-private-key.pem

# Store this file securely (encrypted disk, password manager, etc.)
# You'll need it to sign ALL future updates!
```

### 1.3 Update Info.plist

Add these keys to `SuperDimmer/Supporting Files/Info.plist`:

```xml
<!-- Sparkle Update Configuration -->
<key>SUFeedURL</key>
<string>https://superdimmer.com/sparkle/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>YOUR_PUBLIC_KEY_FROM_GENERATE_KEYS</string>

<key>SUEnableAutomaticChecks</key>
<true/>

<!-- Optional: Check every 24 hours (86400 seconds) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>
```

### 1.4 Implement Sparkle in Code

Create `UpdateManager.swift`:

```swift
//
//  UpdateManager.swift
//  SuperDimmer
//
//  PURPOSE:
//  Handles automatic software updates using the Sparkle framework.
//  This follows the same pattern as BetterDisplay, f.lux, and other
//  macOS utility apps that distribute outside the Mac App Store.
//
//  HOW IT WORKS:
//  1. App starts → Sparkle checks SUFeedURL for appcast.xml
//  2. If newer version found → Shows update dialog to user
//  3. User approves → Downloads DMG/ZIP, verifies EdDSA signature
//  4. Installs update and relaunches app
//
//  REFERENCE: BetterDisplay uses Sparkle with Paddle licensing
//  (same combination we're using for SuperDimmer)
//

import Foundation
import Sparkle

/// Manages automatic software updates via Sparkle framework
/// This is a singleton because we only need one updater for the app lifecycle
final class UpdateManager: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance - use UpdateManager.shared.checkForUpdates()
    static let shared = UpdateManager()
    
    // MARK: - Properties
    
    /// The SPUStandardUpdaterController manages the Sparkle update lifecycle
    /// It handles checking for updates, downloading, UI, and installation
    /// We use the standard controller for typical update behavior
    private var updaterController: SPUStandardUpdaterController!
    
    /// Published so UI can reflect update status
    @Published var lastUpdateCheck: Date?
    @Published var isCheckingForUpdates: Bool = false
    
    // MARK: - Initialization
    
    private init() {
        // IMPORTANT: startUpdater must be true for automatic checks to work
        // The SUFeedURL in Info.plist tells Sparkle where to find updates
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,           // Start checking automatically
            updaterDelegate: nil,            // No custom delegate needed for basic use
            userDriverDelegate: nil          // Use default UI
        )
    }
    
    // MARK: - Public Methods
    
    /// Manually check for updates (e.g., from menu item)
    /// Shows UI if update available, or "up to date" message if not
    func checkForUpdates() {
        isCheckingForUpdates = true
        updaterController.checkForUpdates(nil)  // nil sender for programmatic call
        
        // Sparkle handles the UI, we just track that we initiated a check
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isCheckingForUpdates = false
            self?.lastUpdateCheck = Date()
        }
    }
    
    /// Check if automatic update checking is enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
    
    /// Get the date of last update check
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}
```

### 1.5 Add Update Menu Item

In `MenuBarController.swift` or your menu setup:

```swift
// Add to menu items
NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")

@objc func checkForUpdates() {
    UpdateManager.shared.checkForUpdates()
}
```

---

## 📦 Part 2: Release Workflow (Each Update)

### 2.1 Prepare the Release Build

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App

# 1. Update version numbers in Info.plist
#    CFBundleShortVersionString: "1.1.0" (user-facing)
#    CFBundleVersion: "2" (internal build number - must increment!)

# 2. Build release version
xcodebuild -scheme SuperDimmer \
           -configuration Release \
           -derivedDataPath build \
           clean build

# 3. Find the built app
ls build/Build/Products/Release/SuperDimmer.app
```

### 2.2 Code Sign and Notarize

```bash
# Sign with Developer ID (required for distribution outside Mac App Store)
codesign --force --deep --options runtime \
         --sign "Developer ID Application: Your Name (TEAM_ID)" \
         build/Build/Products/Release/SuperDimmer.app

# Verify signing
codesign --verify --deep --strict --verbose=2 \
         build/Build/Products/Release/SuperDimmer.app

# Create ZIP for notarization
ditto -c -k --keepParent \
     build/Build/Products/Release/SuperDimmer.app \
     SuperDimmer-v1.1.0.zip

# Submit for notarization
xcrun notarytool submit SuperDimmer-v1.1.0.zip \
                        --apple-id "your@email.com" \
                        --password "app-specific-password" \
                        --team-id "YOUR_TEAM_ID" \
                        --wait

# Staple notarization ticket (for DMG)
xcrun stapler staple SuperDimmer.app
```

### 2.3 Create DMG (Optional but Professional)

Use the existing scripts in `packaging/`:

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App/packaging

# Build and create DMG in one step
./build-release.sh --sign --notarize

# Or manually create DMG
./create-dmg.sh
```

### 2.4 Sign the Update Archive with EdDSA

```bash
# Navigate to Sparkle tools
cd /path/to/Sparkle/bin

# Sign the archive (DMG or ZIP)
./sign_update /path/to/SuperDimmer-v1.1.0.dmg

# Output:
# sparkle:edSignature="abc123XYZ...==" length="12345678"
```

**Save this output!** You'll need both values for the appcast.

### 2.5 Generate or Update Appcast

**Option A: Automatic Generation (Recommended)**

```bash
# Put all release archives in one folder
mkdir -p ~/SuperDimmer-releases
cp SuperDimmer-v1.0.0.dmg ~/SuperDimmer-releases/
cp SuperDimmer-v1.1.0.dmg ~/SuperDimmer-releases/

# Generate appcast automatically
/path/to/Sparkle/bin/generate_appcast ~/SuperDimmer-releases/

# This creates appcast.xml with all versions
```

**Option B: Manual Appcast (for fine-grained control)**

Create `appcast.xml`:

```xml
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>SuperDimmer Updates</title>
        <link>https://superdimmer.com/</link>
        <description>Most recent changes for SuperDimmer</description>
        <language>en</language>
        
        <!-- Latest stable release -->
        <item>
            <title>Version 1.1.0</title>
            <pubDate>Thu, 09 Jan 2026 12:00:00 -0800</pubDate>
            
            <!-- Release notes - can be inline or linked -->
            <sparkle:releaseNotesLink>
                https://superdimmer.com/release-notes/v1.1.0.html
            </sparkle:releaseNotesLink>
            
            <!-- Version info (MUST match Info.plist exactly!) -->
            <sparkle:version>2</sparkle:version>
            <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
            
            <!-- Minimum macOS required -->
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            
            <!-- Download enclosure with EdDSA signature -->
            <enclosure 
                url="https://superdimmer.com/releases/SuperDimmer-v1.1.0.dmg" 
                length="18856188"
                type="application/octet-stream"
                sparkle:edSignature="YOUR_ED_SIGNATURE_FROM_SIGN_UPDATE=="/>
        </item>
        
        <!-- Previous releases for rollback -->
        <item>
            <title>Version 1.0.0</title>
            <pubDate>Wed, 08 Jan 2026 12:00:00 -0800</pubDate>
            <sparkle:releaseNotesLink>
                https://superdimmer.com/release-notes/v1.0.0.html
            </sparkle:releaseNotesLink>
            <sparkle:version>1</sparkle:version>
            <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure 
                url="https://superdimmer.com/releases/SuperDimmer-v1.0.0.dmg" 
                length="15000000"
                type="application/octet-stream"
                sparkle:edSignature="PREVIOUS_SIGNATURE=="/>
        </item>
    </channel>
</rss>
```

### 2.6 Upload Files to Hosting

Since SuperDimmer Website is on **Cloudflare Pages** connected to GitHub:

```bash
# Structure in SuperDimmer-Website repo:
SuperDimmer-Website/
├── index.html
├── sparkle/
│   └── appcast.xml          # Update feed
├── releases/
│   ├── SuperDimmer-v1.0.0.dmg
│   ├── SuperDimmer-v1.1.0.dmg
│   └── README.md
└── release-notes/
    ├── v1.0.0.html          # Release notes pages
    └── v1.1.0.html

# Commit and push - Cloudflare Pages auto-deploys
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website
git add sparkle/ releases/ release-notes/
git commit -m "Release v1.1.0 - [release notes summary]"
git push origin main
```

**Cloudflare Pages will automatically deploy within ~1-2 minutes.**

---

## 🔄 Part 3: Update Channels (Optional)

Like BetterDisplay, you can support multiple update channels:

### Beta/Pre-release Channel

Add `<sparkle:channel>` tags to items:

```xml
<!-- Stable release (default) -->
<item>
    <title>Version 1.1.0</title>
    <!-- No channel tag = default/stable -->
    ...
</item>

<!-- Beta release -->
<item>
    <title>Version 1.2.0-beta1</title>
    <sparkle:channel>beta</sparkle:channel>
    ...
</item>

<!-- Internal testing -->
<item>
    <title>Version 1.2.0-internal</title>
    <sparkle:channel>internal</sparkle:channel>
    ...
</item>
```

### Switching Channels in App

```swift
// In UpdateManager.swift
func setUpdateChannel(_ channel: String?) {
    // Set allowed channels
    if let channel = channel {
        UserDefaults.standard.set([channel], forKey: "SUAllowedChannels")
    } else {
        UserDefaults.standard.removeObject(forKey: "SUAllowedChannels")
    }
}
```

---

## 🛠️ Part 4: Automation Scripts

### Complete Release Script

Create `packaging/release.sh`:

```bash
#!/bin/bash
# ==============================================================================
# SuperDimmer Release Script
# ==============================================================================
# This script automates the entire release process:
# 1. Builds the app
# 2. Signs with Developer ID
# 3. Notarizes with Apple
# 4. Creates DMG
# 5. Signs update with EdDSA
# 6. Updates appcast.xml
# 7. Commits to website repo
#
# Usage: ./release.sh 1.1.0
# ==============================================================================

set -e  # Exit on error

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh VERSION"
    echo "Example: ./release.sh 1.1.0"
    exit 1
fi

# Paths
PROJECT_DIR="/Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App"
WEBSITE_DIR="/Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website"
BUILD_DIR="$PROJECT_DIR/build/Release"
OUTPUT_DIR="$PROJECT_DIR/packaging/output"

# Sparkle tools (adjust path based on your setup)
SPARKLE_TOOLS="$HOME/Sparkle/bin"

echo "📦 Building SuperDimmer v$VERSION..."
cd "$PROJECT_DIR"
xcodebuild -scheme SuperDimmer -configuration Release -derivedDataPath build clean build

echo "✍️ Signing with Developer ID..."
codesign --force --deep --options runtime \
         --sign "Developer ID Application: Your Name (TEAM_ID)" \
         "$BUILD_DIR/SuperDimmer.app"

echo "📋 Creating DMG..."
./packaging/create-dmg.sh

echo "🍎 Notarizing with Apple..."
DMG_FILE="$OUTPUT_DIR/SuperDimmer-v$VERSION.dmg"
xcrun notarytool submit "$DMG_FILE" \
                        --apple-id "your@email.com" \
                        --password "@keychain:AC_PASSWORD" \
                        --team-id "YOUR_TEAM_ID" \
                        --wait

echo "📌 Stapling notarization..."
xcrun stapler staple "$DMG_FILE"

echo "🔐 Signing update with EdDSA..."
SIGNATURE=$("$SPARKLE_TOOLS/sign_update" "$DMG_FILE")
echo "Signature: $SIGNATURE"

echo "📝 Updating appcast..."
# (You would generate or update appcast.xml here)

echo "🚀 Copying to website..."
cp "$DMG_FILE" "$WEBSITE_DIR/releases/"

echo "✅ Release v$VERSION ready!"
echo "Next: Review appcast.xml and push to GitHub"
```

---

## 📊 Part 5: Monitoring Updates

### Analytics

Consider adding analytics to track:
- Update success/failure rates
- Version distribution of active users
- Time from release to adoption

### Crash Reporting Integration

Sentry or similar crash reporting should include version info:

```swift
// In AppDelegate
SentrySDK.start { options in
    options.dsn = "YOUR_SENTRY_DSN"
    options.release = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
}
```

---

## ✅ Checklist for Each Release

### Pre-Release
- [ ] Update version in Info.plist (both `CFBundleShortVersionString` and `CFBundleVersion`)
- [ ] Test build thoroughly on multiple macOS versions
- [ ] Write release notes
- [ ] Update changelog

### Build & Sign
- [ ] Clean build with Release configuration
- [ ] Sign with Developer ID
- [ ] Create DMG
- [ ] Notarize with Apple
- [ ] Staple notarization ticket
- [ ] Sign update archive with EdDSA

### Publish
- [ ] Upload DMG to website releases folder
- [ ] Update appcast.xml with new item
- [ ] Update release notes HTML page
- [ ] Commit and push to GitHub
- [ ] Verify Cloudflare Pages deployment
- [ ] Test update from previous version

### Post-Release
- [ ] Monitor crash reports
- [ ] Check update adoption rate
- [ ] Respond to support tickets

---

## 🔗 Reference: How Reference Apps Handle Updates

| App | Update System | Feed URL | Notes |
|-----|--------------|----------|-------|
| **BetterDisplay** | Sparkle 2.x | `betterdisplay.pro/sparkle/appcast.xml` | Multiple channels (stable, internal, pre) |
| **f.lux** | Sparkle | `justgetflux.com/mac/macflux.xml` | Daily check, simple single-channel |
| **Umbra** | Sparkle | (varies) | Gumroad for payment, Sparkle for updates |

---

## ⚠️ Important Security Notes

1. **Never commit your EdDSA private key to Git**
2. **Store private key in Keychain or secure backup**
3. **All updates MUST be served over HTTPS** (Cloudflare handles this)
4. **Always test updates before pushing to production**
5. **Keep previous versions in appcast for rollback capability**

---

## 📞 Support Resources

- **Sparkle Documentation**: https://sparkle-project.org/documentation/
- **Sparkle GitHub**: https://github.com/sparkle-project/Sparkle
- **Apple Notarization**: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution

---

*Document Version: 1.0*
*Created: January 8, 2026*
*Status: Ready for Implementation*
