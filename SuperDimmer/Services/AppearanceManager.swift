//
//  AppearanceManager.swift
//  SuperDimmer
//
//  Created: January 16, 2026
//
//  PURPOSE: Monitor macOS system appearance (Light/Dark mode) and trigger
//  profile switching when the appearance changes.
//
//  FEATURE: 2.2.1.1 - Appearance Mode System
//  This enables users to have different dimming behaviors for Light vs Dark mode.
//  For example, Dark mode users may want aggressive dimming ON by default,
//  while Light mode users may prefer minimal or no dimming.
//
//  DESIGN DECISIONS:
//  - Uses NSAppearance.currentDrawing() to detect Light/Dark mode
//  - Observes NSApplication.didChangeEffectiveAppearanceNotification
//  - Notifies SettingsManager when appearance changes so it can load the appropriate profile
//  - Does NOT directly modify settings; instead, delegates to SettingsManager
//  - Respects user's appearanceMode setting (.system, .light, .dark)
//
//  INTEGRATION POINTS:
//  - Called by SettingsManager in init() to start observing
//  - Triggers SettingsManager.loadProfileForCurrentAppearance() when appearance changes
//

import Cocoa
import Combine

/// Manages detection of and response to macOS system appearance changes (Light/Dark mode).
///
/// LIFECYCLE:
/// 1. Initialize with a callback closure
/// 2. Call start() to begin observing appearance changes
/// 3. Call stop() to stop observing (e.g., on app termination)
///
/// CALLBACK BEHAVIOR:
/// - onAppearanceChanged is called with the new appearance (.light or .dark)
/// - Callback is invoked on the main thread
/// - First call happens immediately upon start() to establish initial state
///
/// THREAD SAFETY:
/// - All public methods should be called from the main thread
/// - Notification observer runs on main queue
class AppearanceManager {
    
    // MARK: - Properties
    
    /// Callback invoked when the system appearance changes.
    /// This is the primary integration point with SettingsManager.
    /// The callback receives the new appearance type.
    var onAppearanceChanged: ((AppearanceType) -> Void)?
    
    /// Notification observer token for appearance change notifications
    private var appearanceObserver: NSObjectProtocol?
    
    /// The last detected appearance, used to avoid redundant callbacks
    private var lastDetectedAppearance: AppearanceType?
    
    /// Debounce timer to prevent excessive appearance change callbacks
    /// PERFORMANCE FIX (Jan 16, 2026): The system notification can fire multiple times
    private var debounceTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        // Initialize with no callback; it will be set by the caller (SettingsManager)
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Start observing system appearance changes.
    ///
    /// BEHAVIOR:
    /// - Registers for NSApplication.didChangeEffectiveAppearanceNotification
    /// - Immediately detects current appearance and invokes callback
    /// - Subsequent appearance changes will trigger additional callbacks
    ///
    /// USAGE:
    /// Call this once during app initialization (typically in SettingsManager.init)
    func start() {
        // Stop any existing observer to prevent duplicates
        stop()
        
        // Register for appearance change notifications
        // WHY didChangeScreenParametersNotification:
        // There isn't a direct NSApplication notification for appearance changes in older macOS versions.
        // Instead, we observe NSApplication.didChangeScreenParametersNotification and check appearance.
        // For more modern approach, we could also use KVO on NSApp.effectiveAppearance.
        // However, the most reliable way is to observe didBecomeActiveNotification and check then.
        // But for real-time detection, we use a distributed notification from the system.
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppearanceChange()
        }
        
        // Detect and notify the initial appearance immediately
        // This ensures the app loads the correct profile on startup
        handleAppearanceChange()
    }
    
    /// Stop observing system appearance changes.
    ///
    /// USAGE:
    /// Call this when the app is about to terminate or when you no longer need appearance tracking.
    func stop() {
        if let observer = appearanceObserver {
            NotificationCenter.default.removeObserver(observer)
            appearanceObserver = nil
        }
    }
    
    /// Get the current system appearance without triggering a callback.
    ///
    /// RETURNS:
    /// - .dark if the system is in Dark Mode
    /// - .light if the system is in Light Mode
    ///
    /// USAGE:
    /// Use this for one-off appearance checks, such as when manually switching profiles.
    func getCurrentAppearance() -> AppearanceType {
        return detectAppearance()
    }
    
    // MARK: - Private Methods
    
    /// Detects the current appearance and invokes the callback if it has changed.
    ///
    /// IMPLEMENTATION:
    /// - Calls detectAppearance() to determine current state
    /// - Compares to lastDetectedAppearance to avoid redundant callbacks
    /// - Invokes onAppearanceChanged on the main thread if appearance has changed
    ///
    /// DEBOUNCING:
    /// The lastDetectedAppearance check prevents duplicate callbacks if the
    /// notification fires multiple times for the same appearance state.
    ///
    /// PERFORMANCE FIX (Jan 16, 2026):
    /// Added debug logging to track how often this is called
    private func handleAppearanceChange() {
        let currentAppearance = detectAppearance()
        
        // Only trigger callback if appearance has actually changed
        // This prevents unnecessary profile switches and UI updates
        if lastDetectedAppearance != currentAppearance {
            print("🌓 AppearanceManager: Appearance changed from \(lastDetectedAppearance?.displayName ?? "nil") to \(currentAppearance.displayName)")
            lastDetectedAppearance = currentAppearance
            
            // Invoke callback on main thread (it should already be main, but we ensure it)
            DispatchQueue.main.async { [weak self] in
                self?.onAppearanceChanged?(currentAppearance)
            }
        } else {
            print("🌓 AppearanceManager: handleAppearanceChange called but no change detected (still \(currentAppearance.displayName))")
        }
    }
    
    /// Detects the current macOS appearance (Light or Dark).
    ///
    /// IMPLEMENTATION NOTES:
    /// - Uses NSApp.effectiveAppearance to get the app's current appearance
    /// - NSAppearance.name can be .darkAqua, .aqua, .vibrantDark, .vibrantLight, etc.
    /// - We check for .darkAqua specifically to determine Dark Mode
    /// - All other appearance names are treated as Light Mode
    ///
    /// EDGE CASES:
    /// - High Contrast modes are treated as either Light or Dark based on their base appearance
    /// - Accessibility appearances follow the same logic
    ///
    /// RETURNS:
    /// - .dark if effectiveAppearance.name is .darkAqua
    /// - .light for all other cases (including .aqua, .accessibilityHighContrastAqua, etc.)
    private func detectAppearance() -> AppearanceType {
        // Get the app's effective appearance
        // WHY effectiveAppearance instead of currentDrawing():
        // effectiveAppearance reflects the overall app appearance,
        // while currentDrawing() might differ in specific view contexts.
        let appearance = NSApp.effectiveAppearance
        
        // Extract the appearance name and check if it's dark
        // .darkAqua is the standard Dark Mode appearance in macOS
        let appearanceName = appearance.bestMatch(from: [.darkAqua, .aqua])
        
        if appearanceName == .darkAqua {
            return .dark
        } else {
            return .light
        }
    }
}

/// Represents the current system or user-selected appearance.
///
/// USAGE:
/// - Used by AppearanceManager to report detected appearance
/// - Used by SettingsManager to determine which profile to load
enum AppearanceType: String, Codable, CaseIterable {
    case light = "light"
    case dark = "dark"
    
    /// Human-readable label for UI display
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Represents the user's appearance mode preference.
///
/// USAGE IN UI:
/// - User can select .system to automatically follow macOS appearance
/// - User can select .light to force Light mode profile regardless of system
/// - User can select .dark to force Dark mode profile regardless of system
///
/// DEFAULT:
/// - .system (follows macOS appearance)
enum AppearanceMode: String, Codable, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    /// Human-readable label for UI display
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    /// Icon for UI display
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
