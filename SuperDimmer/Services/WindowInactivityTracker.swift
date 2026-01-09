/**
 ====================================================================
 WindowInactivityTracker.swift
 Tracks how long each window has been inactive
 ====================================================================
 
 PURPOSE:
 This service tracks the last time each window was active (frontmost).
 It enables the Inactivity Decay Dimming feature, where windows that
 haven't been used recently progressively dim more.
 
 HOW IT WORKS:
 - Observes app activation changes via NSWorkspace
 - When an app becomes frontmost, updates timestamps for its windows
 - Provides inactivity duration for any tracked window
 - Cleans up stale entries when windows close
 
 INTEGRATION:
 - Used by DimmingCoordinator to calculate decay-based dim levels
 - Decay formula: baseDim + (decayRate × max(0, inactivityTime - delay))
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// ====================================================================
// MARK: - Window Inactivity Tracker
// ====================================================================

/**
 Tracks inactivity time for windows to enable decay dimming.
 
 USAGE:
 1. Call `windowBecameActive(windowID:)` when a window becomes frontmost
 2. Call `getInactivityDuration(for:)` to get how long a window has been inactive
 3. Call `cleanup(activeWindowIDs:)` periodically to remove stale entries
 */
final class WindowInactivityTracker: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = WindowInactivityTracker()
    
    // ================================================================
    // MARK: - Types
    // ================================================================
    
    /// Information about a tracked window's activity
    struct WindowActivityInfo {
        /// When this window was last active (frontmost)
        var lastActiveTime: Date
        
        /// Owner PID for grouping windows by app
        var ownerPID: pid_t
        
        /// Owner name for debugging
        var ownerName: String
    }
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Map of window ID to activity info
    private var windowActivity: [CGWindowID: WindowActivityInfo] = [:]
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Last known frontmost app PID
    private var lastFrontmostPID: pid_t = 0
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        print("✓ WindowInactivityTracker initialized")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Marks a window as having just been active.
     
     Call this when a window becomes the frontmost window.
     
     - Parameters:
       - windowID: The CGWindowID of the window
       - ownerPID: The process ID of the window's owner
       - ownerName: The name of the owning application
     */
    func windowBecameActive(_ windowID: CGWindowID, ownerPID: pid_t, ownerName: String) {
        lock.lock()
        defer { lock.unlock() }
        
        windowActivity[windowID] = WindowActivityInfo(
            lastActiveTime: Date(),
            ownerPID: ownerPID,
            ownerName: ownerName
        )
    }
    
    /**
     Marks all windows belonging to an app as active.
     
     Called when an app becomes frontmost - all its windows are considered "active"
     since the user is now interacting with that app.
     
     - Parameter pid: The process ID of the app that became frontmost
     */
    func appBecameActive(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        for (windowID, var info) in windowActivity {
            if info.ownerPID == pid {
                info.lastActiveTime = now
                windowActivity[windowID] = info
            }
        }
        
        lastFrontmostPID = pid
    }
    
    /**
     Gets how long a window has been inactive.
     
     - Parameter windowID: The window to check
     - Returns: Time interval since last active, or 0 if window is currently active or unknown
     */
    func getInactivityDuration(for windowID: CGWindowID) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        
        guard let info = windowActivity[windowID] else {
            // Unknown window - return 0 (no decay)
            return 0
        }
        
        // If this window's app is currently frontmost, it's active
        if info.ownerPID == lastFrontmostPID {
            return 0
        }
        
        return Date().timeIntervalSince(info.lastActiveTime)
    }
    
    /**
     Registers a window if not already tracked.
     
     New windows start with the current time as their last active time,
     so they don't immediately start decaying.
     
     - Parameters:
       - windowID: The window ID
       - ownerPID: The process ID
       - ownerName: The app name
     */
    func registerWindow(_ windowID: CGWindowID, ownerPID: pid_t, ownerName: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if windowActivity[windowID] == nil {
            windowActivity[windowID] = WindowActivityInfo(
                lastActiveTime: Date(),
                ownerPID: ownerPID,
                ownerName: ownerName
            )
        }
    }
    
    /**
     Removes entries for windows that no longer exist.
     
     - Parameter activeWindowIDs: Set of window IDs that are currently visible
     */
    func cleanup(activeWindowIDs: Set<CGWindowID>) {
        lock.lock()
        defer { lock.unlock() }
        
        let staleIDs = Set(windowActivity.keys).subtracting(activeWindowIDs)
        for staleID in staleIDs {
            windowActivity.removeValue(forKey: staleID)
        }
    }
    
    /**
     Returns debug info about tracked windows.
     */
    func debugInfo() -> [(windowID: CGWindowID, ownerName: String, inactivitySeconds: Int)] {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        return windowActivity.map { (windowID, info) in
            let inactivity = info.ownerPID == lastFrontmostPID ? 0 : now.timeIntervalSince(info.lastActiveTime)
            return (windowID, info.ownerName, Int(inactivity))
        }.sorted { $0.inactivitySeconds > $1.inactivitySeconds }
    }
    
    // ================================================================
    // MARK: - Private Methods
    // ================================================================
    
    /**
     Sets up observers for app activation changes.
     */
    private func setupObservers() {
        // Observe when apps become frontmost
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let pid = app.processIdentifier as pid_t? else {
                    return
                }
                self?.appBecameActive(pid: pid)
            }
            .store(in: &cancellables)
        
        // Initialize with current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            lastFrontmostPID = frontmost.processIdentifier
        }
    }
}
