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
 - Every 10 seconds, checks each app's window count
 - If count > threshold, minimizes oldest inactive windows
 - Resets ALL timers when user returns from extended idle
 
 IMPORTANT:
 - This is WINDOW-LEVEL minimizing (uses Accessibility API)
 - More aggressive than auto-hide, so OFF by default
 - Walking away doesn't trigger minimize (active-time only)
 
 CRITICAL FIX (Feb 18, 2026): REPLACED APPLESCRIPT WITH ACCESSIBILITY API
 The previous implementation used NSAppleScript + System Events, which had
 these severe problems:
 
 1. UMBRA HANG: Each AppleScript iterated EVERY window of EVERY process
    via System Events IPC. Multiple concurrent scripts saturated System
    Events, blocking Umbra (which also uses System Events) when switching
    dark/light mode. Quitting SuperDimmer unblocked Umbra.
 
 2. SILENT FAILURE: The AppleScript was likely never actually minimizing
    windows. The "Minimized N windows" log fired BEFORE the script ran
    (dispatch-time, not success-time). Same windows appeared every cycle
    because failed windows stayed in tracking and were retried forever
    with no error logging and no retry limit.
 
 3. THREAD SAFETY: OverlayManager.shared.removeOverlay() was called from
    a background thread but it accesses non-thread-safe dictionaries and
    manipulates NSWindow objects that must be on the main thread.
 
 NEW APPROACH: Uses the macOS Accessibility API directly:
 - AXUIElementCreateApplication(pid) to target ONLY the specific app
 - kAXWindowsAttribute to get ONLY that app's windows (not ALL processes)
 - _AXUIElementGetWindow() (private but widely used) to match CGWindowID
 - kAXMinimizedAttribute to minimize the specific window
 
 This is orders of magnitude lighter than the AppleScript approach because
 it only queries ONE process, not every process on the system.
 
 ====================================================================
 Created: January 8, 2026
 Version: 2.0.0 (Feb 18, 2026 - AX API rewrite)
 ====================================================================
 */

import Foundation
import AppKit
import Combine
import ApplicationServices

// ====================================================================
// MARK: - Private AX API Declaration
// ====================================================================

/// Private API to get CGWindowID from an AXUIElement.
/// This is the standard way macOS window management tools (yabai, Hammerspoon,
/// Amethyst, etc.) bridge between CGWindowList and Accessibility APIs.
/// There is no public API equivalent — Apple never provided one.
/// The function has been stable across macOS 10.x through 15.x+.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ outWindow: UnsafeMutablePointer<CGWindowID>) -> AXError

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
    
    /// Tracking info for a window's active usage time.
    /// ownerPID is stored so we can use the Accessibility API to target
    /// just the owning process rather than iterating every process.
    struct WindowActiveTime {
        var windowID: CGWindowID
        var ownerPID: pid_t
        var ownerBundleID: String
        var ownerName: String
        var activeUsageSeconds: TimeInterval
        var lastUpdated: Date
        /// How many times we tried and failed to minimize this window.
        /// After maxFailedAttempts we stop retrying to avoid endless
        /// System Events / AX traffic (the root cause of the Umbra hang).
        var failedMinimizeAttempts: Int = 0
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
    
    /// Track windows currently being minimized to prevent duplicate operations.
    /// (Jan 24, 2026): Prevents infinite loop where same window gets minimized
    /// repeatedly before the operation completes.
    private var currentlyMinimizing = Set<CGWindowID>()
    
    /// Throttle: Track last time checkAndMinimizeWindows ran.
    /// (Jan 24, 2026): Prevents it from running too frequently.
    private var lastCheckTime: Date = .distantPast
    private let minCheckInterval: TimeInterval = 5.0
    
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
    
    /// Maximum failed minimize attempts before giving up on a window.
    /// After this many failures, the window is removed from tracking so we
    /// stop hammering the Accessibility API (or System Events) with futile
    /// requests. This was the root cause of the Umbra hang: hundreds of
    /// failed AppleScript operations saturated System Events.
    private let maxFailedAttempts = 3
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        
        if settings.autoMinimizeEnabled {
            start()
        }
        
        print("✓ AutoMinimizeManager initialized (AX API mode)")
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    private func setupObservers() {
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
    }
    
    // ================================================================
    // MARK: - Control Methods
    // ================================================================
    
    func start() {
        guard !isRunning else { return }
        
        isRunning = true
        initializeWindowTracking()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateAndCheck()
        }
        
        print("▶️ AutoMinimizeManager started (checking every \(Int(updateInterval))s)")
    }
    
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
    
    private func initializeWindowTracking() {
        let windows = windowTracker.getVisibleWindows()
        let now = Date()
        
        lock.lock()
        defer { lock.unlock() }
        
        windowActiveTimes.removeAll()
        
        for window in windows {
            windowActiveTimes[window.id] = WindowActiveTime(
                windowID: window.id,
                ownerPID: window.ownerPID,
                ownerBundleID: window.bundleID ?? "",
                ownerName: window.ownerName,
                activeUsageSeconds: 0,
                lastUpdated: now,
                failedMinimizeAttempts: 0
            )
        }
        
        trackedWindowCount = windowActiveTimes.count
        print("📊 AutoMinimizeManager: Initialized tracking for \(trackedWindowCount) windows")
    }
    
    private func updateAndCheck() {
        guard settings.autoMinimizeEnabled else { return }
        
        updateWindowTracking()
        
        if activeUsageTracker.getIsUserActive() {
            accumulateActiveTime()
        }
        
        checkAndMinimizeWindows()
    }
    
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
        
        // Add new windows (includes ownerPID for AX API targeting)
        for window in currentWindows {
            if windowActiveTimes[window.id] == nil {
                windowActiveTimes[window.id] = WindowActiveTime(
                    windowID: window.id,
                    ownerPID: window.ownerPID,
                    ownerBundleID: window.bundleID ?? "",
                    ownerName: window.ownerName,
                    activeUsageSeconds: 0,
                    lastUpdated: now,
                    failedMinimizeAttempts: 0
                )
            }
        }
        
        // Reset timer for frontmost window
        if let activeWindow = currentWindows.first(where: { $0.isActive }) {
            if var info = windowActiveTimes[activeWindow.id] {
                info.activeUsageSeconds = 0
                info.lastUpdated = now
                windowActiveTimes[activeWindow.id] = info
            }
        }
        
        trackedWindowCount = windowActiveTimes.count
    }
    
    private func accumulateActiveTime() {
        let now = Date()
        let frontmostWindow = windowTracker.getFrontmostWindow()
        let frontmostID = frontmostWindow?.id ?? 0
        
        lock.lock()
        defer { lock.unlock() }
        
        for (windowID, var info) in windowActiveTimes {
            if windowID == frontmostID {
                info.activeUsageSeconds = 0
                info.lastUpdated = now
                windowActiveTimes[windowID] = info
                continue
            }
            
            let elapsed = now.timeIntervalSince(info.lastUpdated)
            info.activeUsageSeconds += elapsed
            info.lastUpdated = now
            windowActiveTimes[windowID] = info
        }
    }
    
    /**
     Checks each app's window count and minimizes excess inactive windows.
     
     FIX (Feb 18, 2026): The log message now says "Attempting to minimize"
     instead of "Minimized" because the actual operation happens asynchronously.
     Previously the misleading "Minimized" message fired before the operation ran.
     */
    private func checkAndMinimizeWindows() {
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
        let delaySeconds = settings.autoMinimizeDelay * 60.0
        
        var excludedApps = Set<String>()
        for exclusion in settings.appExclusions where exclusion.excludeFromAutoMinimize {
            excludedApps.insert(exclusion.bundleID)
        }
        excludedApps.formUnion(settings.autoMinimizeExcludedApps)
        
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
        
        for (bundleID, windows) in windowsByApp {
            if excludedApps.contains(bundleID) { continue }
            if AppInactivityTracker.isSystemApp(bundleID) { continue }
            if bundleID == Bundle.main.bundleIdentifier { continue }
            if windows.count <= threshold { continue }
            
            let sortedWindows = windows.sorted { $0.info.activeUsageSeconds > $1.info.activeUsageSeconds }
            let toMinimize = windows.count - threshold
            
            var dispatchedCount = 0
            for window in sortedWindows {
                if dispatchedCount >= toMinimize { break }
                
                if window.info.activeUsageSeconds >= delaySeconds {
                    // Skip windows that have exceeded the retry limit
                    if window.info.failedMinimizeAttempts >= maxFailedAttempts {
                        continue
                    }
                    
                    lock.lock()
                    let alreadyMinimizing = currentlyMinimizing.contains(window.id)
                    lock.unlock()
                    
                    if !alreadyMinimizing {
                        let pid = window.info.ownerPID
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            self?.minimizeWindowViaAccessibility(
                                windowID: window.id,
                                ownerPID: pid,
                                appName: window.info.ownerName
                            )
                        }
                        dispatchedCount += 1
                    }
                }
            }
            
            if dispatchedCount > 0 {
                print("📥 AutoMinimizeManager: Attempting to minimize \(dispatchedCount) window(s) from '\(windows.first?.info.ownerName ?? bundleID)'")
            }
        }
    }
    
    // ================================================================
    // MARK: - Accessibility API Minimize
    // ================================================================
    
    /**
     Minimizes a window using the macOS Accessibility API.
     
     APPROACH (Feb 18, 2026):
     Instead of the old AppleScript that iterated EVERY window of EVERY process
     via System Events (causing System Events saturation and blocking Umbra),
     this method targets ONLY the specific owning process:
     
     1. AXUIElementCreateApplication(pid) → target just this app
     2. kAXWindowsAttribute → enumerate only this app's windows
     3. _AXUIElementGetWindow() → match the specific CGWindowID
     4. kAXMinimizedAttribute = true → minimize it
     
     This is O(windows_in_app) instead of O(all_windows_in_system) and does NOT
     use System Events at all, eliminating the IPC contention that blocked Umbra.
     
     THREAD SAFETY FIX (Feb 18, 2026): Overlay removal is now dispatched to
     the main thread. Previously it was called directly from the background
     thread, which is unsafe because OverlayManager accesses non-thread-safe
     dictionaries and manipulates NSWindow objects.
     
     RETRY LIMIT (Feb 18, 2026): If minimize fails, we increment the window's
     failedMinimizeAttempts counter. After maxFailedAttempts (3), we stop retrying
     that window entirely. This prevents the infinite-retry bombardment that was
     the root cause of the System Events saturation / Umbra hang.
     */
    private func minimizeWindowViaAccessibility(windowID: CGWindowID, ownerPID: pid_t, appName: String) {
        // Prevent duplicate operations on the same window
        lock.lock()
        if currentlyMinimizing.contains(windowID) {
            lock.unlock()
            return
        }
        currentlyMinimizing.insert(windowID)
        lock.unlock()
        
        // THREAD SAFETY FIX: Dispatch overlay removal to main thread.
        // OverlayManager's dictionaries and NSWindow operations are not thread-safe.
        DispatchQueue.main.async {
            OverlayManager.shared.removeOverlay(for: windowID)
        }
        
        // Use Accessibility API to minimize the window
        let success = accessibilityMinimize(windowID: windowID, pid: ownerPID)
        
        lock.lock()
        currentlyMinimizing.remove(windowID)
        
        if success {
            addToRecentlyMinimized(windowID: windowID, appName: appName)
            windowActiveTimes.removeValue(forKey: windowID)
            lock.unlock()
            
            print("✅ AutoMinimizeManager: Successfully minimized window \(windowID) from '\(appName)' via AX API")
        } else {
            // Increment failure counter so we stop retrying after maxFailedAttempts
            if var info = windowActiveTimes[windowID] {
                info.failedMinimizeAttempts += 1
                windowActiveTimes[windowID] = info
                let attempts = info.failedMinimizeAttempts
                lock.unlock()
                
                if attempts >= maxFailedAttempts {
                    print("⚠️ AutoMinimizeManager: Giving up on window \(windowID) from '\(appName)' after \(attempts) failed attempts")
                } else {
                    print("⚠️ AutoMinimizeManager: Failed to minimize window \(windowID) from '\(appName)' (attempt \(attempts)/\(maxFailedAttempts))")
                }
            } else {
                lock.unlock()
                print("⚠️ AutoMinimizeManager: Failed to minimize window \(windowID) from '\(appName)' (window no longer tracked)")
            }
        }
    }
    
    /**
     Low-level Accessibility API call to minimize a window by CGWindowID.
     
     Enumerates ONLY the target app's windows (via AXUIElementCreateApplication),
     matches by CGWindowID using the private _AXUIElementGetWindow(), and sets
     kAXMinimizedAttribute to true.
     
     - Parameters:
       - windowID: The CGWindowID to minimize
       - pid: Process ID of the owning application
     - Returns: true if successfully minimized, false otherwise
     */
    private func accessibilityMinimize(windowID: CGWindowID, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        
        // Get the app's windows via Accessibility API
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        guard result == .success, let axWindows = windowsRef as? [AXUIElement] else {
            // App might not support accessibility or has no windows
            return false
        }
        
        // Find the window matching our CGWindowID
        for axWindow in axWindows {
            var axWindowID: CGWindowID = 0
            let getResult = _AXUIElementGetWindow(axWindow, &axWindowID)
            
            if getResult == .success && axWindowID == windowID {
                // Found the matching window — minimize it
                let setResult = AXUIElementSetAttributeValue(
                    axWindow,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanTrue
                )
                return setResult == .success
            }
        }
        
        // Window not found in this app's AX window list
        return false
    }
    
    // ================================================================
    // MARK: - Recently Minimized Management
    // ================================================================
    
    /// NOTE: This method assumes the lock is already held by the caller
    /// when called from minimizeWindowViaAccessibility (lock is held).
    /// When called independently, caller must hold the lock.
    private func addToRecentlyMinimized(windowID: CGWindowID, appName: String) {
        // lock is already held by caller
        recentlyMinimized.insert((windowID: windowID, appName: appName, time: Date()), at: 0)
        
        if recentlyMinimized.count > maxRecentlyMinimized {
            recentlyMinimized = Array(recentlyMinimized.prefix(maxRecentlyMinimized))
        }
    }
    
    func clearRecentlyMinimized() {
        lock.lock()
        recentlyMinimized.removeAll()
        lock.unlock()
    }
    
    // ================================================================
    // MARK: - Debug / Status
    // ================================================================
    
    func getStatusSummary() -> String {
        let running = isRunning ? "Running" : "Stopped"
        let delay = Int(settings.autoMinimizeDelay)
        let threshold = settings.autoMinimizeWindowThreshold
        let tracked = trackedWindowCount
        let recent = recentlyMinimized.count
        
        return "AutoMinimize: \(running), delay=\(delay)min, threshold=\(threshold), tracking=\(tracked), recentlyMinimized=\(recent)"
    }
    
    func getWindowTrackingDetails() -> [(app: String, windowID: CGWindowID, activeTime: TimeInterval)] {
        lock.lock()
        defer { lock.unlock() }
        
        return windowActiveTimes.values.map { info in
            (app: info.ownerName, windowID: info.windowID, activeTime: info.activeUsageSeconds)
        }.sorted { $0.activeTime > $1.activeTime }
    }
}
