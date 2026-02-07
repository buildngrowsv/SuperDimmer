/**
 ====================================================================
 OverlayManager.swift
 Manages lifecycle of all dim overlay windows
 ====================================================================
 
 PURPOSE:
 This class manages the creation, updating, and removal of all
 DimOverlayWindow instances. It acts as a single point of control
 for the overlay system, preventing:
 - Orphaned overlays (windows without owners)
 - Duplicate overlays for the same target
 - Memory leaks from unclosed windows
 
 RESPONSIBILITIES:
 1. Create overlays for detected bright regions or windows
 2. Update overlay positions as windows move
 3. Update overlay dim levels as settings change
 4. Remove overlays when no longer needed
 5. Handle display configuration changes
 
 MODES OF OPERATION:
 - Full-screen mode: One overlay per display (simple mode)
 - Per-window mode: One overlay per bright window (intelligent mode)
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import AppKit
import Combine
import os.log

// ====================================================================
// MARK: - Overlay Manager
// ====================================================================

/**
 Singleton that manages all dim overlay windows in the application.
 
 USAGE:
 - Access via OverlayManager.shared
 - Call methods to create/update/remove overlays
 - The manager handles lifecycle and cleanup
 
 THREADING:
 All UI operations are dispatched to main thread internally.
 Safe to call from any thread.
 */
/// FIX (Feb 5, 2026): Private logger for overlay operations.
/// Using os.log instead of print() to avoid the logging quarantine that was causing
/// macOS to completely stop recording SuperDimmer's diagnostic logs.
/// AppLogger.swift isn't in the Xcode project file, so we create a local Logger here.
private let overlayLogger = Logger(subsystem: "com.superdimmer.app", category: "overlay")

final class OverlayManager {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /**
     Shared singleton instance.
     
     WHY SINGLETON:
     There should only be one source of truth for overlay management.
     Multiple managers would create conflicting overlays.
     */
    static let shared = OverlayManager()
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     Overlays keyed by window ID (for per-window mode).
     
     Maps CGWindowID → DimOverlayWindow so we can update/remove
     overlays when the target window changes.
     */
    private var windowOverlays: [CGWindowID: DimOverlayWindow] = [:]
    
    /**
     Overlays keyed by display ID (for full-screen mode).
     
     Maps CGDirectDisplayID → DimOverlayWindow for full-screen dimming.
     One overlay covers the entire display.
     */
    private var displayOverlays: [CGDirectDisplayID: DimOverlayWindow] = [:]
    
    /**
     Overlays for inactivity decay dimming (full-window overlays).
     
     Maps CGWindowID → DimOverlayWindow for decay-based dimming.
     These cover the entire window and progressively dim based on inactivity.
     Separate from regionOverlays to avoid conflicts.
     */
    private var decayOverlays: [CGWindowID: DimOverlayWindow] = [:]
    
    /**
     Whether the overlay system is currently active.
     
     When false, all overlays are hidden but not destroyed.
     Allows quick enable/disable without recreation overhead.
     */
    private(set) var isActive: Bool = false
    
    /**
     Combine subscriptions for settings observation.
     */
    private var cancellables = Set<AnyCancellable>()
    
    /**
     THREAD SAFETY LOCK (Jan 9, 2026)
     
     FIX: The EXC_BAD_ACCESS crash was caused by race conditions where
     multiple threads accessed overlay dictionaries simultaneously.
     
     Critical sections that need protection:
     - Adding/removing from decayOverlays, regionOverlays, windowOverlays
     - Reading overlay dictionaries during iteration
     - The hiddenOverlays pool
     
     Using NSRecursiveLock because some methods call others that also need the lock.
     */
    private let overlayLock = NSRecursiveLock()
    
    /**
     THROTTLE FIX (Jan 26, 2026): Prevent too-frequent applyDecayDimming calls
     
     With rapid idle/active cycling, applyDecayDimming was being called dozens
     of times per second, creating and destroying overlays constantly. This:
     - Blocked the main thread
     - Caused window server strain
     - Led to "Fetch Current User Activity" deadline misses
     
     SOLUTION: Throttle to max once per 500ms. Decay dimming is gradual anyway,
     so this doesn't affect user experience but prevents the feedback loop.
     */
    private var lastDecayApplyTime: CFAbsoluteTime = 0
    private let minDecayApplyInterval: CFAbsoluteTime = 0.5  // 500ms minimum
    
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Whether overlays are temporarily hidden due to Mission Control / Spaces.
     We hide overlays during Space transitions to avoid visual glitches.
     */
    private var isHiddenForSpaceChange: Bool = false
    
    /**
     Private initializer enforces singleton pattern.
     Sets up observers for settings and display changes.
     
     MEMORY LEAK FIX (Jan 20, 2026): Now also starts periodic cleanup timer
     to prevent hiddenOverlays pool from growing indefinitely.
     */
    private init() {
        setupDisplayChangeObserver()
        setupSettingsObservers()
        setupSpaceChangeObserver()
        // NOTE: startCleanupTimer() was removed - cleanup is now handled differently
        print("✓ OverlayManager initialized")
    }
    
    /**
     Sets up observer for Space changes (Mission Control, Space switching).
     
     MISSION CONTROL HANDLING:
     There's no official API to detect Mission Control activation.
     However, we can detect Space changes which occur when:
     - User switches Spaces via swipe or keyboard
     - User exits Mission Control to a different Space
     - User uses App Exposé
     
     WORKAROUND:
     When a Space change is detected, we hide overlays briefly,
     then show them again. This prevents visual glitches during
     the transition animation.
     */
    private func setupSpaceChangeObserver() {
        // Observe Space changes
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Also observe when we switch TO full screen apps
        // This helps with Mission Control edge cases
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        
        print("✓ OverlayManager: Space change observer configured")
    }
    
    @objc private func handleSpaceChange(_ notification: Notification) {
        // Hide overlays during Space transition
        hideOverlaysForSpaceChange()
        
        // Restore after a brief delay to let animation complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restoreOverlaysAfterSpaceChange()
        }
    }
    
    @objc private func handleWindowDidChangeScreen(_ notification: Notification) {
        // A window moved screens - might be exiting Mission Control
        // Brief hide and restore to sync state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.restoreOverlaysAfterSpaceChange()
        }
    }
    
    /**
     Temporarily hides all overlays during Space/Mission Control transitions.
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions
     with other methods that access overlay dictionaries.
     */
    private func hideOverlaysForSpaceChange() {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        guard !isHiddenForSpaceChange else { return }
        
        isHiddenForSpaceChange = true
        
        // Hide all overlay types - iterate over copies to be extra safe
        for (_, overlay) in windowOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in displayOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in regionOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in decayOverlays {
            overlay.orderOut(nil)
        }
        
        print("🌀 OverlayManager: Overlays hidden for Space change")
    }
    
    /**
     Restores overlays after Space/Mission Control transition completes.
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions
     with other methods that access overlay dictionaries.
     */
    private func restoreOverlaysAfterSpaceChange() {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        guard isHiddenForSpaceChange else { return }
        
        isHiddenForSpaceChange = false
        
        // Only restore if we were active before
        guard isActive else { return }
        
        // Restore all overlay types
        for (_, overlay) in windowOverlays {
            overlay.orderFront(nil)
        }
        for (_, overlay) in displayOverlays {
            overlay.orderFront(nil)
        }
        for (_, overlay) in regionOverlays {
            overlay.orderFront(nil)
        }
        for (_, overlay) in decayOverlays {
            overlay.orderFront(nil)
        }
        
        print("🌀 OverlayManager: Overlays restored after Space change")
    }
    
    // ================================================================
    // MARK: - Full-Screen Mode
    // ================================================================
    
    /**
     Creates a full-screen dim overlay for a specific display.
     
     - Parameters:
       - displayID: The display to cover
       - dimLevel: Initial dim level (0.0-1.0)
     
     Use this for simple full-screen dimming (not intelligent per-window).
     If an overlay already exists for this display, it's updated instead.
     */
    func createFullScreenOverlay(for displayID: CGDirectDisplayID, dimLevel: CGFloat) {
        print("📺 createFullScreenOverlay for displayID: \(displayID), dimLevel: \(dimLevel)")
        
        // Find the NSScreen for this display
        guard let screen = screenForDisplay(displayID) else {
            print("⚠️ No screen found for display \(displayID)")
            return
        }
        
        // Check for existing overlay
        if let existing = displayOverlays[displayID] {
            // Update existing overlay's dim level
            print("📺 Updating existing overlay dim level to \(dimLevel)")
            existing.setDimLevel(dimLevel, animated: true)
            return
        }
        
        // Create new full-screen overlay using factory method
        // FIX (Jan 8, 2026): Start at 0 opacity and FADE IN to target level
        // This prevents the jarring "pop-in" effect when full-screen dimming is enabled
        print("📺 Creating NEW full-screen overlay for \(screen.localizedName)")
        print("📺 Screen frame: \(screen.frame)")
        let overlay = DimOverlayWindow.create(
            frame: screen.frame,
            dimLevel: 0.0,  // Start invisible
            id: "display-\(displayID)"
        )
        
        // Make sure the overlay is visible
        // Note: Don't use makeKeyAndOrderFront because canBecomeKey returns false
        overlay.orderFrontRegardless()  // Force to front
        
        // Store reference
        displayOverlays[displayID] = overlay
        
        // Fade in to target dim level with smooth animation
        overlay.setDimLevel(dimLevel, animated: true, duration: 0.4)
        
        print("📺 ✓ Created full-screen overlay for display \(displayID) with fade-in")
        print("📺   Overlay frame: \(overlay.frame)")
        print("📺   Overlay isVisible: \(overlay.isVisible)")
        print("📺   Overlay level: \(overlay.level.rawValue)")
    }
    
    /**
     Removes the full-screen overlay for a specific display.
     
     - Parameter displayID: The display whose overlay should be removed
     */
    func removeFullScreenOverlay(for displayID: CGDirectDisplayID) {
        guard let overlay = displayOverlays.removeValue(forKey: displayID) else {
            return
        }
        
        overlay.fadeOutAndClose()
        print("📺 Removed full-screen overlay for display \(displayID)")
    }
    
    /**
     Creates full-screen overlays for all connected displays.
     
     - Parameter dimLevel: The dim level to apply
     
     Convenience method for enabling simple full-screen dimming mode.
     */
    func enableFullScreenDimming(dimLevel: CGFloat) {
        print("📺 enableFullScreenDimming called with dimLevel: \(dimLevel)")
        print("📺 Found \(NSScreen.screens.count) screen(s)")
        
        for screen in NSScreen.screens {
            print("📺 Screen: \(screen.localizedName), frame: \(screen.frame)")
            if let displayID = screen.displayID {
                createFullScreenOverlay(for: displayID, dimLevel: dimLevel)
            } else {
                print("⚠️ Could not get displayID for screen: \(screen.localizedName)")
            }
        }
        isActive = true
        print("📺 Full-screen dimming enabled on \(displayOverlays.count) display(s)")
    }
    
    /**
     Removes full-screen overlays from all displays.
     */
    func disableFullScreenDimming() {
        for displayID in displayOverlays.keys {
            removeFullScreenOverlay(for: displayID)
        }
        isActive = false
        print("📺 Full-screen dimming disabled")
    }
    
    // ================================================================
    // MARK: - Per-Window Mode
    // ================================================================
    
    /**
     Creates or updates an overlay for a specific window.
     
     - Parameters:
       - windowID: The target window's ID
       - bounds: The window's frame in screen coordinates
       - dimLevel: The dim level to apply
       - screen: The screen the window is on (optional)
     
     Use this for intelligent per-window dimming. The overlay tracks
     the window's position and can have a different dim level than
     other windows.
     */
    func updateOverlay(for windowID: CGWindowID, bounds: CGRect, dimLevel: CGFloat, screen: NSScreen? = nil) {
        if let existing = windowOverlays[windowID] {
            // Update existing overlay with smooth animation
            // FIX (Jan 8, 2026): Increased duration from 0.15s to 0.35s for smoother
            // active/inactive transitions when switching between windows
            existing.updatePosition(to: bounds)
            existing.setDimLevel(dimLevel, animated: true, duration: 0.35)
        } else {
            // Create new overlay using factory method
            // FIX (Jan 8, 2026): Start at 0 opacity and FADE IN to target level
            // This prevents the jarring "pop-in" effect when new overlays appear
            let overlay = DimOverlayWindow.create(
                frame: bounds,
                dimLevel: 0.0,  // Start invisible
                id: "window-\(windowID)"
            )
            overlay.orderFrontRegardless()
            windowOverlays[windowID] = overlay
            
            // Fade in to target dim level with smooth animation
            overlay.setDimLevel(dimLevel, animated: true, duration: 0.3)
            print("🪟 Created overlay for window \(windowID) with fade-in")
        }
    }
    
    /**
     Removes the overlay for a specific window.
     
     - Parameter windowID: The window whose overlay should be removed
     
     Called when:
     - Window is closed
     - Window becomes dark (below threshold)
     - App rule says never dim this app
     */
    func removeOverlay(for windowID: CGWindowID) {
        guard let overlay = windowOverlays.removeValue(forKey: windowID) else {
            return
        }
        
        overlay.fadeOutAndClose()
        print("🪟 Removed overlay for window \(windowID)")
    }
    
    /**
     Batch update overlays based on dimming decisions.
     
     - Parameter decisions: Array of dimming decisions from coordinator
     
     This is the main entry point for the DimmingCoordinator.
     It processes all decisions and updates overlays accordingly.
     */
    func applyDimmingDecisions(_ decisions: [DimmingDecision]) {
        // Track which windows have current decisions
        var activeWindowIDs = Set<CGWindowID>()
        
        for decision in decisions {
            let windowID = decision.window.id
            activeWindowIDs.insert(windowID)
            
            if decision.shouldDim {
                updateOverlay(
                    for: windowID,
                    bounds: decision.window.bounds,
                    dimLevel: decision.dimLevel
                )
            } else {
                // Window doesn't need dimming - remove overlay if exists
                removeOverlay(for: windowID)
            }
        }
        
        // Remove overlays for windows no longer in decisions
        // (They might have closed or moved off-screen)
        let staleWindowIDs = Set(windowOverlays.keys).subtracting(activeWindowIDs)
        for windowID in staleWindowIDs {
            removeOverlay(for: windowID)
        }
    }
    
    // ================================================================
    // MARK: - Per-Region Mode
    // ================================================================
    
    /// Dictionary of region overlays, keyed by unique region ID
    private var regionOverlays: [String: DimOverlayWindow] = [:]
    
    /// Maps region overlay ID to target window ID (for proper Z-ordering)
    private var regionToWindowID: [String: CGWindowID] = [:]
    
    /// Maps region overlay ID to owner PID (for hybrid z-ordering)
    /// We use this to determine which overlays belong to the frontmost app
    private var regionToOwnerPID: [String: pid_t] = [:]
    
    /// Counter for generating unique region IDs
    private var regionCounter: Int = 0
    
    /// Tracks previous window bounds for position delta calculation (2.2.1.14)
    /// Maps CGWindowID → CGRect (last known window bounds).
    /// Updated during brightness analysis, used by updateOverlayPositions() to
    /// calculate how much a window has moved/resized since last analysis.
    private var previousWindowBounds: [CGWindowID: CGRect] = [:]
    
    /**
     Tracks the last known position of each window for detecting rapid movement.
     
     FIX (Jan 21, 2026): When a window is being actively dragged, we need to detect
     this and update overlays more frequently. We track the last position from the
     previous tracking cycle (not the analysis cycle) to detect continuous movement.
     
     Maps CGWindowID → CGRect (from last tracking cycle, not analysis cycle).
     */
    private var lastTrackedWindowBounds: [CGWindowID: CGRect] = [:]
    
    /**
     Tracks how many consecutive tracking cycles each window has been moving.
     
     FIX (Jan 21, 2026): Used to detect active window dragging. If a window moves
     for 2+ consecutive tracking cycles, we consider it "actively being dragged"
     and switch to high-frequency tracking.
     
     Maps CGWindowID → Int (consecutive movement count).
     */
    private var windowMovementStreak: [CGWindowID: Int] = [:]
    
    /**
     Stores the original overlay frame from the last analysis cycle.
     
     FIX (Jan 21, 2026): When tracking window movement, we need to know where
     the overlay was ORIGINALLY positioned (at analysis time) so we can calculate
     its correct new position relative to the moved window.
     
     Without this, we get overshooting because we're applying deltas to an already-moved overlay.
     
     Maps overlayID → CGRect (original frame from last analysis).
     */
    private var originalOverlayFrames: [String: CGRect] = [:]
    
    /// Current count of active region overlays (for UI status display)
    /// IMPORTANT: This is the ACTUAL count, not a cached analysis result
    var currentRegionOverlayCount: Int {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        return regionOverlays.count
    }
    
    /// Current count of all overlays (display + window + region + decay)
    var totalOverlayCount: Int {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        return displayOverlays.count + windowOverlays.count + regionOverlays.count + decayOverlays.count
    }
    
    // NOTE (Jan 10, 2026): overlaysBeingClosed was REMOVED.
    // We no longer close overlays at all - just hide them and keep them alive.
    // This prevents EXC_BAD_ACCESS crashes from NSWindow.close() triggering
    // AppKit internals that autorelease objects which then crash.
    
    /**
     Applies dimming overlays for specific bright regions within windows.
     
     This is the killer feature of SuperDimmer! Instead of dimming
     entire windows, this creates overlays for specific bright AREAS.
     
     Example: Dark mode Mail app with bright white email content
     - The window itself isn't entirely bright
     - We detect just the email content area and dim only that region
     
     FIX (Jan 9, 2026): COMPLETELY REWRITTEN to fix overlay "jumping" bug.
     
     PREVIOUS BUG: Overlays were matched by sequential INDEX, not by window.
     This caused overlays to "jump" between windows when analysis order changed.
     
     For example:
     - Window A has 2 regions, Window B has 2 regions
     - Analysis returns B first, then A (order changed due to z-order)
     - Old code would assign A's overlays to B's regions!
     
     NEW APPROACH: Match overlays BY WINDOW ID
     1. Group existing overlays by their target window ID
     2. Group incoming decisions by window ID
     3. For each window: update/create/remove only ITS overlays
     4. Overlays NEVER jump between windows
     
     - Parameter decisions: Array of region dimming decisions
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions.
     */
    func applyRegionDimmingDecisions(_ decisions: [RegionDimmingDecision]) {
        // THREAD SAFETY: Lock before any dictionary access
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        // FIX (Jan 9, 2026): Match overlays BY WINDOW, not by global index
        //
        // Step 1: Group existing overlays by their target window
        var existingByWindow: [CGWindowID: [(id: String, overlay: DimOverlayWindow)]] = [:]
        for (overlayID, overlay) in regionOverlays {
            if let windowID = regionToWindowID[overlayID] {
                if existingByWindow[windowID] == nil {
                    existingByWindow[windowID] = []
                }
                existingByWindow[windowID]?.append((id: overlayID, overlay: overlay))
            }
        }
        
        // Step 2: Group incoming decisions by window ID
        var decisionsByWindow: [CGWindowID: [RegionDimmingDecision]] = [:]
        for decision in decisions {
            if decisionsByWindow[decision.windowID] == nil {
                decisionsByWindow[decision.windowID] = []
            }
            decisionsByWindow[decision.windowID]?.append(decision)
        }
        
        // Step 2.5: Update window bounds tracking (2.2.1.14)
        // Store current window bounds so updateOverlayPositions() can calculate position deltas
        for decision in decisions {
            previousWindowBounds[decision.windowID] = decision.windowBounds
        }
        
        // Tolerance for frame comparison (pixels)
        let frameTolerance: CGFloat = 2.0
        
        // Step 3: For each window with existing overlays, update or remove
        for (windowID, existingOverlays) in existingByWindow {
            if let windowDecisions = decisionsByWindow[windowID] {
                // This window has both existing overlays AND new decisions
                // Match them up: reuse overlays, create new ones if needed, remove extras
                
                for (index, decision) in windowDecisions.enumerated() {
                    if index < existingOverlays.count {
                        // Reuse existing overlay for this window
                        let (overlayID, overlay) = existingOverlays[index]
                        updateExistingOverlay(overlay, overlayID: overlayID, decision: decision, frameTolerance: frameTolerance)
                    } else {
                        // Need more overlays for this window - create new one
                        createRegionOverlay(for: decision)
                    }
                }
                
                // CRITICAL FIX (Jan 9, 2026): DON'T destroy extra overlays!
                // Just hide them by setting dimLevel to 0.
                // Destroying overlays causes EXC_BAD_ACCESS crash.
                if existingOverlays.count > windowDecisions.count {
                    for i in windowDecisions.count..<existingOverlays.count {
                        let (_, overlay) = existingOverlays[i]
                        // Hide instead of destroy
                        overlay.setDimLevel(0.0, animated: true)
                        // Keep in dictionary - it's just invisible
                    }
                }
            } else {
                // This window had overlays but no longer has any decisions - HIDE all, don't destroy
                for (_, overlay) in existingOverlays {
                    overlay.setDimLevel(0.0, animated: true)
                    // Keep in dictionary - it's just invisible
                }
            }
        }
        
        // Step 4: Create overlays for windows that are NEW (had no existing overlays)
        for (windowID, windowDecisions) in decisionsByWindow {
            if existingByWindow[windowID] == nil {
                // Brand new window - create all overlays
                for decision in windowDecisions {
                    createRegionOverlay(for: decision)
                }
            }
        }
    }
    
    /**
     Updates an existing overlay with new decision data.
     
     FIX (Jan 9, 2026): Extracted from applyRegionDimmingDecisions for clarity.
     Only updates position/z-order if actually changed to prevent flashing.
     
     - Parameters:
       - overlay: The existing overlay to update
       - overlayID: The overlay's ID in our dictionary
       - decision: The new dimming decision
       - frameTolerance: Minimum change in pixels to trigger frame update
     */
    private func updateExistingOverlay(
        _ overlay: DimOverlayWindow,
        overlayID: String,
        decision: RegionDimmingDecision,
        frameTolerance: CGFloat
    ) {
        let currentFrame = overlay.frame
        let newFrame = decision.regionRect
        
        // Check if frame has meaningfully changed
        let frameChanged = abs(currentFrame.origin.x - newFrame.origin.x) > frameTolerance ||
                           abs(currentFrame.origin.y - newFrame.origin.y) > frameTolerance ||
                           abs(currentFrame.width - newFrame.width) > frameTolerance ||
                           abs(currentFrame.height - newFrame.height) > frameTolerance
        
        // Only update frame if it actually changed
        if frameChanged {
            overlay.updatePosition(to: newFrame, animated: true, duration: 0.3)
            // FIX (Jan 21, 2026): Update original frame when analysis changes it
            originalOverlayFrames[overlayID] = newFrame
        }
        
        // HYBRID Z-ORDERING: Use .floating ONLY for the actual frontmost window
        let targetLevel: NSWindow.Level = decision.isFrontmostWindow ? .floating : .normal
        
        if overlay.level != targetLevel {
            overlay.level = targetLevel
            if decision.isFrontmostWindow {
                overlay.orderFront(nil)
            } else {
                overlay.orderAboveWindow(decision.windowID)
            }
        }
        
        // Update mappings (in case they changed, though they shouldn't for same window)
        regionToWindowID[overlayID] = decision.windowID
        regionToOwnerPID[overlayID] = decision.ownerPID
        
        // Always update dim level with smooth animation
        overlay.setDimLevel(decision.dimLevel, animated: true, duration: 0.35)
        
        // Make sure it's visible
        if !overlay.isVisible {
            if decision.isFrontmostWindow {
                overlay.orderFront(nil)
            } else {
                overlay.orderAboveWindow(decision.windowID)
            }
        }
    }
    
    /**
     Creates an overlay for a specific bright region.
     
     HYBRID Z-ORDERING (Jan 8, 2026):
     - isFrontmostWindow=true: Use .floating level (no flash when clicking)
     - isFrontmostWindow=false: Use .normal level with relative positioning
     
     FIX (Jan 8, 2026): Changed from isFrontmostApp to isFrontmostWindow.
     Previously ALL windows from the frontmost app got .floating, but only
     the actual frontmost window should get .floating.
     
     - Parameter decision: The region dimming decision (includes isFrontmostWindow)
     */
    private func createRegionOverlay(for decision: RegionDimmingDecision) {
        // Generate unique ID for this region
        regionCounter += 1
        let regionID = "region-\(decision.windowID)-\(regionCounter)"
        
        // Debug: Log the region details to our file-based debug log
        let logMessage = """
        🎯 Creating overlay: \(regionID)
           - Window: \(decision.windowName) (PID: \(decision.ownerPID))
           - Rect: \(decision.regionRect)
           - Brightness: \(decision.brightness)
           - DimLevel: \(decision.dimLevel)
           - isFrontmostWindow: \(decision.isFrontmostWindow)
        """
        
        // Write to debug log file
        let logFile = "/tmp/superdimmer_debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(logMessage)\n"
        if let handle = FileHandle(forWritingAtPath: logFile) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
        }
        
        // Create overlay using factory method
        // FIX (Jan 8, 2026): Start at 0 opacity and FADE IN to target level
        // This prevents the jarring "pop-in" effect when new bright regions are detected
        let overlay = DimOverlayWindow.create(
            frame: decision.regionRect,
            dimLevel: 0.0,  // Start invisible
            id: regionID
        )
        
        // HYBRID Z-ORDERING: Set window level based on frontmost status
        if decision.isFrontmostWindow {
            // Frontmost window: Use .floating level so it NEVER falls behind
            // This eliminates flash when clicking within the active window
            overlay.level = .floating
            overlay.orderFront(nil)
        } else {
            // Background window: Use .normal level with relative positioning
            // This ensures proper layering with windows in front
            overlay.level = .normal
            overlay.orderAboveWindow(decision.windowID)
        }
        
        // Store references
        regionOverlays[regionID] = overlay
        regionToWindowID[regionID] = decision.windowID
        regionToOwnerPID[regionID] = decision.ownerPID
        
        // FIX (Jan 21, 2026): Store original frame for accurate movement tracking
        originalOverlayFrames[regionID] = decision.regionRect
        
        // Fade in to target dim level with smooth animation
        overlay.setDimLevel(decision.dimLevel, animated: true, duration: 0.3)
    }
    
    /**
     Hides all region overlays.
     
     CRITICAL FIX (Jan 9, 2026): NEVER destroy overlays!
     Just hide them by setting dimLevel to 0.
     Destroying overlays causes EXC_BAD_ACCESS crash.
     */
    private func removeAllRegionOverlays() {
        // Just hide all overlays, don't destroy them
        for (_, overlay) in regionOverlays {
            overlay.setDimLevel(0.0, animated: false)
            overlay.orderOut(nil)
        }
        // Don't clear the dictionaries - keep references alive
        // regionOverlays.removeAll()  // DISABLED
        // regionToWindowID.removeAll()  // DISABLED
        // regionToOwnerPID.removeAll()  // DISABLED
        // regionCounter = 0  // DISABLED
    }
    
    // ================================================================
    // MARK: - Decay Overlay Management
    // ================================================================
    
    /**
     Decision for decay-based window dimming.
     
     Contains all info needed to create/update a decay overlay
     for an inactive window.
     */
    struct DecayDimmingDecision {
        let windowID: CGWindowID
        let windowName: String
        let ownerPID: pid_t
        let windowBounds: CGRect
        let decayDimLevel: CGFloat
        let isActive: Bool  // If true, no decay overlay needed
    }
    
    /**
     Applies decay dimming to inactive windows.
     
     Creates full-window overlays for inactive windows based on their
     inactivity duration. Active windows get no decay overlay.
     
     THREAD-SAFE REWRITE (Jan 9, 2026):
     - Uses overlayLock to prevent race conditions
     - All dictionary access is now synchronized
     - Detailed logging for crash debugging
     
     - Parameter decisions: Array of decay dimming decisions for all windows
     */
    func applyDecayDimming(_ decisions: [DecayDimmingDecision]) {
        // THROTTLE FIX (Jan 26, 2026): Prevent too-frequent calls
        // Check throttle BEFORE any other work to minimize overhead
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastDecayApplyTime < minDecayApplyInterval {
            // Too soon since last call - skip this one
            // This is normal during rapid idle/active cycling
            return
        }
        lastDecayApplyTime = now
        
        // FIX (Feb 5, 2026): REMOVED high-frequency print() statements from this method.
        // The previous print("🔄 applyDecayDimming START/END...") calls were firing
        // every 500ms (from the throttle interval), producing so much output that macOS
        // QUARANTINED SuperDimmer's logging ("QUARANTINED DUE TO HIGH LOGGING VOLUME").
        // This meant we LOST diagnostic visibility right when we needed it most.
        // Now we only log at debug level via os_log, which is efficient and filterable.
        #if DEBUG
        // Only log in debug builds, and only to os_log (not print/stdout)
        // Use: log stream --predicate 'subsystem == "com.superdimmer.app" AND category == "overlay"'
        let threadName = Thread.isMainThread ? "MAIN" : "BG"
        overlayLogger.debug("applyDecayDimming START [\(threadName, privacy: .public)] decisions=\(decisions.count)")
        #endif
        
        // MUST run on main thread for UI operations
        let applyBlock: () -> Void = { [weak self] in
            guard let self = self else {
                overlayLogger.warning("applyDecayDimming: self was deallocated")
                return
            }
            
            // CRASH FIX (Jan 9, 2026): Wrap entire block in autoreleasepool
            // The EXC_BAD_ACCESS was happening during main run loop's autorelease pool drain.
            // By draining our own pool immediately after CA operations, we catch any
            // autoreleased objects before they become dangling pointers.
            autoreleasepool {
                // CRITICAL: Lock before ANY dictionary access
                self.overlayLock.lock()
                defer { 
                    self.overlayLock.unlock()
                    // FIX (Feb 5, 2026): Removed print() here - was causing logging quarantine.
                    // This was printing every 500ms, producing thousands of log lines per hour.
                    #if DEBUG
                    overlayLogger.debug("applyDecayDimming END - decayOverlays.count=\(self.decayOverlays.count)")
                    #endif
                }
                
                // Update window bounds tracking (2.2.1.14)
                // Store current window bounds for decay overlays so updateOverlayPositions()
                // can track window movement without expensive screenshot analysis
                for decision in decisions {
                    self.previousWindowBounds[decision.windowID] = decision.windowBounds
                }
                
                for decision in decisions {
                    // DEBUG: Log each decision being processed
                    let isActive = decision.isActive
                    let dimLevel = decision.decayDimLevel
                    let windowID = decision.windowID
                    
                    if let existing = self.decayOverlays[windowID] {
                        // REUSE existing overlay - just update dim level
                        let targetLevel = (isActive || dimLevel <= 0.01) ? 0.0 : dimLevel
                        
                        // DEBUG: Verify overlay is still valid before accessing
                        guard existing.contentView != nil else {
                            // FIX (Feb 5, 2026): Switched from print to os_log to reduce logging volume
                            overlayLogger.warning("ZOMBIE DETECTED: Overlay \(existing.overlayID, privacy: .public) has nil contentView")
                            // Remove the zombie reference
                            self.decayOverlays.removeValue(forKey: windowID)
                            continue
                        }
                        
                        existing.updatePosition(to: decision.windowBounds, animated: false)
                        existing.setDimLevel(targetLevel, animated: true)
                        
                        // Only bring to front if visible
                        if targetLevel > 0 {
                            existing.orderAboveWindow(windowID)
                        }
                    } else if !isActive && dimLevel > 0.01 {
                        // Create new overlay only if window needs dimming AND doesn't have one
                        let overlayID = "decay-\(windowID)"
                        // FIX (Feb 5, 2026): Switched from print to os_log - this fires frequently
                        // during normal operation and was contributing to logging quarantine
                        overlayLogger.debug("Creating decay overlay: \(overlayID, privacy: .public)")
                        
                        let overlay = DimOverlayWindow.create(
                            frame: decision.windowBounds,
                            dimLevel: 0.0,
                            id: overlayID
                        )
                        overlay.level = .normal
                        overlay.orderFront(nil)
                        overlay.orderAboveWindow(windowID)
                        
                        // Store in dictionary WHILE holding lock
                        self.decayOverlays[windowID] = overlay
                        overlay.setDimLevel(dimLevel, animated: true, duration: 0.5)
                    }
                    // Active windows with no overlay: do nothing, wait for inactivity
                }
                
                // CLEANUP: Remove overlays for windows that no longer exist
                // FIX (Jan 26, 2026): The previous approach of keeping all overlays forever
                // was causing accumulation. With rapid idle/active cycling, hundreds of
                // overlays would accumulate, causing memory issues and window server strain.
                //
                // NEW APPROACH: Clean up overlays for windows that are no longer in decisions.
                // This happens when:
                // - Window is closed
                // - Window is minimized
                // - Window is no longer tracked by WindowInactivityTracker
                //
                // We use safeHideOverlay() which properly cleans up without causing crashes.
                let currentWindowIDs = Set(decisions.map { $0.windowID })
                let staleOverlayIDs = Set(self.decayOverlays.keys).subtracting(currentWindowIDs)
                
                if !staleOverlayIDs.isEmpty {
                    // FIX (Feb 5, 2026): Switched from print to os_log
                    overlayLogger.debug("Cleaning up \(staleOverlayIDs.count) stale decay overlays")
                    for staleID in staleOverlayIDs {
                        if let staleOverlay = self.decayOverlays.removeValue(forKey: staleID) {
                            self.safeHideOverlay(staleOverlay)
                        }
                    }
                }
            } // End autoreleasepool
        }
        
        if Thread.isMainThread {
            applyBlock()
        } else {
            // Dispatch async to main thread
            DispatchQueue.main.async(execute: applyBlock)
        }
    }
    
    /**
     Hides an overlay window WITHOUT ever calling close().
     
     CRASH FIX (Jan 20, 2026): NEVER call NSWindow.close() on overlays - EVER!
     
     ROOT CAUSE: Calling close() triggers AppKit internal cleanup that autoreleases
     objects. Even with delays, these objects can be accessed after deallocation,
     causing EXC_BAD_ACCESS in objc_release. The crash happens because:
     1. close() triggers AppKit cleanup that autoreleases internal objects
     2. Core Animation may still have references to the layer
     3. When autorelease pool drains, objects are freed
     4. CA tries to access freed objects → crash
     
     SOLUTION: NEVER close overlays - just hide and let ARC deallocate naturally:
     1. Remove all animations (stop CA from accessing layer)
     2. Set dimLevel to 0 (invisible)
     3. Call orderOut(nil) (remove from screen)
     4. Clear all references from dictionaries
     5. Let Swift ARC deallocate the window naturally
     
     NO MORE HIDDEN POOL: We don't need to keep overlays alive anymore.
     Once removed from all dictionaries, ARC will deallocate them safely.
     
     Memory: Overlays are deallocated immediately by ARC once unreferenced.
     No accumulation, no memory leak.
     
     - Parameter overlay: The overlay window to hide
     */
    private func safeHideOverlay(_ overlay: DimOverlayWindow) {
        // Step 1: Remove all animations to stop CA from accessing the layer
        // This is CRITICAL - must happen before orderOut
        autoreleasepool {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.contentView?.layer?.removeAllAnimations()
            overlay.setDimLevel(0.0, animated: false)
            CATransaction.commit()
            CATransaction.flush()
        }
        
        // Step 2: Hide the window (but DON'T close!)
        overlay.orderOut(nil)
        
        // Step 3: That's it! No pool, no delayed close, no cleanup.
        // Once this overlay is removed from all dictionaries (which the caller does),
        // Swift ARC will deallocate it naturally and safely.
        
        print("👻 safeHideOverlay: Hidden \(overlay.overlayID) - will be deallocated by ARC")
    }
    
    /**
     Removes all decay overlays.
     
     Only called when app is quitting or dimming is completely disabled.
     In normal operation, decay overlays are NEVER destroyed (only hidden).
     */
    private func removeAllDecayOverlays() {
        // Just hide all overlays instead of destroying them
        // They'll get cleaned up when app quits
        for (_, overlay) in decayOverlays {
            overlay.setDimLevel(0.0, animated: false)
            overlay.orderOut(nil)
        }
        // Don't clear the dictionary - keep references alive
        // decayOverlays.removeAll()  // DISABLED - keep overlays alive
    }
    
    // ================================================================
    // MARK: - Control Methods
    // ================================================================
    
    /**
     Removes all overlays (both window and display).
     
     Called when:
     - App is quitting
     - User disables all dimming
     - Major configuration change
     */
    func removeAllOverlays() {
        // CRASH FIX (Jan 21, 2026): NEVER call overlay.close() - use safeHideOverlay()
        // Calling close() causes EXC_BAD_ACCESS crashes in Core Animation
        
        // Remove window overlays
        for (_, overlay) in windowOverlays {
            safeHideOverlay(overlay)
        }
        windowOverlays.removeAll()
        
        // Remove display overlays
        for (_, overlay) in displayOverlays {
            safeHideOverlay(overlay)
        }
        displayOverlays.removeAll()
        
        // Remove region overlays (per-region mode)
        removeAllRegionOverlays()
        
        // Remove decay overlays
        removeAllDecayOverlays()
        
        // OPTIMIZATION (Jan 21, 2026): Clean up all tracking data
        lastTrackedWindowBounds.removeAll()
        windowMovementStreak.removeAll()
        originalOverlayFrames.removeAll()
        
        isActive = false
        print("🗑️ All overlays removed")
    }
    
    /**
     Updates dim level for all existing overlays.
     
     - Parameter dimLevel: The new dim level to apply
     
     Used when user changes global dim setting.
     Animates the transition on all overlays simultaneously.
     */
    func updateAllOverlayLevels(_ dimLevel: CGFloat) {
        for (_, overlay) in windowOverlays {
            overlay.setDimLevel(dimLevel, animated: true)
        }
        for (_, overlay) in displayOverlays {
            overlay.setDimLevel(dimLevel, animated: true)
        }
    }
    
    /**
     Hides all overlays without destroying them.
     Used for temporary pause functionality.
     */
    func hideAllOverlays() {
        for (_, overlay) in windowOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in displayOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in regionOverlays {
            overlay.orderOut(nil)
        }
        for (_, overlay) in decayOverlays {
            overlay.orderOut(nil)
        }
        isActive = false
    }
    
    /**
     Updates debug borders on all existing overlays.
     
     Call this when the debugOverlayBorders setting changes to update
     all visible overlays without recreating them.
     */
    func updateAllDebugBorders() {
        for (_, overlay) in windowOverlays {
            overlay.updateDebugBorders()
        }
        for (_, overlay) in displayOverlays {
            overlay.updateDebugBorders()
        }
        for (_, overlay) in regionOverlays {
            overlay.updateDebugBorders()
        }
        for (_, overlay) in decayOverlays {
            overlay.updateDebugBorders()
        }
        let total = windowOverlays.count + displayOverlays.count + regionOverlays.count + decayOverlays.count
        print("🔴 Updated debug borders on all \(total) overlays")
    }
    
    /**
     Updates corner radius on all existing overlays.
     
     FEATURE 2.8.2b: Rounded Corners for Overlays
     
     Call this when the overlayCornerRadius setting changes to update
     all visible overlays without recreating them.
     */
    func updateAllCornerRadius() {
        for (_, overlay) in windowOverlays {
            overlay.applyCornerRadius()
        }
        for (_, overlay) in displayOverlays {
            overlay.applyCornerRadius()
        }
        for (_, overlay) in regionOverlays {
            overlay.applyCornerRadius()
        }
        for (_, overlay) in decayOverlays {
            overlay.applyCornerRadius()
        }
        let total = windowOverlays.count + displayOverlays.count + regionOverlays.count + decayOverlays.count
        let radius = SettingsManager.shared.overlayCornerRadius
        print("🔘 Updated corner radius (\(radius)pt) on all \(total) overlays")
    }
    
    /**
     Shows all previously hidden overlays.
     */
    func showAllOverlays() {
        for (_, overlay) in windowOverlays {
            overlay.orderFront(nil)
        }
        for (_, overlay) in displayOverlays {
            overlay.orderFront(nil)
        }
        for (_, overlay) in regionOverlays {
            overlay.orderFront(nil)
        }
        isActive = true
    }
    
    // ================================================================
    // MARK: - Lightweight Window Tracking
    // ================================================================
    
    /**
     Updates overlay positions based on current window positions.
     
     This is a LIGHTWEIGHT operation - no screenshots or brightness analysis.
     Called by the fast window tracking timer (every 0.5s by default).
     
     - Parameter visibleWindowIDs: Set of currently visible window IDs
     - Parameter windows: Current window data from WindowTrackerService
     */
    /**
     Updates overlay positions when windows move or resize.
     
     IMPLEMENTATION (2.2.1.14): This provides smooth overlay tracking without waiting
     for the slow (2-second) brightness analysis cycle. We track the window's position
     change and apply the same delta to all region overlays for that window.
     
     PERFORMANCE: This is lightweight - only frame updates, no screenshots or analysis.
     
     IMPORTANT: We maintain the same dim level and region shapes until the next
     brightness analysis cycle. This method only handles POSITION/SIZE tracking.
     
     - Parameters:
       - visibleWindowIDs: Set of currently visible window IDs
       - windows: Array of tracked windows with current bounds
     */
    func updateOverlayPositions(visibleWindowIDs: Set<CGWindowID>, windows: [TrackedWindow]) {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        // OPTIMIZATION (Jan 21, 2026): Early exit if no overlays to track
        // This prevents unnecessary CPU usage when dimming is disabled or no overlays exist
        guard !regionOverlays.isEmpty || !decayOverlays.isEmpty else {
            return
        }
        
        // Build lookup dictionary for quick window access
        let windowLookup = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        
        var updatedCount = 0
        
        // ============================================================
        // DETECT ACTIVE WINDOW DRAGGING (FIX Jan 21, 2026)
        // ============================================================
        // PROBLEM: When a window is being dragged, the 0.5s tracking interval
        // causes overlays to "skip ahead" instead of smoothly following.
        //
        // SOLUTION: Detect windows that are moving continuously across multiple
        // tracking cycles. For these windows, we know they're being actively
        // dragged, so we can use interpolation or request faster updates.
        //
        // We track movement streaks: if a window moves in 2+ consecutive cycles,
        // it's likely being dragged. We'll use this to adjust our update strategy.
        // ============================================================
        
        // OPTIMIZATION (Jan 21, 2026): Build set of windows that have overlays
        // Only track movement for windows we're actually managing overlays for
        var windowsWithOverlays = Set<CGWindowID>()
        for windowID in regionToWindowID.values {
            windowsWithOverlays.insert(windowID)
        }
        for windowID in decayOverlays.keys {
            windowsWithOverlays.insert(windowID)
        }
        
        var currentlyMovingWindows = Set<CGWindowID>()
        
        // First pass: detect which windows are currently moving
        // OPTIMIZATION: Only check windows that have overlays
        for window in windows where windowsWithOverlays.contains(window.id) {
            let currentBounds = window.bounds
            
            // Check if window moved since last tracking cycle
            if let lastBounds = lastTrackedWindowBounds[window.id] {
                let deltaX = abs(currentBounds.origin.x - lastBounds.origin.x)
                let deltaY = abs(currentBounds.origin.y - lastBounds.origin.y)
                
                // Movement threshold: 2 pixels (to avoid jitter from sub-pixel rendering)
                if deltaX > 2.0 || deltaY > 2.0 {
                    currentlyMovingWindows.insert(window.id)
                    
                    // Increment movement streak
                    let currentStreak = windowMovementStreak[window.id] ?? 0
                    windowMovementStreak[window.id] = currentStreak + 1
                } else {
                    // Window stopped moving - reset streak
                    windowMovementStreak[window.id] = 0
                }
            }
            
            // Update last tracked bounds for next cycle
            lastTrackedWindowBounds[window.id] = currentBounds
        }
        
        // ============================================================
        // UPDATE REGION OVERLAY POSITIONS (2.2.1.14)
        // ============================================================
        // Region overlays are positioned relative to their target window.
        // When a window moves, we need to move all of its region overlays by the same delta.
        //
        // We store the original window bounds at analysis time in previousWindowBounds.
        // By comparing current window bounds to previous bounds, we can calculate
        // the position delta and apply it to all region overlays.
        //
        // EXAMPLE:
        // - Window was at (100, 200), now at (150, 250) → delta = (+50, +50)
        // - Region overlay was at (110, 210), moves to (160, 260)
        //
        // This keeps overlays visually synchronized with their target windows
        // without requiring expensive screenshot analysis.
        // ============================================================
        
        for (overlayID, overlay) in regionOverlays {
            guard let windowID = regionToWindowID[overlayID],
                  let window = windowLookup[windowID] else {
                continue
            }
            
            // Get the window bounds we used during the last analysis
            guard let previousBounds = previousWindowBounds[windowID] else {
                // No previous bounds stored - skip this update
                // (Will be handled on next analysis cycle)
                continue
            }
            
            // Calculate position delta and scale
            let currentBounds = window.bounds
            let deltaX = currentBounds.origin.x - previousBounds.origin.x
            let deltaY = currentBounds.origin.y - previousBounds.origin.y
            let scaleX = currentBounds.size.width / previousBounds.size.width
            let scaleY = currentBounds.size.height / previousBounds.size.height
            
            // Only update if window actually moved or resized significantly (avoid jitter)
            let positionChanged = abs(deltaX) > 1.0 || abs(deltaY) > 1.0
            let sizeChanged = abs(scaleX - 1.0) > 0.01 || abs(scaleY - 1.0) > 0.01
            
            if positionChanged || sizeChanged {
                // FIX (Jan 21, 2026): Calculate overlay's position RELATIVE to the window
                // at the time of the last analysis, then apply that same relative position
                // to the window's current bounds.
                //
                // PROBLEM: Previously we were adding deltas to the current overlay frame,
                // which caused overshooting because the overlay may have already moved
                // partially in a previous tracking cycle.
                //
                // SOLUTION: Use the ORIGINAL overlay frame (from analysis time) to calculate
                // the correct relative position, then apply to current window bounds.
                
                // Get the original overlay frame from when it was last analyzed
                guard let originalFrame = originalOverlayFrames[overlayID] else {
                    // No original frame stored - skip this update
                    // (Will be handled on next analysis cycle)
                    continue
                }
                
                // Calculate overlay's relative position within the window at analysis time
                let relativeX = originalFrame.origin.x - previousBounds.origin.x
                let relativeY = originalFrame.origin.y - previousBounds.origin.y
                
                // Calculate new absolute position based on current window position
                var newFrame = originalFrame
                newFrame.origin.x = currentBounds.origin.x + relativeX
                newFrame.origin.y = currentBounds.origin.y + relativeY
                
                // Apply scaling if window was resized
                if sizeChanged {
                    // Scale the relative position and size
                    let scaledRelativeX = relativeX * scaleX
                    let scaledRelativeY = relativeY * scaleY
                    
                    newFrame.origin.x = currentBounds.origin.x + scaledRelativeX
                    newFrame.origin.y = currentBounds.origin.y + scaledRelativeY
                    newFrame.size.width = originalFrame.size.width * scaleX
                    newFrame.size.height = originalFrame.size.height * scaleY
                }
                
                // OPTIMIZATION (Jan 21, 2026): Only update if frame actually changed
                // Check if the new frame is different from current frame to avoid
                // unnecessary updates that waste CPU/memory
                let currentFrame = overlay.frame
                let frameDifferenceThreshold: CGFloat = 0.5  // Sub-pixel threshold
                
                let frameActuallyChanged = 
                    abs(currentFrame.origin.x - newFrame.origin.x) > frameDifferenceThreshold ||
                    abs(currentFrame.origin.y - newFrame.origin.y) > frameDifferenceThreshold ||
                    abs(currentFrame.size.width - newFrame.size.width) > frameDifferenceThreshold ||
                    abs(currentFrame.size.height - newFrame.size.height) > frameDifferenceThreshold
                
                if frameActuallyChanged {
                    // FIX (Jan 21, 2026): Update overlay frame instantly
                    // We use instant updates (no animation) to avoid lag perception
                    // The high-frequency tracking timer (30fps) provides smooth movement
                    // when windows are being actively dragged
                    //
                    // OPTIMIZATION: Update directly on main thread if already on main thread
                    // to avoid dispatch overhead
                    if Thread.isMainThread {
                        overlay.setFrame(newFrame, display: false)
                    } else {
                        DispatchQueue.main.async {
                            overlay.setFrame(newFrame, display: false)
                        }
                    }
                    
                    updatedCount += 1
                }
            }
        }
        
        // ============================================================
        // UPDATE DECAY OVERLAY POSITIONS (2.2.1.14)
        // ============================================================
        // Decay overlays are full-window overlays, so they simply match
        // their target window's bounds.
        // ============================================================
        
        for (windowID, overlay) in decayOverlays {
            guard let window = windowLookup[windowID] else {
                continue
            }
            
            let currentFrame = overlay.frame
            let targetFrame = window.bounds
            
            // Only update if bounds changed significantly
            if abs(currentFrame.origin.x - targetFrame.origin.x) > 1.0 ||
               abs(currentFrame.origin.y - targetFrame.origin.y) > 1.0 ||
               abs(currentFrame.size.width - targetFrame.size.width) > 1.0 ||
               abs(currentFrame.size.height - targetFrame.size.height) > 1.0 {
                
                // OPTIMIZATION (Jan 21, 2026): Update directly on main thread if already there
                if Thread.isMainThread {
                    overlay.setFrame(targetFrame, display: false)
                } else {
                    DispatchQueue.main.async {
                        overlay.setFrame(targetFrame, display: false)
                    }
                }
                
                updatedCount += 1
            }
        }
        
        // OPTIMIZATION (Jan 21, 2026): Reduce logging frequency to avoid console spam
        // Only log every 10th update when in high-frequency mode
        if updatedCount > 0 {
            // Throttle logging - only print occasionally
            // FIX (Feb 5, 2026): Switched from print to os_log - this fires every 0.5s
            // from the window tracking timer and was a major contributor to logging quarantine.
            // Only log when something significant happened (>5 overlays updated)
            if updatedCount > 5 {
                overlayLogger.debug("Updated \(updatedCount) overlay positions (window movement tracking)")
            }
        }
    }
    
    /**
     Checks if any windows are currently being actively moved/dragged.
     
     FIX (Jan 21, 2026): Used by DimmingCoordinator to determine if high-frequency
     tracking should be activated. Returns true if any window has been moving for
     2+ consecutive tracking cycles, indicating active dragging.
     
     - Returns: True if active window movement is detected, false otherwise
     */
    func hasActiveWindowMovement() -> Bool {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        // OPTIMIZATION (Jan 21, 2026): Early exit if no overlays
        guard !regionOverlays.isEmpty || !decayOverlays.isEmpty else {
            return false
        }
        
        // Check if any window has a movement streak of 2 or more
        // This indicates the window is being actively dragged
        for (_, streak) in windowMovementStreak {
            if streak >= 2 {
                return true
            }
        }
        
        return false
    }
    
    /**
     Removes overlays for windows that are no longer visible.
     
     Called by the window tracking timer to clean up stale overlays
     without waiting for the slower brightness analysis cycle.
     
     - Parameter visibleWindowIDs: Set of currently visible window IDs
     */
    func cleanupOrphanedOverlays(visibleWindowIDs: Set<CGWindowID>) {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        // Find region overlays for windows that are no longer visible
        var orphanedIDs: [String] = []
        for (overlayID, _) in regionOverlays {
            if let windowID = regionToWindowID[overlayID] {
                if !visibleWindowIDs.contains(windowID) {
                    orphanedIDs.append(overlayID)
                }
            }
        }
        
        // Remove orphaned region overlays
        for overlayID in orphanedIDs {
            if let overlay = regionOverlays.removeValue(forKey: overlayID) {
                safeHideOverlay(overlay)
            }
            let windowID = regionToWindowID.removeValue(forKey: overlayID)
            regionToOwnerPID.removeValue(forKey: overlayID)
            originalOverlayFrames.removeValue(forKey: overlayID)
            
            // OPTIMIZATION (Jan 21, 2026): Clean up tracking data for this window
            if let wid = windowID {
                lastTrackedWindowBounds.removeValue(forKey: wid)
                windowMovementStreak.removeValue(forKey: wid)
            }
        }
        
        // Find decay overlays for windows that are no longer visible
        var orphanedDecayWindowIDs: [CGWindowID] = []
        for (windowID, _) in decayOverlays {
            if !visibleWindowIDs.contains(windowID) {
                orphanedDecayWindowIDs.append(windowID)
            }
        }
        
        // Remove orphaned decay overlays
        for windowID in orphanedDecayWindowIDs {
            if let overlay = decayOverlays.removeValue(forKey: windowID) {
                safeHideOverlay(overlay)
            }
            // OPTIMIZATION (Jan 21, 2026): Clean up tracking data
            lastTrackedWindowBounds.removeValue(forKey: windowID)
            windowMovementStreak.removeValue(forKey: windowID)
        }
        
        if !orphanedIDs.isEmpty || !orphanedDecayWindowIDs.isEmpty {
            print("🧹 Cleaned up \(orphanedIDs.count) region + \(orphanedDecayWindowIDs.count) decay orphaned overlays")
        }
    }
    
    // ================================================================
    // MARK: - App/Window Hide/Minimize Support
    // ================================================================
    
    /**
     Removes all overlays belonging to a specific app.
     
     Called when:
     - App is hidden by user (Cmd+H)
     - App is hidden by AutoHideManager
     
     This removes region overlays and decay overlays for all windows
     of the hidden app. They'll be recreated when the app is unhidden
     and comes back into focus.
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions.
     
     - Parameter pid: The process ID of the hidden app
     */
    func removeOverlaysForApp(pid: pid_t) {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        var removedCount = 0
        
        // Remove region overlays for this app's windows
        let regionIDsToRemove = regionToOwnerPID.filter { $0.value == pid }.map { $0.key }
        for overlayID in regionIDsToRemove {
            if let overlay = regionOverlays.removeValue(forKey: overlayID) {
                safeHideOverlay(overlay)
                removedCount += 1
            }
            regionToWindowID.removeValue(forKey: overlayID)
            regionToOwnerPID.removeValue(forKey: overlayID)
        }
        
        // Remove decay overlays for this app's windows
        // We need to check the window info to find which windows belong to this app
        // Since decayOverlays is keyed by windowID, we iterate and check PID
        let decayWindowIDsToRemove = decayOverlays.compactMap { (windowID, overlay) -> CGWindowID? in
            // Check if this window belongs to the hidden app
            // We stored PID info during creation via the TrackedWindow
            if let info = WindowInactivityTracker.shared.getWindowInfo(for: windowID),
               info.ownerPID == pid {
                return windowID
            }
            return nil
        }
        
        for windowID in decayWindowIDsToRemove {
            if let overlay = decayOverlays.removeValue(forKey: windowID) {
                safeHideOverlay(overlay)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            print("🙈 Removed \(removedCount) overlays for hidden app (PID \(pid))")
        }
    }
    
    /**
     Removes all overlays for a specific window.
     
     Called when:
     - Window is minimized
     - Window is closed
     
     This removes both region overlays and decay overlay for the window.
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions.
     
     - Parameter windowID: The window ID to remove overlays for
     */
    func removeOverlaysForWindow(windowID: CGWindowID) {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        var removedCount = 0
        
        // Remove region overlays for this window
        // Find all region overlay IDs associated with this window
        let regionIDsToRemove = regionToWindowID.filter { $0.value == windowID }.map { $0.key }
        for overlayID in regionIDsToRemove {
            if let overlay = regionOverlays.removeValue(forKey: overlayID) {
                safeHideOverlay(overlay)
                removedCount += 1
            }
            regionToWindowID.removeValue(forKey: overlayID)
            regionToOwnerPID.removeValue(forKey: overlayID)
        }
        
        // Remove decay overlay for this window
        if let overlay = decayOverlays.removeValue(forKey: windowID) {
            safeHideOverlay(overlay)
            removedCount += 1
        }
        
        // Also remove from windowOverlays (per-window mode)
        if let overlay = windowOverlays.removeValue(forKey: windowID) {
            safeHideOverlay(overlay)
            removedCount += 1
        }
        
        if removedCount > 0 {
            print("📦 Removed \(removedCount) overlays for window \(windowID)")
        }
    }
    
    /**
     Immediately re-orders all region overlays to be above their target windows.
     
     FIX (Jan 8, 2026): Called when window focus changes to prevent overlays
     from appearing behind windows after the user clicks. When a window is
     clicked and brought to front, its z-order changes but our overlays stay
     at their old position. This method immediately repositions all overlays.
     
     This is a fast operation - it just changes z-order, doesn't redraw anything.
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions.
     */
    func reorderAllRegionOverlays() {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        guard isActive else { return }
        
        var reorderedCount = 0
        for (overlayID, overlay) in regionOverlays {
            // Only reorder visible overlays
            guard overlay.isVisible else { continue }
            
            // Get the target window ID this overlay should be above
            if let targetWindowID = regionToWindowID[overlayID] {
                overlay.orderAboveWindow(targetWindowID)
                reorderedCount += 1
            }
        }
        
        if reorderedCount > 0 {
            print("🔄 Reordered \(reorderedCount) overlays after window focus change")
        }
    }
    
    /**
     HYBRID Z-ORDERING: Updates overlay window levels based on the frontmost WINDOW.
     
     FIX (Jan 8, 2026): This is the KEY fix for eliminating flash when clicking windows!
     
     UPDATE (Jan 8, 2026): Changed from frontmost APP to frontmost WINDOW.
     Previously ALL windows from the frontmost app got .floating overlays, but
     only the actual frontmost window should get .floating. Other windows from
     the same app should use .normal with relative positioning.
     
     The solution: Use TWO different window levels:
     - FRONTMOST WINDOW overlays: .floating level (always on top, never flash)
     - ALL OTHER WINDOW overlays: .normal level with orderAboveWindow()
     
     When the frontmost window changes:
     1. Demote old frontmost window's overlays to .normal
     2. Promote new frontmost window's overlays to .floating
     3. Reorder background overlays relative to their target windows
     
     THREAD-SAFE (Jan 9, 2026): Uses overlayLock to prevent race conditions.
     */
    func updateOverlayLevelsForFrontmostApp() {
        overlayLock.lock()
        defer { overlayLock.unlock() }
        
        guard isActive else { return }
        
        // Get the actual frontmost WINDOW ID (not just frontmost app)
        guard let frontmostWindow = WindowTrackerService.shared.getFrontmostWindow() else {
            return
        }
        let frontmostWindowID = frontmostWindow.id
        
        var promotedCount = 0
        var demotedCount = 0
        
        for (overlayID, overlay) in regionOverlays {
            guard overlay.isVisible else { continue }
            
            guard let targetWindowID = regionToWindowID[overlayID] else { continue }
            
            if targetWindowID == frontmostWindowID {
                // This overlay belongs to the frontmost WINDOW - use .floating
                if overlay.level != .floating {
                    overlay.level = .floating
                    overlay.orderFront(nil)
                    promotedCount += 1
                }
            } else {
                // This overlay belongs to a background window - use .normal with relative ordering
                if overlay.level != .normal {
                    overlay.level = .normal
                    demotedCount += 1
                }
                // Reorder relative to target window
                overlay.orderAboveWindow(targetWindowID)
            }
        }
        
        if promotedCount > 0 || demotedCount > 0 {
            print("🔄 Hybrid z-order: promoted \(promotedCount), demoted \(demotedCount) overlays (frontmost window: \(frontmostWindowID))")
        }
    }
    
    // ================================================================
    // MARK: - Display Change Handling
    // ================================================================
    
    /**
     Sets up observer for display configuration changes.
     
     Called when:
     - Display is connected/disconnected
     - Display resolution changes
     - Display arrangement changes
     */
    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    /**
     Handles display configuration changes.
     
     When displays change, we need to:
     1. Remove overlays for disconnected displays
     2. Recreate overlays for connected displays (if in full-screen mode)
     3. Update overlay positions for remaining displays
     */
    @objc private func displayConfigurationChanged() {
        print("🖥️ Display configuration changed")
        
        // Get current display IDs
        let currentDisplayIDs = Set(NSScreen.screens.compactMap { $0.displayID })
        
        // Remove overlays for disconnected displays
        // CRASH FIX (Jan 21, 2026): Use safeHideOverlay() instead of close()
        let disconnectedDisplays = Set(displayOverlays.keys).subtracting(currentDisplayIDs)
        for displayID in disconnectedDisplays {
            if let overlay = displayOverlays.removeValue(forKey: displayID) {
                safeHideOverlay(overlay)
            }
            print("🖥️ Removed overlay for disconnected display \(displayID)")
        }
        
        // Update positions for remaining display overlays
        for (displayID, overlay) in displayOverlays {
            if let screen = screenForDisplay(displayID) {
                overlay.updatePosition(to: screen.frame)
            }
        }
    }
    
    // ================================================================
    // MARK: - Settings Observers
    // ================================================================
    
    /**
     Sets up observers for settings that affect overlays.
     */
    private func setupSettingsObservers() {
        // Observe global dim level changes
        SettingsManager.shared.$globalDimLevel
            .dropFirst() // Skip initial value
            .sink { [weak self] newLevel in
                self?.updateAllOverlayLevels(newLevel)
            }
            .store(in: &cancellables)
        
        // Observe corner radius changes (2.8.2b)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCornerRadiusChanged),
            name: .overlayCornerRadiusChanged,
            object: nil
        )
    }
    
    /**
     Handles corner radius setting changes.
     
     FEATURE 2.8.2b: Rounded Corners for Overlays
     
     When the user changes the corner radius setting, this updates all
     existing overlays immediately without recreating them.
     */
    @objc private func handleCornerRadiusChanged(_ notification: Notification) {
        updateAllCornerRadius()
    }
    
    // ================================================================
    // MARK: - Helper Methods
    // ================================================================
    
    /**
     Finds the NSScreen for a given display ID.
     
     - Parameter displayID: The CGDirectDisplayID to find
     - Returns: The corresponding NSScreen, or nil if not found
     */
    private func screenForDisplay(_ displayID: CGDirectDisplayID) -> NSScreen? {
        return NSScreen.screens.first { $0.displayID == displayID }
    }
    
    /**
     Returns the current overlay count for debugging.
     */
    var overlayCount: Int {
        return windowOverlays.count + displayOverlays.count
    }
}

// ====================================================================
// MARK: - NSScreen Extension
// ====================================================================

/**
 Extension to get display ID from NSScreen.
 */
extension NSScreen {
    
    /**
     The CGDirectDisplayID for this screen.
     
     Extracted from the screen's deviceDescription dictionary.
     */
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

// ====================================================================
// MARK: - Dimming Decision Model
// ====================================================================

/**
 Represents a decision about whether and how much to dim a window.
 
 Created by DimmingCoordinator based on brightness analysis.
 Consumed by OverlayManager to create/update overlays.
 */
struct DimmingDecision {
    /// The window this decision applies to
    let window: TrackedWindow
    
    /// Whether this window should be dimmed
    let shouldDim: Bool
    
    /// The dim level to apply (0.0-1.0)
    let dimLevel: CGFloat
    
    /// The reason for this decision (for debugging/logging)
    let reason: DimmingReason
    
    /// Possible reasons for a dimming decision
    enum DimmingReason: String {
        case aboveThreshold = "Brightness above threshold"
        case belowThreshold = "Brightness below threshold"
        case appRuleAlwaysDim = "App rule: always dim"
        case appRuleNeverDim = "App rule: never dim"
        case activeWindowReduced = "Active window (reduced dimming)"
        case inactiveWindowIncreased = "Inactive window (increased dimming)"
    }
}

// ====================================================================
// MARK: - Tracked Window Model
// ====================================================================

// NOTE: TrackedWindow is defined in WindowTrackerService.swift
// We reference it here for DimmingDecision but the authoritative
// definition is in the service file.

// ====================================================================
// MARK: - Region Dimming Decision
// ====================================================================

/**
 Represents a decision to dim a specific region within a window.
 
 Used by Per-Region detection mode where we find and dim
 bright AREAS within windows, not entire windows.
 */
struct RegionDimmingDecision {
    /// The window this region belongs to
    let windowID: CGWindowID
    
    /// Window owner name (for debugging)
    let windowName: String
    
    /// Process ID of the window's owner app
    let ownerPID: pid_t
    
    /// Whether THIS SPECIFIC WINDOW is the frontmost window (not just frontmost app)
    /// FIX (Jan 8, 2026): Previously we used ownerPID to determine floating level,
    /// but that made ALL windows from the frontmost app have .floating overlays.
    /// Now we track the actual frontmost window so only its overlays float.
    let isFrontmostWindow: Bool
    
    /// The region to dim (in screen coordinates)
    let regionRect: CGRect
    
    /// The brightness of this region (0.0-1.0)
    let brightness: Float
    
    /// The dim level to apply (0.0-1.0)
    let dimLevel: CGFloat
    
    /// The full window bounds (for tracking window movement in 2.2.1.14)
    /// This allows updateOverlayPositions() to calculate position deltas
    /// without requiring expensive screenshot analysis
    let windowBounds: CGRect
}
