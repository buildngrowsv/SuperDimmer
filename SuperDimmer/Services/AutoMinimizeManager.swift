/**
 ====================================================================
 AutoMinimizeManager.swift
 Automatically minimizes inactive windows when apps have too many open
 ====================================================================
 
 PURPOSE:
 This service implements the Auto-Minimize Inactive Windows feature.
 It minimizes windows that have been inactive for too long, but only
 when an app has more than the threshold number of windows.
 
 KEY FEATURES:
 1. ACTIVE-TIME ONLY: Only counts time when user is actively working
 2. IDLE RESET: All timers reset after extended idle (no overnight surprise)
 3. THRESHOLD: Only minimizes if app has > N windows (keeps N)
 4. PER-APP: Can exclude specific apps from auto-minimize
 
 HOW IT WORKS:
 - Tracks "active usage time" per window (only when user is active)
 - Every 30 seconds, checks each app's window count
 - If count > threshold, minimizes oldest inactive windows
 - Resets ALL timers when user returns from extended idle
 
 IMPORTANT:
 - This is WINDOW-LEVEL minimizing (uses NSWindow.miniaturize)
 - More aggressive than auto-hide, so OFF by default
 - Walking away doesn't trigger minimize (active-time only)
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// ====================================================================
// MARK: - Auto Minimize Manager
// ====================================================================

/**
 Manages automatic minimizing of inactive windows.
 
 USAGE:
 1. Call `start()` to begin auto-minimize monitoring
 2. Call `stop()` to pause
 3. Tracks active-time per window, respecting idle periods
 */
final class AutoMinimizeManager: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = AutoMinimizeManager()
    
    // ================================================================
    // MARK: - Types
    // ================================================================
    
    /// Tracking info for a window's active usage time
    struct WindowActiveTime {
        var windowID: CGWindowID
        var ownerBundleID: String
        var ownerName: String
        var activeUsageSeconds: TimeInterval  // Only counts when user is active
        var lastUpdated: Date
    }
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /// Whether auto-minimize is currently running
    @Published private(set) var isRunning: Bool = false
    
    /// Number of windows currently being tracked
    @Published private(set) var trackedWindowCount: Int = 0
    
    /// Recently auto-minimized windows for potential restore
    @Published private(set) var recentlyMinimized: [(windowID: CGWindowID, appName: String, time: Date)] = []
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Timer for periodic checks and accumulation
    private var updateTimer: Timer?
    
    /// CRITICAL FIX (Jan 24, 2026): Track windows currently being minimized
    /// to prevent infinite loop where same window gets minimized repeatedly
    /// before the AppleScript completes and removes it from tracking.
    /// This was causing the rainbow spinning cursor crash.
    private var currentlyMinimizing = Set<CGWindowID>()
    
    /// ADDITIONAL SAFETY (Jan 24, 2026): Track last time checkAndMinimizeWindows ran
    /// to prevent it from running too frequently if called from multiple places
    private var lastCheckTime: Date = .distantPast
    private let minCheckInterval: TimeInterval = 5.0  // Don't check more than once per 5 seconds
    
    /// Active usage time per window
    private var windowActiveTimes: [CGWindowID: WindowActiveTime] = [:]
    
    /// Settings manager
    private let settings = SettingsManager.shared
    
    /// Window tracker
    private let windowTracker = WindowTrackerService.shared
    
    /// Active usage tracker
    private let activeUsageTracker = ActiveUsageTracker.shared
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// How often to update accumulators and check (seconds)
    private let updateInterval: TimeInterval = 10.0
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// Maximum recently minimized to track
    private let maxRecentlyMinimized = 20
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        
        // Start automatically if enabled in settings
        if settings.autoMinimizeEnabled {
            start()
        }
        
        print("✓ AutoMinimizeManager initialized")
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    private func setupObservers() {
        // Observe settings changes
        settings.$autoMinimizeEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
        
        // Observe extended idle returns to reset all timers
        NotificationCenter.default.publisher(for: .userReturnedFromExtendedIdle)
            .sink { [weak self] _ in
                self?.resetAllTimers()
            }
            .store(in: &cancellables)
    }
    
    // ================================================================
    // MARK: - Control Methods
    // ================================================================
    
    /**
     Starts the auto-minimize monitoring.
     */
    func start() {
        guard !isRunning else { return }
        
        isRunning = true
        
        // Initialize tracking for current windows
        initializeWindowTracking()
        
        // Create timer for periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateAndCheck()
        }
        
        print("▶️ AutoMinimizeManager started (checking every \(Int(updateInterval))s)")
    }
    
    /**
     Stops the auto-minimize monitoring.
     */
    func stop() {
        guard isRunning else { return }
        
        updateTimer?.invalidate()
        updateTimer = nil
        isRunning = false
        
        print("⏸️ AutoMinimizeManager stopped")
    }
    
    // ================================================================
    // MARK: - Core Logic
    // ================================================================
    
    /**
     Initialize tracking for all currently visible windows.
     */
    private func initializeWindowTracking() {
        let windows = windowTracker.getVisibleWindows()
        let now = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        windowActiveTimes.removeAll()
        
        for window in windows {
            windowActiveTimes[window.id] = WindowActiveTime(
                windowID: window.id,
                ownerBundleID: window.bundleID ?? "",
                ownerName: window.ownerName,
                activeUsageSeconds: 0,
                lastUpdated: now
            )
        }
        
        trackedWindowCount = windowActiveTimes.count
        print("📊 AutoMinimizeManager: Initialized tracking for \(trackedWindowCount) windows")
    }
    
    /**
     Resets all window timers.
     Called when user returns from extended idle or wake from sleep.
     */
    func resetAllTimers() {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        for (windowID, var info) in windowActiveTimes {
            info.activeUsageSeconds = 0
            info.lastUpdated = now
            windowActiveTimes[windowID] = info
        }
        
        print("🔄 AutoMinimizeManager: Reset all \(windowActiveTimes.count) window timers (user returned from idle)")
    }
    
    /**
     Main update loop: accumulate active time and check for windows to minimize.
     Called periodically by the timer.
     */
    private func updateAndCheck() {
        guard settings.autoMinimizeEnabled else { return }
        
        // Update tracked windows
        updateWindowTracking()
        
        // Accumulate active time if user is active
        if activeUsageTracker.getIsUserActive() {
            accumulateActiveTime()
        }
        
        // Check and minimize if needed
        checkAndMinimizeWindows()
    }
    
    /**
     Updates window tracking - adds new windows, removes closed ones.
     */
    private func updateWindowTracking() {
        let currentWindows = windowTracker.getVisibleWindows()
        let currentIDs = Set(currentWindows.map { $0.id })
        let now = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        // Remove windows that no longer exist
        let staleIDs = Set(windowActiveTimes.keys).subtracting(currentIDs)
        for staleID in staleIDs {
            windowActiveTimes.removeValue(forKey: staleID)
        }
        
        // Add new windows
        for window in currentWindows {
            if windowActiveTimes[window.id] == nil {
                windowActiveTimes[window.id] = WindowActiveTime(
                    windowID: window.id,
                    ownerBundleID: window.bundleID ?? "",
                    ownerName: window.ownerName,
                    activeUsageSeconds: 0,
                    lastUpdated: now
                )
            }
        }
        
        // Reset timer for active window (the frontmost one)
        if let activeWindow = currentWindows.first(where: { $0.isActive }) {
            if var info = windowActiveTimes[activeWindow.id] {
                info.activeUsageSeconds = 0
                info.lastUpdated = now
                windowActiveTimes[activeWindow.id] = info
            }
        }
        
        trackedWindowCount = windowActiveTimes.count
    }
    
    /**
     Accumulates active time for all non-active windows.
     Only called when user is actively using the computer.
     */
    private func accumulateActiveTime() {
        let now = Date()
        
        // Get frontmost window ID
        let frontmostWindow = windowTracker.getFrontmostWindow()
        let frontmostID = frontmostWindow?.id ?? 0
        
        lock.lock()
        defer { lock.unlock() }
        
        for (windowID, var info) in windowActiveTimes {
            // Skip the active window
            if windowID == frontmostID {
                info.activeUsageSeconds = 0
                info.lastUpdated = now
                windowActiveTimes[windowID] = info
                continue
            }
            
            // Accumulate time since last update
            let elapsed = now.timeIntervalSince(info.lastUpdated)
            info.activeUsageSeconds += elapsed
            info.lastUpdated = now
            windowActiveTimes[windowID] = info
        }
    }
    
    /**
     Checks each app's window count and minimizes excess inactive windows.
     
     CRITICAL FIX (Jan 24, 2026): Added throttle to prevent this from running too frequently.
     Without this, if called from multiple places or in rapid succession, it can cause
     an infinite loop where windows are minimized repeatedly.
     */
    private func checkAndMinimizeWindows() {
        // THROTTLE: Don't run more frequently than minCheckInterval
        lock.lock()
        let now = Date()
        let timeSinceLastCheck = now.timeIntervalSince(lastCheckTime)
        if timeSinceLastCheck < minCheckInterval {
            lock.unlock()
            return
        }
        lastCheckTime = now
        lock.unlock()
        
        let threshold = settings.autoMinimizeWindowThreshold
        let delaySeconds = settings.autoMinimizeDelay * 60.0  // Convert minutes to seconds
        
        // Get excluded apps from unified exclusion system (2.2.1.12)
        var excludedApps = Set<String>()
        for exclusion in settings.appExclusions where exclusion.excludeFromAutoMinimize {
            excludedApps.insert(exclusion.bundleID)
        }
        // Also include legacy exclusions for backwards compatibility
        excludedApps.formUnion(settings.autoMinimizeExcludedApps)
        
        // Group windows by app
        lock.lock()
        var windowsByApp: [String: [(id: CGWindowID, info: WindowActiveTime)]] = [:]
        
        for (windowID, info) in windowActiveTimes {
            let bundleID = info.ownerBundleID
            if bundleID.isEmpty { continue }
            
            if windowsByApp[bundleID] == nil {
                windowsByApp[bundleID] = []
            }
            windowsByApp[bundleID]?.append((id: windowID, info: info))
        }
        lock.unlock()
        
        // Check each app
        for (bundleID, windows) in windowsByApp {
            // Skip excluded apps
            if excludedApps.contains(bundleID) { continue }
            
            // Skip system apps
            if AppInactivityTracker.isSystemApp(bundleID) { continue }
            
            // Skip our own app
            if bundleID == Bundle.main.bundleIdentifier { continue }
            
            // Only process if window count exceeds threshold
            if windows.count <= threshold { continue }
            
            // Sort by active usage time (highest = oldest inactive)
            let sortedWindows = windows.sorted { $0.info.activeUsageSeconds > $1.info.activeUsageSeconds }
            
            // Calculate how many to minimize
            let toMinimize = windows.count - threshold
            
            // Minimize the oldest inactive windows that exceed the delay
            var minimizedCount = 0
            for window in sortedWindows {
                if minimizedCount >= toMinimize { break }
                
                // Only minimize if exceeded the delay
                if window.info.activeUsageSeconds >= delaySeconds {
                    minimizeWindow(windowID: window.id, appName: window.info.ownerName)
                    minimizedCount += 1
                }
            }
            
            if minimizedCount > 0 {
                print("📥 AutoMinimizeManager: Minimized \(minimizedCount) windows from '\(windows.first?.info.ownerName ?? bundleID)'")
            }
        }
    }
    
    /**
     Minimizes a specific window.
     
     IMPORTANT (2.2.1.10): We remove all overlays for this window BEFORE minimizing it
     to prevent orphaned overlays that remain visible after the window is minimized.
     
     CRITICAL FIX (Jan 24, 2026): Added guard to prevent minimizing same window multiple times.
     The AppleScript execution is slow (100-500ms), and during that time the analysis cycle
     continues running. Without this guard, the same window gets queued for minimization
     repeatedly, causing an infinite loop and rainbow spinning cursor crash.
     
     - Parameters:
       - windowID: The CGWindowID of the window to minimize
       - appName: The app name (for logging and tracking)
     */
    private func minimizeWindow(windowID: CGWindowID, appName: String) {
        // CRITICAL: Check if this window is already being minimized
        lock.lock()
        if currentlyMinimizing.contains(windowID) {
            lock.unlock()
            // Already minimizing this window, skip to prevent infinite loop
            return
        }
        // Mark as currently minimizing
        currentlyMinimizing.insert(windowID)
        lock.unlock()
        
        // CRITICAL FIX (2.2.1.10): Remove all overlays for this window BEFORE minimizing it
        // This prevents orphaned overlays that remain visible after the window is minimized.
        // The overlays will be recreated when the window is unminimized and becomes visible again.
        OverlayManager.shared.removeOverlay(for: windowID)
        
        // Unfortunately, there's no direct way to minimize a window by CGWindowID
        // We need to use Accessibility API or AppleScript
        // For now, we'll use AppleScript as it's more reliable
        
        let script = """
        tell application "System Events"
            set theWindows to every window of every process
            repeat with theProcess in every process
                repeat with theWindow in every window of theProcess
                    try
                        if (get id of theWindow) is \(windowID) then
                            set miniaturized of theWindow to true
                            return true
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return false
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            lock.lock()
            // Always remove from currentlyMinimizing, whether success or failure
            currentlyMinimizing.remove(windowID)
            
            if error == nil && result.booleanValue {
                // Track in recently minimized
                addToRecentlyMinimized(windowID: windowID, appName: appName)
                
                // Remove from tracking
                windowActiveTimes.removeValue(forKey: windowID)
                lock.unlock()
                
                print("📥 AutoMinimizeManager: Minimized window \(windowID) from '\(appName)'")
            } else {
                lock.unlock()
                // AppleScript may fail for some windows - not critical
                // The window might have been closed or the app doesn't support it
            }
        } else {
            // Failed to create script object
            lock.lock()
            currentlyMinimizing.remove(windowID)
            lock.unlock()
        }
    }
    
    // ================================================================
    // MARK: - Recently Minimized Management
    // ================================================================
    
    private func addToRecentlyMinimized(windowID: CGWindowID, appName: String) {
        lock.lock()
        defer { lock.unlock() }
        
        recentlyMinimized.insert((windowID: windowID, appName: appName, time: Date()), at: 0)
        
        if recentlyMinimized.count > maxRecentlyMinimized {
            recentlyMinimized = Array(recentlyMinimized.prefix(maxRecentlyMinimized))
        }
    }
    
    /**
     Clears the recently minimized list.
     */
    func clearRecentlyMinimized() {
        lock.lock()
        recentlyMinimized.removeAll()
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
        let delay = Int(settings.autoMinimizeDelay)
        let threshold = settings.autoMinimizeWindowThreshold
        let tracked = trackedWindowCount
        let recent = recentlyMinimized.count
        
        return "AutoMinimize: \(running), delay=\(delay)min, threshold=\(threshold), tracking=\(tracked), recentlyMinimized=\(recent)"
    }
    
    /**
     Gets detailed window tracking info for debugging.
     */
    func getWindowTrackingDetails() -> [(app: String, windowID: CGWindowID, activeTime: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        
        return windowActiveTimes.values.map { info in
            (app: info.ownerName, windowID: info.windowID, activeTime: info.activeUsageSeconds)
        }.sorted { $0.activeTime > $1.activeTime }
    }
}
