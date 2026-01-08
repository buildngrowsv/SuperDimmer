# SuperDimmer - Market & Technical Research
## Comprehensive Analysis of Existing Solutions and Technical Implementation

---

## 🎯 Executive Summary

**SuperDimmer fills a unique gap in the market.** While numerous macOS apps exist for screen brightness control, **none currently offer intelligent, automatic, region-specific dimming of bright content areas**. Existing solutions either:

1. Dim the **entire screen** uniformly
2. Control hardware brightness via DDC/CI (monitor's backlight)
3. Apply per-app appearance switching (Light/Dark mode toggles)

**SuperDimmer's Innovation:** Automatically detect and dim specific bright regions on screen (like white emails, bright webpages in dark mode apps, light-themed embedded content) while leaving the rest of the screen at normal brightness.

---

## 📊 Competitive Landscape

### Major Existing Apps

| App | Focus | How It Works | Gap vs SuperDimmer |
|-----|-------|--------------|-------------------|
| **Lunar** | External monitor brightness + automation | DDC/CI hardware control, gamma tables, overlay windows, app presets | Dims entire display, not specific bright regions |
| **MonitorControl** | Free, open-source brightness control | DDC/CI + gamma + overlay (for virtual displays) | Full-screen only |
| **BetterDisplay** | Virtual displays, HDR/XDR, advanced settings | Display configuration + brightness | Per-display, not per-region |
| **DisplayBuddy** | Simple commercial brightness | DDC/CI + software fallback | Full-screen only |
| **f.lux / Night Shift** | Color temperature / blue light | Gamma table color shift | Affects entire screen uniformly |
| **Brightness Slider** | Simple dimming below minimum | Pure software overlay dimming | Full-screen only |
| **Vivid** | HDR/XDR brightness boosting | Unlocks extra display brightness | Opposite goal (brighter, not dimmer) |
| **Gray / NightOwl** | Per-app Light/Dark mode switching | Forces appearance mode per-app | Toggles mode, doesn't dim specific content |

### Market Gap Confirmed

Research confirms:
> "I could not find a maintained macOS app that detects 'bright content' in an individual window or region and automatically overlays/dims only that region dynamically."

**SuperDimmer would be the FIRST to offer this capability.**

---

## 🏗️ Technical Architecture Overview

SuperDimmer requires multiple technical systems working together:

```
┌─────────────────────────────────────────────────────────────────┐
│                      SuperDimmer Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │  Screen Capture  │───▶│ Brightness       │                   │
│  │  Service         │    │ Analysis Engine  │                   │
│  │ CGWindowList     │    │ (vImage/Accel.)  │                   │
│  └──────────────────┘    └────────┬─────────┘                   │
│                                   │                              │
│  ┌──────────────────┐             │                              │
│  │  Window Tracker  │             │                              │
│  │  CGWindowList    │             ▼                              │
│  │  NSWorkspace     │    ┌──────────────────┐                   │
│  └────────┬─────────┘    │  Region          │                   │
│           │              │  Detection       │                   │
│           │              │  (Bright Spots)  │                   │
│           ▼              └────────┬─────────┘                   │
│  ┌──────────────────┐             │                              │
│  │  Active/Inactive │             │                              │
│  │  Window State    │◀────────────┘                              │
│  └────────┬─────────┘                                            │
│           │                                                      │
│           ▼                                                      │
│  ┌──────────────────────────────────────────┐                   │
│  │            Overlay Manager                │                   │
│  │  • Per-region NSWindow overlays           │                   │
│  │  • Variable opacity based on brightness   │                   │
│  │  • Different dimming for active/inactive  │                   │
│  └──────────────────────────────────────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Technical Implementation Details

### 1. Screen Capture (Requires Screen Recording Permission)

**API:** `CGWindowListCreateImage` / `CGDisplayCreateImage`

```swift
// Capture entire screen
func captureMainDisplayImage() -> CGImage? {
    let displayID = CGMainDisplayID()
    return CGDisplayCreateImage(displayID)
}

// Capture specific region
func captureScreenRegion(rect: CGRect) -> CGImage? {
    return CGWindowListCreateImage(
        rect,
        .optionOnScreenOnly,
        kCGNullWindowID,
        [.bestResolution, .boundsIgnoreFraming]
    )
}
```

**Required Entitlement:**
```xml
<key>com.apple.security.device.screen-capture</key>
<true/>
```

**User Permission:** System Settings → Privacy & Security → Screen Recording

---

### 2. Brightness Analysis Engine

**API:** Accelerate framework (vImage) for high-performance pixel analysis

**Luminance Formula (Rec. 709):**
```
Y' = 0.2126 × R + 0.7152 × G + 0.0722 × B
```

**Algorithm for Detecting Bright Regions:**

```swift
import Accelerate

func brightSpotsMask(from image: CGImage, threshold: UInt8 = 230) -> CGImage? {
    // 1. Convert to grayscale via vImage
    // 2. Apply threshold to create binary mask
    // 3. Morphological operations to clean up (dilate/erode)
    // 4. Connected component analysis to find regions
    // 5. Return bounding boxes of bright regions
}

func averageLuminance(in image: CGImage, rect: CGRect) -> Double? {
    // Sample pixels in region
    // Calculate average luminance 0.0-1.0
    // Return brightness value
}
```

**Performance Considerations:**
- Don't analyze full-res every frame - downsample first
- Use grid-based sampling instead of pixel-by-pixel
- Cache results and only re-analyze when content changes
- Use Accelerate framework for SIMD-optimized operations

---

### 3. Window Tracking System

**API:** `CGWindowListCopyWindowInfo` + `NSWorkspace`

```swift
struct WindowInfo {
    let windowID: CGWindowID
    let ownerName: String
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int
    let isOnscreen: Bool
    let title: String
}

func getVisibleWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) 
          as? [[String: Any]] else {
        return []
    }
    // Parse window info...
}

// Detect frontmost/active app
func getFrontmostApp() -> NSRunningApplication? {
    return NSWorkspace.shared.frontmostApplication
}
```

**Active vs Inactive Windows:**
- Track frontmost application PID
- Windows from frontmost app = "active"
- All other windows = "inactive"
- Apply different dimming intensity to each category

---

### 4. Overlay Window System

**API:** NSWindow with special configuration for transparent overlays

```swift
final class DimOverlayWindow: NSWindow {
    init(frame: CGRect, screen: NSScreen, dimmingLevel: CGFloat) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // Critical configuration for overlay behavior
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true  // Let clicks pass through!
        self.level = .screenSaver       // High enough to be on top
        self.collectionBehavior = [
            .canJoinAllSpaces,           // Appear on all Spaces
            .fullScreenAuxiliary         // Work with fullscreen apps
        ]
        
        // Dim view with specified opacity
        let dimView = NSView(frame: frame)
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(dimmingLevel).cgColor
        self.contentView = dimView
    }
}
```

**Window Levels (NSWindow.Level):**
- `.normal` - Regular app windows
- `.floating` - Above normal windows
- `.statusBar` - Menu bar level
- `.modalPanel` - Modal dialogs
- `.screenSaver` - Very high, good for overlays
- Custom CGWindowLevel values for fine control

---

### 5. Intelligent Dimming Algorithm

**Core Logic:**

```swift
class SuperDimmerEngine {
    var brightnessThreshold: Double = 0.85  // 85% = "bright"
    var activeDimAmount: CGFloat = 0.15     // 15% dim for active windows
    var inactiveDimAmount: CGFloat = 0.35   // 35% dim for inactive windows
    
    func analyzaAndDim() {
        // 1. Capture screen
        guard let screenImage = captureMainDisplayImage() else { return }
        
        // 2. Get all visible windows
        let windows = getVisibleWindows()
        let frontmostPID = getFrontmostApp()?.processIdentifier
        
        // 3. For each window, analyze brightness
        for window in windows {
            let isActive = window.ownerPID == frontmostPID
            let brightness = averageLuminance(in: screenImage, rect: window.bounds)
            
            if let brightness, brightness > brightnessThreshold {
                // This window has bright content - dim it
                let dimLevel = isActive ? activeDimAmount : inactiveDimAmount
                createOrUpdateOverlay(for: window, dimLevel: dimLevel)
            } else {
                // Not bright enough - remove any existing overlay
                removeOverlay(for: window)
            }
        }
    }
}
```

---

## 🔑 Required macOS Permissions & Entitlements

### App Sandbox Entitlements (for distribution)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- Screen Capture (required for brightness analysis) -->
    <key>com.apple.security.device.screen-capture</key>
    <true/>
</dict>
</plist>
```

### User Permissions Required

1. **Screen Recording** - System Settings → Privacy & Security → Screen Recording
   - Required for CGWindowListCreateImage to capture other apps
   - Without this, only your own app's windows are visible
   
2. **Accessibility** (optional, for enhanced window tracking)
   - System Settings → Privacy & Security → Accessibility
   - May be needed for some advanced window manipulation features

---

## 📈 Unique Selling Propositions (USPs)

### What Makes SuperDimmer Different

1. **Region-Specific Dimming**
   - Only dims bright areas, not the whole screen
   - Dark content stays at normal brightness

2. **Intelligent Detection**
   - Automatically identifies bright spots
   - No manual region selection needed

3. **Active vs Inactive Differentiation**
   - Less dimming on the window you're working in
   - More dimming on background windows
   - Maintains focus awareness

4. **The "Email Problem" Solved**
   - Dark mode Mail app with bright email content
   - Dark mode browser with white webpage backgrounds
   - Mixed light/dark extensions and widgets

5. **No Hardware Required**
   - Pure software solution
   - Works on any display
   - No DDC/CI compatibility issues

---

## 🚀 Implementation Phases

### Phase 1: Core Engine (MVP)
- [ ] Screen capture with permission handling
- [ ] Basic brightness analysis (whole screen)
- [ ] Simple full-window overlay dimming
- [ ] Menu bar app with on/off toggle

### Phase 2: Intelligent Dimming
- [ ] Per-window brightness analysis
- [ ] Active/inactive window differentiation
- [ ] Adjustable brightness threshold slider
- [ ] Per-display support

### Phase 3: Region Detection
- [ ] Sub-window bright region detection
- [ ] Connected component analysis for regions
- [ ] Per-region overlays (not just per-window)
- [ ] Smooth transitions/animations

### Phase 4: Polish & Features
- [ ] App-specific exclusions
- [ ] Scheduling (dim at night)
- [ ] Sync with macOS appearance changes
- [ ] Keyboard shortcuts
- [ ] License/activation system

---

## ⚙️ Performance Considerations

| Operation | Performance Impact | Mitigation |
|-----------|-------------------|------------|
| Screen capture | Medium-High | Reduce capture frequency, downsample |
| Brightness analysis | Medium | Use Accelerate/vImage, sample grid |
| Window tracking | Low | Poll on timer, not continuous |
| Overlay rendering | Low | Metal/Core Animation layers |

**Recommended Refresh Rate:** 0.5-2 seconds per analysis cycle

---

## 📚 Reference Documentation & Code

- **MonitorControl (open source):** https://github.com/MonitorControl/MonitorControl
  - Best reference for DDC/CI + gamma + overlay techniques
  
- **Apple Documentation:**
  - Core Graphics: CGWindowList functions
  - Accelerate: vImage for image processing
  - AppKit: NSWindow for overlay windows

---

## 💡 Conclusion

SuperDimmer addresses a **genuine unmet need** in the macOS ecosystem. While display brightness control apps are plentiful, **intelligent region-specific dimming does not exist**. This creates a clear market opportunity for a well-executed solution that solves the "bright content in dark mode" problem that affects many users working in dark environments or with light-sensitive eyes.

The technical implementation is achievable with standard macOS APIs, though it requires careful attention to:
1. Screen Recording permission handling
2. Performance optimization for real-time analysis
3. Overlay window management at scale
4. User experience for configuration and feedback
