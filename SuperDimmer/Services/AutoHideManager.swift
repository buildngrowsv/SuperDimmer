/**
 ====================================================================
 AutoHideManager.swift
 Automatically hides apps that have been inactive too long
 ====================================================================
 
 PURPOSE:
 This service implements the Auto-Hide Inactive Apps feature.
 It periodically checks which apps have been inactive longer than
 the configured delay and hides them (like pressing Cmd+H).
 
 HOW IT WORKS:
 - Runs a timer every 60 seconds to check for inactive apps
 - Uses AppInactivityTracker for inactivity durations
 - Respects exclusion lists (user-defined + system apps)
 - Hides apps via NSRunningApplication.hide()
 - Logs actions for user transparency
 
 IMPORTANT:
 - This is APP-LEVEL hiding (hides all windows of the app)
 - Non-destructive: apps remain in Dock and can be unhidden
 - ON by default because it's a helpful, non-disruptive feature
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// ====================================================================
// MARK: - Auto Hide Manager
// ====================================================================

/**
 Manages automatic hiding of inactive apps.
 
 USAGE:
 1. Call `start()` to begin auto-hide monitoring
 2. Call `stop()` to pause auto-hide
 3. Recently hidden apps are tracked for potential unhiding
 */
final class AutoHideManager: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = AutoHideManager()
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /// Whether auto-hide is currently running
    @Published private(set) var isRunning: Bool = false
    
    /// Recently auto-hidden apps (bundleID, name, hiddenTime)
    @Published private(set) var recentlyHiddenApps: [(bundleID: String, name: String, hiddenTime: Date)] = []
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Timer for periodic checks
    private var checkTimer: Timer?
    
    /// Settings manager
    private let settings = SettingsManager.shared
    
    /// App inactivity tracker
    private let appTracker = AppInactivityTracker.shared
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// How often to check for inactive apps (seconds)
    private let checkInterval: TimeInterval = 60.0
    
    /// Maximum number of recently hidden apps to track
    private let maxRecentlyHidden = 10
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        
        // Start automatically if enabled in settings
        if settings.autoHideEnabled {
            start()
        }
        
        print("✓ AutoHideManager initialized")
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    private func setupObservers() {
        // Observe settings changes
        settings.$autoHideEnabled
            .dropFirst()  // Skip initial value
            .sink { [weak self] enabled in
                if enabled {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
    }
    
    // ================================================================
    // MARK: - Control Methods
    // ================================================================
    
    /**
     Starts the auto-hide monitoring.
     */
    func start() {
        guard !isRunning else { return }
        
        isRunning = true
        
        // Create timer for periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkAndHideInactiveApps()
        }
        
        print("▶️ AutoHideManager started (checking every \(Int(checkInterval))s)")
    }
    
    /**
     Stops the auto-hide monitoring.
     */
    func stop() {
        guard isRunning else { return }
        
        checkTimer?.invalidate()
        checkTimer = nil
        isRunning = false
        
        print("⏸️ AutoHideManager stopped")
    }
    
    // ================================================================
    // MARK: - Core Logic
    // ================================================================
    
    /**
     Checks for inactive apps and hides them if they exceed the delay.
     Called periodically by the timer.
     */
    private func checkAndHideInactiveApps() {
        guard settings.autoHideEnabled else { return }
        
        // Convert delay from minutes to seconds
        let delaySeconds = settings.autoHideDelay * 60.0
        
        // Get excluded apps
        let excludedApps = Set(settings.autoHideExcludedApps)
        
        // Get inactive apps
        let inactiveApps = appTracker.getInactiveApps(
            olderThan: delaySeconds,
            excludeSystemApps: settings.autoHideExcludeSystemApps,
            excludedBundleIDs: excludedApps
        )
        
        // Hide each inactive app
        for bundleID in inactiveApps {
            hideApp(bundleID: bundleID)
        }
        
        if !inactiveApps.isEmpty {
            print("🙈 AutoHideManager: Hid \(inactiveApps.count) inactive app(s)")
        }
    }
    
    /**
     Hides a specific app by bundle ID.
     
     - Parameter bundleID: The bundle identifier of the app to hide
     - Returns: true if successfully hidden
     */
    @discardableResult
    func hideApp(bundleID: String) -> Bool {
        // Find the running app
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            print("⚠️ AutoHideManager: Could not find running app: \(bundleID)")
            return false
        }
        
        // Don't hide our own app
        if bundleID == Bundle.main.bundleIdentifier {
            return false
        }
        
        // Don't hide if it's already hidden
        if app.isHidden {
            return false
        }
        
        // Hide the app
        let result = app.hide()
        
        if result {
            // Track in recently hidden
            let appName = app.localizedName ?? bundleID
            addToRecentlyHidden(bundleID: bundleID, name: appName)
            
            print("🙈 AutoHideManager: Hid '\(appName)' (inactive for >\(Int(settings.autoHideDelay))min)")
        } else {
            print("⚠️ AutoHideManager: Failed to hide '\(app.localizedName ?? bundleID)'")
        }
        
        return result
    }
    
    /**
     Unhides a previously hidden app.
     
     - Parameter bundleID: The bundle identifier of the app to unhide
     - Returns: true if successfully unhidden
     */
    @discardableResult
    func unhideApp(bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return false
        }
        
        let result = app.unhide()
        
        if result {
            // Remove from recently hidden
            removeFromRecentlyHidden(bundleID: bundleID)
            
            // Optionally activate the app so it comes to front
            app.activate(options: [.activateIgnoringOtherApps])
            
            print("👁️ AutoHideManager: Unhid '\(app.localizedName ?? bundleID)'")
        }
        
        return result
    }
    
    /**
     Unhides all recently hidden apps.
     */
    func unhideAllRecent() {
        lock.lock()
        let appsToUnhide = recentlyHiddenApps.map { $0.bundleID }
        lock.unlock()
        
        for bundleID in appsToUnhide {
            unhideApp(bundleID: bundleID)
        }
    }
    
    // ================================================================
    // MARK: - Recently Hidden Management
    // ================================================================
    
    private func addToRecentlyHidden(bundleID: String, name: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove if already in list (we'll add fresh)
        recentlyHiddenApps.removeAll { $0.bundleID == bundleID }
        
        // Add to front
        recentlyHiddenApps.insert((bundleID: bundleID, name: name, hiddenTime: Date()), at: 0)
        
        // Trim to max
        if recentlyHiddenApps.count > maxRecentlyHidden {
            recentlyHiddenApps = Array(recentlyHiddenApps.prefix(maxRecentlyHidden))
        }
    }
    
    private func removeFromRecentlyHidden(bundleID: String) {
        lock.lock()
        defer { lock.unlock() }
        
        recentlyHiddenApps.removeAll { $0.bundleID == bundleID }
    }
    
    /**
     Clears the recently hidden list.
     */
    func clearRecentlyHidden() {
        lock.lock()
        recentlyHiddenApps.removeAll()
        lock.unlock()
    }
    
    // ================================================================
    // MARK: - Debug / Status
    // ================================================================
    
    /**
     Gets a status summary for debugging.
     */
    func getStatusSummary() -> String {
        let running = isRunning ? "Running" : "Stopped"
        let delay = Int(settings.autoHideDelay)
        let excluded = settings.autoHideExcludedApps.count
        let recent = recentlyHiddenApps.count
        
        return "AutoHide: \(running), delay=\(delay)min, excluded=\(excluded), recentlyHidden=\(recent)"
    }
}
