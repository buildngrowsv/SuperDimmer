/**
 ====================================================================
 ActiveUsageTracker.swift
 Detects whether the user is actively using the computer
 ====================================================================
 
 PURPOSE:
 This service tracks user activity (mouse movement, keyboard input)
 to enable "active time" tracking for the Auto-Minimize feature.
 
 WHY THIS MATTERS:
 Auto-minimize should only count time when the user is actively working,
 not when they're away (lunch, meeting, overnight). This prevents
 coming back to find all windows minimized.
 
 HOW IT WORKS:
 - Uses CGEvent to detect mouse/keyboard activity
 - Tracks "isUserActive" state (true if activity within threshold)
 - Provides "idle time" (seconds since last activity)
 - Notifies when user returns from extended idle (to reset timers)
 
 INTEGRATION:
 - Used by AutoMinimizeManager for active-time-only tracking
 - Posts notification when user returns from extended idle
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// ====================================================================
// MARK: - Active Usage Tracker
// ====================================================================

/**
 Tracks user activity to distinguish active use from idle time.
 
 USAGE:
 1. Check `isUserActive` to see if user is currently active
 2. Check `idleTime` to get seconds since last activity
 3. Observe `userReturnedFromIdle` notification for extended idle returns
 */
final class ActiveUsageTracker: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = ActiveUsageTracker()
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /// Whether the user is currently active (activity within last 30 seconds)
    @Published private(set) var isUserActive: Bool = true
    
    /// Seconds since last user activity
    @Published private(set) var idleTime: TimeInterval = 0
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Last detected activity timestamp
    private var lastActivityTime: Date = Date()
    
    /// Timer for checking idle state
    private var idleCheckTimer: Timer?
    
    /// Event tap for detecting mouse/keyboard
    private var eventTap: CFMachPort?
    
    /// Run loop source for event tap
    private var runLoopSource: CFRunLoopSource?
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    /// How long without activity before considered "idle"
    /// Default: 30 seconds of no mouse/keyboard = idle
    private let activeThreshold: TimeInterval = 30.0
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Settings manager reference
    private let settings = SettingsManager.shared
    
    /// DEBOUNCE FIX (Jan 26, 2026): Prevent rapid idle/active state toggling
    /// The event monitors fire on EVERY mouse movement, causing isUserActive
    /// to toggle dozens of times per second. This creates a feedback loop where:
    /// - WindowInactivityTracker publishes state changes
    /// - AppInactivityTracker publishes state changes
    /// - SwiftUI updates views
    /// - This blocks the main thread and causes "Fetch Current User Activity" deadline misses
    ///
    /// SOLUTION: Only publish state changes if:
    /// 1. At least 2 seconds have passed since last change
    /// 2. The state actually changed (not just flickering)
    private let minStateChangeInterval: TimeInterval = 2.0
    private var lastStateChangeTime: Date = Date()
    private var lastPublishedState: Bool = true
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupEventTap()
        startIdleCheckTimer()
        setupWakeFromSleepObserver()
        print("✓ ActiveUsageTracker initialized")
    }
    
    deinit {
        stopEventTap()
        idleCheckTimer?.invalidate()
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    /**
     Sets up a global event tap to detect mouse and keyboard events.
     
     NOTE: This requires Accessibility permissions. If not granted,
     we fall back to NSEvent global monitoring which is less reliable
     but doesn't require special permissions.
     */
    private func setupEventTap() {
        // First try global NSEvent monitors (no accessibility required)
        // These catch mouse movement and key presses
        setupGlobalEventMonitors()
        
        print("🎯 ActiveUsageTracker: Using NSEvent global monitors for activity detection")
    }
    
    /**
     Sets up NSEvent global monitors for activity detection.
     Works without Accessibility permissions.
     */
    private func setupGlobalEventMonitors() {
        // Monitor mouse movement and clicks
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            self?.recordActivity()
        }
        
        // Monitor key presses (won't catch all keys without Accessibility, but catches most)
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] _ in
            self?.recordActivity()
        }
        
        // Also monitor local events (within our app)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.recordActivity()
            return event
        }
    }
    
    /**
     Records that user activity was detected.
     Called by event monitors.
     */
    private func recordActivity() {
        lock.lock()
        lastActivityTime = Date()
        lock.unlock()
    }
    
    /**
     Starts a timer to periodically check idle state.
     Updates published properties and detects extended idle returns.
     */
    private func startIdleCheckTimer() {
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateIdleState()
        }
    }
    
    /**
     Sets up observer for wake from sleep events.
     We reset timers when waking from sleep since the user was away.
     */
    private func setupWakeFromSleepObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    @objc private func handleWakeFromSleep() {
        print("☀️ ActiveUsageTracker: Wake from sleep detected")
        
        // Reset the last activity time to now
        lock.lock()
        lastActivityTime = Date()
        lock.unlock()
    }
    
    // ================================================================
    // MARK: - Idle State Management
    // ================================================================
    
    /**
     Updates the idle state based on time since last activity.
     Called every second by the timer.
     */
    private func updateIdleState() {
        lock.lock()
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)
        lock.unlock()
        
        // Update published properties on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Always update idle time (this doesn't trigger SwiftUI updates)
            self.idleTime = timeSinceActivity
            
            // Calculate new active state
            let newActiveState = timeSinceActivity < self.activeThreshold
            
            // DEBOUNCE FIX (Jan 26, 2026): Only publish state change if:
            // 1. The state actually changed (not just flickering)
            // 2. Enough time has passed since last change (prevent rapid toggling)
            //
            // This prevents the rapid idle/active cycling that was causing:
            // - Main thread blocking
            // - "Fetch Current User Activity" deadline misses
            // - Hundreds of overlays being created/destroyed per minute
            let now = Date()
            let stateChanged = newActiveState != self.lastPublishedState
            let enoughTimePassed = now.timeIntervalSince(self.lastStateChangeTime) >= self.minStateChangeInterval
            
            if stateChanged && enoughTimePassed {
                // State changed and enough time passed - publish the change
                self.isUserActive = newActiveState
                self.lastPublishedState = newActiveState
                self.lastStateChangeTime = now
                
                // Log state changes for debugging
                print("🔄 ActiveUsageTracker: State changed to \(newActiveState ? "ACTIVE" : "IDLE")")
            }
        }
    }
    
    /**
     Stops the event tap when no longer needed.
     */
    private func stopEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Manually record activity (e.g., when app receives focus).
     */
    func recordManualActivity() {
        recordActivity()
    }
    
    /**
     Gets whether the user is currently active.
     Thread-safe accessor.
     */
    func getIsUserActive() -> Bool {
        lock.lock()
        let active = Date().timeIntervalSince(lastActivityTime) < activeThreshold
        lock.unlock()
        return active
    }
    
    /**
     Gets seconds since last user activity.
     Thread-safe accessor.
     */
    func getIdleTime() -> TimeInterval {
        lock.lock()
        let idle = Date().timeIntervalSince(lastActivityTime)
        lock.unlock()
        return idle
    }
}

