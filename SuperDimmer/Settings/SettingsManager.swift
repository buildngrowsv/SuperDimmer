/**
 ====================================================================
 SettingsManager.swift
 Centralized settings storage using UserDefaults
 ====================================================================
 
 PURPOSE:
 This singleton manages all user preferences for SuperDimmer.
 It provides:
 - Type-safe access to settings
 - Automatic persistence via UserDefaults
 - Reactive updates via @Published properties (Combine)
 - Default values for first-time users
 
 WHY SINGLETON:
 - Settings need to be accessible from anywhere in the app
 - Single source of truth prevents inconsistencies
 - Singleton pattern is standard for preference managers
 
 PERSISTENCE:
 All @Published properties are backed by UserDefaults. When a value
 changes, it's automatically saved. On app launch, saved values are
 loaded (or defaults used if not present).
 
 REACTIVE UPDATES:
 Using @Published makes all settings work seamlessly with SwiftUI.
 Any view using @EnvironmentObject or @ObservedObject will
 automatically update when settings change.
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import Combine
import AppKit

// ====================================================================
// MARK: - Detection Mode Enum
// ====================================================================

/**
 Detection mode for intelligent dimming.
 
 Determines how the app analyzes window brightness:
 - perWindow: Analyzes entire window, dims if bright
 - perRegion: Analyzes regions within window, dims only bright areas
 
 MOVED HERE (2.2.1.1): Needed before DimmingProfile for Codable synthesis
 */
enum DetectionMode: String, Codable, CaseIterable, Identifiable {
    /// Analyze entire window - if bright, dim the whole window
    case perWindow = "perWindow"
    
    /// Analyze regions within windows - dim only the bright areas
    /// This handles cases like dark Mail app with bright email content
    case perRegion = "perRegion"
    
    var id: String { rawValue }
    
    /// User-facing display name
    var displayName: String {
        switch self {
        case .perWindow: return "Per Window"
        case .perRegion: return "Per Region"
        }
    }
    
    /// Description for the UI
    var description: String {
        switch self {
        case .perWindow:
            return "Dims entire windows that are bright"
        case .perRegion:
            return "Finds and dims bright areas within windows"
        }
    }
    
    /// Icon for the mode
    var icon: String {
        switch self {
        case .perWindow: return "macwindow"
        case .perRegion: return "rectangle.split.3x3"
        }
    }
}

// ====================================================================
// MARK: - Dimming Profile Model
// ====================================================================

/**
 Represents a complete set of dimming-related preferences for a specific appearance mode.
 
 PURPOSE (2.2.1.1 - Appearance Mode System):
 Users want different dimming behaviors for Light vs Dark mode.
 - Dark mode users: Typically want aggressive dimming ON by default
 - Light mode users: Typically prefer minimal or no dimming
 
 DESIGN:
 Instead of having ONE set of dimming settings, we maintain TWO profiles:
 - darkModeProfile: Settings active when macOS is in Dark Mode
 - lightModeProfile: Settings active when macOS is in Light Mode
 
 When the user switches appearance (or system auto-switches), the app
 loads the appropriate profile and applies those settings.
 
 INCLUDED SETTINGS:
 - Super Dimming ON/OFF and dim level
 - Super Dimming Auto mode and range
 - Intelligent Dimming (per-window/per-region) ON/OFF
 - Active/Inactive dim levels
 - Brightness threshold
 - Scan and tracking intervals
 - SuperFocus features (decay, auto-hide, auto-minimize)
 
 NOT INCLUDED (global across appearances):
 - Color temperature settings (separate schedule system)
 - Wallpaper settings (may respect appearance in Phase 4.4)
 - Permission states
 - Launch at login
 - Developer mode
 */
struct DimmingProfile: Codable, Equatable {
    // Super Dimming (full-screen mode)
    var isDimmingEnabled: Bool = true  // ON by default for dark mode
    var globalDimLevel: Double = 0.25  // 25% dim
    var superDimmingAutoEnabled: Bool = true  // Auto-adjust based on screen brightness
    var autoAdjustRange: Double = 0.15  // ±15% adjustment
    
    // Intelligent Dimming (per-window/per-region mode)
    var intelligentDimmingEnabled: Bool = false  // OFF by default (Beta)
    var detectionMode: DetectionMode = .perWindow
    var brightnessThreshold: Double = 0.85  // 85% brightness triggers dimming
    var activeDimLevel: Double = 0.15  // 15% for active windows
    var inactiveDimLevel: Double = 0.35  // 35% for inactive windows
    var differentiateActiveInactive: Bool = true
    var regionGridSize: Int = 6  // 6x6 grid for region detection
    
    // Performance & Timing
    var scanInterval: Double = 2.0  // Brightness analysis interval (seconds)
    var windowTrackingInterval: Double = 0.5  // Position/z-order tracking interval
    
    // SuperFocus Features
    var superFocusEnabled: Bool = false
    var inactivityDecayEnabled: Bool = false
    var decayRate: Double = 0.01  // 1% per second
    var decayStartDelay: TimeInterval = 30.0  // 30 seconds before decay starts
    var maxDecayDimLevel: Double = 0.8  // 80% max decay dim
    var autoHideEnabled: Bool = true  // Auto-hide inactive apps
    var autoHideDelay: Double = 30.0  // 30 minutes
    var autoMinimizeEnabled: Bool = false  // Auto-minimize windows
    var autoMinimizeDelay: Double = 15.0  // 15 minutes
    var autoMinimizeIdleResetTime: Double = 5.0  // 5 minutes idle resets timers
    var autoMinimizeWindowThreshold: Int = 3  // Keep at least 3 windows
    
    /// Creates a profile with default values for Dark Mode
    static func defaultDarkMode() -> DimmingProfile {
        return DimmingProfile(
            isDimmingEnabled: true,
            globalDimLevel: 0.25,
            superDimmingAutoEnabled: true,
            autoAdjustRange: 0.15,
            intelligentDimmingEnabled: false,
            detectionMode: .perWindow,
            brightnessThreshold: 0.85,
            activeDimLevel: 0.15,
            inactiveDimLevel: 0.35,
            differentiateActiveInactive: true,
            regionGridSize: 6,
            scanInterval: 2.0,
            windowTrackingInterval: 0.5,
            superFocusEnabled: false,
            inactivityDecayEnabled: false,
            decayRate: 0.01,
            decayStartDelay: 30.0,
            maxDecayDimLevel: 0.8,
            autoHideEnabled: true,
            autoHideDelay: 30.0,
            autoMinimizeEnabled: false,
            autoMinimizeDelay: 15.0,
            autoMinimizeIdleResetTime: 5.0,
            autoMinimizeWindowThreshold: 3
        )
    }
    
    /// Creates a profile with default values for Light Mode
    /// Light mode users typically don't want aggressive dimming
    static func defaultLightMode() -> DimmingProfile {
        return DimmingProfile(
            isDimmingEnabled: false,  // OFF by default in light mode
            globalDimLevel: 0.15,  // Lighter dimming if enabled
            superDimmingAutoEnabled: false,  // No auto-adjustment
            autoAdjustRange: 0.10,  // Smaller range if enabled
            intelligentDimmingEnabled: false,
            detectionMode: .perWindow,
            brightnessThreshold: 0.90,  // Higher threshold (less aggressive)
            activeDimLevel: 0.10,  // Lighter dimming
            inactiveDimLevel: 0.25,  // Lighter dimming
            differentiateActiveInactive: true,
            regionGridSize: 6,
            scanInterval: 2.0,
            windowTrackingInterval: 0.5,
            superFocusEnabled: false,
            inactivityDecayEnabled: false,
            decayRate: 0.01,
            decayStartDelay: 30.0,
            maxDecayDimLevel: 0.6,  // Lower max decay
            autoHideEnabled: false,  // OFF by default in light mode
            autoHideDelay: 30.0,
            autoMinimizeEnabled: false,
            autoMinimizeDelay: 15.0,
            autoMinimizeIdleResetTime: 5.0,
            autoMinimizeWindowThreshold: 3
        )
    }
}

// ====================================================================
// MARK: - App Exclusion Model
// ====================================================================

/**
 Represents an app's exclusion settings for various SuperDimmer features.
 
 Instead of separate exclusion lists per feature, we have ONE unified list
 where each app has checkboxes for which features it's excluded from.
 
 FEATURES:
 - Dimming: Brightness overlay dimming (intelligent mode)
 - Decay Dimming: Inactivity-based progressive dimming
 - Auto-Hide: Automatically hide inactive apps
 - Auto-Minimize: Automatically minimize inactive windows
 */
struct AppExclusion: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    
    /// The app's bundle identifier (e.g., "com.apple.Safari")
    var bundleID: String
    
    /// Display name resolved from bundle ID (cached for performance)
    var appName: String
    
    /// Exclude from brightness dimming overlays
    var excludeFromDimming: Bool = false
    
    /// Exclude from inactivity decay dimming
    var excludeFromDecayDimming: Bool = false
    
    /// Exclude from auto-hide inactive apps
    var excludeFromAutoHide: Bool = false
    
    /// Exclude from auto-minimize inactive windows
    var excludeFromAutoMinimize: Bool = false
    
    /// Creates an exclusion entry with all flags set to a default value
    init(bundleID: String, appName: String? = nil, allExcluded: Bool = false) {
        self.bundleID = bundleID
        self.appName = appName ?? AppExclusion.resolveAppName(from: bundleID)
        if allExcluded {
            self.excludeFromDimming = true
            self.excludeFromDecayDimming = true
            self.excludeFromAutoHide = true
            self.excludeFromAutoMinimize = true
        }
    }
    
    /// Resolves the app name from a bundle identifier
    static func resolveAppName(from bundleID: String) -> String {
        // Try to find the app in running applications first
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return app.localizedName ?? bundleID
        }
        
        // Try to get it from the bundle
        if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: bundleURL),
           let name = bundle.infoDictionary?["CFBundleName"] as? String ?? 
                      bundle.infoDictionary?["CFBundleDisplayName"] as? String {
            return name
        }
        
        // Fallback: extract readable name from bundle ID
        // e.g., "com.apple.Safari" -> "Safari"
        let components = bundleID.split(separator: ".")
        if let lastComponent = components.last {
            return String(lastComponent)
        }
        
        return bundleID
    }
    
    /// Returns true if the app has any exclusion enabled
    var hasAnyExclusion: Bool {
        excludeFromDimming || excludeFromDecayDimming || excludeFromAutoHide || excludeFromAutoMinimize
    }
}

/**
 Enum for checking exclusion by feature type.
 */
enum ExclusionFeature {
    case dimming
    case decayDimming
    case autoHide
    case autoMinimize
}

// ====================================================================
// MARK: - Settings Manager
// ====================================================================

/**
 Manages all user preferences with automatic persistence and reactive updates.
 
 USAGE:
 - Access via SettingsManager.shared singleton
 - In SwiftUI: @EnvironmentObject var settings: SettingsManager
 - Changes automatically persist and trigger UI updates
 
 THREAD SAFETY:
 @Published and UserDefaults operations should be on main thread.
 SwiftUI's @EnvironmentObject handles this for UI interactions.
 */
final class SettingsManager: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /**
     Shared singleton instance.
     
     WHY SINGLETON:
     Settings are app-global state. Having multiple instances would
     cause inconsistencies. Singleton ensures all code sees the same values.
     */
    static let shared = SettingsManager()
    
    // ================================================================
    // MARK: - User Defaults Keys
    // ================================================================
    
    /**
     Keys for UserDefaults storage.
     
     Using enum prevents typos and enables autocomplete.
     All keys prefixed to avoid conflicts with system or other apps.
     */
    private enum Keys: String {
        // General
        case isFirstLaunch = "superdimmer.isFirstLaunch"
        case launchAtLogin = "superdimmer.launchAtLogin"
        case betaUpdatesEnabled = "superdimmer.betaUpdatesEnabled"
        
        // Dimming
        case isDimmingEnabled = "superdimmer.isDimmingEnabled"
        case globalDimLevel = "superdimmer.globalDimLevel"
        case brightnessThreshold = "superdimmer.brightnessThreshold"
        case activeDimLevel = "superdimmer.activeDimLevel"
        case inactiveDimLevel = "superdimmer.inactiveDimLevel"
        case differentiateActiveInactive = "superdimmer.differentiateActiveInactive"
        case intelligentDimmingEnabled = "superdimmer.intelligentDimmingEnabled"
        case detectionMode = "superdimmer.detectionMode"
        case regionGridSize = "superdimmer.regionGridSize"
        case scanInterval = "superdimmer.scanInterval"
        case windowTrackingInterval = "superdimmer.windowTrackingInterval"
        
        // Super Dimming Auto Mode (2.2.1.2)
        // Auto mode adjusts dim level based on overall screen brightness
        case superDimmingAutoEnabled = "superdimmer.superDimmingAutoEnabled"
        case autoAdjustRange = "superdimmer.autoAdjustRange"  // ±X% adjustment (default 0.15 = ±15%)
        
        // Debug mode (shows colored borders on overlays)
        case debugOverlayBorders = "superdimmer.debugOverlayBorders"
        
        // Overlay Corner Radius (2.8.2b - Rounded Corners)
        case overlayCornerRadius = "superdimmer.overlayCornerRadius"
        
        // Inactivity Decay Dimming
        case inactivityDecayEnabled = "superdimmer.inactivityDecayEnabled"
        case decayRate = "superdimmer.decayRate"
        case decayStartDelay = "superdimmer.decayStartDelay"
        case maxDecayDimLevel = "superdimmer.maxDecayDimLevel"
        
        // Excluded Apps (LEGACY - migrated to appExclusions)
        case excludedAppBundleIDs = "superdimmer.excludedAppBundleIDs"
        
        // Per-Feature App Exclusions (2.2.1.12) - UNIFIED exclusion list
        case appExclusions = "superdimmer.comExclusions"
        case exclusionsMigrated = "superdimmer.exclusionsMigrated"
        
        // Auto-Hide Inactive Apps (APP-LEVEL)
        case autoHideEnabled = "superdimmer.autoHideEnabled"
        case autoHideDelay = "superdimmer.autoHideDelay"
        case autoHideExcludedApps = "superdimmer.autoHideExcludedApps"
        case autoHideExcludeSystemApps = "superdimmer.autoHideExcludeSystemApps"
        
        // Auto-Minimize Inactive Windows (WINDOW-LEVEL)
        case autoMinimizeEnabled = "superdimmer.autoMinimizeEnabled"
        case autoMinimizeDelay = "superdimmer.autoMinimizeDelay"
        case autoMinimizeIdleResetTime = "superdimmer.autoMinimizeIdleResetTime"
        case autoMinimizeWindowThreshold = "superdimmer.autoMinimizeWindowThreshold"
        case autoMinimizeExcludedApps = "superdimmer.autoMinimizeExcludedApps"
        
        // SuperFocus (2.2.1.5) - Groups productivity features
        case superFocusEnabled = "superdimmer.superFocusEnabled"
        
        // Color Temperature
        case colorTemperatureEnabled = "superdimmer.colorTemperatureEnabled"
        case colorTemperature = "superdimmer.colorTemperature"
        case colorTemperatureScheduleEnabled = "superdimmer.colorTemperatureScheduleEnabled"
        case dayTemperature = "superdimmer.dayTemperature"
        case nightTemperature = "superdimmer.nightTemperature"
        case scheduleStartHour = "superdimmer.scheduleStartHour"
        case scheduleStartMinute = "superdimmer.scheduleStartMinute"
        case scheduleEndHour = "superdimmer.scheduleEndHour"
        case scheduleEndMinute = "superdimmer.scheduleEndMinute"
        case transitionDuration = "superdimmer.transitionDuration"
        case useLocationBasedSchedule = "superdimmer.useLocationBasedSchedule"
        
        // Wallpaper
        case wallpaperAutoSwitchEnabled = "superdimmer.wallpaperAutoSwitchEnabled"
        case wallpaperDimEnabled = "superdimmer.wallpaperDimEnabled"
        case wallpaperDimLevel = "superdimmer.wallpaperDimLevel"
        
        // Super Spaces (Jan 21, 2026)
        case superSpacesEnabled = "superdimmer.superSpacesEnabled"
        case spaceNames = "superdimmer.spaceNames"
        case superSpacesDisplayMode = "superdimmer.superSpacesDisplayMode"
        case superSpacesAutoHide = "superdimmer.superSpacesAutoHide"
        
        // Appearance Mode System (2.2.1.1)
        case appearanceMode = "superdimmer.comearanceMode"
        case darkModeProfile = "superdimmer.darkModeProfile"
        case lightModeProfile = "superdimmer.lightModeProfile"
    }
    
    // ================================================================
    // MARK: - UserDefaults Instance
    // ================================================================
    
    /**
     The UserDefaults store for persistence.
     Using .standard which is the app's default domain.
     */
    private let defaults = UserDefaults.standard
    
    // ================================================================
    // MARK: - General Settings
    // ================================================================
    
    /**
     Whether this is the first time launching the app.
     
     Used to show onboarding flow and set up initial state.
     Set to false after first launch completes.
     */
    @Published var isFirstLaunch: Bool {
        didSet {
            defaults.set(isFirstLaunch, forKey: Keys.isFirstLaunch.rawValue)
        }
    }
    
    /**
     Whether to launch SuperDimmer when the user logs in.
     
     Uses ServiceManagement framework to add/remove login item.
     See LaunchAtLoginManager for implementation.
     */
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin.rawValue)
            // TODO: Actually update login item via LaunchAtLoginManager
        }
    }
    
    /**
     Whether to receive beta updates instead of stable releases.
     
     BETA CHANNEL:
     - When true: UpdateChecker fetches version-beta.json (may have pre-release versions)
     - When false (default): UpdateChecker fetches version.json (stable releases only)
     
     BEHAVIOR:
     Beta versions are typically:
     - Released more frequently
     - May have new features not yet in stable
     - May have bugs or incomplete features
     - Good for power users who want early access
     
     Default: false (stable channel)
     */
    @Published var betaUpdatesEnabled: Bool {
        didSet {
            defaults.set(betaUpdatesEnabled, forKey: Keys.betaUpdatesEnabled.rawValue)
            // Sync with UpdateChecker's setting
            UpdateChecker.shared.isBetaChannelEnabled = betaUpdatesEnabled
            print("📍 Update channel: \(betaUpdatesEnabled ? "BETA" : "STABLE")")
        }
    }
    
    // ================================================================
    // MARK: - Dimming Settings
    // ================================================================
    
    /**
     Master toggle for the dimming feature.
     
     When false, no overlays are created and analysis stops.
     This is the main "off switch" for the app's core functionality.
     */
    @Published var isDimmingEnabled: Bool {
        didSet {
            defaults.set(isDimmingEnabled, forKey: Keys.isDimmingEnabled.rawValue)
            // Notify dimming coordinator to start/stop
            NotificationCenter.default.post(
                name: .dimmingEnabledChanged,
                object: nil,
                userInfo: ["enabled": isDimmingEnabled]
            )
        }
    }
    
    /**
     Global dim level applied to bright regions.
     
     Range: 0.0 (no dimming) to 0.8 (80% opacity black overlay)
     Default: 0.25 (25% dim)
     
     WHY MAX 0.8:
     - Going to 1.0 would make content completely invisible
     - 0.8 still allows content to be readable
     - Users who need more can adjust display brightness
     */
    @Published var globalDimLevel: Double {
        didSet {
            defaults.set(globalDimLevel, forKey: Keys.globalDimLevel.rawValue)
        }
    }
    
    /**
     Brightness threshold for triggering dimming.
     
     Range: 0.0 to 1.0 (representing 0-100% brightness)
     Default: 0.85 (85%)
     
     Areas with luminance above this threshold are considered "bright"
     and will have dimming applied. Lower values = more aggressive dimming.
     
     LUMINANCE CALCULATION:
     Uses Rec. 709: Y' = 0.2126*R + 0.7152*G + 0.0722*B
     */
    @Published var brightnessThreshold: Double {
        didSet {
            defaults.set(brightnessThreshold, forKey: Keys.brightnessThreshold.rawValue)
        }
    }
    
    /**
     Dim level for active (frontmost) windows.
     
     Range: 0.0 to 0.5
     Default: 0.15 (15% dim)
     
     Active windows get lighter dimming so you can clearly see
     what you're working on. Only applied when differentiateActiveInactive is true.
     */
    @Published var activeDimLevel: Double {
        didSet {
            defaults.set(activeDimLevel, forKey: Keys.activeDimLevel.rawValue)
        }
    }
    
    /**
     Dim level for inactive (background) windows.
     
     Range: 0.0 to 0.8
     Default: 0.35 (35% dim)
     
     Inactive windows can be dimmed more aggressively since you're
     not actively looking at them. Only applied when differentiateActiveInactive is true.
     */
    @Published var inactiveDimLevel: Double {
        didSet {
            defaults.set(inactiveDimLevel, forKey: Keys.inactiveDimLevel.rawValue)
        }
    }
    
    /**
     Whether to apply different dim levels to active vs inactive windows.
     
     When true: active windows use activeDimLevel, inactive use inactiveDimLevel
     When false: all windows use globalDimLevel uniformly
     
     This is a Pro feature - gated by license.
     */
    @Published var differentiateActiveInactive: Bool {
        didSet {
            defaults.set(differentiateActiveInactive, forKey: Keys.differentiateActiveInactive.rawValue)
        }
    }
    
    /**
     Whether to use intelligent per-window dimming.
     
     When true: Analyzes each window's brightness and dims individually
     When false: Uses simple full-screen dimming (Phase 1 mode)
     
     Intelligent mode requires Screen Recording permission.
     If permission not granted, falls back to simple mode automatically.
     
     This is a Pro feature - requires license for per-window targeting.
     */
    @Published var intelligentDimmingEnabled: Bool {
        didSet {
            defaults.set(intelligentDimmingEnabled, forKey: Keys.intelligentDimmingEnabled.rawValue)
        }
    }
    
    /**
     The detection mode for intelligent dimming.
     
     - perWindow: Analyzes entire window brightness, dims whole window
     - perRegion: Finds bright AREAS within windows, dims only those regions
     
     perRegion mode is the killer feature - it handles cases like:
     - Dark mode Mail app with bright white email content
     - Code editor with bright preview pane
     - Any app where only part of the window is bright
     */
    @Published var detectionMode: DetectionMode {
        didSet {
            defaults.set(detectionMode.rawValue, forKey: Keys.detectionMode.rawValue)
        }
    }
    
    /**
     Grid size for region detection (NxN grid).
     
     Higher values = more precise detection but more overlays.
     - 4 = 16 regions (fast, coarse)
     - 8 = 64 regions (balanced)
     - 16 = 256 regions (precise, slower)
     
     Default: 8
     */
    @Published var regionGridSize: Int {
        didSet {
            defaults.set(regionGridSize, forKey: Keys.regionGridSize.rawValue)
        }
    }
    
    /**
     Interval between brightness analysis cycles (seconds).
     
     Range: 0.5 to 5.0 seconds
     Default: 1.0 second
     
     Lower values = more responsive but higher CPU usage.
     Higher values = less responsive but better battery life.
     */
    @Published var scanInterval: Double {
        didSet {
            defaults.set(scanInterval, forKey: Keys.scanInterval.rawValue)
        }
    }
    
    /**
     Interval between window tracking updates (seconds).
     
     This is SEPARATE from scanInterval because:
     - Brightness analysis (scanInterval): CPU-intensive screenshots, runs slower
     - Window tracking (this): Lightweight position/z-order updates, runs faster
     
     Window tracking handles:
     - Overlay position following window movement
     - Z-order updates when focus changes
     - Removing overlays for hidden/minimized windows
     
     Range: 0.1 to 2.0 seconds
     Default: 0.5 seconds (faster than brightness scan)
     
     Lower values = more responsive window following
     Higher values = less CPU usage
     */
    @Published var windowTrackingInterval: Double {
        didSet {
            defaults.set(windowTrackingInterval, forKey: Keys.windowTrackingInterval.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Super Dimming Auto Mode (2.2.1.2)
    // ================================================================
    
    /**
     Whether Super Dimming Auto mode is enabled.
     
     AUTO MODE BEHAVIOR:
     When enabled, the dim level automatically adjusts based on the overall
     brightness of your screen content. This is different from the basic
     ON/OFF mode which applies a fixed dim level.
     
     - Bright screen content → dimming increases (up to +autoAdjustRange)
     - Dark screen content → dimming decreases (down to -autoAdjustRange)
     
     This creates an adaptive experience where the dimming matches what
     you're viewing. E.g., if you open a bright website, dimming increases
     automatically; if you switch to a dark IDE, dimming backs off.
     
     CALCULATION:
     currentDim = baseDimLevel + (screenBrightness - 0.5) * autoAdjustRange * 2
     
     So with baseDimLevel=0.25, autoAdjustRange=0.15:
     - Screen brightness 1.0 (very bright) → 0.25 + 0.5*0.3 = 0.40 (40% dim)
     - Screen brightness 0.5 (neutral) → 0.25 (25% dim - base)
     - Screen brightness 0.0 (dark) → 0.25 - 0.5*0.3 = 0.10 (10% dim)
     
     Default: true (Auto mode is the default experience)
     */
    @Published var superDimmingAutoEnabled: Bool {
        didSet {
            defaults.set(superDimmingAutoEnabled, forKey: Keys.superDimmingAutoEnabled.rawValue)
        }
    }
    
    /**
     The adjustment range for Auto mode (±X%).
     
     Range: 0.05 to 0.30 (5% to 30%)
     Default: 0.15 (±15%)
     
     Higher values = more dramatic adjustment based on screen brightness
     Lower values = subtler adjustment, closer to fixed dimming
     
     At 0.15, dim level can swing ±15% from the base globalDimLevel.
     So if globalDimLevel is 25%, actual dimming ranges from 10% to 40%
     depending on screen content.
     */
    @Published var autoAdjustRange: Double {
        didSet {
            defaults.set(autoAdjustRange, forKey: Keys.autoAdjustRange.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Debug Settings
    // ================================================================
    
    /**
     Debug mode: Shows colored borders around dim overlays.
     
     When enabled, overlays will have a red border so you can see exactly
     where they are positioned. Useful for diagnosing coordinate issues.
     
     Default: false (disabled)
     */
    @Published var debugOverlayBorders: Bool {
        didSet {
            defaults.set(debugOverlayBorders, forKey: Keys.debugOverlayBorders.rawValue)
        }
    }
    
    /**
     Corner radius for overlay windows (in points).
     
     FEATURE: 2.8.2b - Rounded Corners for Overlays
     
     Provides a softer, more polished look than hard rectangular edges.
     Uses CALayer.cornerRadius which is GPU-accelerated and performant.
     
     Range: 0.0 (sharp corners) to 20.0 (very rounded)
     Default: 8.0 points
     
     WHY THIS APPROACH:
     - Simple and reliable (just layer.cornerRadius)
     - GPU-accelerated (no performance impact)
     - Works perfectly with debug borders
     - No visual artifacts during animations
     - Cleaner than mask-based feathered edges
     
     Setting to 0 gives sharp edges for users who prefer that look.
     */
    @Published var overlayCornerRadius: Double {
        didSet {
            defaults.set(overlayCornerRadius, forKey: Keys.overlayCornerRadius.rawValue)
            // Notify overlay manager to update all existing overlays
            NotificationCenter.default.post(
                name: .overlayCornerRadiusChanged,
                object: nil,
                userInfo: ["radius": overlayCornerRadius]
            )
        }
    }
    
    /**
     Whether the app is running in developer mode.
     
     IMPLEMENTATION (2.2.1.6):
     Dev mode is true when:
     1. Running a DEBUG build, OR
     2. User has enabled devToolsUnlocked flag (via hidden gesture)
     
     When true, additional developer tools are visible in Preferences:
     - Debug Borders toggle
     - Analysis timing logs
     - Force refresh buttons
     - Overlay count displays
     */
    var isDevMode: Bool {
        // Check if this is a DEBUG build
        #if DEBUG
        return true
        #else
        // Check if user has unlocked dev tools manually
        return defaults.bool(forKey: "superdimmer.devToolsUnlocked")
        #endif
    }
    
    /**
     Unlocks developer tools in release builds.
     
     This can be toggled via a hidden gesture (e.g., Option+Click version 5 times)
     to enable dev tools without recompiling.
     */
    func toggleDevTools() {
        let current = defaults.bool(forKey: "superdimmer.devToolsUnlocked")
        defaults.set(!current, forKey: "superdimmer.devToolsUnlocked")
        print(current ? "🔧 Dev tools LOCKED" : "🔧 Dev tools UNLOCKED")
    }
    
    // ================================================================
    // MARK: - Inactivity Decay Dimming
    // ================================================================
    
    /**
     Whether inactivity decay dimming is enabled.
     
     When true, windows that haven't been active for a while will
     progressively dim more, creating a visual hierarchy that
     emphasizes the active window.
     */
    @Published var inactivityDecayEnabled: Bool {
        didSet {
            defaults.set(inactivityDecayEnabled, forKey: Keys.inactivityDecayEnabled.rawValue)
        }
    }
    
    /**
     Rate at which inactive windows decay (dim increase per second).
     
     Range: 0.005 to 0.05 (0.5% to 5% per second)
     Default: 0.01 (1% per second)
     
     At default rate, a window would reach max decay after ~40 seconds
     of inactivity (assuming 30s delay + 40s to reach 40% additional dim).
     */
    @Published var decayRate: Double {
        didSet {
            defaults.set(decayRate, forKey: Keys.decayRate.rawValue)
        }
    }
    
    /**
     Seconds of inactivity before decay starts.
     
     Range: 5 to 120 seconds
     Default: 30 seconds
     
     This grace period prevents decay from starting immediately
     when you briefly switch to another window.
     */
    @Published var decayStartDelay: TimeInterval {
        didSet {
            defaults.set(decayStartDelay, forKey: Keys.decayStartDelay.rawValue)
        }
    }
    
    /**
     Maximum dim level from decay (cap).
     
     Range: 0.0 to 1.0 (0% to 100%)
     Default: 0.8 (80%)
     
     CHANGED (Jan 8, 2026): Now allows full 0-100% range.
     At 100%, windows will become completely black after full decay.
     */
    @Published var maxDecayDimLevel: Double {
        didSet {
            defaults.set(maxDecayDimLevel, forKey: Keys.maxDecayDimLevel.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Excluded Apps
    // ================================================================
    
    /**
     Bundle IDs of apps that should never have their windows dimmed.
     
     LEGACY: This is kept for migration. Use `appExclusions` instead.
     
     Users can add apps that:
     - Have their own dark mode or dimming
     - Need precise color accuracy (design tools)
     - Should remain bright for specific workflows
     
     Example: ["com.adobe.Photoshop", "com.apple.FaceTime"]
     */
    @Published var excludedAppBundleIDs: [String] {
        didSet {
            defaults.set(excludedAppBundleIDs, forKey: Keys.excludedAppBundleIDs.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Per-Feature App Exclusions (2.2.1.12)
    // ================================================================
    
    /**
     Unified list of app exclusions with per-feature checkboxes.
     
     This replaces the old separate exclusion lists:
     - excludedAppBundleIDs (dimming)
     - autoHideExcludedApps (auto-hide)
     - autoMinimizeExcludedApps (auto-minimize)
     
     Each app can be excluded from:
     - Brightness dimming overlays
     - Decay dimming (inactivity fade)
     - Auto-hide (automatic app hiding)
     - Auto-minimize (automatic window minimizing)
     */
    @Published var appExclusions: [AppExclusion] {
        didSet {
            saveAppExclusions()
        }
    }
    
    /// Saves app exclusions to UserDefaults as JSON
    private func saveAppExclusions() {
        if let data = try? JSONEncoder().encode(appExclusions) {
            defaults.set(data, forKey: Keys.appExclusions.rawValue)
        }
    }
    
    /// Loads app exclusions from UserDefaults
    private func loadAppExclusions() -> [AppExclusion] {
        guard let data = defaults.data(forKey: Keys.appExclusions.rawValue),
              let exclusions = try? JSONDecoder().decode([AppExclusion].self, from: data) else {
            return []
        }
        return exclusions
    }
    
    // ================================================================
    // MARK: - Exclusion Helper Methods
    // ================================================================
    
    /**
     Checks if an app is excluded from a specific feature.
     
     - Parameters:
       - feature: The feature to check
       - bundleID: The app's bundle identifier
     - Returns: true if the app should be excluded from that feature
     */
    func isAppExcluded(from feature: ExclusionFeature, bundleID: String) -> Bool {
        guard let exclusion = appExclusions.first(where: { $0.bundleID == bundleID }) else {
            return false
        }
        
        switch feature {
        case .dimming:
            return exclusion.excludeFromDimming
        case .decayDimming:
            return exclusion.excludeFromDecayDimming
        case .autoHide:
            return exclusion.excludeFromAutoHide
        case .autoMinimize:
            return exclusion.excludeFromAutoMinimize
        }
    }
    
    /**
     Gets the exclusion entry for an app, if it exists.
     
     - Parameter bundleID: The app's bundle identifier
     - Returns: The AppExclusion if found, nil otherwise
     */
    func getExclusion(for bundleID: String) -> AppExclusion? {
        return appExclusions.first { $0.bundleID == bundleID }
    }
    
    /**
     Adds or updates an app exclusion.
     
     - Parameter exclusion: The exclusion to add/update
     */
    func setExclusion(_ exclusion: AppExclusion) {
        if let index = appExclusions.firstIndex(where: { $0.bundleID == exclusion.bundleID }) {
            appExclusions[index] = exclusion
        } else {
            appExclusions.append(exclusion)
        }
    }
    
    /**
     Removes an app from the exclusions list.
     
     - Parameter bundleID: The app's bundle identifier
     */
    func removeExclusion(for bundleID: String) {
        appExclusions.removeAll { $0.bundleID == bundleID }
    }
    
    /**
     Toggles a specific feature exclusion for an app.
     Creates the exclusion entry if it doesn't exist.
     
     - Parameters:
       - feature: The feature to toggle
       - bundleID: The app's bundle identifier
       - appName: Optional app name (resolved from bundle ID if not provided)
     */
    func toggleExclusion(feature: ExclusionFeature, for bundleID: String, appName: String? = nil) {
        var exclusion = getExclusion(for: bundleID) ?? AppExclusion(bundleID: bundleID, appName: appName)
        
        switch feature {
        case .dimming:
            exclusion.excludeFromDimming.toggle()
        case .decayDimming:
            exclusion.excludeFromDecayDimming.toggle()
        case .autoHide:
            exclusion.excludeFromAutoHide.toggle()
        case .autoMinimize:
            exclusion.excludeFromAutoMinimize.toggle()
        }
        
        // If all flags are off, remove the entry
        if !exclusion.hasAnyExclusion {
            removeExclusion(for: bundleID)
        } else {
            setExclusion(exclusion)
        }
    }
    
    // ================================================================
    // MARK: - Auto-Hide Inactive Apps Settings
    // ================================================================
    
    /**
     Master toggle for auto-hiding inactive apps.
     
     When enabled, apps that haven't been used for `autoHideDelay` minutes
     will be automatically hidden (like pressing Cmd+H).
     
     Default: true (ON by default - this is a non-destructive feature)
     */
    @Published var autoHideEnabled: Bool {
        didSet {
            defaults.set(autoHideEnabled, forKey: Keys.autoHideEnabled.rawValue)
        }
    }
    
    /**
     Minutes of inactivity before an app is auto-hidden.
     
     Range: 5-120 minutes
     Default: 30 minutes
     
     The timer starts when an app loses focus. If the user returns to the app
     before the delay, the timer resets.
     */
    @Published var autoHideDelay: Double {
        didSet {
            defaults.set(autoHideDelay, forKey: Keys.autoHideDelay.rawValue)
        }
    }
    
    /**
     Bundle IDs of apps that should never be auto-hidden.
     
     These apps will remain visible regardless of inactivity.
     Example: ["com.apple.finder", "com.apple.systempreferences"]
     */
    @Published var autoHideExcludedApps: [String] {
        didSet {
            defaults.set(autoHideExcludedApps, forKey: Keys.autoHideExcludedApps.rawValue)
        }
    }
    
    /**
     Whether to automatically exclude system apps from auto-hide.
     
     When true, apps like Finder, System Preferences, Activity Monitor
     will never be auto-hidden. Default: true
     */
    @Published var autoHideExcludeSystemApps: Bool {
        didSet {
            defaults.set(autoHideExcludeSystemApps, forKey: Keys.autoHideExcludeSystemApps.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Auto-Minimize Inactive Windows Settings
    // ================================================================
    
    /**
     Master toggle for auto-minimizing inactive windows.
     
     When enabled, windows that have been inactive for `autoMinimizeDelay`
     minutes of ACTIVE user time will be minimized to the Dock IF the
     app has more than `autoMinimizeWindowThreshold` windows open.
     
     IMPORTANT: This only counts active usage time (mouse/keyboard activity).
     Walking away won't cause windows to minimize.
     
     Default: false (OFF by default - this is more aggressive)
     */
    @Published var autoMinimizeEnabled: Bool {
        didSet {
            defaults.set(autoMinimizeEnabled, forKey: Keys.autoMinimizeEnabled.rawValue)
        }
    }
    
    /**
     Minutes of ACTIVE use before inactive windows are minimized.
     
     Range: 5-60 minutes
     Default: 15 minutes
     
     NOTE: This only counts time when the user is actively using the computer
     (mouse movement, keyboard input). Idle time doesn't count.
     */
    @Published var autoMinimizeDelay: Double {
        didSet {
            defaults.set(autoMinimizeDelay, forKey: Keys.autoMinimizeDelay.rawValue)
        }
    }
    
    /**
     Minutes of user idle time that resets ALL window minimize timers.
     
     Range: 2-30 minutes
     Default: 5 minutes
     
     WHY: If you walk away for 5+ minutes (coffee break, meeting),
     all timers reset. This prevents coming back to everything minimized.
     Also resets on wake from sleep.
     */
    @Published var autoMinimizeIdleResetTime: Double {
        didSet {
            defaults.set(autoMinimizeIdleResetTime, forKey: Keys.autoMinimizeIdleResetTime.rawValue)
        }
    }
    
    /**
     Minimum windows per app before auto-minimize kicks in.
     
     Range: 1-10
     Default: 3
     
     Example: If set to 3 and Cursor has 8 windows, the 5 oldest inactive
     windows will be minimized (leaving 3). If Cursor has 2 windows, none
     will be minimized.
     */
    @Published var autoMinimizeWindowThreshold: Int {
        didSet {
            defaults.set(autoMinimizeWindowThreshold, forKey: Keys.autoMinimizeWindowThreshold.rawValue)
        }
    }
    
    /**
     Bundle IDs of apps that should never have windows auto-minimized.
     
     These apps' windows will remain visible regardless of count or inactivity.
     Example: ["com.apple.finder", "com.apple.mail"]
     */
    @Published var autoMinimizeExcludedApps: [String] {
        didSet {
            defaults.set(autoMinimizeExcludedApps, forKey: Keys.autoMinimizeExcludedApps.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - SuperFocus (2.2.1.5)
    // ================================================================
    
    /**
     Master toggle for SuperFocus productivity mode.
     
     SUPERFOCUS CONCEPT:
     SuperFocus groups all productivity-focused features together,
     making it easy to enable/disable the entire "focus mode" with one toggle.
     
     FEATURES GROUPED:
     - Inactivity Decay Dimming: Dims inactive windows to emphasize active work
     - Auto-Hide Inactive Apps: Hides apps not used recently
     - Auto-Minimize Windows: Reduces window clutter per app
     
     BEHAVIOR:
     - When SuperFocus is enabled: All grouped features are enabled
     - When SuperFocus is disabled: Individual features remain at their settings
       (user can still enable them individually)
     
     This allows two workflows:
     1. Quick: Toggle SuperFocus to enable/disable all productivity features
     2. Custom: Disable SuperFocus and configure features individually
     
     Default: false (off by default, user opts-in)
     */
    @Published var superFocusEnabled: Bool {
        didSet {
            defaults.set(superFocusEnabled, forKey: Keys.superFocusEnabled.rawValue)
            
            // When SuperFocus is turned ON, enable all grouped features
            // When turned OFF, leave individual settings as-is
            if superFocusEnabled {
                inactivityDecayEnabled = true
                autoHideEnabled = true
                autoMinimizeEnabled = true
            }
        }
    }
    
    // ================================================================
    // MARK: - Color Temperature Settings
    // ================================================================
    
    /**
     Master toggle for color temperature feature.
     
     When true, display gamma is adjusted to warm colors.
     Similar to f.lux blue light filter.
     */
    @Published var colorTemperatureEnabled: Bool {
        didSet {
            defaults.set(colorTemperatureEnabled, forKey: Keys.colorTemperatureEnabled.rawValue)
            // Notify color temperature engine to update
            NotificationCenter.default.post(
                name: .colorTemperatureEnabledChanged,
                object: nil,
                userInfo: ["enabled": colorTemperatureEnabled]
            )
        }
    }
    
    /**
     Current color temperature in Kelvin.
     
     Range: 1900K (candlelight) to 6500K (daylight)
     Default: 6500K (no color shift)
     
     Lower values = warmer/orange tint = less blue light
     Higher values = cooler/white = more blue light
     */
    @Published var colorTemperature: Double {
        didSet {
            defaults.set(colorTemperature, forKey: Keys.colorTemperature.rawValue)
            // Notify color temperature engine to update
            NotificationCenter.default.post(
                name: .colorTemperatureChanged,
                object: nil,
                userInfo: ["temperature": colorTemperature]
            )
        }
    }
    
    /**
     Whether automatic scheduling is enabled for color temperature.
     
     When true, temperature follows a schedule (manual times or sunrise/sunset).
     When false, manual temperature setting is used.
     */
    @Published var colorTemperatureScheduleEnabled: Bool {
        didSet {
            defaults.set(colorTemperatureScheduleEnabled, forKey: Keys.colorTemperatureScheduleEnabled.rawValue)
        }
    }
    
    /**
     Day temperature in Kelvin (neutral/cool).
     Used when outside of night schedule.
     Default: 6500K (daylight)
     */
    @Published var dayTemperature: Double {
        didSet {
            defaults.set(dayTemperature, forKey: Keys.dayTemperature.rawValue)
        }
    }
    
    /**
     Night temperature in Kelvin (warm).
     Used during night schedule.
     Default: 2700K (warm white)
     */
    @Published var nightTemperature: Double {
        didSet {
            defaults.set(nightTemperature, forKey: Keys.nightTemperature.rawValue)
        }
    }
    
    /**
     Start time for night schedule (when to start warming).
     Stored as hour component.
     Default: 20 (8:00 PM)
     */
    @Published var scheduleStartHour: Int {
        didSet {
            defaults.set(scheduleStartHour, forKey: Keys.scheduleStartHour.rawValue)
        }
    }
    
    /**
     Start time for night schedule (minute component).
     Default: 0
     */
    @Published var scheduleStartMinute: Int {
        didSet {
            defaults.set(scheduleStartMinute, forKey: Keys.scheduleStartMinute.rawValue)
        }
    }
    
    /**
     End time for night schedule (when to return to day).
     Stored as hour component.
     Default: 7 (7:00 AM)
     */
    @Published var scheduleEndHour: Int {
        didSet {
            defaults.set(scheduleEndHour, forKey: Keys.scheduleEndHour.rawValue)
        }
    }
    
    /**
     End time for night schedule (minute component).
     Default: 0
     */
    @Published var scheduleEndMinute: Int {
        didSet {
            defaults.set(scheduleEndMinute, forKey: Keys.scheduleEndMinute.rawValue)
        }
    }
    
    /**
     Duration of gradual transition in seconds.
     Default: 60 (1 minute)
     */
    @Published var transitionDuration: TimeInterval {
        didSet {
            defaults.set(transitionDuration, forKey: Keys.transitionDuration.rawValue)
        }
    }
    
    /**
     Whether to use location-based sunrise/sunset times.
     When true, uses LocationService for schedule.
     When false, uses manual scheduleStartTime/scheduleEndTime.
     */
    @Published var useLocationBasedSchedule: Bool {
        didSet {
            defaults.set(useLocationBasedSchedule, forKey: Keys.useLocationBasedSchedule.rawValue)
        }
    }
    
    /// Computed property: Schedule start time as Date
    var scheduleStartTime: Date {
        Calendar.current.date(bySettingHour: scheduleStartHour, minute: scheduleStartMinute, second: 0, of: Date()) ?? Date()
    }
    
    /// Computed property: Schedule end time as Date
    var scheduleEndTime: Date {
        Calendar.current.date(bySettingHour: scheduleEndHour, minute: scheduleEndMinute, second: 0, of: Date()) ?? Date()
    }
    
    // ================================================================
    // MARK: - Wallpaper Settings
    // ================================================================
    
    /**
     Whether to automatically switch wallpapers with appearance mode.
     
     When true, switching Light ↔ Dark mode will change wallpaper
     to the paired wallpaper for that mode.
     */
    @Published var wallpaperAutoSwitchEnabled: Bool {
        didSet {
            defaults.set(wallpaperAutoSwitchEnabled, forKey: Keys.wallpaperAutoSwitchEnabled.rawValue)
        }
    }
    
    /**
     Whether wallpaper dimming is enabled.
     
     When true, a dim overlay is placed above the wallpaper but
     below windows, dimming just the desktop.
     */
    @Published var wallpaperDimEnabled: Bool {
        didSet {
            defaults.set(wallpaperDimEnabled, forKey: Keys.wallpaperDimEnabled.rawValue)
        }
    }
    
    /**
     Dim level for wallpaper.
     
     Range: 0.0 to 0.8
     Default: 0.3 (30% dim)
     */
    @Published var wallpaperDimLevel: Double {
        didSet {
            defaults.set(wallpaperDimLevel, forKey: Keys.wallpaperDimLevel.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Super Spaces Settings (Jan 21, 2026)
    // ================================================================
    
    /**
     Whether Super Spaces HUD is enabled.
     
     FEATURE: Super Spaces - Floating HUD for Space navigation
     
     When true, users can toggle the Super Spaces HUD with a keyboard shortcut
     to see current Space and switch between Spaces.
     
     DEFAULT: false (opt-in feature)
     */
    @Published var superSpacesEnabled: Bool {
        didSet {
            defaults.set(superSpacesEnabled, forKey: Keys.superSpacesEnabled.rawValue)
        }
    }
    
    /**
     Custom names for Spaces.
     
     Dictionary mapping Space number (1-based) to custom name.
     Example: [1: "Email", 2: "Browse", 3: "Development"]
     
     DEFAULT: Empty (uses default names)
     */
    @Published var spaceNames: [Int: String] {
        didSet {
            // Convert Int keys to String keys for UserDefaults
            let stringKeyDict = Dictionary(uniqueKeysWithValues: spaceNames.map { (String($0.key), $0.value) })
            defaults.set(stringKeyDict, forKey: Keys.spaceNames.rawValue)
        }
    }
    
    /**
     Display mode for Super Spaces HUD.
     
     VALUES:
     - "mini": Minimal (arrows and number)
     - "compact": Numbered buttons (default)
     - "expanded": Grid with names
     
     DEFAULT: "compact"
     */
    @Published var superSpacesDisplayMode: String {
        didSet {
            defaults.set(superSpacesDisplayMode, forKey: Keys.superSpacesDisplayMode.rawValue)
        }
    }
    
    /**
     Whether Super Spaces HUD should auto-hide after switching.
     
     When true, HUD automatically hides after user switches Spaces.
     When false, HUD stays visible until manually closed.
     
     DEFAULT: false (stays visible)
     */
    @Published var superSpacesAutoHide: Bool {
        didSet {
            defaults.set(superSpacesAutoHide, forKey: Keys.superSpacesAutoHide.rawValue)
        }
    }
    
    // ================================================================
    // MARK: - Appearance Mode System (2.2.1.1)
    // ================================================================
    
    /**
     The user's appearance mode preference.
     
     FEATURE: 2.2.1.1 - Appearance Mode System
     
     VALUES:
     - .system: Automatically follow macOS Light/Dark mode
     - .light: Force Light mode profile regardless of system
     - .dark: Force Dark mode profile regardless of system
     
     DEFAULT: .system (follows macOS)
     
     BEHAVIOR:
     When this changes, or when system appearance changes (if .system),
     the app loads the appropriate profile (darkModeProfile or lightModeProfile)
     and applies those settings to the active @Published properties.
     
     WHY SEPARATE FROM SETTINGS:
     We store TWO complete profiles (one for Light, one for Dark) but only
     ONE set is "active" at any time. The active settings are what the rest
     of the app reads. This allows seamless switching without losing preferences.
     */
    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode.rawValue)
            // When user changes appearance mode, load the appropriate profile
            loadProfileForCurrentAppearance()
        }
    }
    
    /**
     Dimming settings profile for Dark Mode.
     
     USAGE:
     - Loaded when system appearance is dark (if appearanceMode == .system)
     - Loaded when user forces dark mode (if appearanceMode == .dark)
     - Updated whenever settings change while in dark mode
     
     DEFAULT:
     Aggressive dimming ON by default. Dark mode users benefit from dimming.
     */
    @Published var darkModeProfile: DimmingProfile {
        didSet {
            // Save profile to UserDefaults as JSON
            if let encoded = try? JSONEncoder().encode(darkModeProfile) {
                defaults.set(encoded, forKey: Keys.darkModeProfile.rawValue)
            }
            // If currently in dark mode, apply the profile changes immediately
            if getCurrentActiveAppearance() == .dark {
                loadProfileForCurrentAppearance()
            }
        }
    }
    
    /**
     Dimming settings profile for Light Mode.
     
     USAGE:
     - Loaded when system appearance is light (if appearanceMode == .system)
     - Loaded when user forces light mode (if appearanceMode == .light)
     - Updated whenever settings change while in light mode
     
     DEFAULT:
     Minimal or no dimming. Light mode users typically don't want aggressive dimming.
     */
    @Published var lightModeProfile: DimmingProfile {
        didSet {
            // Save profile to UserDefaults as JSON
            if let encoded = try? JSONEncoder().encode(lightModeProfile) {
                defaults.set(encoded, forKey: Keys.lightModeProfile.rawValue)
            }
            // If currently in light mode, apply the profile changes immediately
            if getCurrentActiveAppearance() == .light {
                loadProfileForCurrentAppearance()
            }
        }
    }
    
    /**
     The AppearanceManager instance for observing system appearance changes.
     
     LIFECYCLE:
     - Initialized in init()
     - Started in init() with callback to loadProfileForCurrentAppearance()
     - Stopped when app terminates (handled by AppearanceManager's deinit)
     */
    private var appearanceManager: AppearanceManager?
    
    /**
     Flag to indicate we're currently loading a profile.
     
     PERFORMANCE FIX (Jan 16, 2026):
     When loading profiles, we update many @Published properties at once.
     This flag helps avoid redundant observer triggers during bulk updates.
     */
    private var isLoadingProfile: Bool = false
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Private initializer enforces singleton pattern.
     Loads saved values from UserDefaults or uses defaults.
     */
    private init() {
        // ============================================================
        // Load General Settings
        // ============================================================
        // For first launch, there's no saved value, so we default to true
        // This will be set to false after onboarding completes
        self.isFirstLaunch = defaults.object(forKey: Keys.isFirstLaunch.rawValue) == nil ?
            true : defaults.bool(forKey: Keys.isFirstLaunch.rawValue)
        
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin.rawValue)
        
        self.betaUpdatesEnabled = defaults.bool(forKey: Keys.betaUpdatesEnabled.rawValue)
        
        // ============================================================
        // Load Dimming Settings
        // ============================================================
        // FIRST LAUNCH EXPERIENCE (2.2.1.9):
        // Super Dimming should be ON by default on first launch.
        // This provides immediate value and demonstrates the core feature.
        // Users can turn it off if they don't want it.
        self.isDimmingEnabled = defaults.object(forKey: Keys.isDimmingEnabled.rawValue) != nil ?
            defaults.bool(forKey: Keys.isDimmingEnabled.rawValue) : true  // ON by default
        
        self.globalDimLevel = defaults.object(forKey: Keys.globalDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.globalDimLevel.rawValue) : 0.25
        
        self.brightnessThreshold = defaults.object(forKey: Keys.brightnessThreshold.rawValue) != nil ?
            defaults.double(forKey: Keys.brightnessThreshold.rawValue) : 0.85
        
        self.activeDimLevel = defaults.object(forKey: Keys.activeDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.activeDimLevel.rawValue) : 0.15
        
        self.inactiveDimLevel = defaults.object(forKey: Keys.inactiveDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.inactiveDimLevel.rawValue) : 0.35
        
        self.differentiateActiveInactive = defaults.object(forKey: Keys.differentiateActiveInactive.rawValue) != nil ?
            defaults.bool(forKey: Keys.differentiateActiveInactive.rawValue) : true
        
        self.intelligentDimmingEnabled = defaults.object(forKey: Keys.intelligentDimmingEnabled.rawValue) != nil ?
            defaults.bool(forKey: Keys.intelligentDimmingEnabled.rawValue) : false  // Default OFF - users can enable
        
        // Load detection mode (perWindow or perRegion)
        if let modeString = defaults.string(forKey: Keys.detectionMode.rawValue),
           let mode = DetectionMode(rawValue: modeString) {
            self.detectionMode = mode
        } else {
            self.detectionMode = .perWindow  // Default to simpler per-window mode
        }
        
        // FIX (Jan 8, 2026): Reduced default from 8 to 6 for larger, more cohesive regions
        // Smaller grids = fewer, larger cells = larger bright region detections
        self.regionGridSize = defaults.object(forKey: Keys.regionGridSize.rawValue) != nil ?
            defaults.integer(forKey: Keys.regionGridSize.rawValue) : 6  // 6x6 grid default (was 8x8)
        
        // Default scan interval: 2.0 seconds for per-region mode (heavy analysis)
        // Can be reduced to 1.0 or 0.5 for per-window mode which is faster
        self.scanInterval = defaults.object(forKey: Keys.scanInterval.rawValue) != nil ?
            defaults.double(forKey: Keys.scanInterval.rawValue) : 2.0
        
        // Window tracking interval: 0.5 seconds (faster than brightness analysis)
        // This controls how often we update overlay positions and z-order
        // Lightweight operation - just window list enumeration, no screenshots
        self.windowTrackingInterval = defaults.object(forKey: Keys.windowTrackingInterval.rawValue) != nil ?
            defaults.double(forKey: Keys.windowTrackingInterval.rawValue) : 0.5
        
        // ============================================================
        // Load Super Dimming Auto Mode Settings (2.2.1.2)
        // ============================================================
        // Super Dimming Auto is the DEFAULT experience - automatically adjusts
        // dim level based on screen brightness for seamless comfort
        self.superDimmingAutoEnabled = defaults.object(forKey: Keys.superDimmingAutoEnabled.rawValue) != nil ?
            defaults.bool(forKey: Keys.superDimmingAutoEnabled.rawValue) : true  // ON by default
        
        // ±15% adjustment range - dim level swings 15% above/below base based on screen brightness
        self.autoAdjustRange = defaults.object(forKey: Keys.autoAdjustRange.rawValue) != nil ?
            defaults.double(forKey: Keys.autoAdjustRange.rawValue) : 0.15
        
        // Debug mode - shows red borders on overlays for positioning verification
        self.debugOverlayBorders = defaults.bool(forKey: Keys.debugOverlayBorders.rawValue)
        
        // Overlay corner radius (2.8.2b - Rounded Corners)
        self.overlayCornerRadius = defaults.object(forKey: Keys.overlayCornerRadius.rawValue) != nil ?
            defaults.double(forKey: Keys.overlayCornerRadius.rawValue) : 8.0  // 8pt default
        
        // ============================================================
        // Load Inactivity Decay Settings
        // ============================================================
        self.inactivityDecayEnabled = defaults.bool(forKey: Keys.inactivityDecayEnabled.rawValue)
        
        self.decayRate = defaults.object(forKey: Keys.decayRate.rawValue) != nil ?
            defaults.double(forKey: Keys.decayRate.rawValue) : 0.01  // 1% per second
        
        self.decayStartDelay = defaults.object(forKey: Keys.decayStartDelay.rawValue) != nil ?
            defaults.double(forKey: Keys.decayStartDelay.rawValue) : 30.0  // 30 seconds
        
        self.maxDecayDimLevel = defaults.object(forKey: Keys.maxDecayDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.maxDecayDimLevel.rawValue) : 0.8  // 80% max (can go to 100%)
        
        // ============================================================
        // Load Excluded Apps (Legacy)
        // ============================================================
        self.excludedAppBundleIDs = defaults.object(forKey: Keys.excludedAppBundleIDs.rawValue) as? [String] ?? []
        
        // ============================================================
        // Load Per-Feature App Exclusions (2.2.1.12)
        // ============================================================
        // Initialize first (required before self is available)
        self.appExclusions = []
        // Then load from storage
        if let data = defaults.data(forKey: Keys.appExclusions.rawValue),
           let exclusions = try? JSONDecoder().decode([AppExclusion].self, from: data) {
            self.appExclusions = exclusions
        }
        
        // ============================================================
        // Load Auto-Hide Settings
        // ============================================================
        // NOTE: Auto-Hide is ON by default (non-destructive feature)
        self.autoHideEnabled = defaults.object(forKey: Keys.autoHideEnabled.rawValue) != nil ?
            defaults.bool(forKey: Keys.autoHideEnabled.rawValue) : true  // ON by default
        
        self.autoHideDelay = defaults.object(forKey: Keys.autoHideDelay.rawValue) != nil ?
            defaults.double(forKey: Keys.autoHideDelay.rawValue) : 30.0  // 30 minutes
        
        self.autoHideExcludedApps = defaults.object(forKey: Keys.autoHideExcludedApps.rawValue) as? [String] ?? []
        
        self.autoHideExcludeSystemApps = defaults.object(forKey: Keys.autoHideExcludeSystemApps.rawValue) != nil ?
            defaults.bool(forKey: Keys.autoHideExcludeSystemApps.rawValue) : true  // Exclude system apps by default
        
        // ============================================================
        // Load Auto-Minimize Settings
        // ============================================================
        // NOTE: Auto-Minimize is OFF by default (more aggressive feature)
        self.autoMinimizeEnabled = defaults.bool(forKey: Keys.autoMinimizeEnabled.rawValue)  // OFF by default
        
        self.autoMinimizeDelay = defaults.object(forKey: Keys.autoMinimizeDelay.rawValue) != nil ?
            defaults.double(forKey: Keys.autoMinimizeDelay.rawValue) : 15.0  // 15 minutes of active use
        
        self.autoMinimizeIdleResetTime = defaults.object(forKey: Keys.autoMinimizeIdleResetTime.rawValue) != nil ?
            defaults.double(forKey: Keys.autoMinimizeIdleResetTime.rawValue) : 5.0  // 5 minutes idle resets timers
        
        self.autoMinimizeWindowThreshold = defaults.object(forKey: Keys.autoMinimizeWindowThreshold.rawValue) != nil ?
            defaults.integer(forKey: Keys.autoMinimizeWindowThreshold.rawValue) : 3  // Keep at least 3 windows
        
        self.autoMinimizeExcludedApps = defaults.object(forKey: Keys.autoMinimizeExcludedApps.rawValue) as? [String] ?? []
        
        // ============================================================
        // Load SuperFocus Settings (2.2.1.5)
        // ============================================================
        // SuperFocus is OFF by default - user opts-in to productivity mode
        self.superFocusEnabled = defaults.bool(forKey: Keys.superFocusEnabled.rawValue)
        
        // ============================================================
        // Load Color Temperature Settings
        // ============================================================
        self.colorTemperatureEnabled = defaults.bool(forKey: Keys.colorTemperatureEnabled.rawValue)
        
        self.colorTemperature = defaults.object(forKey: Keys.colorTemperature.rawValue) != nil ?
            defaults.double(forKey: Keys.colorTemperature.rawValue) : 6500.0
        
        self.colorTemperatureScheduleEnabled = defaults.bool(forKey: Keys.colorTemperatureScheduleEnabled.rawValue)
        
        // Schedule settings
        self.dayTemperature = defaults.object(forKey: Keys.dayTemperature.rawValue) != nil ?
            defaults.double(forKey: Keys.dayTemperature.rawValue) : 6500.0
        
        self.nightTemperature = defaults.object(forKey: Keys.nightTemperature.rawValue) != nil ?
            defaults.double(forKey: Keys.nightTemperature.rawValue) : 2700.0
        
        self.scheduleStartHour = defaults.object(forKey: Keys.scheduleStartHour.rawValue) != nil ?
            defaults.integer(forKey: Keys.scheduleStartHour.rawValue) : 20  // 8 PM
        
        self.scheduleStartMinute = defaults.object(forKey: Keys.scheduleStartMinute.rawValue) != nil ?
            defaults.integer(forKey: Keys.scheduleStartMinute.rawValue) : 0
        
        self.scheduleEndHour = defaults.object(forKey: Keys.scheduleEndHour.rawValue) != nil ?
            defaults.integer(forKey: Keys.scheduleEndHour.rawValue) : 7  // 7 AM
        
        self.scheduleEndMinute = defaults.object(forKey: Keys.scheduleEndMinute.rawValue) != nil ?
            defaults.integer(forKey: Keys.scheduleEndMinute.rawValue) : 0
        
        self.transitionDuration = defaults.object(forKey: Keys.transitionDuration.rawValue) != nil ?
            defaults.double(forKey: Keys.transitionDuration.rawValue) : 60.0  // 1 minute
        
        self.useLocationBasedSchedule = defaults.bool(forKey: Keys.useLocationBasedSchedule.rawValue)
        
        // ============================================================
        // Load Wallpaper Settings
        // ============================================================
        self.wallpaperAutoSwitchEnabled = defaults.bool(forKey: Keys.wallpaperAutoSwitchEnabled.rawValue)
        
        self.wallpaperDimEnabled = defaults.bool(forKey: Keys.wallpaperDimEnabled.rawValue)
        
        self.wallpaperDimLevel = defaults.object(forKey: Keys.wallpaperDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.wallpaperDimLevel.rawValue) : 0.3
        
        // ============================================================
        // Load Super Spaces Settings (Jan 21, 2026)
        // ============================================================
        self.superSpacesEnabled = defaults.bool(forKey: Keys.superSpacesEnabled.rawValue)
        
        // Load Space names dictionary
        if let namesDict = defaults.dictionary(forKey: Keys.spaceNames.rawValue) as? [String: String] {
            // Convert String keys to Int keys
            self.spaceNames = Dictionary(uniqueKeysWithValues: namesDict.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } else {
            self.spaceNames = [:]
        }
        
        self.superSpacesDisplayMode = defaults.string(forKey: Keys.superSpacesDisplayMode.rawValue) ?? "compact"
        self.superSpacesAutoHide = defaults.bool(forKey: Keys.superSpacesAutoHide.rawValue)
        
        // ============================================================
        // Load Appearance Mode System (2.2.1.1)
        // ============================================================
        // Appearance mode: system, light, or dark
        if let modeString = defaults.string(forKey: Keys.appearanceMode.rawValue),
           let mode = AppearanceMode(rawValue: modeString) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system  // Default to following system appearance
        }
        
        // Load Dark Mode profile (or use defaults)
        if let data = defaults.data(forKey: Keys.darkModeProfile.rawValue),
           let profile = try? JSONDecoder().decode(DimmingProfile.self, from: data) {
            self.darkModeProfile = profile
        } else {
            self.darkModeProfile = .defaultDarkMode()
        }
        
        // Load Light Mode profile (or use defaults)
        if let data = defaults.data(forKey: Keys.lightModeProfile.rawValue),
           let profile = try? JSONDecoder().decode(DimmingProfile.self, from: data) {
            self.lightModeProfile = profile
        } else {
            self.lightModeProfile = .defaultLightMode()
        }
        
        // ============================================================
        // Migrate Legacy Exclusion Lists (2.2.1.12)
        // ============================================================
        migrateExclusionsIfNeeded()
        
        // ============================================================
        // Initialize AppearanceManager (2.2.1.1)
        // ============================================================
        // IMPORTANT: The settings we just loaded from UserDefaults are the user's SAVED state.
        // We must preserve them! The appearance system should only kick in when appearance CHANGES,
        // not on every startup.
        //
        // FIXED (Jan 16, 2026): Don't overwrite user's settings on startup.
        // Instead:
        // 1. Settings are loaded from UserDefaults (user's last state)
        // 2. Initialize AppearanceManager (but don't start it yet)
        // 3. Save current settings to the appropriate profile
        // 4. Start monitoring for appearance changes
        // 5. Only when appearance CHANGES do we load a different profile
        
        // Initialize AppearanceManager first (but don't start monitoring yet)
        self.appearanceManager = AppearanceManager()
        
        // Save current loaded settings to the active profile
        // This ensures the profile system has the user's current preferences
        saveCurrentSettingsToActiveProfile()
        let activeAppearance = getCurrentActiveAppearance()
        print("💾 Saved current settings to \(activeAppearance.displayName) profile (preserving user state)")
        
        // Now set up appearance monitoring for FUTURE changes only
        self.appearanceManager?.onAppearanceChanged = { [weak self] newAppearance in
            print("🌓 System appearance changed to: \(newAppearance.displayName)")
            self?.loadProfileForCurrentAppearance()
        }
        self.appearanceManager?.start()
        
        print("✓ SettingsManager loaded from UserDefaults")
        print("🎨 Appearance Mode: \(appearanceMode.displayName)")
        print("🎨 Active Appearance: \(activeAppearance.displayName)")
    }
    
    // ================================================================
    // MARK: - Exclusion Migration
    // ================================================================
    
    /**
     Migrates old separate exclusion arrays to the new unified format.
     
     This runs once on first launch after the update. It:
     1. Reads old excludedAppBundleIDs → sets excludeFromDimming = true
     2. Reads old autoHideExcludedApps → sets excludeFromAutoHide = true
     3. Reads old autoMinimizeExcludedApps → sets excludeFromAutoMinimize = true
     4. Merges entries with the same bundle ID
     5. Clears old arrays (but keeps keys for safety)
     */
    private func migrateExclusionsIfNeeded() {
        // Check if already migrated
        guard !defaults.bool(forKey: Keys.exclusionsMigrated.rawValue) else {
            return
        }
        
        print("🔄 Migrating legacy exclusion lists to unified format...")
        
        var migrated: [String: AppExclusion] = [:]
        var migratedCount = 0
        
        // Migrate dimming exclusions
        for bundleID in excludedAppBundleIDs {
            if var exclusion = migrated[bundleID] {
                exclusion.excludeFromDimming = true
                migrated[bundleID] = exclusion
            } else {
                var newExclusion = AppExclusion(bundleID: bundleID)
                newExclusion.excludeFromDimming = true
                migrated[bundleID] = newExclusion
                migratedCount += 1
            }
        }
        
        // Migrate auto-hide exclusions
        for bundleID in autoHideExcludedApps {
            if var exclusion = migrated[bundleID] {
                exclusion.excludeFromAutoHide = true
                migrated[bundleID] = exclusion
            } else {
                var newExclusion = AppExclusion(bundleID: bundleID)
                newExclusion.excludeFromAutoHide = true
                migrated[bundleID] = newExclusion
                migratedCount += 1
            }
        }
        
        // Migrate auto-minimize exclusions
        for bundleID in autoMinimizeExcludedApps {
            if var exclusion = migrated[bundleID] {
                exclusion.excludeFromAutoMinimize = true
                migrated[bundleID] = exclusion
            } else {
                var newExclusion = AppExclusion(bundleID: bundleID)
                newExclusion.excludeFromAutoMinimize = true
                migrated[bundleID] = newExclusion
                migratedCount += 1
            }
        }
        
        // Save migrated exclusions
        if !migrated.isEmpty {
            appExclusions = Array(migrated.values)
            print("✅ Migrated \(migratedCount) apps to unified exclusion format")
        }
        
        // Mark migration as complete
        defaults.set(true, forKey: Keys.exclusionsMigrated.rawValue)
    }
    
    // ================================================================
    // MARK: - Appearance Profile Management (2.2.1.1)
    // ================================================================
    
    /**
     Determines which appearance should be active based on user's appearance mode.
     
     LOGIC:
     - If appearanceMode == .system → use system's current appearance
     - If appearanceMode == .light → always return .light
     - If appearanceMode == .dark → always return .dark
     
     RETURNS:
     The appearance type that should determine which profile to load.
     */
    private func getCurrentActiveAppearance() -> AppearanceType {
        switch appearanceMode {
        case .system:
            // Follow system appearance
            return appearanceManager?.getCurrentAppearance() ?? .dark
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    /**
     Loads the appropriate profile based on current appearance and applies it to active settings.
     
     WHEN CALLED:
     - On app launch (after init)
     - When system appearance changes (if appearanceMode == .system)
     - When user changes appearanceMode
     - When user directly modifies a profile (to immediately apply it if active)
     
     BEHAVIOR:
     1. Determine active appearance (light or dark)
     2. Load the corresponding profile (lightModeProfile or darkModeProfile)
     3. Apply all profile settings to the @Published properties
     4. Dimming coordinator will react to these changes automatically
     
     IMPORTANT:
     This does NOT trigger profile saving (to avoid infinite loops).
     The didSet handlers are temporarily bypassed by directly modifying properties.
     */
    private func loadProfileForCurrentAppearance() {
        let activeAppearance = getCurrentActiveAppearance()
        let profile = activeAppearance == .dark ? darkModeProfile : lightModeProfile
        
        print("🔄 Loading \(activeAppearance.displayName) mode profile...")
        
        // PERFORMANCE FIX (Jan 16, 2026):
        // Set loading flag to prevent redundant observer triggers.
        // When we update 20+ @Published properties, each one fires observers
        // which can recreate timers, restart services, etc.
        // By setting this flag, observers can check it and skip redundant work.
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        
        // Apply profile settings to active @Published properties
        // OPTIMIZATION: Only update if value actually changed to minimize observer triggers
        
        // Super Dimming
        if isDimmingEnabled != profile.isDimmingEnabled {
            isDimmingEnabled = profile.isDimmingEnabled
        }
        if globalDimLevel != profile.globalDimLevel {
            globalDimLevel = profile.globalDimLevel
        }
        if superDimmingAutoEnabled != profile.superDimmingAutoEnabled {
            superDimmingAutoEnabled = profile.superDimmingAutoEnabled
        }
        if autoAdjustRange != profile.autoAdjustRange {
            autoAdjustRange = profile.autoAdjustRange
        }
        
        // Intelligent Dimming
        if intelligentDimmingEnabled != profile.intelligentDimmingEnabled {
            intelligentDimmingEnabled = profile.intelligentDimmingEnabled
        }
        if detectionMode != profile.detectionMode {
            detectionMode = profile.detectionMode
        }
        if brightnessThreshold != profile.brightnessThreshold {
            brightnessThreshold = profile.brightnessThreshold
        }
        if activeDimLevel != profile.activeDimLevel {
            activeDimLevel = profile.activeDimLevel
        }
        if inactiveDimLevel != profile.inactiveDimLevel {
            inactiveDimLevel = profile.inactiveDimLevel
        }
        if differentiateActiveInactive != profile.differentiateActiveInactive {
            differentiateActiveInactive = profile.differentiateActiveInactive
        }
        if regionGridSize != profile.regionGridSize {
            regionGridSize = profile.regionGridSize
        }
        
        // Performance & Timing (CRITICAL: These trigger timer recreation!)
        if scanInterval != profile.scanInterval {
            scanInterval = profile.scanInterval
        }
        if windowTrackingInterval != profile.windowTrackingInterval {
            windowTrackingInterval = profile.windowTrackingInterval
        }
        
        // SuperFocus Features
        if superFocusEnabled != profile.superFocusEnabled {
            superFocusEnabled = profile.superFocusEnabled
        }
        if inactivityDecayEnabled != profile.inactivityDecayEnabled {
            inactivityDecayEnabled = profile.inactivityDecayEnabled
        }
        if decayRate != profile.decayRate {
            decayRate = profile.decayRate
        }
        if decayStartDelay != profile.decayStartDelay {
            decayStartDelay = profile.decayStartDelay
        }
        if maxDecayDimLevel != profile.maxDecayDimLevel {
            maxDecayDimLevel = profile.maxDecayDimLevel
        }
        if autoHideEnabled != profile.autoHideEnabled {
            autoHideEnabled = profile.autoHideEnabled
        }
        if autoHideDelay != profile.autoHideDelay {
            autoHideDelay = profile.autoHideDelay
        }
        if autoMinimizeEnabled != profile.autoMinimizeEnabled {
            autoMinimizeEnabled = profile.autoMinimizeEnabled
        }
        if autoMinimizeDelay != profile.autoMinimizeDelay {
            autoMinimizeDelay = profile.autoMinimizeDelay
        }
        if autoMinimizeIdleResetTime != profile.autoMinimizeIdleResetTime {
            autoMinimizeIdleResetTime = profile.autoMinimizeIdleResetTime
        }
        if autoMinimizeWindowThreshold != profile.autoMinimizeWindowThreshold {
            autoMinimizeWindowThreshold = profile.autoMinimizeWindowThreshold
        }
        
        print("✅ \(activeAppearance.displayName) mode profile applied")
    }
    
    /**
     Saves the current active settings to the appropriate profile.
     
     WHEN TO CALL:
     - When user changes a dimming-related setting in preferences
     - Automatically called from property didSet handlers (future enhancement)
     
     BEHAVIOR:
     1. Determine active appearance
     2. Create a DimmingProfile from current @Published settings
     3. Save to darkModeProfile or lightModeProfile
     4. The profile's didSet will persist to UserDefaults
     
     USAGE:
     This allows users to configure different settings for Light vs Dark mode.
     When they adjust a setting, it saves to the currently active profile,
     preserving the other profile's settings.
     */
    func saveCurrentSettingsToActiveProfile() {
        let activeAppearance = getCurrentActiveAppearance()
        
        // Create profile from current settings
        let currentProfile = DimmingProfile(
            isDimmingEnabled: isDimmingEnabled,
            globalDimLevel: globalDimLevel,
            superDimmingAutoEnabled: superDimmingAutoEnabled,
            autoAdjustRange: autoAdjustRange,
            intelligentDimmingEnabled: intelligentDimmingEnabled,
            detectionMode: detectionMode,
            brightnessThreshold: brightnessThreshold,
            activeDimLevel: activeDimLevel,
            inactiveDimLevel: inactiveDimLevel,
            differentiateActiveInactive: differentiateActiveInactive,
            regionGridSize: regionGridSize,
            scanInterval: scanInterval,
            windowTrackingInterval: windowTrackingInterval,
            superFocusEnabled: superFocusEnabled,
            inactivityDecayEnabled: inactivityDecayEnabled,
            decayRate: decayRate,
            decayStartDelay: decayStartDelay,
            maxDecayDimLevel: maxDecayDimLevel,
            autoHideEnabled: autoHideEnabled,
            autoHideDelay: autoHideDelay,
            autoMinimizeEnabled: autoMinimizeEnabled,
            autoMinimizeDelay: autoMinimizeDelay,
            autoMinimizeIdleResetTime: autoMinimizeIdleResetTime,
            autoMinimizeWindowThreshold: autoMinimizeWindowThreshold
        )
        
        // Save to the active profile
        if activeAppearance == .dark {
            darkModeProfile = currentProfile
            print("💾 Saved settings to Dark Mode profile")
        } else {
            lightModeProfile = currentProfile
            print("💾 Saved settings to Light Mode profile")
        }
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Explicitly save all settings to UserDefaults.
     
     Note: Individual properties already save on change via didSet.
     This method is for explicit sync, e.g., before app termination.
     */
    func save() {
        defaults.synchronize()
        print("✓ Settings synchronized to disk")
    }
    
    /**
     Reset all settings to defaults.
     
     Used for troubleshooting or fresh start.
     Does NOT reset license state.
     */
    /**
     Resets all settings to their default values.
     
     IMPLEMENTATION (2.2.1.7):
     This provides users with a way to return to factory settings if they've
     misconfigured the app or want a fresh start.
     
     IMPORTANT: This does NOT clear isFirstLaunch intentionally, so users
     won't see the onboarding flow again after reset.
     */
    func resetToDefaults() {
        // ============================================================
        // General Settings
        // ============================================================
        // Note: isFirstLaunch intentionally NOT reset (keeps false)
        launchAtLogin = false
        
        // ============================================================
        // Appearance Mode System (2.2.1.1)
        // ============================================================
        appearanceMode = .system  // Follow system by default
        darkModeProfile = .defaultDarkMode()
        lightModeProfile = .defaultLightMode()
        
        // Load the appropriate profile for current appearance
        loadProfileForCurrentAppearance()
        
        // NOTE: The rest of the dimming settings will be set by loadProfileForCurrentAppearance()
        // But we set them here too for clarity and to ensure they're in the correct state
        // before the profile loads (in case profile loading is delayed)
        
        // ============================================================
        // Dimming Settings (2.2.1.2 - Super Dimming defaults)
        // ============================================================
        isDimmingEnabled = true  // Super Dimming ON by default (2.2.1.9)
        globalDimLevel = 0.25
        brightnessThreshold = 0.85
        activeDimLevel = 0.15
        inactiveDimLevel = 0.35
        differentiateActiveInactive = true
        
        // Super Dimming Auto Mode (2.2.1.2)
        superDimmingAutoEnabled = true  // Auto mode ON by default
        autoAdjustRange = 0.15  // ±15%
        
        // Intelligent Dimming (OFF by default until we implement 2.2.1.3/2.2.1.4)
        intelligentDimmingEnabled = false
        detectionMode = .perRegion  // Per-region detection
        regionGridSize = 8
        
        // Performance
        scanInterval = 2.0  // 2 seconds for brightness analysis
        windowTrackingInterval = 0.5  // 0.5 seconds for position tracking
        
        // Debug
        debugOverlayBorders = false
        
        // ============================================================
        // Inactivity Features (2.2.1.5 - SuperFocus OFF by default)
        // ============================================================
        superFocusEnabled = false
        
        // Window Decay Dimming
        inactivityDecayEnabled = false
        decayRate = 0.01
        decayStartDelay = 30.0
        maxDecayDimLevel = 0.8
        
        // Auto-Hide Apps (ON by default when SuperFocus is enabled)
        autoHideEnabled = true
        autoHideDelay = 30.0
        autoHideExcludeSystemApps = true
        autoHideExcludedApps = []  // Legacy, will be migrated
        
        // Auto-Minimize Windows (OFF by default)
        autoMinimizeEnabled = false
        autoMinimizeDelay = 15.0
        autoMinimizeIdleResetTime = 5.0
        autoMinimizeWindowThreshold = 3
        autoMinimizeExcludedApps = []  // Legacy, will be migrated
        
        // ============================================================
        // Exclusions (2.2.1.12 - Unified system)
        // ============================================================
        appExclusions = []
        excludedAppBundleIDs = []  // Legacy, kept for backwards compat
        
        // ============================================================
        // Color Temperature
        // ============================================================
        colorTemperatureEnabled = false
        colorTemperature = 6500.0
        colorTemperatureScheduleEnabled = false
        dayTemperature = 6500.0
        nightTemperature = 2700.0
        scheduleStartHour = 20
        scheduleStartMinute = 0
        scheduleEndHour = 7
        scheduleEndMinute = 0
        transitionDuration = 60.0
        useLocationBasedSchedule = false
        
        // ============================================================
        // Wallpaper
        // ============================================================
        wallpaperAutoSwitchEnabled = false
        wallpaperDimEnabled = false
        wallpaperDimLevel = 0.3
        
        // ============================================================
        // Super Spaces (Jan 21, 2026)
        // ============================================================
        superSpacesEnabled = true  // Enabled by default
        spaceNames = [:]
        superSpacesDisplayMode = "compact"
        superSpacesAutoHide = false
        
        print("✓ Settings reset to defaults (2.2.1.7)")
        print("   Super Dimming: ON with Auto mode")
        print("   Intelligent Dimming: OFF")
        print("   SuperFocus: OFF")
        print("   All exclusions cleared")
    }
}

// ====================================================================
// MARK: - Notification Names
// ====================================================================

/**
 Custom notification names for settings changes.
 
 Used by services that need to react to settings changes but
 don't have direct access to the SettingsManager ObservableObject.
 */
extension Notification.Name {
    /// Posted when isDimmingEnabled changes
    static let dimmingEnabledChanged = Notification.Name("superdimmer.dimmingEnabledChanged")
    
    /// Posted when colorTemperatureEnabled changes
    static let colorTemperatureEnabledChanged = Notification.Name("superdimmer.colorTemperatureEnabledChanged")
    
    /// Posted when colorTemperature value changes
    static let colorTemperatureChanged = Notification.Name("superdimmer.colorTemperatureChanged")
    
    /// Posted when overlayCornerRadius changes (2.8.2b)
    static let overlayCornerRadiusChanged = Notification.Name("superdimmer.overlayCornerRadiusChanged")
}

// NOTE: DetectionMode enum moved to top of file (before DimmingProfile) for Codable synthesis
