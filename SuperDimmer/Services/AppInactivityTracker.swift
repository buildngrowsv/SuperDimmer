/**
 ====================================================================
 AppInactivityTracker.swift
 Tracks how long each app has been inactive (not frontmost)
 ====================================================================
 
 PURPOSE:
 This service tracks when apps were last used (frontmost) to enable
 the Auto-Hide Inactive Apps feature. Unlike WindowInactivityTracker
 which tracks individual windows, this tracks at the APP level.
 
 HOW IT WORKS:
 - Observes NSWorkspace.didActivateApplicationNotification
 - Records timestamp when each app becomes frontmost
 - Provides "time since last used" for any running app
 - Used by AutoHideManager to decide which apps to hide
 
 INTEGRATION:
 - Used by AutoHideManager for auto-hide decisions
 - Works alongside WindowInactivityTracker (they don't conflict)
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// ====================================================================
// MARK: - App Inactivity Tracker
// ====================================================================

/**
 Tracks inactivity time for apps to enable auto-hide feature.
 
 USAGE:
 1. Automatically tracks when apps become frontmost
 2. Call `getInactivityDuration(for:)` to get time since app was last used
 3. Call `getInactiveApps(olderThan:)` to get list of apps to hide
 */
final class AppInactivityTracker: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = AppInactivityTracker()
    
    // ================================================================
    // MARK: - Types
    // ================================================================
    
    /// Information about a tracked app's activity
    struct AppActivityInfo {
        /// When this app was last frontmost
        var lastActiveTime: Date
        
        /// Bundle ID for identification
        var bundleID: String
        
        /// Localized name for display
        var localizedName: String
        
        /// PID of the running app
        var processID: pid_t
    }
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Map of bundle ID to activity info
    private var appActivity: [String: AppActivityInfo] = [:]
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Currently frontmost app bundle ID
    private var currentFrontmostBundleID: String?
    
    /// System app bundle IDs that should be excluded by default
    /// These are apps that generally should never be auto-hidden
    static let systemAppBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemPreferences",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.screencaptureui",
        "com.apple.ActivityMonitor"
    ]
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        initializeRunningApps()
        print("✓ AppInactivityTracker initialized")
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    /**
     Sets up notification observers for app activation.
     */
    private func setupObservers() {
        // Observe app activation changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Observe app termination to clean up
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Observe app launch
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
    }
    
    /**
     Initialize tracking for all currently running apps.
     Sets their last active time to now so they don't immediately get hidden.
     */
    private func initializeRunningApps() {
        let now = Date()
        
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Skip background-only apps
            if app.activationPolicy != .regular { continue }
            
            lock.lock()
            appActivity[bundleID] = AppActivityInfo(
                lastActiveTime: now,
                bundleID: bundleID,
                localizedName: app.localizedName ?? bundleID,
                processID: app.processIdentifier
            )
            lock.unlock()
        }
        
        // Mark the frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier {
            currentFrontmostBundleID = bundleID
        }
        
        print("📱 AppInactivityTracker: Initialized \(appActivity.count) running apps")
    }
    
    // ================================================================
    // MARK: - Notification Handlers
    // ================================================================
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        // Update the activity info
        appActivity[bundleID] = AppActivityInfo(
            lastActiveTime: Date(),
            bundleID: bundleID,
            localizedName: app.localizedName ?? bundleID,
            processID: app.processIdentifier
        )
        
        currentFrontmostBundleID = bundleID
    }
    
    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        // Skip background-only apps
        if app.activationPolicy != .regular { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        // New apps start with current time
        appActivity[bundleID] = AppActivityInfo(
            lastActiveTime: Date(),
            bundleID: bundleID,
            localizedName: app.localizedName ?? bundleID,
            processID: app.processIdentifier
        )
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        lock.lock()
        defer { lock.unlock() }
        
        appActivity.removeValue(forKey: bundleID)
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Gets how long an app has been inactive (not frontmost).
     
     - Parameter bundleID: The bundle identifier to check
     - Returns: Time interval since last active, or 0 if app is currently active or unknown
     */
    func getInactivityDuration(for bundleID: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        // Currently frontmost app has 0 inactivity
        if bundleID == currentFrontmostBundleID {
            return 0
        }
        
        guard let info = appActivity[bundleID] else {
            return 0  // Unknown app
        }
        
        return Date().timeIntervalSince(info.lastActiveTime)
    }
    
    /**
     Gets all apps that have been inactive longer than the specified duration.
     
     - Parameters:
       - duration: Minimum inactivity time in seconds
       - excludeSystemApps: Whether to exclude system apps
       - excludedBundleIDs: Additional bundle IDs to exclude
     - Returns: Array of bundle IDs that have been inactive too long
     */
    func getInactiveApps(
        olderThan duration: TimeInterval,
        excludeSystemApps: Bool = true,
        excludedBundleIDs: Set<String> = []
    ) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        var inactiveApps: [String] = []
        
        for (bundleID, info) in appActivity {
            // Skip frontmost app
            if bundleID == currentFrontmostBundleID { continue }
            
            // Skip excluded apps
            if excludedBundleIDs.contains(bundleID) { continue }
            
            // Skip system apps if requested
            if excludeSystemApps && Self.systemAppBundleIDs.contains(bundleID) { continue }
            
            // Check inactivity duration
            let inactivity = now.timeIntervalSince(info.lastActiveTime)
            if inactivity >= duration {
                inactiveApps.append(bundleID)
            }
        }
        
        return inactiveApps
    }
    
    /**
     Gets information about a tracked app.
     
     - Parameter bundleID: The bundle identifier to look up
     - Returns: Activity info if tracked, nil otherwise
     */
    func getAppInfo(for bundleID: String) -> AppActivityInfo? {
        lock.lock()
        defer { lock.unlock() }
        return appActivity[bundleID]
    }
    
    /**
     Gets all tracked apps with their inactivity durations.
     
     - Returns: Array of tuples (bundleID, localizedName, inactivitySeconds)
     */
    func getAllAppsWithInactivity() -> [(bundleID: String, name: String, inactivity: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        return appActivity.map { (bundleID, info) in
            let inactivity = bundleID == currentFrontmostBundleID ? 0 : now.timeIntervalSince(info.lastActiveTime)
            return (bundleID: bundleID, name: info.localizedName, inactivity: inactivity)
        }.sorted { $0.inactivity > $1.inactivity }  // Most inactive first
    }
    
    /**
     Checks if an app is a system app that should typically be excluded.
     
     - Parameter bundleID: The bundle identifier to check
     - Returns: true if this is a system app
     */
    static func isSystemApp(_ bundleID: String) -> Bool {
        return systemAppBundleIDs.contains(bundleID)
    }
}
