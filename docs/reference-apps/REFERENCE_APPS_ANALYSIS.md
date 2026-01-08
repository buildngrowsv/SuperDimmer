# Reference Apps Analysis
## Copied from local Mac for SuperDimmer development reference

---

## 📁 Apps Copied

| App | Source | Version | Bundle ID |
|-----|--------|---------|-----------|
| **BetterDisplay** | /Applications | 4.1.1 | `pro.betterdisplay.BetterDisplay` |
| **MonitorControlLite** | /Applications | 1.0.0 | `app.monitorcontrol.MonitorControlLite` |
| **Flux** | ~/Applications | 42.2 | `org.herf.Flux` |
| **Display Maid** | /Applications | 3.3.10 | `com.Funk-iSoft.Display-Maid` |
| **Umbra** | /Applications | 1.4 | `com.replay.Umbra` |

---

## 🔑 Entitlements Analysis

### BetterDisplay
```xml
com.apple.security.cs.allow-jit = true
com.apple.security.network.client = true
```
- **NOT sandboxed** - runs outside App Sandbox
- Uses JIT compilation (probably for performance)
- Network access for updates/licensing

### MonitorControlLite
```xml
com.apple.security.app-sandbox = true
com.apple.developer.team-identifier = 299YSU96J7
com.apple.application-identifier = 299YSU96J7.app.monitorcontrol.MonitorControlLite
```
- **App Store sandboxed app**
- No screen recording entitlement (interesting!)
- Uses DDC/CI which doesn't require screen capture

### Flux
```xml
com.apple.security.automation.apple-events = true
com.apple.security.personal-information.location = true
```
- **NOT sandboxed**
- Uses AppleEvents (for automation)
- Location access (for sunrise/sunset times)
- Modifies gamma tables (doesn't need entitlement)

### Display Maid
```xml
com.apple.security.cs.disable-library-validation = true
```
- Can load unsigned libraries
- Window position management (doesn't need screen capture)

### Umbra
```xml
com.apple.security.app-sandbox = false
com.apple.security.automation.apple-events = true
com.apple.security.files.user-selected.read-only = true
```
- **NOT sandboxed** - can modify system settings
- Uses AppleEvents to toggle dark mode via System Events
- File picker access for wallpaper selection
- Uses Gumroad for "Pay What You Want" distribution

---

## 🎯 Key Insights for SuperDimmer

### What These Apps DON'T Need:
- **Screen Recording Permission** - None of them capture screen content
- They modify display settings at the hardware/driver level

### What SuperDimmer WILL Need (unique):
- **Screen Recording Permission** - Required for brightness analysis
- `com.apple.security.device.screen-capture` entitlement

### Common Patterns:

1. **LSUIElement = true** - All are menu bar apps (no dock icon)
2. **LSApplicationCategoryType = public.app-category.utilities**
3. **Minimum macOS 10.13-13.2** (varies by app)
4. **NSPrincipalClass = NSApplication** (standard AppKit)

---

## 📋 Info.plist Key Settings (for SuperDimmer)

```xml
<!-- Menu bar only (no dock icon) -->
<key>LSUIElement</key>
<true/>

<!-- App category -->
<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>

<!-- Minimum macOS version -->
<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<!-- Copyright -->
<key>NSHumanReadableCopyright</key>
<string>Copyright © 2024 YourCompany. All rights reserved.</string>
```

---

## 🔧 Technical Approaches by App

### BetterDisplay
- Virtual display management
- HDR/XDR brightness control
- Uses private CoreDisplay APIs
- Direct display configuration

### MonitorControlLite
- DDC/CI over I²C (HDMI/DisplayPort)
- Gamma table manipulation for software dimming
- Native Apple display protocol
- Open-source reference available at: https://github.com/MonitorControl/MonitorControl

### Flux
- Color temperature via gamma tables
- Location-based scheduling
- Uses CoreGraphics CGSetDisplayTransferByTable

### Display Maid
- Window position saving/restoring
- Multi-monitor window management
- Uses Accessibility APIs for window control

### Umbra ⭐ Highly Relevant
- Light/Dark wallpaper switching
- **Dark Mode wallpaper dimming** - makes wallpaper darker in dark mode
- System appearance toggle via AppleScript
- Unsplash integration for wallpaper browsing
- Per-Space wallpaper support
- SwiftUI + AppKit hybrid architecture
- Uses ShortcutRecorder for global keyboard shortcuts
- Launch at login via ServiceManagement.framework

---

## 📂 App Bundle Structure Reference

```
MyApp.app/
└── Contents/
    ├── Info.plist          # App metadata
    ├── MacOS/
    │   └── MyApp           # Main executable
    ├── Resources/
    │   ├── AppIcon.icns    # App icon
    │   └── *.lproj/        # Localizations
    ├── Frameworks/         # Embedded frameworks
    ├── _CodeSignature/     # Code signature
    └── PkgInfo             # Package info (APPL????)
```

---

## 💡 For SuperDimmer Development

### Copy these patterns:
1. Menu bar app architecture (LSUIElement)
2. Utilities category
3. Sparkle for updates (SUFeedURL pattern from BetterDisplay/Flux)

### Unique to SuperDimmer:
1. Screen Recording permission handling
2. Real-time brightness analysis
3. Per-region overlay windows
4. Active/inactive window differentiation

### Consider:
- MonitorControl is open source - study their gamma/overlay code
- BetterDisplay has sophisticated display handling
- Flux's location-based scheduling could inspire time-based features
- **Umbra's wallpaper dimming could be a feature in SuperDimmer** - combine with screen dimming for complete dark mode experience
- Umbra's SwiftUI+AppKit hybrid architecture is modern and recommended
