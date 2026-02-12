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
//  REORDER DETECTION (Feb 11, 2026):
//  - Also monitors the ORDER of Space UUIDs in the plist array
//  - When user drags a Space in Mission Control to reorder, the plist array order changes
//  - ManagedSpaceID and UUID are STABLE - they do NOT change on reorder
//  - Only the array position changes (confirmed empirically with test-space-reorder-ids.swift)
//  - We detect this by comparing the UUID order snapshot on each poll
//  - When reorder is detected, we fire a separate reorderCallbacks notification
//  - This allows the HUD and settings to refresh their display while keeping data
//    correctly associated with the right Space via UUID
//
//  PERFORMANCE:
//  - Notification-based: Instant, no CPU overhead
//  - Polling: 0.5s interval, ~0.1% CPU (only when polling is active)
//  - SpaceDetector.getCurrentSpace(): ~2-4ms per call
//  - Reorder check adds ~1ms (array comparison)
//  - Total impact: Negligible
//
//  USAGE:
//  ```swift
//  let monitor = SpaceChangeMonitor()
//  monitor.addObserver { spaceNumber in
//      print("Switched to Space \(spaceNumber)")
//      updateUI(for: spaceNumber)
//  }
//  monitor.addReorderObserver {
//      print("Spaces were reordered in Mission Control!")
//      refreshSpaceList()
//  }
//  ```
//
//  PRODUCT CONTEXT:
//  This powers the Super Spaces HUD auto-update feature.
//  When users switch Spaces, the HUD immediately highlights the new current Space.
//  When users reorder Spaces in Mission Control, the HUD refreshes to match.
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
/// REORDER DETECTION (Feb 11, 2026):
/// Added ability to detect when user reorders Spaces in Mission Control.
/// ManagedSpaceID and UUID are stable identifiers that don't change on reorder -
/// only the plist array order changes. We track the UUID order and fire separate
/// reorder callbacks when it changes. This was confirmed empirically by capturing
/// all Space identifiers before and after a drag-reorder in Mission Control.
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
    
    /// Callbacks invoked when Space changes (user switches to a different Space)
    /// Changed from single callback to array to support multiple observers
    /// Each callback receives the new Space number (1-based)
    private var spaceChangeCallbacks: [(Int) -> Void] = []
    
    /// Callbacks invoked when Spaces are reordered in Mission Control
    /// FEATURE (Feb 11, 2026): Reorder detection
    /// When the user drags Spaces to rearrange them in Mission Control, we detect
    /// the change in the plist array order and fire these callbacks so the HUD
    /// and settings can update their display to match the new order.
    /// The callbacks receive no parameters because the consumers should re-read
    /// the full Space list from SpaceDetector to get the updated order.
    private var reorderCallbacks: [() -> Void] = []
    
    /// Timer for polling Space changes (fallback mechanism)
    /// Used in addition to NSWorkspace notifications for reliability
    private var pollingTimer: Timer?
    
    /// Last known Space number
    /// Used to detect actual changes and prevent duplicate notifications
    private var lastKnownSpace: Int?
    
    /// Last known order of Space UUIDs (from plist array order)
    /// FEATURE (Feb 11, 2026): Reorder detection
    /// We track the UUID sequence from SpaceDetector.getAllSpaces() and compare
    /// on each poll. If the UUID sequence changes but the set of UUIDs is the same,
    /// it means the user reordered Spaces in Mission Control.
    /// UUIDs are stable identifiers - they survive reordering (confirmed empirically).
    private var lastKnownSpaceUUIDOrder: [String] = []
    
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
    
    /// Adds an observer for Space changes (active space switched)
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
    
    /// Adds an observer for Space reorder events (user dragged Spaces in Mission Control)
    ///
    /// FEATURE (Feb 11, 2026): Reorder detection
    /// When the user drags a Space to reorder it in Mission Control, the plist file
    /// updates the array order. ManagedSpaceID and UUID are STABLE and don't change -
    /// only their position in the array changes.
    ///
    /// This was confirmed empirically: we ran test-space-reorder-ids.swift which captures
    /// all identifiers (ManagedSpaceID, UUID, id64, array index) before and after a
    /// drag-reorder. Result: UUIDs and ManagedSpaceIDs stayed the same, only array
    /// positions changed.
    ///
    /// WHY SEPARATE CALLBACK:
    /// - Space switch and reorder are different events that need different handling
    /// - On space switch: update current highlight, record visit
    /// - On reorder: refresh the entire space list, remap display positions
    /// - Reorder doesn't change which space is active, just the ordering
    ///
    /// USAGE:
    /// ```swift
    /// SpaceChangeMonitor.shared.addReorderObserver {
    ///     // Spaces were reordered in Mission Control
    ///     refreshSpaceList()
    /// }
    /// ```
    ///
    /// - Parameter callback: Callback invoked (no params) when reorder detected
    func addReorderObserver(_ callback: @escaping () -> Void) {
        // Add callback to list
        reorderCallbacks.append(callback)
        
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
        
        // Get initial Space and UUID order
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            lastKnownSpace = currentSpace.spaceNumber
            print("✓ SpaceChangeMonitor: Initial Space: \(currentSpace.spaceNumber)")
        }
        
        // Capture initial UUID order for reorder detection
        // FEATURE (Feb 11, 2026): Store the initial sequence of Space UUIDs
        // so we can detect when Mission Control reorders them
        let allSpaces = SpaceDetector.getAllSpaces()
        lastKnownSpaceUUIDOrder = allSpaces.map { $0.uuid }
        print("✓ SpaceChangeMonitor: Initial UUID order: \(lastKnownSpaceUUIDOrder.map { String($0.prefix(8)) })")
        
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
        // Also used for reorder detection since there is no notification for reorders
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
        
        print("✓ SpaceChangeMonitor: Started monitoring (with reorder detection)")
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
    
    /// Checks if Space has changed and/or if Spaces were reordered, and notifies accordingly
    ///
    /// CHANGE DETECTION:
    /// 1. Query SpaceDetector for current Space
    /// 2. Compare with lastKnownSpace for active space change
    /// 3. Compare UUID order with lastKnownSpaceUUIDOrder for reorder detection
    /// 4. Notify appropriate callbacks
    ///
    /// REORDER DETECTION (Feb 11, 2026):
    /// In addition to detecting active space changes, we also detect when the user
    /// rearranges Spaces in Mission Control. This is done by comparing the current
    /// UUID order (from getAllSpaces()) with the cached lastKnownSpaceUUIDOrder.
    /// If the order changed but the set of UUIDs is the same, it's a reorder event.
    /// If UUIDs were added or removed, it means spaces were created/deleted.
    ///
    /// WHY WE CHECK REORDER ON EVERY POLL:
    /// - There is NO macOS notification for Space reorder events
    /// - The plist updates asynchronously after a Mission Control drag
    /// - Polling every 0.5s catches reorders within ~1s of them happening
    /// - The UUID comparison is O(n) where n = number of spaces (typically < 10)
    ///
    /// CALLED BY:
    /// - handleWorkspaceSpaceChange (after debounce)
    /// - pollingTimer (every 0.5s)
    ///
    /// PERFORMANCE:
    /// - SpaceDetector.getCurrentSpace(): ~2-4ms
    /// - SpaceDetector.getAllSpaces(): ~3-5ms (only called when checking reorder)
    /// - UUID array comparison: negligible
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
        
        // Check if Space actually changed (active space switch)
        if currentSpaceNumber != lastKnownSpace {
            print("✓ SpaceChangeMonitor: Space changed: \(lastKnownSpace ?? 0) -> \(currentSpaceNumber)")
            
            // Update cache
            lastKnownSpace = currentSpaceNumber
            
            // Notify all space-change observers
            notifyObservers(newSpace: currentSpaceNumber)
        }
        
        // FEATURE (Feb 11, 2026): Check for Space reorder
        // Read the current UUID order and compare with cached order
        // This detects when the user drags Spaces to reorder in Mission Control
        checkForSpaceReorder()
    }
    
    /// Checks if Spaces were reordered in Mission Control and notifies observers if so
    ///
    /// FEATURE (Feb 11, 2026): Reorder detection
    ///
    /// HOW IT WORKS:
    /// 1. Read current Space list from SpaceDetector.getAllSpaces()
    /// 2. Extract UUID order
    /// 3. Compare with lastKnownSpaceUUIDOrder
    /// 4. If different:
    ///    a. If same set of UUIDs → reorder event (drag in Mission Control)
    ///    b. If different set → space added/removed event
    ///    c. Either way, fire reorder callbacks so HUD refreshes
    /// 5. Update cached order
    ///
    /// EMPIRICAL EVIDENCE (Feb 11, 2026):
    /// We verified with test-space-reorder-ids.swift that:
    /// - ManagedSpaceID is STABLE across reorders (doesn't change)
    /// - UUID is STABLE across reorders (doesn't change)
    /// - id64 is STABLE across reorders (always equals ManagedSpaceID)
    /// - Only the plist array position changes
    /// This means UUID is a reliable key for associating data with Spaces.
    private func checkForSpaceReorder() {
        let currentSpaces = SpaceDetector.getAllSpaces()
        let currentUUIDOrder = currentSpaces.map { $0.uuid }
        
        // Only check if we have a previous snapshot to compare against
        guard !lastKnownSpaceUUIDOrder.isEmpty else {
            lastKnownSpaceUUIDOrder = currentUUIDOrder
            return
        }
        
        // Compare UUID orders
        if currentUUIDOrder != lastKnownSpaceUUIDOrder {
            // Something changed! Determine what kind of change
            let oldSet = Set(lastKnownSpaceUUIDOrder)
            let newSet = Set(currentUUIDOrder)
            
            if oldSet == newSet {
                // Same UUIDs, different order → user reordered Spaces in Mission Control
                print("✓ SpaceChangeMonitor: Spaces REORDERED in Mission Control!")
                print("  Before: \(lastKnownSpaceUUIDOrder.map { String($0.prefix(8)) })")
                print("  After:  \(currentUUIDOrder.map { String($0.prefix(8)) })")
            } else {
                // Different UUIDs → Spaces were added or removed
                let added = newSet.subtracting(oldSet)
                let removed = oldSet.subtracting(newSet)
                if !added.isEmpty {
                    print("✓ SpaceChangeMonitor: Spaces ADDED: \(added.map { String($0.prefix(8)) })")
                }
                if !removed.isEmpty {
                    print("✓ SpaceChangeMonitor: Spaces REMOVED: \(removed.map { String($0.prefix(8)) })")
                }
            }
            
            // Update cached order
            lastKnownSpaceUUIDOrder = currentUUIDOrder
            
            // Notify all reorder observers
            // Both reorder and add/remove events trigger this since the HUD
            // needs to refresh its Space list in either case
            notifyReorderObservers()
        }
    }
    
    /// Notifies all registered observers of a space change (active space switch)
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
    
    /// Notifies all registered reorder observers that Spaces were reordered
    ///
    /// FEATURE (Feb 11, 2026): Reorder detection
    /// Called when we detect that the UUID order in the plist has changed.
    /// This can happen when the user:
    /// 1. Drags a Space to reorder in Mission Control
    /// 2. Creates a new Space
    /// 3. Deletes a Space
    ///
    /// Observers should re-read the Space list from SpaceDetector to get
    /// the updated order and refresh their UI accordingly.
    private func notifyReorderObservers() {
        for callback in reorderCallbacks {
            callback()
        }
    }
}
