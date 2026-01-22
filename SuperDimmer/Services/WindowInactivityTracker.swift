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
        
        /// Space number where this window was last seen/active
        /// FEATURE (Jan 21, 2026): Space-aware decay freezing
        /// When user switches spaces, windows on other spaces freeze their decay timers.
        /// This prevents windows from continuing to dim when they're not visible.
        var lastSeenOnSpace: Int?
        
        /// Accumulated inactivity time (seconds) when window was on a different space
        /// FEATURE (Jan 21, 2026): Space-aware decay freezing
        /// When a window is on a non-current space, we freeze the timer by storing
        /// the elapsed time. When the space becomes active again, we resume from this point.
        var frozenInactivityTime: TimeInterval
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
    
    /// Apps that are currently hidden (for detecting unhide vs window switch)
    /// FIX (Jan 9, 2026): We need to distinguish between:
    /// - App was hidden and got unhidden → reset ALL windows
    /// - App was visible, user clicked another window → reset only THAT window
    private var hiddenAppPIDs: Set<pid_t> = []
    
    /// Current active space number
    /// FEATURE (Jan 21, 2026): Space-aware decay freezing
    /// Tracks which space is currently active. When this changes, we freeze
    /// decay timers for windows on the old space and resume timers for windows
    /// on the new space.
    private var currentSpaceNumber: Int = 1
    
    /// Active usage tracker for idle detection
    /// FEATURE (Jan 22, 2026): Idle-aware decay dimming
    /// When user is idle (no mouse/keyboard activity), we pause decay timers.
    /// This prevents windows from continuing to dim when user is away from computer.
    private let activeUsageTracker = ActiveUsageTracker.shared
    
    /// Timestamp when user became idle (for calculating pause duration)
    /// FEATURE (Jan 22, 2026): Idle-aware decay dimming
    /// When user goes idle, we store this timestamp. When they return, we can
    /// calculate how long they were away and adjust timers accordingly.
    private var idleSinceTime: Date?
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        setupIdleTracking()
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
     
     CHANGED (Jan 21, 2026): Added space tracking for space-aware decay freezing.
     Records which space the window is on so decay can be frozen when user switches spaces.
     
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
            ownerName: ownerName,
            lastSeenOnSpace: currentSpaceNumber,
            frozenInactivityTime: 0
        )
        
        // Track the specific frontmost window for window-level decay
        lastFrontmostWindowID = windowID
        lastFrontmostPID = ownerPID
    }
    
    /**
     Updates tracking when an app becomes frontmost (via system notification).
     
     FIX (Jan 9, 2026): Only reset ALL windows if app was previously HIDDEN.
     If app was already visible and user just clicked a different window,
     only that specific window should reset (via windowBecameActive).
     
     - Parameter pid: The process ID of the app that became frontmost
     */
    func appBecameActive(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        
        // Check if this app was previously hidden
        let wasHidden = hiddenAppPIDs.contains(pid)
        
        // App is now active, remove from hidden set
        hiddenAppPIDs.remove(pid)
        
        lastFrontmostPID = pid
        
        // Only reset ALL windows if app was UNHIDDEN (not just window switch)
        if wasHidden {
            let now = Date()
            for (windowID, var info) in windowActivity {
                if info.ownerPID == pid {
                    info.lastActiveTime = now
                    windowActivity[windowID] = info
                }
            }
            print("⏰ App unhidden (PID \(pid)) - reset all window timers")
        }
        // If app wasn't hidden, individual window resets via windowBecameActive()
    }
    
    /**
     Called when an app is hidden.
     
     We track hidden apps so we can reset all their window timers
     when they're unhidden (vs just clicking a different window).
     
     - Parameter pid: The process ID of the hidden app
     */
    func appWasHidden(pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        
        hiddenAppPIDs.insert(pid)
    }
    
    /**
     Gets how long a window has been inactive.
     
     CHANGED (Jan 8, 2026): Now tracks at WINDOW level, not APP level.
     Only the actual frontmost window (lastFrontmostWindowID) returns 0.
     Other windows of the same app WILL decay if they're not the active window.
     
     CHANGED (Jan 21, 2026): Space-aware decay freezing.
     Windows on non-current spaces return their frozen inactivity time instead of
     continuing to accumulate. This prevents windows from dimming when they're not visible.
     
     CHANGED (Jan 22, 2026): Idle-aware decay dimming.
     When user is idle (no activity), decay timers pause. This prevents windows from
     continuing to dim when user is away from computer (lunch, meeting, etc.).
     
     HOW IT WORKS:
     - If window is on current space: calculate normal inactivity time
     - If window is on different space: return frozen time (decay paused)
     - If user is idle: pause decay accumulation (don't count idle time)
     - When space becomes active again: resume from frozen time
     
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
        
        // FEATURE (Jan 21, 2026): Space-aware decay freezing
        // If window is on a different space than current, return frozen time
        // This prevents decay from continuing when windows aren't visible
        if let windowSpace = info.lastSeenOnSpace, windowSpace != currentSpaceNumber {
            // Window is on a different space - return frozen inactivity time
            // Decay is paused until this space becomes active again
            return info.frozenInactivityTime
        }
        
        // FEATURE (Jan 22, 2026): Idle-aware decay dimming
        // If user is currently idle, we need to calculate time excluding idle period
        let currentInactivity: TimeInterval
        if !activeUsageTracker.isUserActive, let idleStart = idleSinceTime {
            // User is idle - calculate time up to when they became idle
            // Don't count the idle time itself
            currentInactivity = idleStart.timeIntervalSince(info.lastActiveTime)
        } else {
            // User is active - calculate normal elapsed time
            currentInactivity = Date().timeIntervalSince(info.lastActiveTime)
        }
        
        // Window is on current space - calculate inactivity time
        // Add any previously frozen time to current elapsed time
        return info.frozenInactivityTime + max(0, currentInactivity)
    }
    
    /**
     Registers or refreshes a window's tracking.
     
     FIX (Jan 9, 2026): Changed to ALWAYS update timestamp for new windows,
     not just if window was never tracked. This ensures:
     - New windows start with no decay
     - Windows that were closed and reopened (same ID) also reset
     
     CHANGED (Jan 21, 2026): Added space tracking for new windows.
     
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
                ownerName: ownerName,
                lastSeenOnSpace: currentSpaceNumber,
                frozenInactivityTime: 0
            )
        }
    }
    
    /**
     Updates the current active space number.
     
     FEATURE (Jan 21, 2026): Space-aware decay freezing
     
     When the user switches spaces, this method:
     1. Freezes decay timers for windows on the old space
     2. Updates the current space number
     3. Resumes decay timers for windows on the new space
     
     HOW FREEZING WORKS:
     - For each window on the old space, we calculate its current inactivity time
     - We store this as "frozenInactivityTime" so decay stops accumulating
     - When the space becomes active again, we resume from this frozen time
     
     - Parameter spaceNumber: The new current space number (1-based)
     */
    func updateCurrentSpace(_ spaceNumber: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        // If space hasn't changed, nothing to do
        guard spaceNumber != currentSpaceNumber else { return }
        
        let oldSpace = currentSpaceNumber
        let now = Date()
        
        // Freeze timers for windows on the old space
        for (windowID, var info) in windowActivity {
            if info.lastSeenOnSpace == oldSpace {
                // This window is on the old space - freeze its timer
                let currentInactivity = now.timeIntervalSince(info.lastActiveTime)
                info.frozenInactivityTime = info.frozenInactivityTime + currentInactivity
                info.lastActiveTime = now  // Reset base time for when space becomes active again
                windowActivity[windowID] = info
            }
        }
        
        // Update current space
        currentSpaceNumber = spaceNumber
        
        // Windows on the new space will automatically resume decay calculation
        // because getInactivityDuration() will now see they match currentSpaceNumber
        
        print("⏰ Space changed: \(oldSpace) → \(spaceNumber) - froze timers for old space")
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
     Gets the stored info for a window.
     
     Used by OverlayManager to check which app owns a window
     when removing overlays for hidden apps.
     
     - Parameter windowID: The window to look up
     - Returns: Window activity info if tracked, nil otherwise
     */
    func getWindowInfo(for windowID: CGWindowID) -> WindowActivityInfo? {
        lock.lock()
        defer { lock.unlock() }
        
        return windowActivity[windowID]
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
     Sets up observers for app activation and hide changes.
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
        
        // Observe when apps are hidden (Cmd+H or programmatically)
        // FIX (Jan 9, 2026): Track hidden apps so we know when they're UNHIDDEN
        // vs just switching windows within an already-visible app
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                self?.appWasHidden(pid: app.processIdentifier)
            }
            .store(in: &cancellables)
        
        // Initialize with current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            lastFrontmostPID = frontmost.processIdentifier
        }
        
        // Initialize hidden apps set from currently running apps
        for app in NSWorkspace.shared.runningApplications {
            if app.isHidden {
                hiddenAppPIDs.insert(app.processIdentifier)
            }
        }
    }
    
    // ================================================================
    // MARK: - Idle Tracking
    // ================================================================
    
    /**
     Sets up idle state tracking to pause decay timers when user is away.
     
     FEATURE (Jan 22, 2026): Idle-aware decay dimming
     
     WHY THIS MATTERS:
     Without idle tracking, windows continue to decay dim even when you're away
     from your computer (lunch break, meeting, overnight). This means you come back
     to find everything heavily dimmed even though you weren't actively ignoring them.
     
     HOW IT WORKS:
     - Subscribe to ActiveUsageTracker's isUserActive property
     - When user becomes idle: record the timestamp
     - When user returns: getInactivityDuration() automatically excludes idle time
     - Result: Decay only accumulates during active computer use
     
     INTEGRATION:
     - Works alongside space-aware freezing (both features are independent)
     - Decay pauses for BOTH idle periods AND space switches
     */
    private func setupIdleTracking() {
        // Observe user activity state changes
        activeUsageTracker.$isUserActive
            .sink { [weak self] isActive in
                guard let self = self else { return }
                
                self.lock.lock()
                defer { self.lock.unlock() }
                
                if !isActive && self.idleSinceTime == nil {
                    // User just became idle - record timestamp
                    self.idleSinceTime = Date()
                    print("⏸️ WindowInactivityTracker: User idle - pausing decay timers")
                } else if isActive && self.idleSinceTime != nil {
                    // User returned from idle - clear timestamp
                    let idleDuration = Date().timeIntervalSince(self.idleSinceTime!)
                    self.idleSinceTime = nil
                    print("▶️ WindowInactivityTracker: User active - resuming decay timers (was idle for \(Int(idleDuration))s)")
                }
            }
            .store(in: &cancellables)
    }
}
