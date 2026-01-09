# SuperDimmer - Product Requirements Document (PRD)
## Intelligent Region-Specific Screen Dimming for macOS
### Version 1.0 | January 7, 2026

---

## 📋 Document Information

| Item | Details |
|------|---------|
| **Product Name** | SuperDimmer |
| **Platform** | macOS (menu bar utility) |
| **Target macOS** | 13.0+ (Ventura and later) |
| **Business Model** | Freemium with Paddle licensing |
| **Development Stack** | Swift 5.9+, SwiftUI + AppKit |

---

## 🎯 Executive Summary

### The Problem

Users working in dark environments or with light sensitivity face a common frustration: **bright content islands appearing within dark-themed applications**. Examples include:

1. **Email apps** (Mail, Outlook, Gmail) - Dark UI but emails from others often have white backgrounds
2. **Web browsers** - Dark mode browser chrome, but many websites are blindingly white
3. **Extensions & widgets** - Mixed appearance themes within apps
4. **Document viewers** - White documents in dark-themed apps
5. **Chat apps** - Dark interface but embedded content/images may be bright

Existing brightness control apps offer only **full-screen uniform dimming** - they cannot selectively dim only the bright regions while leaving dark content at normal brightness.

### The Solution

**SuperDimmer** is the **first macOS app** to offer **intelligent, automatic, region-specific dimming** of bright content. It analyzes screen content in real-time and applies targeted dimming overlays only to areas that exceed a user-defined brightness threshold.

### Market Opportunity

- **Confirmed market gap** - No existing macOS app offers region-specific brightness detection and dimming
- **Growing dark mode adoption** - Most users now prefer dark themes, making bright content more jarring
- **Remote work normalization** - More users working in varied lighting conditions
- **Eye health awareness** - Increased concern about screen strain and blue light exposure

---

## 🚀 Product Vision

> **SuperDimmer:** Your eyes' intelligent shield against bright content - dimming what hurts, preserving what doesn't.

### Core Value Propositions

1. **Region-Specific Intelligence** - Only dims bright areas, dark content stays untouched
2. **Context-Aware Dimming** - Less dimming on active windows, more on background windows
3. **Zero Configuration Needed** - Works automatically out of the box with smart defaults
4. **Professional Polish** - Beautiful UI, smooth animations, seamless integration
5. **Complete Solution** - Combines bright spot dimming + wallpaper management + color temperature

---

## 👥 Target Users

### Primary Personas

| Persona | Description | Key Pain Points |
|---------|-------------|-----------------|
| **Night Owl Developer** | Works late in dark environment | Bright terminal output, white web docs, mixed-theme IDEs |
| **Light-Sensitive Professional** | Medical condition or preference | Any unexpected bright content causes discomfort |
| **Media Creative** | Video/photo editor in dark room | Need accurate colors but bright UI elements strain eyes |
| **Remote Worker** | Home office with varied lighting | Switching between light/dark environments |

### Secondary Personas

- Power users seeking granular control over display appearance
- Users with multiple monitors wanting different brightness zones
- Users who want automatic light/dark wallpaper switching (Umbra-style feature)

---

## 🎁 Feature Specification

### Feature Categories

```
┌─────────────────────────────────────────────────────────────────┐
│                    SuperDimmer Feature Map                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ CORE: Intelligent Bright Region Dimming                   │   │
│  │ • Real-time brightness detection                          │   │
│  │ • Per-region overlay dimming                              │   │
│  │ • Active/inactive window differentiation                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ COMFORT: Color Temperature & Scheduling                   │   │
│  │ • Blue light filter (f.lux-style)                         │   │
│  │ • Time-based scheduling                                   │   │
│  │ • Sunrise/sunset automation                               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ AESTHETICS: Wallpaper Management (Umbra-style)            │   │
│  │ • Light/dark wallpaper pairs                              │   │
│  │ • Automatic switching with appearance                     │   │
│  │ • Wallpaper dimming                                       │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ PRO: Advanced Controls                                    │   │
│  │ • Per-app rules and exclusions                            │   │
│  │ • Per-display settings                                    │   │
│  │ • Keyboard shortcuts                                      │   │
│  │ • Scheduled profiles                                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 🔥 CORE FEATURE: Intelligent Bright Region Dimming

**This is SuperDimmer's unique differentiator - no other app does this.**

#### Feature: Real-Time Brightness Detection

| Attribute | Specification |
|-----------|---------------|
| **Description** | Continuously analyze screen content to identify regions exceeding brightness threshold |
| **Scan Frequency** | 0.5 - 2 seconds (user configurable) |
| **Detection Method** | Luminance calculation using Rec. 709: `Y' = 0.2126×R + 0.7152×G + 0.0722×B` |
| **Granularity** | Grid-based sampling (configurable: per-window, per-region, per-pixel-block) |
| **Performance** | Accelerate/vImage framework for SIMD optimization |

**User Controls:**
- **Brightness Threshold Slider**: 0-100% (default: 85%)
  - "Only dim very bright content" → 95%
  - "Dim moderately bright content" → 70%
  - "Dim anything not truly dark" → 50%

#### Feature: Region-Specific Overlay Dimming

| Attribute | Specification |
|-----------|---------------|
| **Description** | Apply transparent dimming overlays only to detected bright regions |
| **Overlay Type** | NSWindow with `ignoresMouseEvents = true` (click-through) |
| **Window Level** | `.screenSaver` or custom CGWindowLevel (above content, below system UI) |
| **Behavior** | Joins all Spaces, works with fullscreen apps |
| **Animation** | Smooth fade in/out transitions (0.2-0.3s) |

**Dimming Levels:**
- Minimum dimming: 0% (effectively off)
- Maximum dimming: 80% (near black but content still visible)
- Default: 25% for active windows, 40% for inactive windows

#### Feature: Active vs Inactive Window Differentiation

| Attribute | Specification |
|-----------|---------------|
| **Description** | Apply different dimming intensity based on window focus state |
| **Detection** | Track `NSWorkspace.shared.frontmostApplication` |
| **Active Window** | Window belongs to frontmost app → lighter dimming |
| **Inactive Windows** | All other visible windows → heavier dimming |
| **Rationale** | Preserves visibility of content you're actively using |

**User Controls:**
- Active window dim amount: 0-50% (default: 15%)
- Inactive window dim amount: 0-80% (default: 35%)
- Option to disable differentiation (uniform dimming)

---

### 🌡️ COMFORT FEATURE: Color Temperature & Scheduling

**Similar to f.lux - provides blue light filtering for additional eye comfort.**

#### Feature: Color Temperature Adjustment

| Attribute | Specification |
|-----------|---------------|
| **Description** | Shift display color temperature to reduce blue light |
| **Implementation** | Gamma table manipulation via `CGSetDisplayTransferByTable` |
| **Temperature Range** | 6500K (daylight) → 1900K (candlelight) |
| **Default Presets** | Daylight (6500K), Sunset (4100K), Night (2700K), Bedtime (1900K) |

#### Feature: Time-Based Scheduling

| Attribute | Specification |
|-----------|---------------|
| **Description** | Automatically adjust color temperature based on time of day |
| **Schedule Types** | Manual times, Sunrise/Sunset (location-based), Custom profiles |
| **Transition** | Gradual shift over user-defined duration (default: 60 minutes) |
| **Location** | CoreLocation for sunrise/sunset calculation |

---

### 🖼️ AESTHETICS FEATURE: Wallpaper Management

**Inspired by Umbra - automatic wallpaper switching with appearance mode.**

#### Feature: Light/Dark Wallpaper Pairs

| Attribute | Specification |
|-----------|---------------|
| **Description** | Set different wallpapers for Light Mode and Dark Mode |
| **Switching** | Automatic when macOS appearance changes |
| **Per-Space Support** | Different pairs for each Space/Desktop |
| **Per-Display Support** | Different pairs for each connected display |

#### Feature: Wallpaper Dimming

| Attribute | Specification |
|-----------|---------------|
| **Description** | Apply dimming overlay specifically to desktop wallpaper |
| **Use Case** | Reduce bright wallpaper distraction without affecting windows |
| **Dim Amount** | 0-80% adjustable |
| **Schedule** | Can follow color temperature schedule |

---

### 🧹 PRODUCTIVITY FEATURE: Inactivity Management

**Smart window and app management based on usage patterns.**

#### Feature: Inactivity Decay Dimming (Window-Level)

| Attribute | Specification |
|-----------|---------------|
| **Description** | Windows progressively dim based on how long they've been inactive |
| **Level** | Per-WINDOW (not per-app) - each window tracks independently |
| **Formula** | `dimLevel = decayRate × max(0, inactiveTime - decayStartDelay)` |
| **Reset** | When window becomes frontmost, decay resets to 0 |
| **Visual Effect** | Creates natural hierarchy - active window clear, stale windows faded |

**User Controls:**
- **Enable/Disable Toggle**: On/Off (default: Off)
- **Fade Speed**: Slow (0.5%/s) / Medium (1%/s) / Fast (2%/s)
- **Decay Start Delay**: How long before decay begins (default: 30 seconds)
- **Max Fade Level**: Cap on how dark windows can get (0-100%, default: 80%)

#### Feature: Auto-Hide Inactive Apps (App-Level)

| Attribute | Specification |
|-----------|---------------|
| **Description** | Automatically hide entire apps that haven't been used |
| **Level** | Per-APP (uses `NSRunningApplication.hide()`) |
| **Trigger** | App not frontmost for configured duration |
| **Exclusions** | System apps (Finder), user-defined apps |
| **Recovery** | Apps remain in Dock, easily unhidden |

**User Controls:**
- **Enable/Disable Toggle**: On/Off (default: Off)
- **Hide After**: Time before hiding (5-120 minutes, default: 30)
- **Excluded Apps**: List of bundle IDs to never hide
- **Exclude System Apps**: Checkbox (default: On)

#### Feature: Auto-Minimize Inactive Windows (Window-Level)

| Attribute | Specification |
|-----------|---------------|
| **Description** | Minimize oldest inactive windows when app has too many open |
| **Level** | Per-WINDOW (uses `NSWindow.miniaturize()`) |
| **Intelligence** | Only counts ACTIVE usage time (pauses when user idle) |
| **Threshold** | Per-app: "Keep at least N windows, minimize extras" |
| **Idle Reset** | All timers reset after extended user idle (prevents overnight minimize) |

**User Controls:**
- **Enable/Disable Toggle**: On/Off (default: Off)
- **Minimize After**: Active usage time before minimize (5-60 min, default: 15)
- **Reset After Idle**: User idle time to reset all timers (2-30 min, default: 5)
- **Keep At Least**: Minimum windows per app (1-10, default: 3)
- **Excluded Apps**: List of bundle IDs to never auto-minimize

**Why This Feature:**
During a workday, you might open 15 browser windows or 8 IDE instances.
Instead of manually closing them, SuperDimmer minimizes the oldest inactive
windows while keeping your most recent work accessible. Walking away overnight
won't minimize everything because timers reset after idle.

---

### ⚡ PRO FEATURES: Advanced Controls

**Premium features for power users - requires Pro license.**

#### Feature: Per-App Rules

| Attribute | Specification |
|-----------|---------------|
| **Description** | Customize dimming behavior for specific applications |
| **Rule Types** | Always dim, Never dim, Custom threshold, Custom dim amount |
| **App Selection** | Browse running apps or select from /Applications |

#### Feature: Per-Display Settings

| Attribute | Specification |
|-----------|---------------|
| **Description** | Different brightness thresholds and dim amounts per monitor |
| **Detection** | Automatic display identification |
| **Profiles** | Save and switch between display configurations |

#### Feature: Keyboard Shortcuts

| Attribute | Specification |
|-----------|---------------|
| **Description** | Quick access to common controls via keyboard |
| **Implementation** | Using KeyboardShortcuts library (like MonitorControlLite) |
| **Default Shortcuts** | Toggle on/off, increase/decrease dim, cycle presets |

#### Feature: Scheduled Profiles

| Attribute | Specification |
|-----------|---------------|
| **Description** | Different settings for different times/contexts |
| **Profile Examples** | "Daytime Work", "Evening Relaxation", "Movie Night", "Late Night Coding" |
| **Triggers** | Time-based, Location-based, Manual switching |

---

## 🏗️ Technical Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SuperDimmer System Architecture                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                        Menu Bar Interface                          │  │
│   │    [Icon] → Quick Toggles | Sliders | Settings | Preferences      │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│                                    ▼                                     │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                      Settings Manager                              │  │
│   │    UserDefaults | Profiles | Per-App Rules | License State        │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                    │                                     │
│           ┌────────────────────────┼────────────────────────┐           │
│           │                        │                        │           │
│           ▼                        ▼                        ▼           │
│   ┌──────────────┐      ┌──────────────────┐      ┌────────────────┐   │
│   │  Screen      │      │  Window          │      │  Appearance    │   │
│   │  Capture     │      │  Tracker         │      │  Observer      │   │
│   │  Service     │      │  Service         │      │  Service       │   │
│   │              │      │                  │      │                │   │
│   │CGWindowList  │      │CGWindowListCopy  │      │NSAppearance    │   │
│   │CreateImage   │      │WindowInfo        │      │EffectiveChange │   │
│   └──────┬───────┘      └────────┬─────────┘      └───────┬────────┘   │
│          │                       │                        │            │
│          └───────────────┬───────┴────────────────────────┘            │
│                          │                                              │
│                          ▼                                              │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                    Brightness Analysis Engine                      │  │
│   │                                                                    │  │
│   │   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐   │  │
│   │   │  Downsampler   │──▶│  Luminance     │──▶│  Region        │   │  │
│   │   │  (vImage)      │   │  Calculator    │   │  Detector      │   │  │
│   │   │                │   │  (Rec. 709)    │   │  (Components)  │   │  │
│   │   └────────────────┘   └────────────────┘   └────────────────┘   │  │
│   │                                                                    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                          │                                              │
│                          ▼                                              │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                     Overlay Manager                                │  │
│   │                                                                    │  │
│   │   • Creates/updates/removes DimOverlayWindow instances            │  │
│   │   • Manages window lifecycle and z-ordering                        │  │
│   │   • Animates opacity transitions                                   │  │
│   │   • Handles multi-display coordination                             │  │
│   │                                                                    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                          │                                              │
│                          ▼                                              │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                     Color Temperature Engine                       │  │
│   │                                                                    │  │
│   │   • CGSetDisplayTransferByTable for gamma control                 │  │
│   │   • Kelvin → RGB gamma curve calculation                          │  │
│   │   • Smooth transition animations                                   │  │
│   │                                                                    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                          │                                              │
│                          ▼                                              │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │                     Wallpaper Manager                              │  │
│   │                                                                    │  │
│   │   • NSWorkspace wallpaper APIs                                    │  │
│   │   • AppleScript for appearance toggle (like f.lux)                │  │
│   │   • Per-space wallpaper configuration                              │  │
│   │                                                                    │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### Core Technical Components

#### 1. Screen Capture Service

**Purpose:** Capture screen content for brightness analysis

**Implementation Pattern (from research):**
```swift
// Based on BetterDisplay/MonitorControl approaches
// Requires Screen Recording permission

import CoreGraphics

final class ScreenCaptureService {
    
    /// Captures the entire main display for brightness analysis
    /// Uses CGDisplayCreateImage which requires Screen Recording permission
    /// Returns downsampled image for performance (analyzing full resolution not needed)
    func captureMainDisplay() -> CGImage? {
        let displayID = CGMainDisplayID()
        return CGDisplayCreateImage(displayID)
    }
    
    /// Captures a specific screen region for targeted analysis
    /// Useful for analyzing only visible window regions
    func captureRegion(_ rect: CGRect) -> CGImage? {
        return CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }
}
```

**Key Learnings from Reference Apps:**
- **f.lux** and **MonitorControlLite** do NOT use screen capture - they modify gamma/overlays
- **SuperDimmer UNIQUELY requires screen capture** for brightness detection
- Must handle permission gracefully with clear user messaging

---

#### 2. Window Tracker Service

**Purpose:** Track visible windows and their ownership for active/inactive differentiation

**Implementation Pattern (from research):**
```swift
import AppKit
import CoreGraphics

/// Represents a visible window on screen with its metadata
/// Used to determine which windows need dimming and at what level
struct TrackedWindow {
    let windowID: CGWindowID       // Unique identifier for this window
    let ownerPID: pid_t            // Process ID of owning application
    let ownerName: String          // Application name (e.g., "Safari")
    let bounds: CGRect             // Window position and size
    let layer: Int                 // Window layer (z-order)
    let title: String              // Window title if available
    let isActive: Bool             // True if belongs to frontmost app
}

final class WindowTrackerService {
    
    /// Gets all visible windows with their metadata
    /// Filters out desktop elements, menu bar, dock, etc.
    func getVisibleWindows() -> [TrackedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) 
              as? [[String: Any]] else {
            return []
        }
        
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        
        return infoList.compactMap { info -> TrackedWindow? in
            // Parse window info dict into TrackedWindow struct
            // Mark windows from frontmost app as "active"
        }
    }
}
```

---

#### 3. Brightness Analysis Engine

**Purpose:** Analyze captured screen regions to detect bright content

**Implementation Pattern (from research):**
```swift
import Accelerate
import CoreGraphics

/// Engine for detecting bright regions in screen captures
/// Uses Accelerate framework for high-performance SIMD operations
final class BrightnessAnalysisEngine {
    
    /// Brightness threshold - regions brighter than this trigger dimming
    /// Range 0.0-1.0, default 0.85 (85% brightness)
    var brightnessThreshold: Float = 0.85
    
    /// Calculates average luminance for a screen region using Rec. 709 formula
    /// Y' = 0.2126×R + 0.7152×G + 0.0722×B
    /// Returns value from 0.0 (black) to 1.0 (white)
    func averageLuminance(in image: CGImage, rect: CGRect) -> Float? {
        // 1. Extract pixels using vImage
        // 2. Apply luminance coefficients
        // 3. Return average
    }
    
    /// Detects distinct bright regions within an image
    /// Uses grid-based sampling for performance
    /// Returns bounding boxes of regions exceeding threshold
    func detectBrightRegions(in image: CGImage) -> [CGRect] {
        // 1. Downsample for performance
        // 2. Calculate luminance grid
        // 3. Threshold to binary
        // 4. Connected component analysis
        // 5. Return bounding rectangles
    }
}
```

**Performance Optimizations (learned from reference apps):**
- **Downsample first** - Don't analyze at full resolution
- **Grid sampling** - Check brightness at regular intervals, not every pixel
- **Cache results** - Only re-analyze when content likely changed
- **Background thread** - Don't block main thread during analysis

---

#### 4. Overlay Manager

**Purpose:** Create and manage transparent dimming overlay windows

**Implementation Pattern (from MonitorControlLite/Lunar):**
```swift
import AppKit

/// Transparent overlay window that dims content beneath it
/// Configured to be click-through so it doesn't interfere with mouse events
/// Appears on all Spaces and works with fullscreen apps
final class DimOverlayWindow: NSWindow {
    
    init(frame: CGRect, screen: NSScreen, dimLevel: CGFloat) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // CRITICAL: These settings make the overlay non-intrusive
        // Learned from MonitorControlLite and Lunar implementations
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true       // Let clicks pass through
        self.level = .screenSaver            // High z-order but below critical UI
        self.collectionBehavior = [
            .canJoinAllSpaces,               // Appear on all Spaces
            .fullScreenAuxiliary,            // Work with fullscreen apps
            .stationary                      // Don't move with window dragging
        ]
        
        // The dimming view - a black semi-transparent layer
        let dimView = NSView(frame: frame)
        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimLevel).cgColor
        self.contentView = dimView
    }
    
    /// Animate opacity change for smooth transitions
    /// Prevents jarring sudden darkness changes
    func setDimLevel(_ level: CGFloat, animated: Bool = true) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = animated ? 0.25 : 0
        contentView?.layer?.add(animation, forKey: "opacity")
        contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(level).cgColor
    }
}

/// Manages lifecycle of all overlay windows
/// Creates, updates, removes overlays as bright regions change
final class OverlayManager {
    private var activeOverlays: [CGWindowID: DimOverlayWindow] = [:]
    
    /// Update overlays based on detected bright regions
    /// Creates new overlays, updates existing ones, removes stale ones
    func updateOverlays(for brightRegions: [(window: TrackedWindow, regions: [CGRect])]) {
        // Implementation details...
    }
}
```

---

#### 5. Color Temperature Engine

**Purpose:** Adjust display color temperature for blue light filtering

**Implementation Pattern (from f.lux analysis):**
```swift
import CoreGraphics

/// Controls display color temperature via gamma table manipulation
/// Based on f.lux implementation approach
final class ColorTemperatureEngine {
    
    /// Current color temperature in Kelvin
    /// Range: 1900K (candlelight) to 6500K (daylight)
    private var currentTemperature: Int = 6500
    
    /// Apply color temperature to display using gamma tables
    /// Uses CGSetDisplayTransferByTable API
    func setTemperature(_ kelvin: Int, for displayID: CGDirectDisplayID) {
        // 1. Calculate RGB multipliers from Kelvin value
        // 2. Generate gamma table curves
        // 3. Apply via CGSetDisplayTransferByTable
    }
    
    /// Convert Kelvin temperature to RGB multipliers
    /// Algorithm based on Tanner Helland's approximation
    private func kelvinToRGB(_ kelvin: Int) -> (r: Float, g: Float, b: Float) {
        // Temperature conversion algorithm
    }
}
```

---

### Required Permissions & Entitlements

#### Entitlements File (SuperDimmer.entitlements)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Screen capture for brightness analysis (UNIQUE to SuperDimmer) -->
    <key>com.apple.security.device.screen-capture</key>
    <true/>
    
    <!-- Network for license validation and update checks -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- AppleEvents for wallpaper/appearance control (like f.lux/Umbra) -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    
    <!-- Location for sunrise/sunset (like f.lux) -->
    <key>com.apple.security.personal-information.location</key>
    <true/>
</dict>
</plist>
```

#### User Permission Requests

| Permission | Purpose | When Requested |
|------------|---------|----------------|
| **Screen Recording** | Capture screen for brightness analysis | First launch or when enabling bright region detection |
| **Location** | Calculate sunrise/sunset times | When enabling "Automatic" color temperature schedule |
| **Automation/AppleEvents** | Toggle appearance mode, set wallpapers | When using wallpaper switching features |

**Permission Handling Strategy:**
- Request permissions just-in-time, not at launch
- Provide clear explanations of why each permission is needed
- Gracefully degrade features if permission denied
- Show settings deep-link to manually grant permissions

---

### Info.plist Key Settings

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Bundle Identity -->
    <key>CFBundleIdentifier</key>
    <string>com.superdimmer.app</string>
    <key>CFBundleName</key>
    <string>SuperDimmer</string>
    <key>CFBundleDisplayName</key>
    <string>SuperDimmer</string>
    
    <!-- Version -->
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    
    <!-- Menu Bar App (no dock icon) - like all reference apps -->
    <key>LSUIElement</key>
    <true/>
    
    <!-- App Category - same as reference apps -->
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    
    <!-- Minimum macOS -->
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    
    <!-- Application Type -->
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    
    <!-- Permission Descriptions -->
    <key>NSScreenCaptureUsageDescription</key>
    <string>SuperDimmer needs screen access to detect bright areas and apply intelligent dimming.</string>
    
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>SuperDimmer uses your location to calculate sunrise and sunset times for automatic color temperature adjustments.</string>
    
    <key>NSAppleEventsUsageDescription</key>
    <string>SuperDimmer needs this permission to change wallpapers and toggle between Light and Dark mode.</string>
    
    <!-- Sparkle Auto-Updates (like BetterDisplay, f.lux, Umbra) -->
    <key>SUFeedURL</key>
    <string>https://superdimmer.app/sparkle/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>[EdDSA public key goes here]</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    
    <!-- Graceful termination -->
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    
    <!-- Copyright -->
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 SuperDimmer. All rights reserved.</string>
</dict>
</plist>
```

---

## 💰 Business Model & Licensing

### Model: Freemium with Paddle

**Why Paddle? (based on reference app analysis)**

| Factor | Paddle | Mac App Store |
|--------|--------|---------------|
| Commission | ~5% + $0.50 | 15-30% |
| Screen Recording | ✅ Allowed | ⚠️ May limit |
| Private APIs | ✅ Allowed | ❌ Prohibited |
| Trial Support | ✅ Built-in | ❌ Not supported |
| License Flexibility | ✅ Full control | ❌ Apple's rules |

**BetterDisplay uses Paddle successfully** with a similar freemium model.

### Tier Structure

#### Free Tier (No License Required)

| Feature | Included |
|---------|----------|
| Full-screen uniform dimming | ✅ |
| Basic brightness threshold | ✅ |
| Menu bar controls | ✅ |
| Single display support | ✅ |
| Basic keyboard shortcuts | ✅ |

#### Pro License ($19.99 one-time)

| Feature | Pro Only |
|---------|----------|
| Intelligent region detection | ⭐ |
| Active/inactive differentiation | ⭐ |
| Per-app rules | ⭐ |
| Multi-display support | ⭐ |
| Color temperature control | ⭐ |
| Wallpaper management | ⭐ |
| Scheduled profiles | ⭐ |
| Priority support | ⭐ |

### License Implementation (Paddle SDK)

```swift
import Paddle

/// Handles license validation and feature gating
/// Based on BetterDisplay's Paddle implementation
final class LicenseManager {
    
    enum LicenseState {
        case unlicensedFree        // Free tier only
        case trialActive(daysLeft: Int)
        case proActivated
        case trialExpired
    }
    
    private let paddle: Paddle
    var currentState: LicenseState = .unlicensedFree
    
    /// Check if a Pro feature should be available
    func isProFeatureAvailable() -> Bool {
        switch currentState {
        case .proActivated, .trialActive:
            return true
        case .unlicensedFree, .trialExpired:
            return false
        }
    }
    
    /// Activate license with key from Paddle
    func activateLicense(_ key: String) async throws {
        // Paddle SDK activation
    }
}
```

---

## 🎨 User Interface Design

### Menu Bar Presence

Like all reference apps (BetterDisplay, f.lux, Umbra, MonitorControlLite), SuperDimmer is a **menu bar app** with no dock icon.

#### Menu Bar Icon States

| State | Icon Appearance |
|-------|-----------------|
| Disabled | Outline/empty sun icon |
| Active (dimming) | Filled sun icon with dim effect |
| Color temp active | Sun icon with warm tint |
| Overlay active | Sun icon with half-shaded |

### Menu Bar Dropdown

```
┌────────────────────────────────────────┐
│  SuperDimmer                    Pro ✓  │
├────────────────────────────────────────┤
│  ☀️ Brightness Detection     [Toggle]  │
│     Threshold: ████████░░ 80%          │
│                                        │
│  👁️ Active Window Dim         15%     │
│     Inactive Window Dim       35%      │
│                                        │
├────────────────────────────────────────┤
│  🌡️ Color Temperature        [Toggle]  │
│     Current: 4800K (Sunset)            │
│     ████████████░░░ ←→                 │
│                                        │
├────────────────────────────────────────┤
│  🖼️ Wallpaper Auto-Switch    [Toggle]  │
│                                        │
├────────────────────────────────────────┤
│  ⚙️ Preferences...                     │
│  📊 About SuperDimmer                  │
│  ❌ Quit                               │
└────────────────────────────────────────┘
```

### Preferences Window

**Tabs:**
1. **General** - Enable/disable, launch at login, keyboard shortcuts
2. **Brightness** - Threshold, dim amounts, scan frequency
3. **Color** - Temperature schedules, presets, transition duration
4. **Wallpaper** - Light/dark pairs, per-space settings
5. **Apps** - Per-app rules and exclusions
6. **Displays** - Per-display settings
7. **License** - Pro activation, trial status

---

## 📅 Implementation Phases

### Phase 1: Foundation (MVP) - 4 weeks

**Goal:** Working menu bar app with basic full-screen dimming

| Task | Description | Priority |
|------|-------------|----------|
| Xcode project setup | Swift, SwiftUI + AppKit, proper entitlements | P0 |
| Menu bar app skeleton | NSStatusItem, basic dropdown | P0 |
| Full-screen overlay | DimOverlayWindow implementation | P0 |
| Basic controls | On/off toggle, dim level slider | P0 |
| Permission handling | Screen Recording request flow | P0 |
| Persistence | UserDefaults for settings | P0 |

**Deliverable:** App that can dim entire screen with adjustable opacity

---

### Phase 2: Intelligent Detection - 3 weeks

**Goal:** Detect bright regions and dim them specifically

| Task | Description | Priority |
|------|-------------|----------|
| Screen capture service | CGWindowListCreateImage integration | P0 |
| Brightness analysis | vImage/Accelerate luminance calculation | P0 |
| Window tracking | CGWindowListCopyWindowInfo integration | P0 |
| Per-window overlays | Multiple overlay windows | P0 |
| Active/inactive logic | Frontmost app detection | P0 |
| Performance optimization | Downsampling, caching, throttling | P1 |

**Deliverable:** Working intelligent region-specific dimming

---

### Phase 3: Comfort Features - 2 weeks

**Goal:** Color temperature control and scheduling

| Task | Description | Priority |
|------|-------------|----------|
| Gamma table engine | CGSetDisplayTransferByTable | P0 |
| Temperature UI | Slider with presets | P0 |
| Schedule system | Time-based profiles | P1 |
| Location service | CoreLocation for sunrise/sunset | P1 |
| Smooth transitions | Animated temperature changes | P1 |

**Deliverable:** f.lux-style color temperature control

---

### Phase 4: Wallpaper Features - 2 weeks

**Goal:** Umbra-style wallpaper management

| Task | Description | Priority |
|------|-------------|----------|
| Wallpaper manager | NSWorkspace wallpaper APIs | P0 |
| Light/dark pairs | UI for setting pairs | P0 |
| Auto-switching | Appearance change observer | P0 |
| Wallpaper dimming | Desktop overlay option | P1 |
| Per-space support | Space detection and config | P2 |

**Deliverable:** Automatic wallpaper switching with appearance

---

### Phase 5: Pro Features & Polish - 3 weeks

**Goal:** Premium features and production polish

| Task | Description | Priority |
|------|-------------|----------|
| Paddle integration | License validation, trial, activation | P0 |
| Per-app rules | Rule engine and UI | P0 |
| Multi-display | Per-display settings | P0 |
| Keyboard shortcuts | KeyboardShortcuts framework | P1 |
| Sparkle updates | Auto-update integration | P1 |
| Preferences polish | Beautiful settings window | P1 |
| Onboarding | First-run experience | P1 |

**Deliverable:** Feature-complete Pro version

---

### Phase 6: Launch Preparation - 2 weeks

**Goal:** Marketing-ready release

| Task | Description | Priority |
|------|-------------|----------|
| Website | Landing page with purchase | P0 |
| Documentation | Help docs, FAQ | P0 |
| App notarization | Apple notarization for Gatekeeper | P0 |
| Sparkle appcast | Update feed setup | P0 |
| Beta testing | TestFlight or manual distribution | P1 |
| Marketing materials | Screenshots, video demo | P1 |

**Deliverable:** Publicly launchable product

---

## ⚡ Performance Requirements

| Metric | Target | Measurement |
|--------|--------|-------------|
| CPU usage (idle) | < 0.5% | Activity Monitor |
| CPU usage (active analysis) | < 5% | Activity Monitor |
| Memory footprint | < 50 MB | Activity Monitor |
| Analysis cycle time | < 100ms | Instruments |
| Overlay creation time | < 16ms | Frame timing |
| Time to first dim | < 2 seconds | User-perceived |

### Performance Strategies

1. **Downsample captures** - Analyze at 1/4 or 1/8 resolution
2. **Grid sampling** - Don't analyze every pixel
3. **Change detection** - Skip analysis if screen unchanged
4. **Background processing** - Never block main thread
5. **Lazy overlay creation** - Don't create overlays until needed
6. **Recycle overlay windows** - Reuse instead of create/destroy

---

## 🧪 Testing Requirements

### Unit Tests

- Luminance calculation accuracy
- Region detection algorithms
- Window tracking logic
- Settings persistence
- License state transitions

### Integration Tests

- Screen capture permission flow
- Overlay window behavior
- Multi-display scenarios
- Appearance change response
- Wallpaper switching

### Manual Test Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| Open white webpage in dark browser | Bright region detected and dimmed |
| Switch between apps | Active/inactive dim levels swap |
| Add external display | New display detected and handled |
| Enter fullscreen mode | Overlays follow correctly |
| Fast window switching | No flickering or lag |
| System sleep/wake | State preserved, resumes correctly |

---

## 📚 Dependencies & Frameworks

### Apple Frameworks

| Framework | Purpose |
|-----------|---------|
| SwiftUI | Modern UI components |
| AppKit | NSWindow, NSStatusItem, menu bar |
| CoreGraphics | Screen capture, display control |
| Accelerate | vImage for fast image processing |
| CoreLocation | Sunrise/sunset calculation |
| ServiceManagement | Launch at login |

### Third-Party Libraries

| Library | Purpose | License |
|---------|---------|---------|
| **Paddle SDK** | License management | Commercial (free to integrate) |
| **Sparkle** | Auto-updates | MIT |
| **KeyboardShortcuts** | Keyboard shortcut recording | MIT |

### Open Source References

- **MonitorControl** (https://github.com/MonitorControl/MonitorControl) - Overlay and gamma techniques
- **Lunar** (if available) - Advanced display control patterns

---

## 🔐 Security Considerations

1. **Screen Recording Permission** - Only capture when actively analyzing; never record or store
2. **License Validation** - Paddle handles securely; no license keys stored in plain text
3. **Network Communication** - HTTPS only; certificate pinning for license API
4. **Code Signing** - Developer ID for distribution; hardened runtime
5. **Notarization** - Required for Gatekeeper on macOS 10.15+

---

## 📊 Success Metrics

### Launch Targets (First 90 Days)

| Metric | Target |
|--------|--------|
| Downloads | 5,000+ |
| Pro conversions | 5-10% |
| Trial starts | 30% |
| Trial-to-paid | 20% |
| Support tickets | < 2% of users |
| Crash-free rate | 99.5% |

### Long-term Goals (Year 1)

| Metric | Target |
|--------|--------|
| Active users | 25,000+ |
| Pro licenses sold | 2,500+ |
| Revenue | $50,000+ |
| App Store rating | 4.5+ stars |
| User retention (30-day) | 60%+ |

---

## 📝 Appendices

### Appendix A: Competitive Feature Matrix

| Feature | SuperDimmer | Lunar | MonitorControl | f.lux | Umbra |
|---------|------------|-------|----------------|-------|-------|
| Region-specific dimming | ✅ **UNIQUE** | ❌ | ❌ | ❌ | ❌ |
| Full-screen dimming | ✅ | ✅ | ✅ | ✅ | ❌ |
| Active/inactive differentiation | ✅ **UNIQUE** | ❌ | ❌ | ❌ | ❌ |
| Color temperature | ✅ | ✅ | ❌ | ✅ | ❌ |
| Wallpaper switching | ✅ | ❌ | ❌ | ❌ | ✅ |
| DDC/CI hardware control | ❌ | ✅ | ✅ | ❌ | ❌ |
| Per-app rules | ✅ | ✅ | ❌ | ✅ | ❌ |

### Appendix B: Reference App Licensing Comparison

| App | Method | Commission | Notes |
|-----|--------|------------|-------|
| BetterDisplay | Paddle SDK | ~5% | Freemium, trial, perpetual |
| MonitorControlLite | Mac App Store | 15-30% | Paid upfront |
| f.lux | Freeware | 0% | Donations only |
| Umbra | Gumroad (PWYW) | ~5% | Pay what you want |

**Recommendation:** Follow BetterDisplay's Paddle approach for maximum flexibility and revenue.

### Appendix C: Technical Reference Links

- Apple CGWindow: https://developer.apple.com/documentation/coregraphics/quartz_window_services
- Accelerate vImage: https://developer.apple.com/documentation/accelerate/vimage
- NSWindow Levels: https://developer.apple.com/documentation/appkit/nswindow/level
- Paddle SDK: https://developer.paddle.com/
- Sparkle: https://sparkle-project.org/documentation/

---

*Document Version: 1.0*  
*Last Updated: January 7, 2026*  
*Status: Ready for Development*
