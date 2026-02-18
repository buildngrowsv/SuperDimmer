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
    
    /**
     Tracks bundle IDs for which hide() has recently failed, along with the
     timestamp of the last failure.
     
     FIX (Feb 6, 2026): Prevents the "failed hide + overlay removal" loop.
     
     THE BUG:
     Without this, every 60-second check cycle would attempt to hide the same
     app, call removeOverlaysForApp() before checking the result, get a failure
     from app.hide(), and leave the user with flickering overlays as they get
     removed and recreated each cycle.
     
     THE FIX:
     After a failed hide attempt, we record the bundle ID and timestamp here.
     We won't retry that app for `hideRetryCooldown` seconds (5 minutes).
     This prevents the overlay flicker loop while still retrying eventually
     in case conditions change (e.g., user switches away from that app).
     */
    private var failedHideAttempts: [String: Date] = [:]
    
    /**
     Cooldown period after a failed hide attempt before retrying.
     5 minutes is long enough to prevent flickering but short enough to
     retry in case the app is no longer frontmost.
     */
    private let hideRetryCooldown: TimeInterval = 300.0  // 5 minutes
    
    /**
     FIX (Feb 7, 2026): Minimum grace period after activation/unhide before auto-hide.
     
     THE BUG:
     When user unhides Chrome (Cmd+Tab, Dock click, etc.) and then switches to
     another app briefly, Chrome could be re-hidden within 60-120 seconds because:
     1. `currentFrontmostBundleID` can go stale during space changes
     2. The accumulated time from before the unhide wasn't always properly cleared
     3. The 10-second accumulation timer could race with the activation notification
     
     THE FIX:
     After any activation or unhide, the app gets a 5-minute immunity window
     where it CANNOT be auto-hidden. This guarantees the user has time to work
     with the app, even if they briefly switch to another app during that time.
     
     5 minutes was chosen because:
     - It's long enough for the user to switch between apps while working
     - It's short enough that truly abandoned apps still get hidden
     - It matches the hideRetryCooldown for consistency
     */
    private let activationGracePeriod: TimeInterval = 300.0  // 5 minutes
    
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
        
        // FIX (Feb 6, 2026): Clear failed hide cooldowns when apps become active.
        // When the user activates an app, that app's conditions have changed —
        // it was frontmost, and now has a fresh inactivity timer. We should clear
        // any previous failed hide cooldown so the app can be properly re-evaluated
        // after the full autoHideDelay passes again.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            
            self.lock.lock()
            self.failedHideAttempts.removeValue(forKey: bundleID)
            self.lock.unlock()
        }
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
        
        // Get excluded apps from unified exclusion system (2.2.1.12)
        var excludedApps = Set<String>()
        for exclusion in settings.appExclusions where exclusion.excludeFromAutoHide {
            excludedApps.insert(exclusion.bundleID)
        }
        // Also include legacy exclusions for backwards compatibility
        excludedApps.formUnion(settings.autoHideExcludedApps)
        
        // Get inactive apps
        let inactiveApps = appTracker.getInactiveApps(
            olderThan: delaySeconds,
            excludeSystemApps: settings.autoHideExcludeSystemApps,
            excludedBundleIDs: excludedApps
        )
        
        // Hide each inactive app and count successes
        // FIX (Jan 28, 2026): Track actual successful hides, not just attempted hides
        // This fixes misleading logging that said "Hid X apps" even when some failed
        var hiddenCount = 0
        for bundleID in inactiveApps {
            if hideApp(bundleID: bundleID) {
                hiddenCount += 1
            }
        }
        
        if hiddenCount > 0 {
            print("🙈 AutoHideManager: Hid \(hiddenCount) inactive app(s)")
        }
    }
    
    /**
     Hides a specific app by bundle ID.
     
     FIX (Feb 6, 2026): Major rewrite to fix overlay flickering bug.
     
     PREVIOUS BUG:
     We used to call removeOverlaysForApp() BEFORE app.hide(). When the hide
     failed (e.g., app is frontmost, or macOS rejected it), overlays were removed
     for a still-visible app. The next analysis cycle would recreate them, causing
     a visible flicker every 60 seconds. Logs showed repeated messages like:
       ⚠️ AutoHideManager: Failed to hide 'Cursor'
       🙈 Removed 3 overlays for hidden app (PID 67448)
     
     FIXES APPLIED:
     1. Added frontmost app check — never attempt to hide the active app
     2. Moved removeOverlaysForApp() to AFTER successful hide
     3. Added cooldown for failed hide attempts to prevent retry loops
     4. DimmingCoordinator already observes didHideApplicationNotification for
        overlay cleanup, so our explicit call is just for immediate response
     
     - Parameter bundleID: The bundle identifier of the app to hide
     - Returns: true if successfully hidden
     */
    @discardableResult
    func hideApp(bundleID: String) -> Bool {
        // Find the running app
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
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
        
        // FIX (Feb 6, 2026): Don't hide the frontmost (active) app.
        // The user is currently interacting with it. macOS would reject
        // the hide anyway, but checking here avoids the side effects
        // (overlay removal attempt, log noise, cooldown tracking).
        if app == NSWorkspace.shared.frontmostApplication {
            return false
        }
        
        // FIX (Feb 7, 2026): Grace period check — don't hide apps that were
        // recently activated or unhidden by the user. This prevents the bug where
        // Chrome gets re-hidden immediately after the user opens it, because:
        // - The frontmost tracking (`currentFrontmostBundleID`) can go stale
        //   during space changes when `didActivateApplicationNotification` doesn't fire
        // - Old accumulated inactivity time from before idle wasn't fully cleared
        // - The user briefly switched away from Chrome (to check something else)
        //   and Chrome started re-accumulating time before the grace period elapsed
        //
        // With this check, any app the user recently interacted with gets a minimum
        // 5-minute window where it stays visible, regardless of accumulated time.
        if let timeSinceActivation = appTracker.getTimeSinceLastActivation(for: bundleID) {
            if timeSinceActivation < activationGracePeriod {
                return false  // App was recently activated/unhidden — don't hide yet
            }
        }
        
        // FIX (Feb 6, 2026): Check cooldown for previously failed hide attempts.
        // This prevents the overlay flickering loop where we remove overlays
        // every 60s for an app that refuses to be hidden.
        lock.lock()
        if let lastFailed = failedHideAttempts[bundleID] {
            let timeSinceFailure = Date().timeIntervalSince(lastFailed)
            if timeSinceFailure < hideRetryCooldown {
                lock.unlock()
                return false  // Still in cooldown, skip this attempt
            }
        }
        lock.unlock()
        
        // Attempt to hide the app
        let result = app.hide()
        
        if result {
            // FIX (Feb 6, 2026): MOVED overlay removal to AFTER successful hide.
            // Previously this was before hide(), causing overlays to be removed
            // even when hide failed — creating the flickering bug.
            //
            // NOTE: DimmingCoordinator also handles overlay removal via
            // didHideApplicationNotification, but we call explicitly here for
            // immediate response (the notification may be slightly delayed).
            let pid = app.processIdentifier
            OverlayManager.shared.removeOverlaysForApp(pid: pid)
            
            // Track in recently hidden
            let appName = app.localizedName ?? bundleID
            addToRecentlyHidden(bundleID: bundleID, name: appName)
            
            // Clear any previous failure cooldown since hide succeeded
            lock.lock()
            failedHideAttempts.removeValue(forKey: bundleID)
            lock.unlock()
            
            print("🙈 AutoHideManager: Hid '\(appName)' (inactive for >\(Int(settings.autoHideDelay))min)")
        } else {
            // Hide failed — record the failure timestamp for cooldown.
            // Don't log every failure because it creates noise every 60s.
            // Common failure reason: app is somehow protected or in a state
            // where macOS won't allow hiding (not frontmost — we checked that
            // above — but some apps resist programmatic hiding).
            lock.lock()
            failedHideAttempts[bundleID] = Date()
            lock.unlock()
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
