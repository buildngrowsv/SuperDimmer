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
        
        // Debug mode (shows colored borders on overlays)
        case debugOverlayBorders = "superdimmer.debugOverlayBorders"
        
        // Excluded Apps
        case excludedAppBundleIDs = "superdimmer.excludedAppBundleIDs"
        
        // Color Temperature
        case colorTemperatureEnabled = "superdimmer.colorTemperatureEnabled"
        case colorTemperature = "superdimmer.colorTemperature"
        case colorTemperatureScheduleEnabled = "superdimmer.colorTemperatureScheduleEnabled"
        
        // Wallpaper
        case wallpaperAutoSwitchEnabled = "superdimmer.wallpaperAutoSwitchEnabled"
        case wallpaperDimEnabled = "superdimmer.wallpaperDimEnabled"
        case wallpaperDimLevel = "superdimmer.wallpaperDimLevel"
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
    
    // ================================================================
    // MARK: - Excluded Apps
    // ================================================================
    
    /**
     Bundle IDs of apps that should never have their windows dimmed.
     
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
        
        // ============================================================
        // Load Dimming Settings
        // ============================================================
        // For isDimmingEnabled, default to false so app doesn't immediately dim
        // User should consciously enable after understanding the feature
        self.isDimmingEnabled = defaults.bool(forKey: Keys.isDimmingEnabled.rawValue)
        
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
        
        // Debug mode - shows red borders on overlays for positioning verification
        self.debugOverlayBorders = defaults.bool(forKey: Keys.debugOverlayBorders.rawValue)
        
        // ============================================================
        // Load Excluded Apps
        // ============================================================
        self.excludedAppBundleIDs = defaults.object(forKey: Keys.excludedAppBundleIDs.rawValue) as? [String] ?? []
        
        // ============================================================
        // Load Color Temperature Settings
        // ============================================================
        self.colorTemperatureEnabled = defaults.bool(forKey: Keys.colorTemperatureEnabled.rawValue)
        
        self.colorTemperature = defaults.object(forKey: Keys.colorTemperature.rawValue) != nil ?
            defaults.double(forKey: Keys.colorTemperature.rawValue) : 6500.0
        
        self.colorTemperatureScheduleEnabled = defaults.bool(forKey: Keys.colorTemperatureScheduleEnabled.rawValue)
        
        // ============================================================
        // Load Wallpaper Settings
        // ============================================================
        self.wallpaperAutoSwitchEnabled = defaults.bool(forKey: Keys.wallpaperAutoSwitchEnabled.rawValue)
        
        self.wallpaperDimEnabled = defaults.bool(forKey: Keys.wallpaperDimEnabled.rawValue)
        
        self.wallpaperDimLevel = defaults.object(forKey: Keys.wallpaperDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.wallpaperDimLevel.rawValue) : 0.3
        
        print("✓ SettingsManager loaded from UserDefaults")
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
    func resetToDefaults() {
        // General
        isFirstLaunch = false // Don't show onboarding again
        launchAtLogin = false
        
        // Dimming
        isDimmingEnabled = false
        globalDimLevel = 0.25
        brightnessThreshold = 0.85
        activeDimLevel = 0.15
        inactiveDimLevel = 0.35
        differentiateActiveInactive = true
        intelligentDimmingEnabled = false
        detectionMode = .perWindow
        regionGridSize = 8
        scanInterval = 1.0
        excludedAppBundleIDs = []
        
        // Color Temperature
        colorTemperatureEnabled = false
        colorTemperature = 6500.0
        colorTemperatureScheduleEnabled = false
        
        // Wallpaper
        wallpaperAutoSwitchEnabled = false
        wallpaperDimEnabled = false
        wallpaperDimLevel = 0.3
        
        print("✓ Settings reset to defaults")
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
}

// ====================================================================
// MARK: - Detection Mode
// ====================================================================

/**
 Detection modes for intelligent dimming.
 
 This is a key differentiator for SuperDimmer. While other apps only
 offer full-screen dimming, we can dim specific bright REGIONS within
 windows, handling complex scenarios like dark mode apps with bright content.
 */
enum DetectionMode: String, CaseIterable, Identifiable {
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
