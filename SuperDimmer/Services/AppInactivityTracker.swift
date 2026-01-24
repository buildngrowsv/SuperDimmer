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
        
        /// Accumulated inactivity time (seconds) excluding idle periods
        /// FEATURE (Jan 22, 2026): Idle-aware auto-hide
        /// Tracks how long the app has been inactive during active user sessions only.
        /// Idle time (lunch, meetings, etc.) is NOT counted toward auto-hide.
        var accumulatedInactivityTime: TimeInterval
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
    
    /// Active usage tracker for idle detection
    /// FEATURE (Jan 22, 2026): Idle-aware auto-hide
    /// When user is idle (no mouse/keyboard activity), we pause auto-hide timers.
    /// This prevents apps from being hidden when user is away from computer.
    private let activeUsageTracker = ActiveUsageTracker.shared
    
    /// Timestamp when user became idle (for calculating pause duration)
    /// FEATURE (Jan 22, 2026): Idle-aware auto-hide
    /// When user goes idle, we store this timestamp and freeze all app timers.
    /// When they return, we resume from where we left off.
    private var idleSinceTime: Date?
    
    /// Timer for accumulating inactivity time (only when user is active)
    /// FEATURE (Jan 22, 2026): Idle-aware auto-hide
    /// Runs every 10 seconds to accumulate inactivity time for non-frontmost apps.
    /// Only accumulates when user is actively using the computer.
    private var accumulationTimer: Timer?
    
    /// Current active space number
    /// FEATURE (Jan 24, 2026): Space-aware auto-hide
    /// Tracks which space is currently active. Apps without windows on the current
    /// space don't accumulate inactivity time (their timer is paused).
    private var currentSpaceNumber: Int = 1
    
    /// Window tracker service for checking which apps have windows on current space
    /// FEATURE (Jan 24, 2026): Space-aware auto-hide
    private let windowTracker = WindowTrackerService.shared
    
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
        setupIdleTracking()
        setupSpaceTracking()
        startAccumulationTimer()
        print("✓ AppInactivityTracker initialized")
    }
    
    deinit {
        accumulationTimer?.invalidate()
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
                processID: app.processIdentifier,
                accumulatedInactivityTime: 0
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
        
        // Update the activity info - this resets the auto-hide timer
        // NOTE: This fires when:
        // - User clicks on an app
        // - User Cmd+Tabs to an app
        // - User clicks app icon in Dock
        // - App is UNHIDDEN (via Dock, Cmd+Tab, etc.)
        // So unhiding an app automatically resets its auto-hide timer ✅
        appActivity[bundleID] = AppActivityInfo(
            lastActiveTime: Date(),
            bundleID: bundleID,
            localizedName: app.localizedName ?? bundleID,
            processID: app.processIdentifier,
            accumulatedInactivityTime: 0  // Reset accumulated time when app becomes active
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
            processID: app.processIdentifier,
            accumulatedInactivityTime: 0
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
     
     CHANGED (Jan 22, 2026): Idle-aware auto-hide
     Now returns accumulated inactivity time that excludes idle periods.
     This prevents apps from being hidden due to time when user was away.
     
     HOW IT WORKS:
     - Accumulated time only increases when user is actively using computer
     - Idle periods (lunch, meetings, etc.) are NOT counted
     - When app becomes frontmost, accumulated time resets to 0
     
     - Parameter bundleID: The bundle identifier to check
     - Returns: Time interval of active inactivity, or 0 if app is currently active or unknown
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
        
        // Return accumulated inactivity time (excludes idle periods)
        return info.accumulatedInactivityTime
    }
    
    /**
     Gets all apps that have been inactive longer than the specified duration.
     
     IMPORTANT (Jan 24, 2026): Uses accumulated inactivity time, which excludes idle periods.
     This ensures apps are only hidden based on active usage time, not time when user was away.
     
     - Parameters:
       - duration: Minimum inactivity time in seconds (active time only)
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
        
        var inactiveApps: [String] = []
        
        for (bundleID, info) in appActivity {
            // Skip frontmost app
            if bundleID == currentFrontmostBundleID { continue }
            
            // Skip excluded apps
            if excludedBundleIDs.contains(bundleID) { continue }
            
            // Skip system apps if requested
            if excludeSystemApps && Self.systemAppBundleIDs.contains(bundleID) { continue }
            
            // FIX (Jan 24, 2026): Use accumulated inactivity time instead of lastActiveTime
            // This properly excludes idle periods so apps aren't hidden when user is away
            let inactivity = info.accumulatedInactivityTime
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
    
    // ================================================================
    // MARK: - Idle Tracking & Accumulation
    // ================================================================
    
    /**
     Sets up idle state tracking to pause auto-hide timers when user is away.
     
     FEATURE (Jan 22, 2026): Idle-aware auto-hide
     
     WHY THIS MATTERS:
     Without idle tracking, apps continue accumulating inactivity time even when
     you're away from your computer (lunch break, meeting, overnight). This means
     you come back to find apps hidden even though you weren't actively using
     other apps - you were just away.
     
     HOW IT WORKS:
     - Subscribe to ActiveUsageTracker's isUserActive property
     - When user becomes idle: stop accumulating inactivity time
     - When user returns: resume accumulation
     - Result: Auto-hide only counts time during active computer use
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
                    print("⏸️ AppInactivityTracker: User idle - pausing auto-hide timers")
                } else if isActive && self.idleSinceTime != nil {
                    // User returned from idle - clear timestamp
                    let idleDuration = Date().timeIntervalSince(self.idleSinceTime!)
                    self.idleSinceTime = nil
                    print("▶️ AppInactivityTracker: User active - resuming auto-hide timers (was idle for \(Int(idleDuration))s)")
                }
            }
            .store(in: &cancellables)
    }
    
    /**
     Starts the accumulation timer that tracks inactivity time for apps.
     
     FEATURE (Jan 22, 2026): Idle-aware auto-hide
     
     This timer runs every 10 seconds and accumulates inactivity time for
     non-frontmost apps, but ONLY when the user is actively using the computer.
     
     WHY A TIMER:
     We can't just calculate time on-demand because we need to exclude idle periods.
     The timer allows us to accumulate time only during active sessions.
     
     HOW IT WORKS:
     - Every 10 seconds, check if user is active
     - If active: add 10 seconds to all non-frontmost apps' accumulated time
     - If idle: don't accumulate (timer still runs, but doesn't add time)
     - Result: Accurate tracking of active-only inactivity
     */
    private func startAccumulationTimer() {
        // Run on main thread's RunLoop
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.accumulationTimer = Timer.scheduledTimer(
                withTimeInterval: 10.0,  // Check every 10 seconds
                repeats: true
            ) { [weak self] _ in
                self?.accumulateInactivityTime()
            }
            
            // Ensure timer is added to RunLoop
            if let timer = self.accumulationTimer {
                RunLoop.main.add(timer, forMode: .common)
                print("✓ AppInactivityTracker: Accumulation timer started (10s interval)")
            }
        }
    }
    
    /**
     Accumulates inactivity time for non-frontmost apps.
     Called every 10 seconds by the accumulation timer.
     
     ONLY accumulates when:
     1. User is actively using the computer (not idle)
     2. App has at least one window on the current space
     
     FEATURE (Jan 24, 2026): Space-aware auto-hide
     Apps without windows on the current space don't accumulate time.
     This prevents hiding apps that are on other spaces and not visible.
     */
    private func accumulateInactivityTime() {
        // Only accumulate if user is active
        guard activeUsageTracker.isUserActive else {
            return  // User is idle - don't accumulate
        }
        
        // Get all visible windows to check which apps have windows on current space
        let allWindows = windowTracker.getVisibleWindows()
        
        // Build set of bundle IDs that have windows on current space
        var appsWithWindowsOnCurrentSpace = Set<String>()
        for window in allWindows {
            if let bundleID = window.bundleID {
                appsWithWindowsOnCurrentSpace.insert(bundleID)
            }
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        let accumulationInterval: TimeInterval = 10.0  // Match timer interval
        
        // Add time to all non-frontmost apps that have windows on current space
        for (bundleID, var info) in appActivity {
            // Skip frontmost app
            if bundleID == currentFrontmostBundleID {
                continue
            }
            
            // FEATURE (Jan 24, 2026): Space-aware auto-hide
            // Only accumulate if app has windows on current space
            // If app has no windows on current space, its timer is paused
            guard appsWithWindowsOnCurrentSpace.contains(bundleID) else {
                continue  // App not on current space - don't accumulate
            }
            
            // Accumulate inactivity time
            info.accumulatedInactivityTime += accumulationInterval
            appActivity[bundleID] = info
        }
    }
    
    // ================================================================
    // MARK: - Space Tracking
    // ================================================================
    
    /**
     Sets up space change tracking to pause timers for apps on other spaces.
     
     FEATURE (Jan 24, 2026): Space-aware auto-hide
     
     WHY THIS MATTERS:
     Without space tracking, apps on other spaces continue accumulating inactivity
     time even though they're not visible to the user. This means switching to
     Space 2 for a while would cause apps on Space 1 to be hidden, which is
     unexpected and confusing.
     
     HOW IT WORKS:
     - Subscribe to space change notifications from SpaceChangeMonitor
     - Update currentSpaceNumber when user switches spaces
     - accumulateInactivityTime() only counts time for apps with windows on current space
     - Result: Apps only accumulate time when their windows are actually visible
     
     INTEGRATION:
     - Works alongside idle tracking (both features are independent)
     - Auto-hide pauses for BOTH idle periods AND when app is on different space
     */
    private func setupSpaceTracking() {
        // Get initial space number
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            lock.lock()
            currentSpaceNumber = currentSpace.spaceNumber
            lock.unlock()
            print("✓ AppInactivityTracker: Initial space \(currentSpace.spaceNumber)")
        }
        
        // Monitor for space changes
        let spaceMonitor = SpaceChangeMonitor()
        spaceMonitor.startMonitoring { [weak self] newSpaceNumber in
            guard let self = self else { return }
            
            self.lock.lock()
            let oldSpace = self.currentSpaceNumber
            self.currentSpaceNumber = newSpaceNumber
            self.lock.unlock()
            
            print("⏰ AppInactivityTracker: Space changed \(oldSpace) → \(newSpaceNumber) - timers paused for apps on other spaces")
        }
    }
    
    /**
     Updates the current space number.
     Called by external components when space changes are detected.
     
     - Parameter spaceNumber: The new current space number (1-based)
     */
    func updateCurrentSpace(_ spaceNumber: Int) {
        lock.lock()
        defer { lock.unlock() }
        
        guard spaceNumber != currentSpaceNumber else { return }
        
        let oldSpace = currentSpaceNumber
        currentSpaceNumber = spaceNumber
        
        print("⏰ AppInactivityTracker: Space updated \(oldSpace) → \(spaceNumber)")
    }
}
