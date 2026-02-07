//
//  SpaceChangeMonitor.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Monitors for changes in the active macOS desktop Space and notifies observers.
//  Enables real-time updates to the Super Spaces HUD when users switch between Spaces.
//
//  WHY THIS APPROACH:
//  - NSWorkspace.activeSpaceDidChangeNotification exists but doesn't provide Space details
//  - We combine NSWorkspace notification with SpaceDetector plist reading
//  - Polling as fallback ensures we catch changes even if notification is missed
//  - Hybrid approach provides both responsiveness and reliability
//
//  TECHNICAL DETAILS:
//  - Primary: NSWorkspace.activeSpaceDidChangeNotification for immediate detection
//  - Secondary: Timer-based polling every 0.5s as fallback
//  - Debouncing to prevent duplicate notifications during Space transitions
//  - Caches last known Space to detect actual changes
//
//  PERFORMANCE:
//  - Notification-based: Instant, no CPU overhead
//  - Polling: 0.5s interval, ~0.1% CPU (only when polling is active)
//  - SpaceDetector.getCurrentSpace(): ~2-4ms per call
//  - Total impact: Negligible
//
//  USAGE:
//  ```swift
//  let monitor = SpaceChangeMonitor()
//  monitor.startMonitoring { spaceNumber in
//      print("Switched to Space \(spaceNumber)")
//      updateUI(for: spaceNumber)
//  }
//  ```
//
//  PRODUCT CONTEXT:
//  This powers the Super Spaces HUD auto-update feature.
//  When users switch Spaces, the HUD immediately highlights the new current Space.
//  No manual refresh needed - it "just works".
//

import Foundation
import AppKit
import os.log

/// Monitors for changes in the active macOS desktop Space
/// and notifies observers when the user switches between Spaces.
///
/// SINGLETON FIX (Jan 26, 2026):
/// Changed to singleton pattern to prevent multiple instances from creating notification storms.
/// Previously, DimmingCoordinator, AppInactivityTracker, and SuperSpacesHUD each created
/// their own monitor, resulting in 3x the notifications and 55% CPU usage during space changes.
///
/// Now only ONE monitor exists, but multiple observers can register callbacks.
final class SpaceChangeMonitor {
    
    // MARK: - Singleton
    
    /// Shared instance
    /// Only one monitor should exist to prevent notification storms
    static let shared = SpaceChangeMonitor()
    
    /// Private initializer to enforce singleton pattern
    private init() {}
    
    // MARK: - Properties
    
    /// Callbacks invoked when Space changes
    /// Changed from single callback to array to support multiple observers
    /// Each callback receives the new Space number (1-based)
    private var spaceChangeCallbacks: [(Int) -> Void] = []
    
    /// Timer for polling Space changes (fallback mechanism)
    /// Used in addition to NSWorkspace notifications for reliability
    private var pollingTimer: Timer?
    
    /// Last known Space number
    /// Used to detect actual changes and prevent duplicate notifications
    private var lastKnownSpace: Int?
    
    /// Debounce timer to prevent rapid-fire notifications during transitions
    /// macOS Space transitions can trigger multiple events
    private var debounceTimer: Timer?
    
    /// Debounce interval in seconds
    /// Prevents multiple notifications during the ~300ms Space transition animation
    private let debounceInterval: TimeInterval = 0.3
    
    /// Whether monitoring is currently active
    private var isMonitoring: Bool = false
    
    // MARK: - Lifecycle
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Adds an observer for Space changes
    ///
    /// SINGLETON PATTERN (Jan 26, 2026):
    /// Multiple observers can register, but only one monitor runs.
    /// This prevents notification storms from multiple instances.
    ///
    /// MONITORING STRATEGY:
    /// 1. Register for NSWorkspace.activeSpaceDidChangeNotification
    ///    - Provides immediate notification when Space changes
    ///    - No Space details provided, so we query SpaceDetector
    /// 2. Start polling timer as fallback
    ///    - Catches changes if notification is missed
    ///    - 0.5s interval balances responsiveness and efficiency
    /// 3. Debounce notifications
    ///    - Prevents duplicate calls during Space transition animation
    ///
    /// PERFORMANCE:
    /// - Notification: Instant, no overhead
    /// - Polling: 0.5s interval, ~0.1% CPU
    /// - Debouncing: Prevents wasted work during transitions
    ///
    /// - Parameter callback: Callback invoked with new Space number when change detected
    func addObserver(_ callback: @escaping (Int) -> Void) {
        // Add callback to list
        spaceChangeCallbacks.append(callback)
        
        // Start monitoring if not already started
        if !isMonitoring {
            startMonitoringInternal()
        }
    }
    
    /// Internal method to start monitoring (called once)
    private func startMonitoringInternal() {
        guard !isMonitoring else {
            print("⚠️ SpaceChangeMonitor: Already monitoring")
            return
        }
        
        self.isMonitoring = true
        
        // Get initial Space
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            lastKnownSpace = currentSpace.spaceNumber
            print("✓ SpaceChangeMonitor: Initial Space: \(currentSpace.spaceNumber)")
        }
        
        // Register for NSWorkspace Space change notifications
        // This provides immediate notification but no Space details
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Start polling timer as fallback
        // Catches changes if notification is missed or delayed
        // CRITICAL: Timer must be on main thread's RunLoop to fire
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.pollingTimer = Timer.scheduledTimer(
                withTimeInterval: 0.5,
                repeats: true
            ) { [weak self] _ in
                self?.checkForSpaceChange()
            }
            
            // Ensure timer is added to RunLoop
            if let timer = self.pollingTimer {
                RunLoop.main.add(timer, forMode: .common)
                print("✓ SpaceChangeMonitor: Polling timer scheduled on main RunLoop")
            }
        }
        
        print("✓ SpaceChangeMonitor: Started monitoring")
    }
    
    /// Stops monitoring for Space changes
    ///
    /// Cleans up all observers and timers.
    /// Safe to call multiple times.
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Remove notification observer
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Stop polling timer
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        // Stop debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil
        
        isMonitoring = false
        print("✓ SpaceChangeMonitor: Stopped monitoring")
    }
    
    // MARK: - Private Methods
    
    /// Handles NSWorkspace Space change notification
    ///
    /// TECHNICAL NOTES:
    /// - NSWorkspace.activeSpaceDidChangeNotification fires when Space changes
    /// - Notification contains no Space information (just that a change occurred)
    /// - We query SpaceDetector to get actual Space number
    /// - Debouncing prevents multiple calls during transition animation
    ///
    /// WHY DEBOUNCING:
    /// - macOS Space transitions take ~300ms
    /// - Multiple notifications can fire during transition
    /// - Debouncing ensures we only notify once per actual change
    ///
    /// @objc required for #selector
    @objc private func handleWorkspaceSpaceChange(_ notification: Notification) {
        // Debounce to prevent rapid-fire notifications
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(
            withTimeInterval: debounceInterval,
            repeats: false
        ) { [weak self] _ in
            self?.checkForSpaceChange()
        }
    }
    
    /// Checks if Space has changed and notifies if so
    ///
    /// CHANGE DETECTION:
    /// 1. Query SpaceDetector for current Space
    /// 2. Compare with lastKnownSpace
    /// 3. If different, update cache and notify
    /// 4. If same, do nothing (prevents duplicate notifications)
    ///
    /// CALLED BY:
    /// - handleWorkspaceSpaceChange (after debounce)
    /// - pollingTimer (every 0.5s)
    ///
    /// PERFORMANCE:
    /// - SpaceDetector.getCurrentSpace(): ~2-4ms
    /// - Comparison: Negligible
    /// - Callback: Depends on observer implementation
    ///
    /// ERROR HANDLING:
    /// - If SpaceDetector fails, we don't notify (prevents false positives)
    /// - Logs warning for debugging
    private func checkForSpaceChange() {
        guard let currentSpace = SpaceDetector.getCurrentSpace() else {
            // FIX (Feb 5, 2026): Removed print() here - this fires every 0.5s
            // when polling is active and was contributing to logging quarantine.
            // Only log at debug level which is stripped in release builds.
            #if DEBUG
            // Use os_log directly instead of AppLogger to avoid project dependency issues
            os_log(.debug, "SpaceChangeMonitor: Failed to get current Space")
            #endif
            return
        }
        
        let currentSpaceNumber = currentSpace.spaceNumber
        
        // Check if Space actually changed
        if currentSpaceNumber != lastKnownSpace {
            print("✓ SpaceChangeMonitor: Space changed: \(lastKnownSpace ?? 0) -> \(currentSpaceNumber)")
            
            // Update cache
            lastKnownSpace = currentSpaceNumber
            
            // Notify all observers
            notifyObservers(newSpace: currentSpaceNumber)
        }
    }
    
    /// Notifies all registered observers of a space change
    ///
    /// SINGLETON PATTERN (Jan 26, 2026):
    /// Calls all registered callbacks with the new space number.
    /// This allows multiple components to react to space changes
    /// without creating multiple monitor instances.
    ///
    /// - Parameter newSpace: The new space number
    private func notifyObservers(newSpace: Int) {
        for callback in spaceChangeCallbacks {
            callback(newSpace)
        }
    }
}
