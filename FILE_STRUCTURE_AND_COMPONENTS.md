# SuperDimmer - File Structure & Components
## Complete Project Architecture with Descriptive File Names
### Version 1.0 | January 7, 2026

---

## 📁 Complete File Tree

```
SuperDimmer-Mac-App/
│
├── SuperDimmer.xcodeproj/                    # Xcode project file
│   ├── project.pbxproj                       # Project configuration
│   └── xcshareddata/                         # Shared schemes
│       └── xcschemes/
│           └── SuperDimmer.xcscheme
│
├── SuperDimmer/                              # Main app target source
│   │
│   ├── App/                                  # Application entry point and lifecycle
│   │   ├── SuperDimmerApp.swift              # @main entry, app delegate setup
│   │   └── AppDelegate.swift                 # NSApplicationDelegate for menu bar app
│   │
│   ├── MenuBar/                              # Menu bar UI components
│   │   ├── MenuBarController.swift           # NSStatusItem management, icon states
│   │   ├── MenuBarView.swift                 # SwiftUI popover content
│   │   ├── QuickControlsView.swift           # Toggles and sliders in dropdown
│   │   └── MenuBarIconStateManager.swift     # Icon appearance based on app state
│   │
│   ├── Preferences/                          # Preferences window and tabs
│   │   ├── PreferencesWindowController.swift # NSWindowController for preferences
│   │   ├── PreferencesView.swift             # Main preferences container (tabs)
│   │   ├── GeneralPreferencesTab.swift       # General settings (launch at login, etc.)
│   │   ├── BrightnessPreferencesTab.swift    # Threshold, dim levels, scan frequency
│   │   ├── ColorTemperaturePreferencesTab.swift  # Temperature, schedule, presets
│   │   ├── WallpaperPreferencesTab.swift     # Wallpaper pairs, auto-switch
│   │   ├── AppRulesPreferencesTab.swift      # Per-app dimming rules
│   │   ├── DisplaysPreferencesTab.swift      # Per-display settings
│   │   └── LicensePreferencesTab.swift       # Pro license activation
│   │
│   ├── Overlay/                              # Dimming overlay window system
│   │   ├── DimOverlayWindow.swift            # NSWindow subclass for transparent overlay
│   │   ├── OverlayManager.swift              # Lifecycle management for all overlays
│   │   ├── OverlayAnimator.swift             # Smooth fade transitions
│   │   └── OverlayPositionTracker.swift      # Tracks window positions for overlay placement
│   │
│   ├── ScreenCapture/                        # Screen capture for brightness analysis
│   │   ├── ScreenCaptureService.swift        # CGWindowListCreateImage wrapper
│   │   ├── ScreenCapturePermissionHandler.swift  # Permission request flow
│   │   └── CaptureThrottler.swift            # Rate limiting for performance
│   │
│   ├── BrightnessAnalysis/                   # Core brightness detection engine
│   │   ├── BrightnessAnalysisEngine.swift    # Main analysis coordinator
│   │   ├── LuminanceCalculator.swift         # Rec. 709 luminance calculation
│   │   ├── ImageDownsampler.swift            # Reduces resolution for faster analysis
│   │   ├── BrightRegionDetector.swift        # Finds regions above threshold
│   │   └── BrightnessCache.swift             # Caches results to reduce re-analysis
│   │
│   ├── WindowTracking/                       # Window tracking and state
│   │   ├── WindowTrackerService.swift        # CGWindowListCopyWindowInfo wrapper
│   │   ├── TrackedWindow.swift               # Model for window metadata
│   │   ├── ActiveWindowDetector.swift        # Frontmost app tracking
│   │   └── WindowChangeObserver.swift        # Detects window add/remove/move
│   │
│   ├── DimmingCoordinator/                   # Main dimming logic coordinator
│   │   ├── DimmingCoordinator.swift          # Orchestrates analysis → overlay pipeline
│   │   ├── DimmingDecision.swift             # Model for per-window dim decisions
│   │   ├── DimmingLoop.swift                 # Timer-based analysis loop
│   │   └── DimmingConfiguration.swift        # Runtime configuration holder
│   │
│   ├── ColorTemperature/                     # Color temperature (f.lux-style)
│   │   ├── ColorTemperatureEngine.swift      # Gamma table manipulation
│   │   ├── KelvinToRGBConverter.swift        # Temperature to RGB multipliers
│   │   ├── GammaTableGenerator.swift         # Creates gamma LUT tables
│   │   ├── TemperatureTransitionAnimator.swift   # Smooth temperature transitions
│   │   └── TemperaturePresets.swift          # Daylight, Sunset, Night, etc.
│   │
│   ├── Scheduling/                           # Time-based automation
│   │   ├── ScheduleManager.swift             # Manages all schedules
│   │   ├── TimeSchedule.swift                # Manual time-based schedule
│   │   ├── SunBasedSchedule.swift            # Sunrise/sunset schedule
│   │   ├── ScheduleTrigger.swift             # Fires events at schedule times
│   │   └── ScheduleTransitionCalculator.swift    # Calculates gradual transition values
│   │
│   ├── Location/                             # Location for sunrise/sunset
│   │   ├── LocationService.swift             # CoreLocation wrapper
│   │   ├── SunriseSunsetCalculator.swift     # Calculates sun times from coordinates
│   │   └── LocationPermissionHandler.swift   # Permission request flow
│   │
│   ├── Wallpaper/                            # Wallpaper management (Umbra-style)
│   │   ├── WallpaperManager.swift            # Set/get wallpapers via NSWorkspace
│   │   ├── WallpaperPair.swift               # Light/dark wallpaper pair model
│   │   ├── WallpaperPairStorage.swift        # Persistence for wallpaper pairs
│   │   ├── AppearanceObserver.swift          # Detects Light/Dark mode changes
│   │   ├── WallpaperSwitcher.swift           # Switches wallpaper on appearance change
│   │   └── WallpaperDimOverlay.swift         # Desktop-only dimming overlay
│   │
│   ├── AppRules/                             # Per-app dimming rules (Pro)
│   │   ├── AppRulesManager.swift             # CRUD for app rules
│   │   ├── AppRule.swift                     # Rule model (never dim, always dim, custom)
│   │   ├── AppRuleEvaluator.swift            # Applies rules during analysis
│   │   └── InstalledAppsScanner.swift        # Lists apps from /Applications
│   │
│   ├── MultiDisplay/                         # Multi-display support (Pro)
│   │   ├── DisplayManager.swift              # Detects and tracks connected displays
│   │   ├── DisplayConfiguration.swift        # Per-display settings model
│   │   ├── DisplayConfigurationStorage.swift # Persistence for display configs
│   │   └── DisplayChangeObserver.swift       # Detects display add/remove
│   │
│   ├── Licensing/                            # Paddle licensing integration
│   │   ├── LicenseManager.swift              # License state and validation
│   │   ├── LicenseState.swift                # Enum: Free, Trial, Pro, Expired
│   │   ├── PaddleIntegration.swift           # Paddle SDK wrapper
│   │   ├── FeatureGate.swift                 # Feature availability based on license
│   │   ├── TrialManager.swift                # Trial period tracking
│   │   └── LicenseActivationView.swift       # UI for entering license key
│   │
│   ├── Updates/                              # Sparkle auto-updates
│   │   ├── UpdateManager.swift               # Sparkle coordinator
│   │   └── UpdateMenuActions.swift           # Check for updates menu item
│   │
│   ├── KeyboardShortcuts/                    # Global keyboard shortcuts
│   │   ├── KeyboardShortcutsManager.swift    # Shortcut registration
│   │   ├── ShortcutActions.swift             # Actions triggered by shortcuts
│   │   └── ShortcutConfigurationView.swift   # UI for customizing shortcuts
│   │
│   ├── Settings/                             # Settings persistence
│   │   ├── SettingsManager.swift             # UserDefaults wrapper singleton
│   │   ├── SettingsKeys.swift                # Type-safe settings key enum
│   │   └── SettingsObserver.swift            # Combine publisher for settings changes
│   │
│   ├── Permissions/                          # Permission handling
│   │   ├── PermissionManager.swift           # Coordinates all permission requests
│   │   ├── ScreenRecordingPermission.swift   # Screen Recording specific handling
│   │   ├── LocationPermission.swift          # Location specific handling
│   │   ├── AutomationPermission.swift        # AppleEvents specific handling
│   │   └── PermissionStatusView.swift        # UI showing permission states
│   │
│   ├── LaunchAtLogin/                        # Login item management
│   │   └── LaunchAtLoginManager.swift        # ServiceManagement wrapper
│   │
│   ├── Utilities/                            # Shared utilities
│   │   ├── CGImageExtensions.swift           # CGImage helper methods
│   │   ├── NSScreenExtensions.swift          # NSScreen helper methods
│   │   ├── CGRectExtensions.swift            # CGRect helper methods
│   │   ├── ColorExtensions.swift             # NSColor/Color helpers
│   │   ├── NotificationNames.swift           # Custom notification name constants
│   │   ├── Logger.swift                      # Unified logging wrapper
│   │   └── PerformanceProfiler.swift         # Instruments for performance monitoring
│   │
│   ├── Models/                               # Shared data models
│   │   ├── DisplayInfo.swift                 # Display metadata model
│   │   ├── ScreenRegion.swift                # Rectangle region on screen
│   │   └── DimLevel.swift                    # Value type for dimming amount
│   │
│   ├── Resources/                            # Assets and resources
│   │   ├── Assets.xcassets/                  # Asset catalog
│   │   │   ├── AppIcon.appiconset/           # App icon
│   │   │   ├── MenuBarIcon.imageset/         # Menu bar icon (template)
│   │   │   ├── MenuBarIconActive.imageset/   # Menu bar icon (active state)
│   │   │   └── Colors/                       # Color definitions
│   │   │       ├── AccentColor.colorset/
│   │   │       └── DimOverlayColor.colorset/
│   │   │
│   │   ├── Localizable.strings               # Localized strings (English)
│   │   ├── InfoPlist.strings                 # Localized Info.plist strings
│   │   └── Credits.rtf                       # Credits for About window
│   │
│   ├── Supporting Files/                     # Configuration files
│   │   ├── Info.plist                        # App configuration
│   │   ├── SuperDimmer.entitlements          # Entitlements for signing
│   │   └── SuperDimmer-Bridging-Header.h     # ObjC bridging (if needed)
│   │
│   └── Preview Content/                      # SwiftUI preview assets
│       └── Preview Assets.xcassets/
│
├── SuperDimmerTests/                         # Unit tests
│   ├── BrightnessAnalysis/
│   │   ├── LuminanceCalculatorTests.swift
│   │   ├── BrightRegionDetectorTests.swift
│   │   └── ImageDownsamplerTests.swift
│   ├── WindowTracking/
│   │   └── WindowTrackerServiceTests.swift
│   ├── Settings/
│   │   └── SettingsManagerTests.swift
│   ├── Licensing/
│   │   └── FeatureGateTests.swift
│   └── Utilities/
│       └── ExtensionsTests.swift
│
├── SuperDimmerUITests/                       # UI tests
│   ├── MenuBarUITests.swift
│   ├── PreferencesUITests.swift
│   └── OnboardingUITests.swift
│
├── Frameworks/                               # Embedded frameworks (after build)
│   ├── Paddle.framework/                     # Licensing SDK
│   └── Sparkle.framework/                    # Auto-updates
│
└── Scripts/                                  # Build and release scripts
    ├── notarize.sh                           # Apple notarization script
    ├── create-dmg.sh                         # DMG creation for distribution
    ├── update-appcast.sh                     # Sparkle appcast generator
    └── bump-version.sh                       # Version number incrementer
```

---

## 📦 Component Descriptions

### App/ - Application Entry Point

#### `SuperDimmerApp.swift`
```swift
// PURPOSE: Main entry point for the SwiftUI app lifecycle
// ROLE: Creates the app delegate and configures the app as menu-bar only
// DEPENDENCIES: AppDelegate
// CALLED BY: System at launch
// WHY: We use @main with NSApplicationDelegateAdaptor because menu bar apps
//      require AppKit's NSStatusItem which SwiftUI doesn't natively support

import SwiftUI

@main
struct SuperDimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty - all UI is in menu bar, no main window
        Settings { /* Preferences accessible via menu */ }
    }
}
```

#### `AppDelegate.swift`
```swift
// PURPOSE: Traditional AppKit app delegate for menu bar app setup
// ROLE: Initializes MenuBarController, starts services on launch
// DEPENDENCIES: MenuBarController, SettingsManager, DimmingCoordinator
// CALLED BY: SuperDimmerApp via NSApplicationDelegateAdaptor
// WHY: NSStatusItem and menu bar apps require AppKit lifecycle events

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize menu bar, start dimming if enabled
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup: remove overlays, restore gamma tables
    }
}
```

---

### MenuBar/ - Menu Bar UI Components

#### `MenuBarController.swift`
```swift
// PURPOSE: Manages the NSStatusItem (menu bar icon) and its popover/menu
// ROLE: Creates status item, handles click events, shows/hides popover
// DEPENDENCIES: MenuBarView, MenuBarIconStateManager, SettingsManager
// CALLED BY: AppDelegate on launch
// WHY: NSStatusItem is the only way to create menu bar presence in macOS
//      We chose popover (not menu) for richer SwiftUI controls

import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    // Creates the menu bar icon and popover
    func setupMenuBar() { }
    
    // Toggles popover visibility when icon clicked
    @objc func togglePopover() { }
    
    // Updates icon based on dimming state
    func updateIcon(isActive: Bool) { }
}
```

#### `MenuBarView.swift`
```swift
// PURPOSE: SwiftUI content displayed in the menu bar popover
// ROLE: Shows quick controls - toggles, sliders, status indicators
// DEPENDENCIES: SettingsManager (via @EnvironmentObject), QuickControlsView
// CALLED BY: MenuBarController popover
// WHY: SwiftUI provides modern, reactive UI that's faster to build
//      than NSMenu for rich interactive controls

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack {
            // Master toggle, dim level slider, threshold slider
            // Color temperature controls
            // Open Preferences button
            // Quit button
        }
    }
}
```

#### `QuickControlsView.swift`
```swift
// PURPOSE: Reusable control components for menu bar dropdown
// ROLE: Toggle switches, labeled sliders, preset buttons
// DEPENDENCIES: None (pure SwiftUI view components)
// CALLED BY: MenuBarView
// WHY: Separating controls into own file keeps MenuBarView clean
//      and allows reuse in Preferences window

import SwiftUI

struct DimToggleControl: View { }
struct DimLevelSlider: View { }
struct ThresholdSlider: View { }
struct ColorTemperatureControl: View { }
```

#### `MenuBarIconStateManager.swift`
```swift
// PURPOSE: Determines which icon to show based on app state
// ROLE: Maps dimming state, color temp state → icon asset name
// DEPENDENCIES: SettingsManager
// CALLED BY: MenuBarController
// WHY: Icon state logic is complex enough to warrant separate class
//      (disabled, active, color temp on, etc.)

import AppKit

class MenuBarIconStateManager {
    // Returns appropriate icon name for current state
    func currentIconName() -> String { }
    
    // Observes settings changes to trigger icon updates
    func startObserving(onChange: @escaping () -> Void) { }
}
```

---

### Overlay/ - Dimming Overlay Window System

#### `DimOverlayWindow.swift`
```swift
// PURPOSE: Transparent window that dims content beneath it
// ROLE: NSWindow subclass configured for click-through overlay behavior
// DEPENDENCIES: None (standalone NSWindow subclass)
// CALLED BY: OverlayManager
// WHY: Standard NSWindow can't do click-through by default
//      Must configure: ignoresMouseEvents, borderless, transparent, high level
// LEARNED FROM: MonitorControlLite and Lunar implementations

import AppKit

final class DimOverlayWindow: NSWindow {
    // Initialize with frame, screen, and initial dim level
    init(frame: CGRect, screen: NSScreen, dimLevel: CGFloat) {
        // Configure for overlay behavior:
        // - borderless, transparent
        // - ignoresMouseEvents = true (critical!)
        // - level = .screenSaver
        // - collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    // Animate dim level change for smooth transitions
    func setDimLevel(_ level: CGFloat, animated: Bool) { }
    
    // Update position to track a window
    func updatePosition(to rect: CGRect) { }
}
```

#### `OverlayManager.swift`
```swift
// PURPOSE: Creates, updates, and removes all DimOverlayWindow instances
// ROLE: Maintains dictionary of overlays keyed by window ID or region
// DEPENDENCIES: DimOverlayWindow, OverlayAnimator
// CALLED BY: DimmingCoordinator
// WHY: Need central management to avoid orphaned overlays, handle
//      display changes, and coordinate animations

import AppKit

final class OverlayManager {
    // Active overlays keyed by target window ID
    private var windowOverlays: [CGWindowID: DimOverlayWindow] = [:]
    
    // Full-screen overlays per display (for simple mode)
    private var displayOverlays: [CGDirectDisplayID: DimOverlayWindow] = [:]
    
    // Create or update overlay for a specific window
    func updateOverlay(for windowID: CGWindowID, bounds: CGRect, dimLevel: CGFloat) { }
    
    // Remove overlay when window closes or becomes dark
    func removeOverlay(for windowID: CGWindowID) { }
    
    // Create full-screen overlay for entire display
    func createFullScreenOverlay(for displayID: CGDirectDisplayID) { }
    
    // Remove all overlays (cleanup on quit or disable)
    func removeAllOverlays() { }
}
```

#### `OverlayAnimator.swift`
```swift
// PURPOSE: Handles smooth opacity transitions for overlays
// ROLE: Animates dim level changes to avoid jarring flickers
// DEPENDENCIES: None (uses Core Animation)
// CALLED BY: OverlayManager, DimOverlayWindow
// WHY: Instant dimming changes are visually harsh; smooth transitions
//      provide better UX

import AppKit

final class OverlayAnimator {
    static let defaultDuration: TimeInterval = 0.25
    
    // Animate layer opacity with configurable duration
    func animateOpacity(layer: CALayer, to opacity: CGFloat, duration: TimeInterval) { }
}
```

#### `OverlayPositionTracker.swift`
```swift
// PURPOSE: Tracks window movements to reposition overlays
// ROLE: Observes window frame changes, updates overlay positions
// DEPENDENCIES: WindowTrackerService
// CALLED BY: DimmingCoordinator
// WHY: Overlays must follow windows as they move/resize;
//      polling is simpler than Accessibility observers

import AppKit

final class OverlayPositionTracker {
    // Check if any tracked windows have moved
    func checkForPositionChanges() -> [(windowID: CGWindowID, newBounds: CGRect)] { }
    
    // Update cached positions after handling changes
    func updateCachedPositions(_ windows: [TrackedWindow]) { }
}
```

---

### ScreenCapture/ - Screen Capture for Brightness Analysis

#### `ScreenCaptureService.swift`
```swift
// PURPOSE: Captures screen images for brightness analysis
// ROLE: Wraps CGWindowListCreateImage and CGDisplayCreateImage APIs
// DEPENDENCIES: CaptureThrottler
// CALLED BY: BrightnessAnalysisEngine
// WHY: Screen capture is required to analyze actual pixel brightness
//      This is what makes SuperDimmer unique - most apps don't capture
// PERMISSION: Requires Screen Recording permission

import CoreGraphics
import AppKit

final class ScreenCaptureService {
    private let throttler: CaptureThrottler
    
    // Capture entire main display (for full analysis)
    func captureMainDisplay() -> CGImage? { }
    
    // Capture specific region (for targeted analysis)
    func captureRegion(_ rect: CGRect) -> CGImage? { }
    
    // Capture specific window by ID
    func captureWindow(_ windowID: CGWindowID) -> CGImage? { }
}
```

#### `ScreenCapturePermissionHandler.swift`
```swift
// PURPOSE: Handles Screen Recording permission request flow
// ROLE: Checks permission state, prompts user, provides settings link
// DEPENDENCIES: None
// CALLED BY: PermissionManager, ScreenCaptureService
// WHY: Screen Recording permission is required for CGWindowListCreateImage
//      to capture other apps' content (not just our own windows)

import AppKit

final class ScreenCapturePermissionHandler {
    // Check if permission is granted
    func hasPermission() -> Bool { }
    
    // Request permission (triggers system prompt)
    func requestPermission() { }
    
    // Open System Settings to grant permission manually
    func openSystemSettings() { }
}
```

#### `CaptureThrottler.swift`
```swift
// PURPOSE: Rate-limits screen captures for performance
// ROLE: Prevents excessive captures that would spike CPU usage
// DEPENDENCIES: None
// CALLED BY: ScreenCaptureService
// WHY: Capturing full screen is expensive; we don't need 60fps,
//      0.5-2 second intervals are sufficient for brightness detection

import Foundation

final class CaptureThrottler {
    var minimumInterval: TimeInterval = 0.5 // seconds
    
    // Check if enough time has passed since last capture
    func shouldAllowCapture() -> Bool { }
    
    // Record that a capture was performed
    func recordCapture() { }
}
```

---

### BrightnessAnalysis/ - Core Brightness Detection Engine

#### `BrightnessAnalysisEngine.swift`
```swift
// PURPOSE: Main coordinator for brightness analysis pipeline
// ROLE: Orchestrates: capture → downsample → luminance → detect regions
// DEPENDENCIES: ScreenCaptureService, ImageDownsampler, LuminanceCalculator, BrightRegionDetector
// CALLED BY: DimmingCoordinator
// WHY: Analysis has multiple steps; this class coordinates them
//      and handles caching/optimization

import CoreGraphics

final class BrightnessAnalysisEngine {
    // Analyze a captured image and return bright regions
    func analyzeBrightness(of image: CGImage, threshold: Float) -> [ScreenRegion] { }
    
    // Analyze specific window bounds
    func analyzeWindow(_ window: TrackedWindow, threshold: Float) -> Float { }
}
```

#### `LuminanceCalculator.swift`
```swift
// PURPOSE: Calculates luminance values from image pixels
// ROLE: Implements Rec. 709 formula using Accelerate framework
// DEPENDENCIES: Accelerate framework (vImage)
// CALLED BY: BrightnessAnalysisEngine
// WHY: Rec. 709 is the standard for perceived brightness
//      Y' = 0.2126*R + 0.7152*G + 0.0722*B
//      Accelerate provides SIMD optimization for fast processing

import Accelerate
import CoreGraphics

final class LuminanceCalculator {
    // Calculate average luminance for entire image (0.0 - 1.0)
    func averageLuminance(of image: CGImage) -> Float { }
    
    // Calculate luminance for specific region within image
    func luminance(in image: CGImage, rect: CGRect) -> Float { }
    
    // Generate luminance grid for region detection
    func luminanceGrid(of image: CGImage, gridSize: Int) -> [[Float]] { }
}
```

#### `ImageDownsampler.swift`
```swift
// PURPOSE: Reduces image resolution for faster analysis
// ROLE: Scales images down before luminance calculation
// DEPENDENCIES: Accelerate framework (vImage)
// CALLED BY: BrightnessAnalysisEngine
// WHY: Full-resolution analysis is overkill for brightness detection
//      A 100x100 sample is sufficient and much faster

import Accelerate
import CoreGraphics

final class ImageDownsampler {
    // Target dimensions for downsampled analysis
    var targetSize: CGSize = CGSize(width: 100, height: 100)
    
    // Downsample image for faster processing
    func downsample(_ image: CGImage) -> CGImage? { }
}
```

#### `BrightRegionDetector.swift`
```swift
// PURPOSE: Identifies distinct bright regions within an image
// ROLE: Finds contiguous areas above threshold, returns bounding rects
// DEPENDENCIES: LuminanceCalculator
// CALLED BY: BrightnessAnalysisEngine
// WHY: For region-specific dimming, we need to know WHERE bright spots are,
//      not just IF the image is bright overall

import CoreGraphics

final class BrightRegionDetector {
    // Detect all regions above brightness threshold
    func detectBrightRegions(in image: CGImage, threshold: Float) -> [CGRect] { }
    
    // Merge overlapping/adjacent regions into larger ones
    private func mergeAdjacentRegions(_ regions: [CGRect]) -> [CGRect] { }
}
```

#### `BrightnessCache.swift`
```swift
// PURPOSE: Caches brightness analysis results to avoid redundant work
// ROLE: Stores recent results, invalidates when content likely changed
// DEPENDENCIES: None
// CALLED BY: BrightnessAnalysisEngine
// WHY: If a window hasn't changed, no need to re-analyze
//      Reduces CPU usage significantly

import Foundation

final class BrightnessCache {
    // Cache entry with timestamp
    struct CacheEntry {
        let brightness: Float
        let timestamp: Date
        let windowID: CGWindowID
    }
    
    // Get cached brightness if still valid
    func getCachedBrightness(for windowID: CGWindowID) -> Float? { }
    
    // Store analysis result
    func cache(brightness: Float, for windowID: CGWindowID) { }
    
    // Invalidate cache (when user changes settings, etc.)
    func invalidateAll() { }
}
```

---

### WindowTracking/ - Window Tracking and State

#### `WindowTrackerService.swift`
```swift
// PURPOSE: Retrieves list of visible windows on screen
// ROLE: Wraps CGWindowListCopyWindowInfo, parses results into TrackedWindow
// DEPENDENCIES: TrackedWindow model
// CALLED BY: DimmingCoordinator
// WHY: We need window positions and ownership to know what to dim
//      CGWindowListCopyWindowInfo provides this without Accessibility

import CoreGraphics
import AppKit

final class WindowTrackerService {
    // Get all visible windows (excluding system UI)
    func getVisibleWindows() -> [TrackedWindow] { }
    
    // Get only windows for a specific app
    func getWindows(for bundleID: String) -> [TrackedWindow] { }
}
```

#### `TrackedWindow.swift`
```swift
// PURPOSE: Data model representing a tracked window
// ROLE: Holds window metadata: ID, owner, bounds, active state
// DEPENDENCIES: None (pure data model)
// CALLED BY: WindowTrackerService, DimmingCoordinator
// WHY: Strongly-typed struct is cleaner than working with raw dictionaries

import CoreGraphics

struct TrackedWindow: Identifiable {
    let id: CGWindowID          // Unique window ID
    let ownerPID: pid_t         // Process ID of owning app
    let ownerName: String       // App name (e.g., "Safari")
    let bundleID: String?       // Bundle ID if available
    let bounds: CGRect          // Window frame in screen coordinates
    let layer: Int              // Window layer (z-order)
    let title: String           // Window title
    var isActive: Bool          // True if belongs to frontmost app
}
```

#### `ActiveWindowDetector.swift`
```swift
// PURPOSE: Determines which app/window is currently active
// ROLE: Tracks frontmost application via NSWorkspace
// DEPENDENCIES: NSWorkspace
// CALLED BY: WindowTrackerService
// WHY: Active windows get less dimming than inactive windows
//      NSWorkspace.shared.frontmostApplication is the standard API

import AppKit

final class ActiveWindowDetector {
    // Get currently frontmost application
    var frontmostApp: NSRunningApplication? { }
    
    // Check if a window belongs to the frontmost app
    func isWindowActive(_ window: TrackedWindow) -> Bool { }
    
    // Start observing app activation changes
    func startObserving(onChange: @escaping () -> Void) { }
}
```

#### `WindowChangeObserver.swift`
```swift
// PURPOSE: Detects when windows are added, removed, or moved
// ROLE: Triggers re-analysis when window state changes
// DEPENDENCIES: WindowTrackerService
// CALLED BY: DimmingCoordinator
// WHY: Polling every 0.5s catches most changes, but observing
//      app activation events ensures immediate response

import AppKit

final class WindowChangeObserver {
    // Callback when significant window change detected
    var onWindowChange: (() -> Void)?
    
    // Start observing for window changes
    func startObserving() { }
    
    // Stop observing (cleanup)
    func stopObserving() { }
}
```

---

### DimmingCoordinator/ - Main Dimming Logic Coordinator

#### `DimmingCoordinator.swift`
```swift
// PURPOSE: Main controller that orchestrates the entire dimming pipeline
// ROLE: Coordinates: windows → analysis → decisions → overlays
// DEPENDENCIES: All analysis and overlay services
// CALLED BY: AppDelegate
// WHY: Central coordinator prevents spaghetti code between services
//      Single source of truth for dimming state

import Foundation

final class DimmingCoordinator {
    // Main services
    private let windowTracker: WindowTrackerService
    private let analysisEngine: BrightnessAnalysisEngine
    private let overlayManager: OverlayManager
    
    // Start the dimming system
    func start() { }
    
    // Stop and cleanup
    func stop() { }
    
    // Perform one analysis cycle
    func performAnalysisCycle() { }
    
    // Handle settings changes
    func settingsDidChange() { }
}
```

#### `DimmingDecision.swift`
```swift
// PURPOSE: Represents a dimming decision for a specific window
// ROLE: Data structure holding: which window, should it dim, how much
// DEPENDENCIES: TrackedWindow
// CALLED BY: DimmingCoordinator
// WHY: Separating decision from execution makes logic clearer
//      and easier to unit test

import CoreGraphics

struct DimmingDecision {
    let window: TrackedWindow
    let shouldDim: Bool           // Based on threshold comparison
    let dimLevel: CGFloat         // 0.0-1.0, varies by active/inactive
    let reason: DimmingReason     // For debugging/logging
    
    enum DimmingReason {
        case aboveThreshold
        case appRuleAlwaysDim
        case appRuleNeverDim
        case belowThreshold
    }
}
```

#### `DimmingLoop.swift`
```swift
// PURPOSE: Timer-based loop that triggers analysis at regular intervals
// ROLE: Manages Timer that calls DimmingCoordinator.performAnalysisCycle
// DEPENDENCIES: DimmingCoordinator
// CALLED BY: DimmingCoordinator
// WHY: Continuous polling is simpler and more reliable than trying
//      to observe all possible screen content changes

import Foundation

final class DimmingLoop {
    // Interval between analysis cycles (user configurable)
    var interval: TimeInterval = 1.0 // seconds
    
    private var timer: Timer?
    
    // Start the analysis loop
    func start(performCycle: @escaping () -> Void) { }
    
    // Stop the loop
    func stop() { }
    
    // Restart with new interval
    func updateInterval(_ newInterval: TimeInterval) { }
}
```

#### `DimmingConfiguration.swift`
```swift
// PURPOSE: Holds runtime configuration for dimming behavior
// ROLE: Centralizes all settings needed by DimmingCoordinator
// DEPENDENCIES: SettingsManager
// CALLED BY: DimmingCoordinator
// WHY: Pulling from SettingsManager each cycle is slow; this
//      caches current values and updates via observation

import Foundation

struct DimmingConfiguration {
    var isEnabled: Bool = true
    var brightnessThreshold: Float = 0.85
    var activeDimLevel: CGFloat = 0.15
    var inactiveDimLevel: CGFloat = 0.35
    var scanInterval: TimeInterval = 1.0
    var differentiateActiveInactive: Bool = true
}
```

---

### ColorTemperature/ - Color Temperature (f.lux-style)

#### `ColorTemperatureEngine.swift`
```swift
// PURPOSE: Controls display color temperature via gamma tables
// ROLE: Sets display gamma to shift colors warm/cool
// DEPENDENCIES: KelvinToRGBConverter, GammaTableGenerator
// CALLED BY: ScheduleManager, MenuBarView controls
// WHY: f.lux-style color temperature is a common companion feature
//      Implements via CGSetDisplayTransferByTable (same as f.lux)

import CoreGraphics

final class ColorTemperatureEngine {
    // Apply temperature to specific display
    func setTemperature(_ kelvin: Int, for displayID: CGDirectDisplayID) { }
    
    // Reset display to default (6500K)
    func resetToDefault(for displayID: CGDirectDisplayID) { }
    
    // Get current temperature
    func currentTemperature(for displayID: CGDirectDisplayID) -> Int { }
}
```

#### `KelvinToRGBConverter.swift`
```swift
// PURPOSE: Converts Kelvin temperature to RGB multipliers
// ROLE: Mathematical conversion using Tanner Helland's algorithm
// DEPENDENCIES: None (pure math)
// CALLED BY: ColorTemperatureEngine
// WHY: Kelvin is intuitive for users; RGB multipliers are what
//      gamma tables need

import Foundation

final class KelvinToRGBConverter {
    // Convert Kelvin (1000-40000) to RGB multipliers (0.0-1.0)
    func convert(_ kelvin: Int) -> (r: Float, g: Float, b: Float) { }
}
```

#### `GammaTableGenerator.swift`
```swift
// PURPOSE: Generates gamma lookup tables for display
// ROLE: Creates Float arrays for CGSetDisplayTransferByTable
// DEPENDENCIES: KelvinToRGBConverter
// CALLED BY: ColorTemperatureEngine
// WHY: CGSetDisplayTransferByTable requires arrays of values
//      mapping input → output for each RGB channel

import CoreGraphics

final class GammaTableGenerator {
    let tableSize: Int = 256 // Standard LUT size
    
    // Generate gamma tables for given RGB multipliers
    func generateTables(r: Float, g: Float, b: Float) -> (
        red: [Float], green: [Float], blue: [Float]
    ) { }
}
```

#### `TemperatureTransitionAnimator.swift`
```swift
// PURPOSE: Smoothly transitions between color temperatures
// ROLE: Interpolates temperature over duration to avoid jarring changes
// DEPENDENCIES: ColorTemperatureEngine
// CALLED BY: ScheduleManager
// WHY: Instant temperature changes are visually harsh
//      f.lux uses gradual transitions over ~60 minutes

import Foundation

final class TemperatureTransitionAnimator {
    // Animate from current to target temperature over duration
    func transition(from: Int, to: Int, duration: TimeInterval, 
                    onStep: @escaping (Int) -> Void) { }
    
    // Cancel in-progress transition
    func cancelTransition() { }
}
```

#### `TemperaturePresets.swift`
```swift
// PURPOSE: Defines named presets for common color temperatures
// ROLE: Enum with associated Kelvin values
// DEPENDENCIES: None (pure data)
// CALLED BY: ColorTemperatureEngine, UI
// WHY: Named presets are easier for users than raw Kelvin numbers

import Foundation

enum TemperaturePreset: String, CaseIterable, Identifiable {
    case daylight = "Daylight"      // 6500K
    case halogen = "Halogen"        // 3400K
    case fluorescent = "Fluorescent"// 4200K
    case sunset = "Sunset"          // 4100K
    case night = "Night"            // 2700K
    case candlelight = "Candlelight"// 1900K
    
    var kelvin: Int { }
    var id: String { rawValue }
}
```

---

### Licensing/ - Paddle Licensing Integration

#### `LicenseManager.swift`
```swift
// PURPOSE: Central manager for license state and validation
// ROLE: Tracks license state, validates keys, manages trial
// DEPENDENCIES: PaddleIntegration, TrialManager
// CALLED BY: FeatureGate, AppDelegate, LicensePreferencesTab
// WHY: Paddle SDK needs to be wrapped for cleaner integration
//      and to provide testable interface

import Foundation

final class LicenseManager: ObservableObject {
    @Published var state: LicenseState = .free
    
    // Initialize and check existing license
    func initialize() { }
    
    // Activate with license key
    func activate(key: String) async throws { }
    
    // Deactivate current license
    func deactivate() async throws { }
    
    // Start trial period
    func startTrial() { }
}
```

#### `LicenseState.swift`
```swift
// PURPOSE: Enum representing possible license states
// ROLE: Type-safe license state with associated data
// DEPENDENCIES: None
// CALLED BY: LicenseManager, FeatureGate
// WHY: Clear enum prevents bugs from string comparisons

import Foundation

enum LicenseState: Equatable {
    case free                           // No license, free features only
    case trial(daysRemaining: Int)      // Trial active
    case trialExpired                   // Trial ended, no purchase
    case pro(expiresDate: Date?)        // Licensed, optionally time-limited
    
    var isPro: Bool { }
    var canUsePro: Bool { }
}
```

#### `FeatureGate.swift`
```swift
// PURPOSE: Determines if specific features are available
// ROLE: Checks license state before allowing Pro features
// DEPENDENCIES: LicenseManager
// CALLED BY: Throughout app wherever Pro features are used
// WHY: Centralized gating prevents accidental Pro access in free tier
//      Single place to define which features are Pro

import Foundation

final class FeatureGate {
    private let licenseManager: LicenseManager
    
    // Check if feature is available
    func isAvailable(_ feature: ProFeature) -> Bool { }
    
    // Show upgrade prompt if feature is gated
    func requireFeature(_ feature: ProFeature, onAvailable: () -> Void) { }
    
    enum ProFeature: String {
        case intelligentDetection
        case activeInactiveDifferentiation
        case perAppRules
        case multiDisplay
        case colorTemperature
        case wallpaperManagement
        case scheduledProfiles
    }
}
```

---

### Settings/ - Settings Persistence

#### `SettingsManager.swift`
```swift
// PURPOSE: Centralized settings storage using UserDefaults
// ROLE: Read/write all app settings, publish changes
// DEPENDENCIES: SettingsKeys
// CALLED BY: Throughout entire app
// WHY: UserDefaults is standard for preferences
//      ObservableObject makes SwiftUI binding easy

import Foundation
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isDimmingEnabled: Bool
    @Published var globalDimLevel: Double
    @Published var brightnessThreshold: Double
    @Published var activeDimLevel: Double
    @Published var inactiveDimLevel: Double
    @Published var scanInterval: Double
    // ... more settings
    
    // Save all settings to UserDefaults
    func save() { }
    
    // Reset to defaults
    func resetToDefaults() { }
}
```

#### `SettingsKeys.swift`
```swift
// PURPOSE: Type-safe keys for UserDefaults storage
// ROLE: Enum prevents typos in settings key strings
// DEPENDENCIES: None
// CALLED BY: SettingsManager
// WHY: String literals are error-prone; enum is type-safe

import Foundation

enum SettingsKeys: String {
    case isDimmingEnabled
    case globalDimLevel
    case brightnessThreshold
    case activeDimLevel
    case inactiveDimLevel
    case scanInterval
    case colorTemperatureEnabled
    case colorTemperature
    case wallpaperAutoSwitch
    case launchAtLogin
    // ... more keys
}
```

---

### Permissions/ - Permission Handling

#### `PermissionManager.swift`
```swift
// PURPOSE: Coordinates all permission requests and status
// ROLE: Unified interface for checking/requesting all permissions
// DEPENDENCIES: ScreenRecordingPermission, LocationPermission, AutomationPermission
// CALLED BY: AppDelegate, various services
// WHY: Multiple permissions needed; central manager prevents duplication
//      and provides consistent UX

import Foundation

final class PermissionManager: ObservableObject {
    @Published var screenRecordingGranted: Bool = false
    @Published var locationGranted: Bool = false
    @Published var automationGranted: Bool = false
    
    // Check all permission states
    func checkAllPermissions() { }
    
    // Request a specific permission
    func request(_ permission: Permission) { }
    
    enum Permission {
        case screenRecording
        case location
        case automation
    }
}
```

---

## 🔗 Component Dependencies Diagram

```
                           ┌─────────────────────┐
                           │   SuperDimmerApp    │
                           │      @main          │
                           └──────────┬──────────┘
                                      │
                           ┌──────────▼──────────┐
                           │    AppDelegate      │
                           │                     │
                           └──────────┬──────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌────────▼────────┐    ┌────────▼────────┐
    │ MenuBarController │   │DimmingCoordinator│   │ SettingsManager │
    │                   │   │                  │   │   (singleton)   │
    └─────────┬─────────┘   └────────┬─────────┘   └─────────────────┘
              │                      │                       ▲
              │           ┌──────────┼──────────────┐        │
              │           │          │              │        │
              │  ┌────────▼───────┐  │  ┌──────────▼──────┐  │
              │  │ScreenCapture   │  │  │ WindowTracker   │  │
              │  │   Service      │  │  │    Service      │  │
              │  └────────┬───────┘  │  └─────────────────┘  │
              │           │          │                       │
              │  ┌────────▼───────┐  │                       │
              │  │Brightness      │  │                       │
              │  │AnalysisEngine  │  │                       │
              │  └────────┬───────┘  │                       │
              │           │          │                       │
              │  ┌────────▼───────┐  │                       │
              │  │ OverlayManager │◄─┘                       │
              │  └────────────────┘                          │
              │                                              │
    ┌─────────▼─────────┐                                    │
    │   MenuBarView     │────────────────────────────────────┘
    │    (SwiftUI)      │
    └───────────────────┘
```

---

## 📝 File Naming Conventions

### Pattern: `[Domain][Action/Role][Type].swift`

| Pattern | Example | Explanation |
|---------|---------|-------------|
| `*Service.swift` | `ScreenCaptureService.swift` | External API interaction |
| `*Manager.swift` | `OverlayManager.swift` | Manages collection of objects |
| `*Engine.swift` | `BrightnessAnalysisEngine.swift` | Complex processing logic |
| `*Handler.swift` | `PermissionHandler.swift` | Event/action handling |
| `*Observer.swift` | `AppearanceObserver.swift` | Watches for changes |
| `*Calculator.swift` | `LuminanceCalculator.swift` | Math/computation |
| `*View.swift` | `MenuBarView.swift` | SwiftUI view |
| `*Controller.swift` | `MenuBarController.swift` | AppKit controller |

### File Organization Rules

1. **One primary class per file** (helpers/extensions can be in same file if small)
2. **File name matches primary type name** (`DimOverlayWindow.swift` contains `DimOverlayWindow` class)
3. **Group by feature domain** (all window tracking in `WindowTracking/`)
4. **Tests mirror source structure** (`SuperDimmerTests/BrightnessAnalysis/` tests `SuperDimmer/BrightnessAnalysis/`)

---

*Document Version: 1.0*
*Created: January 7, 2026*
