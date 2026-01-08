# Reference Apps Deep Analysis
## Tech Stacks, Features, and Licensing Methods

---

## 📊 Summary Table

| App | Stack | Licensing Method | Update Mechanism | Business Model |
|-----|-------|------------------|------------------|----------------|
| **BetterDisplay** | Swift + SwiftUI + AppKit | **Paddle SDK** (external) | Sparkle | Freemium → Pro License |
| **MonitorControlLite** | Swift + AppKit | **Mac App Store Receipt** | App Store | Paid App (MAS) |
| **f.lux** | Objective-C + AppKit | **Freeware/Donationware** | Sparkle | Free (Donations) |
| **Display Maid** | Swift + AppKit | **Mac App Store Receipt** | App Store | Paid App (MAS) |
| **Umbra** | Swift + SwiftUI + AppKit | **Gumroad** (Pay What You Want) | Sparkle | PWYW / Donationware |

---

## 🔧 Detailed Tech Stack Analysis

### 1. BetterDisplay (v4.1.1)

**Language:** Swift (primary) + SwiftUI for some views  
**UI Framework:** AppKit (NSApplication) + SwiftUI components  
**Architecture:** Universal Binary (x86_64 + arm64)  
**Xcode Version:** 26.1 (Xcode 2601)  
**Min macOS:** 13.2 (Ventura)

**Key Frameworks Used:**
```
- CoreDisplay.framework (display configuration)
- DisplayServices.framework (private, display control)
- CoreBrightness.framework (private, brightness control)
- SkyLight.framework (private, window server)
- OSD.framework (private, on-screen display)
- SidecarCore.framework (private, sidecar displays)
- IOMobileFramebuffer.framework (private, framebuffer access)
- BezelServices.framework (private, hardware bezels)
- Paddle.framework (licensing)
- Sparkle.framework (auto-updates)
- Sentry.framework (crash reporting/analytics)
- AppIntents.framework (Siri/Shortcuts integration)
```

**How It Works:**
- Uses **private Apple APIs** to directly control display hardware
- Accesses CoreDisplay for virtual display creation
- Manipulates gamma tables for software brightness
- Uses DDC/CI for external monitor control
- Creates virtual displays that can scale content

---

### 2. MonitorControlLite (v1.0.0)

**Language:** Swift  
**UI Framework:** AppKit (Storyboard-based)  
**Architecture:** Universal Binary (x86_64 + arm64)  
**Xcode Version:** 13.1  
**Min macOS:** 10.15 (Catalina)

**Key Frameworks Used:**
```
- Standard Swift runtime libraries (embedded)
- AppKit, CoreData, CoreGraphics
- IOKit (for hardware access)
- KeyboardShortcuts bundle (custom keyboard shortcuts)
```

**How It Works:**
- **Software Dimming via Gamma Tables**: Uses `CGSetDisplayTransferByTable` to modify color output
- **Overlay Dimming**: Creates transparent overlay windows for displays that don't support gamma
- Simplified version of full MonitorControl (no DDC/CI hardware control)
- Uses storyboards for UI with NIB files

**Open Source Reference:** The full version (MonitorControl) is open source at:
https://github.com/MonitorControl/MonitorControl

---

### 3. f.lux (v42.2)

**Language:** Objective-C (legacy codebase)  
**UI Framework:** AppKit (NIB-based)  
**Architecture:** Universal Binary (x86_64 + arm64)  
**Xcode Version:** 14.2  
**Min macOS:** 10.9 (Mavericks)

**Key Frameworks Used:**
```
- Cocoa.framework (traditional AppKit app)
- CoreLocation.framework (sunrise/sunset calculation)
- CoreDisplay.framework (display control)
- DisplayServices.framework (private)
- WebKit.framework (for in-app content)
- Sparkle.framework (auto-updates)
```

**How It Works:**
- **Gamma Table Manipulation**: Core technique for color temperature shifting
- Uses `CGSetDisplayTransferByTable()` to apply color transforms
- Functions detected in binary:
  - `getGammaTable`, `makeGammaTable`, `setScaledGamma`
  - `getBrightness`, `setScaledBrightness`
- **Location-based scheduling** via CoreLocation for automatic sunrise/sunset adjustment
- Uses **AppleScript** for dark mode toggling (`darkmode.scpt`, `lightmode.scpt`)

---

### 4. Display Maid (v3.3.10)

**Language:** Swift  
**UI Framework:** AppKit (NIB-based)  
**Architecture:** Universal Binary (x86_64 + arm64)  
**Xcode Version:** 15.0  
**Min macOS:** 10.13 (High Sierra)

**Key Frameworks Used:**
```
- Swift standard libraries (embedded as dylibs)
- CoreData (window position persistence)
- CoreGraphics (window management)
- IOKit (display detection)
```

**How It Works:**
- Uses **Accessibility APIs** for window position management
- CoreData for storing window layouts
- Detects display configurations and restores window positions
- No screen capture or display manipulation needed

---

### 5. Umbra (v1.4) ⭐ HIGHLY RELEVANT FOR SUPERDIMMER

**Language:** Swift  
**UI Framework:** SwiftUI + AppKit (Hybrid)  
**Architecture:** Universal Binary (x86_64 + arm64)  
**Xcode Version:** 15.0.1  
**Min macOS:** 11.5 (Big Sur)

**Bundle ID:** `com.replay.Umbra`  
**Developer:** Replay Software (Alasdair Monk & Hector Simpson)

**Key Frameworks Used:**
```
- SwiftUI.framework (modern UI)
- AppKit.framework (menu bar, NSWindow)
- CoreGraphics.framework (wallpaper management)
- ServiceManagement.framework (launch at login)
- ImageIO.framework (image processing)
- Alamofire/AlamofireImage (networking, image loading)
- ShortcutRecorder bundle (global keyboard shortcuts)
- Sparkle.framework v1.24.0 (auto-updates)
- libswift_Concurrency.dylib (async/await support)
```

**Entitlements:**
```xml
com.apple.security.app-sandbox = false  // NOT sandboxed!
com.apple.security.automation.apple-events = true  // For System Events
com.apple.security.files.user-selected.read-only = true  // File picker
```

**How It Works:**

1. **Wallpaper Switching:**
   - Accesses `/Library/Dock/desktoppicture.db` (SQLite database)
   - Uses `NSWorkspace.shared.setDesktopImageURL(forScreen:options:error:)`
   - Supports JPG, HEIC, PNG, PSD image formats
   - Per-Space wallpaper support

2. **Dark Mode Toggle:**
   - Uses AppleScript via Apple Events automation
   - `tell application "System Events" → tell appearance preferences → set dark mode`
   - Global keyboard shortcut support via ShortcutRecorder

3. **Wallpaper Dimming (Dark Mode):**
   - "Dark Appearance Dims Wallpaper" feature
   - Applies image processing to darken wallpaper in dark mode
   - Not overlay-based, modifies the wallpaper image itself

4. **Unsplash Integration:**
   - Built-in browser for Unsplash wallpapers
   - Categories: Wallpapers, 3D Renders, Patterns, Nature, Travel
   - Uses Alamofire for API requests and image downloading

5. **Multi-Monitor/Spaces Support:**
   - "Apply Wallpapers to All Spaces" option
   - Per-screen wallpaper management
   - Auto-updates wallpapers when Space becomes active

**Sparkle Update Config:**
```xml
<key>SUFeedURL</key>
<string>https://replay-umbra-distribution.s3.amazonaws.com/changelog.xml</string>
<key>SUPublicEDKey</key>
<string>/69QOosOF0DyaYFLTPXjoJ3b5vNfcb+z/FRkUXh2zLA=</string>
```

---

## 💰 Licensing Methods - Detailed Breakdown

### Method 1: Paddle SDK (BetterDisplay)

**What is Paddle?**
Paddle is a **Merchant of Record** (MoR) solution that handles:
- Payment processing worldwide
- Sales tax/VAT calculation and remittance
- License key generation and validation
- Subscription management
- Trial period management

**BetterDisplay's Implementation:**
```swift
// Framework: Paddle.framework v4.4.3
// API endpoint: https://v3.paddleapi.com/3.2/license/activations

// License States detected:
- "Status: Pro License Activated"
- "Status: Unlicensed, Trial Active"  
- "Status: Unlicensed, Trial Expired"
- "Status: Outdated License"

// Features:
- Trial period tracking ("Trial Days Left")
- License activation/deactivation
- Hardware ID binding ("hardware identifiers have changed")
- Multi-device activation limits
- Version-based license validity
```

**BetterDisplay Business Model:**
1. **Free Tier**: Basic features work indefinitely without license
2. **Trial**: Full Pro features for limited days
3. **Pro License**: One-time purchase, perpetual for that major version
4. **Upgrade Required**: New major versions require new license purchase

**Paddle Pricing for Developers:**
- ~5% + $0.50 per transaction (varies by region)
- No monthly fees
- They handle all tax compliance globally

**Implementation Resources:**
- https://paddle.com/developers/
- Paddle macOS SDK documentation

---

### Method 2: Mac App Store Receipt Validation (MonitorControlLite, Display Maid)

**How It Works:**
Both apps have `_MASReceipt/receipt` files - these are **cryptographically signed receipts** from Apple's App Store.

**Receipt Validation Process:**
1. App reads receipt from `Contents/_MASReceipt/receipt`
2. Validates receipt signature against Apple's certificate chain
3. Extracts purchase information (app ID, version, purchase date)
4. Verifies receipt belongs to this specific app installation

**Apple's Receipt Format:**
- PKCS#7 signed data container
- Contains ASN.1 encoded purchase information
- Includes in-app purchase records for IAP apps

**Benefits:**
- No external licensing server needed
- Apple handles all payment processing
- Built-in App Store features (Family Sharing, etc.)
- Automatic updates via App Store

**Limitations:**
- Apple takes 15-30% commission
- App Review process requirements
- Sandboxing requirements may limit functionality
- Can't use private APIs or certain entitlements

---

### Method 3: Freeware/Donationware (f.lux)

**Business Model:**
- App is completely free
- Donations accepted via website
- Revenue from enterprise/educational site licenses
- Revenue from Windows/mobile versions

**Why It Works for f.lux:**
- Established brand (since 2009)
- Large user base provides word-of-mouth marketing
- Cross-platform presence
- Premium partnerships possible

---

### Method 4: Gumroad "Pay What You Want" (Umbra)

**What is Gumroad?**
Gumroad is a simple e-commerce platform for creators and indie developers.

**Umbra's Implementation:**
- Download link: `https://gum.co/umbra-app`
- **"Pay What You Like"** model - users can pay $0 or any amount
- No license key system - download is unlocked after "purchase"
- Website: replay.software/umbra

**How It Works:**
1. User visits website and clicks "Get it now for Mac"
2. Redirects to Gumroad checkout
3. User enters $0 or any amount they choose
4. Receives download link immediately
5. No activation or license validation in app

**Gumroad Pricing for Developers:**
- 10% flat fee per transaction (no monthly fees)
- Simple setup - no SDK integration needed
- No license management - just file downloads

**Pros:**
- Extremely simple implementation (no licensing SDK)
- Low friction for users (can pay $0)
- Good for building user base quickly
- Users who pay tend to pay generously

**Cons:**
- No feature-gating possible
- No trial period management
- No license activation tracking
- Higher commission than Paddle (10% vs 5%)
- Can't prevent piracy or limit installations

**Why It Works for Umbra:**
- Simple utility app with clear value proposition
- Builds goodwill with free option
- Beautiful design attracts paying customers
- Focus on user experience over monetization

---

## 🔄 Auto-Update Mechanisms

### Sparkle Framework (BetterDisplay, f.lux, Umbra)

**What is Sparkle?**
Open-source macOS update framework: https://sparkle-project.org/

**How It Works:**
1. App checks appcast XML file at defined URL
2. Compares current version with latest in feed
3. Downloads delta or full update if available
4. Verifies EdDSA/DSA signature
5. Installs update (often with user prompt)

**BetterDisplay Sparkle Config:**
```xml
<key>SUFeedURL</key>
<string>https://betterdisplay.pro/betterdisplay/sparkle/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>ITSTMp8AypsLawojJ+UR3tm2mN18AFoNMvXf1G3t62s=</string>
```

**f.lux Sparkle Config:**
```xml
<key>SUFeedURL</key>
<string>https://justgetflux.com/mac/macflux.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUScheduledCheckInterval</key>
<string>86400</string>  <!-- Daily -->
```

**Umbra Sparkle Config:**
```xml
<key>SUFeedURL</key>
<string>https://replay-umbra-distribution.s3.amazonaws.com/changelog.xml</string>
<key>SUPublicEDKey</key>
<string>/69QOosOF0DyaYFLTPXjoJ3b5vNfcb+z/FRkUXh2zLA=</string>
```

### App Store Updates (MonitorControlLite, Display Maid)
- Handled automatically by macOS
- No framework needed in app
- User controls update settings in System Settings

---

## 🎯 Feature Implementation Techniques

### Brightness/Dimming Techniques

| Technique | Used By | How It Works |
|-----------|---------|--------------|
| **Gamma Table Manipulation** | f.lux, MonitorControlLite | `CGSetDisplayTransferByTable()` modifies color LUT |
| **DDC/CI Hardware Control** | BetterDisplay (Pro), MonitorControl | I²C commands to monitor's OSD controller |
| **Overlay Window Dimming** | MonitorControlLite, Lunar | Transparent black window on top of content |
| **Private CoreDisplay APIs** | BetterDisplay | Direct display parameter control |
| **Virtual Display Creation** | BetterDisplay | Creates software displays with custom properties |
| **Wallpaper Dimming** | Umbra | Image processing to darken wallpaper in dark mode |
| **System Appearance Toggle** | Umbra | AppleScript via `System Events` to toggle dark mode |

### Code Example - Gamma Table (from f.lux analysis):
```objc
// Functions found in f.lux binary:
- getGammaTable
- makeGammaTable:
- setScaledGamma:syncProfile:
- getGammaValue:greenVal:blueVal:

// API: CGSetDisplayTransferByTable(displayID, tableSize, redTable, greenTable, blueTable)
// Each table is array of floats 0.0-1.0 mapping input to output values
```

### Window Management Techniques (for SuperDimmer's overlay system)

**Key NSWindow Properties:**
```swift
// From research analysis:
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.ignoresMouseEvents = true  // Click-through!
window.level = .screenSaver       // Above most windows
window.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary
]
```

---

## 🎁 Recommendations for SuperDimmer

### Licensing Options (Ranked)

1. **Paddle SDK** ⭐ RECOMMENDED
   - Best for: Direct sales, global customers, feature-gating
   - Pros: Lower commission (~5%), flexible licensing, trial support
   - Cons: More implementation work, self-hosted website needed
   - Best fit for SuperDimmer's freemium model

2. **Mac App Store**
   - Best for: Discoverability, trust, simplicity
   - Pros: Built-in audience, Apple handles everything
   - Cons: 15-30% commission, can't use private APIs, sandboxing limits
   - May limit SuperDimmer's screen capture capabilities

3. **LemonSqueezy** (Alternative to Paddle)
   - Similar to Paddle, newer player
   - Good developer experience
   - Worth evaluating: https://lemonsqueezy.com

4. **Gumroad** (Simple) - *Used by Umbra*
   - Best for: Quick setup, simple products, "pay what you want"
   - Pros: No SDK needed, simple setup, good for building user base
   - Cons: No license management, higher fees (10%), can't feature-gate
   - Good option if SuperDimmer wants a free tier with optional donations

### Update Mechanism
- **Use Sparkle** for non-MAS distribution
- Already proven by BetterDisplay and f.lux
- EdDSA signatures for security
- Delta updates save bandwidth

### Tech Stack Recommendation for SuperDimmer
```
Language: Swift 5.9+
UI: SwiftUI (modern) + AppKit (where needed)
Brightness Analysis: Accelerate/vImage
Screen Capture: CGWindowListCreateImage
Overlay System: Custom NSWindow subclass
Licensing: Paddle SDK
Updates: Sparkle
Analytics: Sentry (optional)
Min macOS: 13.0 (for latest SwiftUI features)
```

---

## 📚 Resources

### Official Documentation
- Paddle SDK: https://developer.paddle.com/
- Sparkle: https://sparkle-project.org/documentation/
- Apple Receipt Validation: https://developer.apple.com/documentation/appstorereceipts

### Open Source References
- MonitorControl: https://github.com/MonitorControl/MonitorControl
- Lunar: https://github.com/alin23/Lunar (if available)
- Sparkle: https://github.com/sparkle-project/Sparkle
- ShortcutRecorder: https://github.com/Kentzo/ShortcutRecorder

---

## 🔍 Umbra - Feature Analysis for SuperDimmer

Umbra is **highly relevant** to SuperDimmer because it demonstrates:

### Features SuperDimmer Should Consider Adopting:

1. **Wallpaper Switching (Light/Dark)**
   - Set different wallpapers for light vs dark mode
   - Auto-switch when system appearance changes
   - Very polished UX with drag-and-drop

2. **Wallpaper Dimming**
   - "Dark appearance dims wallpaper" option
   - Reduces eye strain in dark environments
   - Complements SuperDimmer's bright-region dimming

3. **Unsplash Integration**
   - Built-in wallpaper browser
   - Good for user engagement
   - Could be a premium/pro feature

4. **Global Keyboard Shortcuts**
   - Uses ShortcutRecorder bundle
   - Quick toggle from anywhere
   - Essential for power users

5. **Launch at Login**
   - ServiceManagement.framework
   - LaunchAtLoginHelper.app in `Library/LoginItems/`
   - Standard pattern for menu bar utilities

### Umbra's UI/UX Patterns Worth Noting:

- Beautiful, minimal design
- SwiftUI + AppKit hybrid works well
- Window chrome with light/dark toggle in titlebar
- Clear two-tab organization (Wallpaper | Settings)
- Preview images before applying
- Localized in 5 languages

### What Umbra Does NOT Do (SuperDimmer's Opportunity):

- ❌ Does not dim screen content (only wallpapers)
- ❌ Does not detect bright regions automatically
- ❌ Does not dim individual windows or apps
- ❌ No f.lux-style color temperature shifting
- ❌ No scheduling based on time/location

**SuperDimmer's unique value**: Intelligent, automatic, **region-specific** dimming of bright content areas - something none of these apps provide.

---

*Analysis completed: January 7, 2026*
