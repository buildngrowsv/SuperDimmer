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
    
    /// Last known frontmost app PID (for app-level tracking reference)
    private var lastFrontmostPID: pid_t = 0
    
    /// Last known frontmost WINDOW ID (for window-level tracking)
    /// CHANGED (Jan 8, 2026): Track specific window, not just app
    /// Only this specific window is considered "active" (no decay)
    private var lastFrontmostWindowID: CGWindowID = 0
    
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
     
     CHANGED (Jan 8, 2026): Now sets `lastFrontmostWindowID` for window-level tracking.
     Only this specific window will be considered "active" (no decay applied).
     Other windows of the same app WILL decay.
     
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
        
        // Track the specific frontmost window for window-level decay
        lastFrontmostWindowID = windowID
        lastFrontmostPID = ownerPID
    }
    
    /**
     Updates tracking when an app becomes frontmost (via system notification).
     
     FIX (Jan 9, 2026): Reset decay timers for ALL windows of this app.
     When an app is unhidden/activated, all its windows should start fresh
     with no decay dimming. The user expects "reopening" an app to reset timers.
     
     - Parameter pid: The process ID of the app that became frontmost
     */
    func appBecameActive(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        
        lastFrontmostPID = pid
        
        // FIX: Reset timestamps for ALL windows of this app
        // This ensures unhiding an app resets decay for all its windows
        let now = Date()
        for (windowID, var info) in windowActivity {
            if info.ownerPID == pid {
                info.lastActiveTime = now
                windowActivity[windowID] = info
            }
        }
    }
    
    /**
     Gets how long a window has been inactive.
     
     CHANGED (Jan 8, 2026): Now tracks at WINDOW level, not APP level.
     Only the actual frontmost window (lastFrontmostWindowID) returns 0.
     Other windows of the same app WILL decay if they're not the active window.
     
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
        
        // FIX: Only the ACTUAL frontmost window is considered active
        // Other windows of the same app SHOULD decay
        if windowID == lastFrontmostWindowID {
            return 0
        }
        
        return Date().timeIntervalSince(info.lastActiveTime)
    }
    
    /**
     Registers or refreshes a window's tracking.
     
     FIX (Jan 9, 2026): Changed to ALWAYS update timestamp for new windows,
     not just if window was never tracked. This ensures:
     - New windows start with no decay
     - Windows that were closed and reopened (same ID) also reset
     
     Existing active windows are NOT touched - only truly new appearances.
     
     - Parameters:
       - windowID: The window ID
       - ownerPID: The process ID
       - ownerName: The app name
       - forceReset: If true, always reset the timestamp (for new window detection)
     */
    func registerWindow(_ windowID: CGWindowID, ownerPID: pid_t, ownerName: String, forceReset: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        
        if windowActivity[windowID] == nil || forceReset {
            // New window or forced reset - set timestamp to now
            windowActivity[windowID] = WindowActivityInfo(
                lastActiveTime: Date(),
                ownerPID: ownerPID,
                ownerName: ownerName
            )
        }
    }
    
    /**
     Resets the inactivity timer for a specific window.
     
     Call this when a window is newly opened or becomes visible again
     to prevent immediate decay dimming.
     
     - Parameter windowID: The window to reset
     */
    func resetWindowTimer(_ windowID: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        
        if var info = windowActivity[windowID] {
            info.lastActiveTime = Date()
            windowActivity[windowID] = info
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
