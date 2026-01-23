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
import SwiftUI  // FEATURE 5.5.9: Needed for Color type in hexToColor

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
// MARK: - Dimming Type Enum (Settings Redesign Jan 23, 2026)
// ====================================================================

/**
 Dimming type/mode selection for the SuperDimmer feature.
 
 SETTINGS REDESIGN (Jan 23, 2026):
 Users can now choose between 3 distinct dimming approaches via a clear
 3-button selector in the SuperDimmer settings tab.
 
 This replaces the confusing combination of:
 - isDimmingEnabled + intelligentDimmingEnabled + detectionMode
 
 With a single, clear selection.
 
 MODES:
 - fullScreen: Dims the entire screen uniformly (simplest, lowest CPU)
 - windowLevel: Analyzes each window, dims bright ones individually
 - zoneLevel: Finds bright regions WITHIN windows and dims only those areas
 
 The underlying settings are still maintained for backwards compatibility,
 but this enum provides the user-facing selection.
 */
enum DimmingType: String, Codable, CaseIterable, Identifiable {
    /// Full-screen adaptive dimming - one overlay covers entire display
    /// Uses: isDimmingEnabled=true, intelligentDimmingEnabled=false
    case fullScreen = "fullScreen"
    
    /// Window-level adaptive dimming - one overlay per window
    /// Uses: isDimmingEnabled=true, intelligentDimmingEnabled=true, detectionMode=.perWindow
    case windowLevel = "windowLevel"
    
    /// Zone/Region-level dimming - overlays for specific bright areas
    /// Uses: isDimmingEnabled=true, intelligentDimmingEnabled=true, detectionMode=.perRegion
    case zoneLevel = "zoneLevel"
    
    var id: String { rawValue }
    
    /// User-facing display name for the 3-button selector
    var displayName: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .windowLevel: return "Window Level"
        case .zoneLevel: return "Zone Level"
        }
    }
    
    /// Short description shown below the mode selector
    var shortDescription: String {
        switch self {
        case .fullScreen:
            return "Dims your entire screen uniformly"
        case .windowLevel:
            return "Dims each window based on its brightness"
        case .zoneLevel:
            return "Dims only bright areas within windows"
        }
    }
    
    /// Detailed explanation shown when mode is selected
    var detailedDescription: String {
        switch self {
        case .fullScreen:
            return """
            Full Screen Adaptive Dimming applies a comfortable dimming overlay across your entire display. \
            With Auto Mode enabled, the dimming level automatically adjusts based on your screen's \
            overall brightness - dimming more when viewing bright content, less when viewing dark content. \
            This is the simplest mode with the lowest system resource usage.
            """
        case .windowLevel:
            return """
            Window Level Adaptive Dimming analyzes each window individually and applies appropriate \
            dimming based on that window's content brightness. Bright windows get dimmed while dark \
            windows are left untouched. You can set different dimming levels for the window you're \
            actively using versus background windows. Requires Screen Recording permission.
            """
        case .zoneLevel:
            return """
            Zone Level Dimming is the most precise mode. It detects bright regions WITHIN windows \
            and dims only those specific areas. Perfect for apps like Mail where the interface is \
            dark but email content is bright, or code editors with light-colored preview panes. \
            Uses more system resources but provides the most targeted dimming. Requires Screen Recording permission.
            """
        }
    }
    
    /// Icon for the mode button
    var icon: String {
        switch self {
        case .fullScreen: return "rectangle.fill"
        case .windowLevel: return "macwindow"
        case .zoneLevel: return "rectangle.split.3x3"
        }
    }
    
    /// Whether this mode requires Screen Recording permission
    var requiresScreenRecording: Bool {
        switch self {
        case .fullScreen: return false
        case .windowLevel: return true
        case .zoneLevel: return true
        }
    }
    
    /// Relative CPU usage indicator
    var cpuUsage: String {
        switch self {
        case .fullScreen: return "Low"
        case .windowLevel: return "Medium"
        case .zoneLevel: return "Higher"
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
        
        // Dimming Type (Settings Redesign Jan 23, 2026)
        // Single selection replacing the complex combination of isDimmingEnabled + intelligentDimmingEnabled + detectionMode
        case dimmingType = "superdimmer.dimmingType"
        
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
        case spaceEmojis = "superdimmer.spaceEmojis"
        case spaceNotes = "superdimmer.spaceNotes"
        case spaceColors = "superdimmer.spaceColors"
        case superSpacesDisplayMode = "superdimmer.superSpacesDisplayMode"
        case superSpacesAutoHide = "superdimmer.superSpacesAutoHide"
        case superSpacesPosition = "superdimmer.superSpacesPosition"
        case lastHUDPositionX = "superdimmer.lastHUDPositionX"
        case lastHUDPositionY = "superdimmer.lastHUDPositionY"
        
        // Super Spaces HUD Window Size per Mode (Jan 21, 2026)
        // Stores the last user-set window size for each display mode
        // so switching modes restores the size the user prefers for that mode
        case hudSizeCompactWidth = "superdimmer.hudSizeCompactWidth"
        case hudSizeCompactHeight = "superdimmer.hudSizeCompactHeight"
        case hudSizeNoteWidth = "superdimmer.hudSizeNoteWidth"
        case hudSizeNoteHeight = "superdimmer.hudSizeNoteHeight"
        case hudSizeOverviewWidth = "superdimmer.hudSizeOverviewWidth"
        case hudSizeOverviewHeight = "superdimmer.hudSizeOverviewHeight"
        
        // Super Spaces Button Dimming (5.5.8 - Dim to Indicate Order)
        // Progressive dimming of Space buttons based on visit recency
        case spaceOrderDimmingEnabled = "superdimmer.spaceOrderDimmingEnabled"
        case spaceOrderMaxDimLevel = "superdimmer.spaceOrderMaxDimLevel"
        
        // Super Spaces Float on Top (Jan 21, 2026)
        // Controls whether HUD stays above all other windows
        case superSpacesFloatOnTop = "superdimmer.superSpacesFloatOnTop"
        
        // Super Spaces Font Size (Jan 21, 2026, updated Jan 22, 2026)
        // User's preferred font size multiplier for the HUD (0.8 to 3.0)
        // Allows Cmd+/Cmd- to adjust text size, persisted across app launches
        // Range increased from 1.5 to 3.0 for better accessibility support
        case superSpacesFontSizeMultiplier = "superdimmer.superSpacesFontSizeMultiplier"
        
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
     The currently selected dimming type/mode.
     
     SETTINGS REDESIGN (Jan 23, 2026):
     This is the primary way users select their dimming approach via the
     3-button selector in SuperDimmer settings. This property automatically
     synchronizes the underlying settings:
     
     - .fullScreen: isDimmingEnabled=true, intelligentDimmingEnabled=false
     - .windowLevel: isDimmingEnabled=true, intelligentDimmingEnabled=true, detectionMode=.perWindow
     - .zoneLevel: isDimmingEnabled=true, intelligentDimmingEnabled=true, detectionMode=.perRegion
     
     When changed, the underlying settings are updated to match, ensuring
     backwards compatibility with the existing dimming system.
     */
    @Published var dimmingType: DimmingType {
        didSet {
            defaults.set(dimmingType.rawValue, forKey: Keys.dimmingType.rawValue)
            
            // Synchronize underlying settings based on the selected type
            // This ensures the dimming coordinator works correctly
            synchronizeSettingsForDimmingType(dimmingType)
            
            // Notify that dimming configuration changed
            NotificationCenter.default.post(
                name: .dimmingTypeChanged,
                object: nil,
                userInfo: ["type": dimmingType]
            )
        }
    }
    
    /**
     Synchronizes the underlying dimming settings based on the selected dimming type.
     
     This ensures backwards compatibility - the DimmingCoordinator still uses
     isDimmingEnabled, intelligentDimmingEnabled, and detectionMode internally.
     
     Called when dimmingType changes to update these values accordingly.
     */
    private func synchronizeSettingsForDimmingType(_ type: DimmingType) {
        switch type {
        case .fullScreen:
            // Full-screen mode: disable intelligent mode, enable basic dimming
            if isDimmingEnabled {
                intelligentDimmingEnabled = false
            }
        case .windowLevel:
            // Window-level mode: enable intelligent mode with perWindow detection
            if isDimmingEnabled {
                intelligentDimmingEnabled = true
                detectionMode = .perWindow
            }
        case .zoneLevel:
            // Zone-level mode: enable intelligent mode with perRegion detection
            if isDimmingEnabled {
                intelligentDimmingEnabled = true
                detectionMode = .perRegion
            }
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
     
     INTERNAL STORAGE: This stores the decay rate as % per second for calculation purposes.
     UI PRESENTATION: The UI shows this as "Full decay in X minutes" for better UX.
     
     Range: 0.005 to 0.05 (0.5% to 5% per second)
     Default: 0.01 (1% per second)
     
     CHANGED (Jan 21, 2026): UI now presents this as "full decay time" instead of rate.
     Conversion: decayRate = maxDecayDimLevel / (fullDecayMinutes * 60)
     Example: For 80% max dim and 10 min full decay → 0.80 / (10 * 60) = 0.00133 per second
     */
    @Published var decayRate: Double {
        didSet {
            defaults.set(decayRate, forKey: Keys.decayRate.rawValue)
        }
    }
    
    /**
     Seconds of inactivity before decay starts.
     
     Range: 5 to 1800 seconds (5 seconds to 30 minutes)
     Default: 30 seconds
     
     CHANGED (Jan 21, 2026): Expanded range from 5-120 to 5-1800 seconds to support
     longer delays before dimming starts (up to 30 minutes).
     
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
     Custom emojis/icons for Spaces.
     
     FEATURE: 5.5.5 - Space Name & Emoji Customization
     
     Dictionary mapping Space number (1-based) to emoji string.
     Example: [1: "📧", 2: "🌐", 3: "💻"]
     
     USAGE:
     - Displayed alongside Space names in HUD
     - Helps visually identify Spaces quickly
     - User can pick from emoji picker or type directly
     
     DEFAULT: Empty (no emojis)
     */
    @Published var spaceEmojis: [Int: String] {
        didSet {
            // Convert Int keys to String keys for UserDefaults
            let stringKeyDict = Dictionary(uniqueKeysWithValues: spaceEmojis.map { (String($0.key), $0.value) })
            defaults.set(stringKeyDict, forKey: Keys.spaceEmojis.rawValue)
        }
    }
    
    /**
     Notes for Spaces.
     
     FEATURE: 5.5.6 - Note Mode
     
     Dictionary mapping Space number (1-based) to note text.
     Example: [1: "Check emails and calendar", 2: "Research tasks", 3: "Current project work"]
     
     USAGE:
     - User can switch HUD to "Note Mode"
     - Single-click on Space shows/edits note
     - Double-click switches to that Space
     - Notes auto-save on text change (debounced)
     
     WHY THIS FEATURE:
     - Helps users remember what each Space is for
     - Useful for context switching (what was I working on?)
     - Can include quick reminders or task lists per Space
     
     DEFAULT: Empty (no notes)
     */
    @Published var spaceNotes: [Int: String] {
        didSet {
            // Convert Int keys to String keys for UserDefaults
            let stringKeyDict = Dictionary(uniqueKeysWithValues: spaceNotes.map { (String($0.key), $0.value) })
            defaults.set(stringKeyDict, forKey: Keys.spaceNotes.rawValue)
        }
    }
    
    /**
     Custom colors for Spaces.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     Dictionary mapping Space number (1-based) to color hex string.
     Example: [1: "#FF5733", 2: "#33FF57", 3: "#3357FF"]
     
     USAGE:
     - User can assign a color to each Space when editing name/emoji
     - Color tints the entire HUD when on that Space
     - Active card shows a stronger version of the color
     - Inactive cards show a faded version of their color or remain neutral
     
     WHY THIS FEATURE:
     - Provides instant visual feedback about which Space you're on
     - Color-coding helps with mental organization and context switching
     - Creates a more personalized and visually rich experience
     - Reduces cognitive load by associating colors with specific contexts
     
     COLOR PALETTE:
     - Curated set of professional, accessible colors
     - Includes warm, cool, and neutral tones
     - Colors are vibrant enough to be distinctive but not overwhelming
     - All colors meet WCAG contrast guidelines for readability
     
     DEFAULT: Empty (no custom colors, uses default blue accent)
     */
    @Published var spaceColors: [Int: String] {
        didSet {
            // Convert Int keys to String keys for UserDefaults
            let stringKeyDict = Dictionary(uniqueKeysWithValues: spaceColors.map { (String($0.key), $0.value) })
            defaults.set(stringKeyDict, forKey: Keys.spaceColors.rawValue)
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
    
    /**
     Position preset for Super Spaces HUD.
     
     FEATURE: 5.5.4 - Settings Button Functionality
     
     VALUES:
     - "topLeft": Top-left corner
     - "topRight": Top-right corner (default)
     - "bottomLeft": Bottom-left corner
     - "bottomRight": Bottom-right corner
     - "custom": User has manually positioned (don't auto-reposition)
     
     BEHAVIOR:
     When user selects a preset in quick settings, HUD moves to that corner.
     When user manually drags HUD, position becomes "custom" and won't auto-reposition.
     
     DEFAULT: "topRight"
     */
    @Published var superSpacesPosition: String {
        didSet {
            defaults.set(superSpacesPosition, forKey: Keys.superSpacesPosition.rawValue)
        }
    }
    
    /**
     Last known position of Super Spaces HUD window.
     
     FEATURE: Phase 1.1 - Position Persistence
     
     Stores the window's origin (top-left corner) as CGPoint.
     When HUD is reopened, it appears at this position if valid.
     
     PERSISTENCE:
     - X and Y stored separately in UserDefaults
     - Position validated on load (must be on-screen)
     - If invalid (e.g., monitor disconnected), falls back to default
     
     BEHAVIOR:
     - Saved when window moves (debounced to avoid excessive writes)
     - Restored when HUD opens
     - Validated against current screen configuration
     
     DEFAULT: nil (use default position on first launch)
     */
    @Published var lastHUDPosition: CGPoint? {
        didSet {
            if let position = lastHUDPosition {
                defaults.set(Double(position.x), forKey: Keys.lastHUDPositionX.rawValue)
                defaults.set(Double(position.y), forKey: Keys.lastHUDPositionY.rawValue)
            } else {
                defaults.removeObject(forKey: Keys.lastHUDPositionX.rawValue)
                defaults.removeObject(forKey: Keys.lastHUDPositionY.rawValue)
            }
        }
    }
    
    /**
     Last window size for Compact mode.
     
     FEATURE: Per-Mode Window Size Persistence
     
     Stores the user's preferred window size for Compact display mode.
     When switching to Compact mode, the HUD resizes to this saved size.
     
     BEHAVIOR:
     - Saved when window resizes while in Compact mode (debounced)
     - Restored when switching to Compact mode
     - Nil means use default size
     
     DEFAULT: nil (use default size of 480x140)
     */
    @Published var hudSizeCompact: CGSize? {
        didSet {
            if let size = hudSizeCompact {
                defaults.set(Double(size.width), forKey: Keys.hudSizeCompactWidth.rawValue)
                defaults.set(Double(size.height), forKey: Keys.hudSizeCompactHeight.rawValue)
            } else {
                defaults.removeObject(forKey: Keys.hudSizeCompactWidth.rawValue)
                defaults.removeObject(forKey: Keys.hudSizeCompactHeight.rawValue)
            }
        }
    }
    
    /**
     Last window size for Note mode.
     
     FEATURE: Per-Mode Window Size Persistence
     
     Stores the user's preferred window size for Note display mode.
     When switching to Note mode, the HUD resizes to this saved size.
     
     BEHAVIOR:
     - Saved when window resizes while in Note mode (debounced)
     - Restored when switching to Note mode
     - Nil means use default size
     
     DEFAULT: nil (use default size of 480x400)
     */
    @Published var hudSizeNote: CGSize? {
        didSet {
            if let size = hudSizeNote {
                defaults.set(Double(size.width), forKey: Keys.hudSizeNoteWidth.rawValue)
                defaults.set(Double(size.height), forKey: Keys.hudSizeNoteHeight.rawValue)
            } else {
                defaults.removeObject(forKey: Keys.hudSizeNoteWidth.rawValue)
                defaults.removeObject(forKey: Keys.hudSizeNoteHeight.rawValue)
            }
        }
    }
    
    /**
     Last window size for Overview mode.
     
     FEATURE: Per-Mode Window Size Persistence
     
     Stores the user's preferred window size for Overview display mode.
     When switching to Overview mode, the HUD resizes to this saved size.
     
     BEHAVIOR:
     - Saved when window resizes while in Overview mode (debounced)
     - Restored when switching to Overview mode
     - Nil means use default size
     
     DEFAULT: nil (use default size of 600x550)
     */
    @Published var hudSizeOverview: CGSize? {
        didSet {
            if let size = hudSizeOverview {
                defaults.set(Double(size.width), forKey: Keys.hudSizeOverviewWidth.rawValue)
                defaults.set(Double(size.height), forKey: Keys.hudSizeOverviewHeight.rawValue)
            } else {
                defaults.removeObject(forKey: Keys.hudSizeOverviewWidth.rawValue)
                defaults.removeObject(forKey: Keys.hudSizeOverviewHeight.rawValue)
            }
        }
    }
    
    /**
     Whether Space button dimming based on visit order is enabled.
     
     FEATURE: 5.5.8 - Dim to Indicate Order (Visit Recency Visualization)
     
     When enabled, Space buttons in the HUD are progressively dimmed based on
     how recently each Space was visited. This creates a visual "heat map" of
     your workflow.
     
     BEHAVIOR:
     - Current Space: 100% opacity (fully bright)
     - Last visited: Slightly dimmed (e.g., 95% opacity)
     - Older Spaces: Progressively more dimmed (down to minimum opacity)
     - Maximum dimming controlled by spaceOrderMaxDimLevel
     
     WHY THIS FEATURE:
     - Provides instant visual feedback on which Spaces you've been using
     - Helps identify "stale" Spaces you haven't visited in a while
     - Creates natural visual hierarchy without manual configuration
     - Complements the existing window-level inactivity decay feature
     
     TECHNICAL NOTES:
     - Only dims HUD buttons, NOT the actual Spaces themselves
     - Visit order tracked by SpaceVisitTracker service
     - Opacity calculated based on position in visit history
     - Visit history persists across app restarts
     
     DEFAULT: false (opt-in feature)
     */
    @Published var spaceOrderDimmingEnabled: Bool {
        didSet {
            defaults.set(spaceOrderDimmingEnabled, forKey: Keys.spaceOrderDimmingEnabled.rawValue)
        }
    }
    
    /**
     Maximum dim level for Space button visit order dimming.
     
     FEATURE: 5.5.8 - Dim to Indicate Order
     
     Controls how much the least recently visited Space buttons are dimmed.
     Value represents the maximum opacity reduction (0.0 - 1.0).
     
     EXAMPLES:
     - 0.25 (25%): Least recent Space has 75% opacity (subtle)
     - 0.50 (50%): Least recent Space has 50% opacity (moderate)
     - 0.80 (80%): Least recent Space has 20% opacity (strong indicator)
     
     CALCULATION:
     For N total Spaces:
     - Opacity step = maxDimLevel / N
     - Space at position P: opacity = 1.0 - min(P * step, maxDimLevel)
     
     RANGE: 0.1 (10%) to 0.8 (80%)
     DEFAULT: 0.5 (50% maximum dimming for better visibility)
     
     USER FEEDBACK (Jan 21, 2026):
     - Original 25% max was too subtle, hard to read
     - Increased range to 80% for stronger visual indicator
     - Increased default to 50% for better out-of-box experience
     */
    @Published var spaceOrderMaxDimLevel: Double {
        didSet {
            // Clamp to valid range [0.1, 0.8]
            let clamped = max(0.1, min(0.8, spaceOrderMaxDimLevel))
            if clamped != spaceOrderMaxDimLevel {
                spaceOrderMaxDimLevel = clamped
                return
            }
            defaults.set(spaceOrderMaxDimLevel, forKey: Keys.spaceOrderMaxDimLevel.rawValue)
        }
    }
    
    /**
     Whether Super Spaces HUD should float on top of all other windows.
     
     FEATURE: Float on Top Toggle (Jan 21, 2026)
     
     When true, the HUD uses .floating window level and stays above all other windows.
     When false, the HUD uses .normal window level and can be covered by other windows.
     
     WHY THIS SETTING:
     - Some users want the HUD always visible (float on top)
     - Others prefer it to behave like a normal window (can be covered)
     - Allows users to choose based on their workflow
     
     TECHNICAL NOTES:
     - Changes NSWindow.level between .floating and .normal
     - Applied immediately when setting changes
     - Persists across app restarts
     
     DEFAULT: true (float on top - original behavior)
     */
    @Published var superSpacesFloatOnTop: Bool {
        didSet {
            defaults.set(superSpacesFloatOnTop, forKey: Keys.superSpacesFloatOnTop.rawValue)
        }
    }
    
    /**
     Font size multiplier for Super Spaces HUD text.
     
     FEATURE: Cmd+/Cmd- Text Size Adjustment with Persistence
     
     PURPOSE:
     Users can adjust the HUD text size using Cmd+ and Cmd- keyboard shortcuts.
     This preference is saved so the text size persists across app launches.
     
     RANGE (Updated Jan 22, 2026):
     - Minimum: 0.8 (80% of default size)
     - Maximum: 3.0 (300% of default size) - INCREASED from 1.5x for better accessibility
     - Default: 1.0 (100% - normal size)
     
     BEHAVIOR:
     - Applied to all text in the HUD via scaledFontSize() function
     - Changed via Cmd+ (increase) and Cmd- (decrease) shortcuts
     - Increments/decrements by 0.1 per keypress
     - Persists across app restarts
     - All adaptive layout thresholds scale with this multiplier
     
     WHY THIS MATTERS:
     - Accessibility: Users with vision needs can make text much larger (up to 3x)
     - Preference: Some users prefer more compact or more spacious UI
     - Consistency: Size preference maintained across sessions
     - Adaptive Layout: Column counts and spacing adjust automatically for larger text
     
     TECHNICAL NOTES:
     - Stored as CGFloat in UserDefaults
     - Clamped to valid range (0.8 to 3.0) in the increase/decrease methods
     - Applied via multiplication in scaledFontSize() helper
     - Column thresholds scale proportionally to prevent cramped layouts
     
     DEFAULT: 1.0 (normal size)
     */
    @Published var superSpacesFontSizeMultiplier: CGFloat {
        didSet {
            defaults.set(Double(superSpacesFontSizeMultiplier), forKey: Keys.superSpacesFontSizeMultiplier.rawValue)
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
        // Load Dimming Type (Settings Redesign Jan 23, 2026)
        // ============================================================
        // This is the new primary way users select dimming approach.
        // Default: fullScreen (simple, low CPU, works without permissions)
        // For existing users with intelligentDimmingEnabled, we infer the type.
        if let typeString = defaults.string(forKey: Keys.dimmingType.rawValue),
           let type = DimmingType(rawValue: typeString) {
            self.dimmingType = type
        } else {
            // Migrate from old settings if they exist
            // If intelligent dimming was enabled, determine which type based on detection mode
            let wasIntelligentEnabled = defaults.object(forKey: Keys.intelligentDimmingEnabled.rawValue) != nil ?
                defaults.bool(forKey: Keys.intelligentDimmingEnabled.rawValue) : false
            
            if wasIntelligentEnabled {
                // Check detection mode to determine windowLevel vs zoneLevel
                let modeString = defaults.string(forKey: Keys.detectionMode.rawValue) ?? "perWindow"
                if modeString == "perRegion" {
                    self.dimmingType = .zoneLevel
                } else {
                    self.dimmingType = .windowLevel
                }
            } else {
                // Default to fullScreen for new users
                self.dimmingType = .fullScreen
            }
        }
        
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
        
        // Load Space emojis dictionary
        if let emojisDict = defaults.dictionary(forKey: Keys.spaceEmojis.rawValue) as? [String: String] {
            // Convert String keys to Int keys
            self.spaceEmojis = Dictionary(uniqueKeysWithValues: emojisDict.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } else {
            self.spaceEmojis = [:]
        }
        
        // Load Space notes dictionary
        if let notesDict = defaults.dictionary(forKey: Keys.spaceNotes.rawValue) as? [String: String] {
            // Convert String keys to Int keys
            self.spaceNotes = Dictionary(uniqueKeysWithValues: notesDict.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } else {
            self.spaceNotes = [:]
        }
        
        // Load Space colors dictionary (5.5.9 - Jan 22, 2026)
        if let colorsDict = defaults.dictionary(forKey: Keys.spaceColors.rawValue) as? [String: String] {
            // Convert String keys to Int keys
            self.spaceColors = Dictionary(uniqueKeysWithValues: colorsDict.compactMap { key, value in
                guard let intKey = Int(key) else { return nil }
                return (intKey, value)
            })
        } else {
            self.spaceColors = [:]
        }
        
        self.superSpacesDisplayMode = defaults.string(forKey: Keys.superSpacesDisplayMode.rawValue) ?? "compact"
        self.superSpacesAutoHide = defaults.bool(forKey: Keys.superSpacesAutoHide.rawValue)
        self.superSpacesPosition = defaults.string(forKey: Keys.superSpacesPosition.rawValue) ?? "topRight"
        
        // Load last HUD position
        if let x = defaults.object(forKey: Keys.lastHUDPositionX.rawValue) as? Double,
           let y = defaults.object(forKey: Keys.lastHUDPositionY.rawValue) as? Double {
            self.lastHUDPosition = CGPoint(x: x, y: y)
        } else {
            self.lastHUDPosition = nil
        }
        
        // Load last HUD window sizes per mode (Jan 21, 2026)
        // These store the user's preferred window size for each display mode
        // so switching modes restores the appropriate size
        if let width = defaults.object(forKey: Keys.hudSizeCompactWidth.rawValue) as? Double,
           let height = defaults.object(forKey: Keys.hudSizeCompactHeight.rawValue) as? Double {
            self.hudSizeCompact = CGSize(width: width, height: height)
        } else {
            self.hudSizeCompact = nil
        }
        
        if let width = defaults.object(forKey: Keys.hudSizeNoteWidth.rawValue) as? Double,
           let height = defaults.object(forKey: Keys.hudSizeNoteHeight.rawValue) as? Double {
            self.hudSizeNote = CGSize(width: width, height: height)
        } else {
            self.hudSizeNote = nil
        }
        
        if let width = defaults.object(forKey: Keys.hudSizeOverviewWidth.rawValue) as? Double,
           let height = defaults.object(forKey: Keys.hudSizeOverviewHeight.rawValue) as? Double {
            self.hudSizeOverview = CGSize(width: width, height: height)
        } else {
            self.hudSizeOverview = nil
        }
        
        // ============================================================
        // Load Super Spaces Button Dimming Settings (5.5.8)
        // ============================================================
        // Button dimming is OFF by default (opt-in feature)
        self.spaceOrderDimmingEnabled = defaults.bool(forKey: Keys.spaceOrderDimmingEnabled.rawValue)
        
        // Max dim level defaults to 50% (0.5) for better visibility
        // USER FEEDBACK (Jan 21, 2026): Increased from 25% to 50% for stronger indicator
        self.spaceOrderMaxDimLevel = defaults.object(forKey: Keys.spaceOrderMaxDimLevel.rawValue) != nil ?
            defaults.double(forKey: Keys.spaceOrderMaxDimLevel.rawValue) : 0.5
        
        // Float on top defaults to true (original behavior)
        self.superSpacesFloatOnTop = defaults.object(forKey: Keys.superSpacesFloatOnTop.rawValue) != nil ?
            defaults.bool(forKey: Keys.superSpacesFloatOnTop.rawValue) : true
        
        // Font size multiplier defaults to 1.0 (normal size)
        // Range: 0.8 (80%) to 3.0 (300%) - increased max for accessibility
        // User can adjust with Cmd+/Cmd- shortcuts in the HUD
        self.superSpacesFontSizeMultiplier = defaults.object(forKey: Keys.superSpacesFontSizeMultiplier.rawValue) != nil ?
            CGFloat(defaults.double(forKey: Keys.superSpacesFontSizeMultiplier.rawValue)) : 1.0
        
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
    // ================================================================
    // MARK: - Super Spaces Helper Methods
    // ================================================================
    
    /**
     Default emoji set for Spaces 1-16.
     
     FEATURE: Phase 2.3 - Default Space Emojis
     
     Chosen to represent common desktop use cases:
     - Work/productivity (💻, 📧, 📝, 📊)
     - Creative/media (🎨, 🎵, 🎬)
     - Communication (💬, 📱)
     - Learning/research (📚, 🔬)
     - Entertainment (🎮, 🌐)
     - Organization (🛠️, 🏠, 🌟)
     */
    private let defaultSpaceEmojis = [
        "💻", // 1: Work/Computer
        "🌐", // 2: Web/Internet
        "📧", // 3: Email/Communication
        "🎨", // 4: Design/Creative
        "🎵", // 5: Music/Media
        "💬", // 6: Chat/Social
        "📊", // 7: Data/Analytics
        "📝", // 8: Notes/Writing
        "🎮", // 9: Gaming
        "📚", // 10: Reading/Learning
        "🏠", // 11: Personal/Home
        "🛠️", // 12: Tools/Utilities
        "📱", // 13: Mobile/Apps
        "🎬", // 14: Video/Entertainment
        "🔬", // 15: Research/Science
        "🌟"  // 16: Misc/Other
    ]
    
    /**
     Maximum character length for Space names.
     
     FEATURE: Phase 2.2 - Character Limit
     
     RATIONALE:
     - Long enough for descriptive names ("Development & Testing")
     - Short enough to fit in buttons without excessive width
     - Prevents UI layout issues
     - Default names ("Desktop 1") are well within limit
     */
    let maxSpaceNameLength = 30
    
    /**
     Generates default name for a Space.
     
     FEATURE: Phase 2.2 - Default Space Names
     
     Returns "Desktop 1", "Desktop 2", etc.
     These are generated on-the-fly and not stored in UserDefaults.
     */
    func generateDefaultSpaceName(for spaceNumber: Int) -> String {
        return "Desktop \(spaceNumber)"
    }
    
    /**
     Gets default emoji for a Space (1-16).
     
     FEATURE: Phase 2.3 - Default Space Emojis
     
     Returns emoji from preset array if valid index.
     Returns nil for Spaces > 16 (or could cycle through array).
     */
    func getDefaultEmoji(for spaceNumber: Int) -> String? {
        guard spaceNumber >= 1 && spaceNumber <= defaultSpaceEmojis.count else {
            return nil
        }
        return defaultSpaceEmojis[spaceNumber - 1]  // Convert 1-based to 0-based index
    }
    
    /**
     Curated color palette for Space customization.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     DESIGN RATIONALE:
     - Professional, accessible colors that work well in both light and dark mode
     - Vibrant enough to be distinctive but not overwhelming
     - Includes warm, cool, and neutral tones for variety
     - All colors meet WCAG contrast guidelines for readability
     - Hex format for easy storage and conversion
     
     COLOR CATEGORIES:
     - Blues: Calm, professional, focus (default)
     - Greens: Growth, creativity, balance
     - Purples: Innovation, imagination, luxury
     - Reds/Pinks: Energy, passion, urgency
     - Oranges/Yellows: Warmth, optimism, creativity
     - Neutrals: Sophisticated, minimal, classic
     */
    let spaceColorPalette: [(name: String, hex: String)] = [
        // Blues (calm, professional)
        ("Ocean Blue", "#0EA5E9"),      // Bright cyan-blue
        ("Deep Blue", "#3B82F6"),       // Classic blue
        ("Indigo", "#6366F1"),          // Rich indigo
        
        // Greens (growth, balance)
        ("Emerald", "#10B981"),         // Vibrant green
        ("Mint", "#34D399"),            // Fresh mint
        ("Forest", "#059669"),          // Deep forest green
        
        // Purples (creativity, luxury)
        ("Purple", "#A855F7"),          // Vibrant purple
        ("Violet", "#8B5CF6"),          // Rich violet
        ("Magenta", "#D946EF"),         // Bright magenta
        
        // Reds/Pinks (energy, passion)
        ("Rose", "#F43F5E"),            // Vibrant rose
        ("Pink", "#EC4899"),            // Bright pink
        ("Coral", "#FB7185"),           // Soft coral
        
        // Oranges/Yellows (warmth, creativity)
        ("Orange", "#F97316"),          // Vibrant orange
        ("Amber", "#F59E0B"),           // Rich amber
        ("Yellow", "#EAB308"),          // Bright yellow
        
        // Neutrals (sophisticated, minimal)
        ("Slate", "#64748B"),           // Cool gray-blue
        ("Gray", "#6B7280"),            // Neutral gray
        ("Stone", "#78716C")            // Warm gray-brown
    ]
    
    /**
     Gets the custom color for a Space, or nil if no color is set.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     Returns the hex color string stored for this Space.
     Returns nil if no custom color is assigned (will use default blue).
     */
    func getSpaceColor(for spaceNumber: Int) -> String? {
        return spaceColors[spaceNumber]
    }
    
    /**
     Gets a default color for a Space based on its number.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     WHY DEFAULT COLORS:
     - Provides visual distinction between spaces even before user customizes them
     - Creates a more colorful, engaging experience out of the box
     - Helps users quickly identify spaces by color from the start
     - Reduces the need for manual color assignment for basic usage
     
     IMPLEMENTATION:
     - Cycles through the color palette based on space number
     - Uses modulo to wrap around when there are more spaces than colors
     - Provides consistent colors (Space 1 always gets the same default color)
     - User can override by setting a custom color
     
     USAGE:
     - Call this when a Space has no custom color assigned
     - Provides a sensible default instead of always using blue
     
     - Parameter spaceNumber: The Space number (1-based)
     - Returns: Hex color string from the palette
     */
    func getDefaultSpaceColor(for spaceNumber: Int) -> String {
        // Use modulo to cycle through the color palette
        // Subtract 1 because spaceNumber is 1-based but array is 0-based
        let colorIndex = (spaceNumber - 1) % spaceColorPalette.count
        return spaceColorPalette[colorIndex].hex
    }
    
    /**
     Gets the color for a Space, using custom color if set, or default color otherwise.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     This is the primary method to use when displaying Space colors in the UI.
     It ensures every Space has a color (either custom or default).
     
     - Parameter spaceNumber: The Space number (1-based)
     - Returns: Hex color string (custom or default)
     */
    func getSpaceColorOrDefault(for spaceNumber: Int) -> String {
        return spaceColors[spaceNumber] ?? getDefaultSpaceColor(for: spaceNumber)
    }
    
    /**
     Converts hex color string to SwiftUI Color.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     USAGE:
     - Takes hex string like "#FF5733" or "FF5733"
     - Returns SwiftUI Color object
     - Returns default blue if hex is invalid
     
     IMPLEMENTATION:
     - Handles both formats (with and without #)
     - Parses RGB components
     - Converts to 0-1 range for SwiftUI
     */
    func hexToColor(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            // Invalid hex, return default blue
            return Color.blue
        }
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        return Color(red: red, green: green, blue: blue)
    }
    
    /**
     Converts hex color to NSColor for AppKit usage.
     
     FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
     
     Similar to hexToColor but returns NSColor for use in AppKit contexts.
     */
    func hexToNSColor(_ hex: String) -> NSColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            // Invalid hex, return default blue
            return NSColor.systemBlue
        }
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
    
    /**
     Validates and truncates Space name to character limit.
     
     FEATURE: Phase 2.2 - Character Limit
     
     Ensures name doesn't exceed maxSpaceNameLength.
     Returns truncated string if necessary.
     */
    func validateSpaceName(_ name: String) -> String {
        if name.count > maxSpaceNameLength {
            return String(name.prefix(maxSpaceNameLength))
        }
        return name
    }
    
    // ================================================================
    // MARK: - Decay Rate Conversion Helpers
    // ================================================================
    
    /**
     Converts decay rate (% per second) to full decay time (minutes).
     
     FEATURE: Jan 21, 2026 - User-friendly decay time presentation
     
     The decay rate is stored internally as "% per second" for calculation efficiency,
     but presented to users as "full decay in X minutes" for better UX.
     
     Formula: fullDecayMinutes = maxDecayDimLevel / (decayRate * 60)
     
     Example: If maxDecayDimLevel is 0.8 (80%) and decayRate is 0.00133 per second,
     then full decay time = 0.8 / (0.00133 * 60) = 10 minutes
     
     - Returns: Full decay time in minutes
     */
    func getFullDecayTimeMinutes() -> Double {
        // Prevent division by zero
        guard decayRate > 0 else { return 30.0 }
        
        // Calculate how many seconds it takes to reach maxDecayDimLevel
        let secondsToFullDecay = maxDecayDimLevel / decayRate
        
        // Convert to minutes
        return secondsToFullDecay / 60.0
    }
    
    /**
     Sets decay rate based on desired full decay time (minutes).
     
     FEATURE: Jan 21, 2026 - User-friendly decay time presentation
     
     Converts user-friendly "full decay in X minutes" to internal decay rate.
     
     Formula: decayRate = maxDecayDimLevel / (fullDecayMinutes * 60)
     
     Example: For 80% max dim and 10 min full decay:
     decayRate = 0.8 / (10 * 60) = 0.00133 per second
     
     - Parameter minutes: Desired full decay time in minutes (5-30)
     */
    func setFullDecayTimeMinutes(_ minutes: Double) {
        // Clamp to valid range (5-30 minutes)
        let clampedMinutes = min(max(minutes, 5.0), 30.0)
        
        // Convert to seconds
        let secondsToFullDecay = clampedMinutes * 60.0
        
        // Calculate decay rate: maxDim / timeInSeconds
        let newRate = maxDecayDimLevel / secondsToFullDecay
        
        // Clamp to valid internal range (0.0005 to 0.05 per second)
        // This ensures reasonable decay speeds
        decayRate = min(max(newRate, 0.0005), 0.05)
    }
    
    // ================================================================
    // MARK: - Reset Settings
    // ================================================================
    
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
        spaceEmojis = [:]
        spaceNotes = [:]
        spaceColors = [:]  // 5.5.9 - Jan 22, 2026
        superSpacesDisplayMode = "compact"
        superSpacesAutoHide = false
        superSpacesPosition = "topRight"
        lastHUDPosition = nil  // Reset position
        superSpacesFontSizeMultiplier = 1.0  // Reset to normal size (100%)
        
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
    
    /// Posted when dimmingType changes (Settings Redesign Jan 23, 2026)
    static let dimmingTypeChanged = Notification.Name("superdimmer.dimmingTypeChanged")
    
    /// Posted when colorTemperatureEnabled changes
    static let colorTemperatureEnabledChanged = Notification.Name("superdimmer.colorTemperatureEnabledChanged")
    
    /// Posted when colorTemperature value changes
    static let colorTemperatureChanged = Notification.Name("superdimmer.colorTemperatureChanged")
    
    /// Posted when overlayCornerRadius changes (2.8.2b)
    static let overlayCornerRadiusChanged = Notification.Name("superdimmer.overlayCornerRadiusChanged")
}

// NOTE: DetectionMode enum moved to top of file (before DimmingProfile) for Codable synthesis
