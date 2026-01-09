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
     */
    private init() {
        setupDisplayChangeObserver()
        setupSettingsObservers()
        setupSpaceChangeObserver()
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
     */
    private func hideOverlaysForSpaceChange() {
        guard !isHiddenForSpaceChange else { return }
        
        isHiddenForSpaceChange = true
        
        // Hide all overlay types
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
     */
    private func restoreOverlaysAfterSpaceChange() {
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
    
    /**
     Applies dimming overlays for specific bright regions within windows.
     
     This is the killer feature of SuperDimmer! Instead of dimming
     entire windows, this creates overlays for specific bright AREAS.
     
     Example: Dark mode Mail app with bright white email content
     - The window itself isn't entirely bright
     - We detect just the email content area and dim only that region
     
     OPTIMIZATION: We now REUSE overlays instead of destroy/recreate every cycle.
     This prevents Core Animation crashes ("Ignoring request to entangle context").
     
     - Parameter decisions: Array of region dimming decisions
     */
    func applyRegionDimmingDecisions(_ decisions: [RegionDimmingDecision]) {
        // Strategy: Reuse existing overlays where possible, MINIMIZE updates
        // to avoid jarring visual refreshes when user clicks windows.
        //
        // FIX (Jan 8, 2026): Only update frame/z-order if actually changed.
        // Previously, every analysis cycle called setFrame(display: true) and
        // orderAboveWindow() even when nothing changed, causing visible flashing.
        //
        // 1. If we have more overlays than decisions, hide extras
        // 2. If we have fewer overlays than decisions, create more
        // 3. Update existing overlays ONLY if position/level actually changed
        
        let existingCount = regionOverlays.count
        let neededCount = decisions.count
        
        // Get sorted list of existing overlay IDs for consistent ordering
        let existingIDs = Array(regionOverlays.keys).sorted()
        
        // Tolerance for frame comparison (pixels) - if frame moved less than this,
        // don't update to avoid micro-jitter
        let frameTolerance: CGFloat = 2.0
        
        // Update or create overlays for each decision
        var updatedCount = 0
        for (index, decision) in decisions.enumerated() {
            if index < existingIDs.count {
                // Reuse existing overlay - check if update is actually needed
                let overlayID = existingIDs[index]
                if let overlay = regionOverlays[overlayID] {
                    let currentFrame = overlay.frame
                    let newFrame = decision.regionRect
                    let currentWindowID = regionToWindowID[overlayID]
                    
                    // Check if frame has meaningfully changed
                    let frameChanged = abs(currentFrame.origin.x - newFrame.origin.x) > frameTolerance ||
                                       abs(currentFrame.origin.y - newFrame.origin.y) > frameTolerance ||
                                       abs(currentFrame.width - newFrame.width) > frameTolerance ||
                                       abs(currentFrame.height - newFrame.height) > frameTolerance
                    
                    // Check if window ID changed (overlay needs to be re-ordered)
                    let windowChanged = currentWindowID != decision.windowID
                    
                    // Only update frame if it actually changed
                    if frameChanged {
                        // FIX (Jan 8, 2026): Use updatePosition for smooth animated transitions
                        // when bright regions resize or change aspect ratio
                        overlay.updatePosition(to: newFrame, animated: true, duration: 0.3)
                        updatedCount += 1
                    }
                    
                    // HYBRID Z-ORDERING: Use .floating ONLY for the actual frontmost window
                    // FIX (Jan 8, 2026): Previously used ownerPID which made ALL windows
                    // from the frontmost app have .floating overlays. Now we use
                    // isFrontmostWindow which is set per-window, not per-app.
                    let targetLevel: NSWindow.Level = decision.isFrontmostWindow ? .floating : .normal
                    
                    if overlay.level != targetLevel || windowChanged {
                        overlay.level = targetLevel
                        if decision.isFrontmostWindow {
                            // Frontmost window: just bring to front (stays above all normal windows)
                            overlay.orderFront(nil)
                        } else {
                            // Background window: position relative to target window
                            overlay.orderAboveWindow(decision.windowID)
                        }
                    }
                    
                    // Update mappings
                    regionToWindowID[overlayID] = decision.windowID
                    regionToOwnerPID[overlayID] = decision.ownerPID
                    
                    // Always update dim level with smooth animation
                    // FIX (Jan 8, 2026): Use 0.35s duration for smooth active/inactive
                    // transitions when user switches between windows
                    overlay.setDimLevel(decision.dimLevel, animated: true, duration: 0.35)
                    
                    // Make sure it's visible (in case it was hidden previously)
                    if !overlay.isVisible {
                        if decision.isFrontmostWindow {
                            overlay.orderFront(nil)
                        } else {
                            overlay.orderAboveWindow(decision.windowID)
                        }
                    }
                }
            } else {
                // Need to create a new overlay
                createRegionOverlay(for: decision)
                updatedCount += 1
            }
        }
        
        // Hide (don't destroy!) extra overlays we don't need right now
        if existingCount > neededCount {
            for i in neededCount..<existingCount {
                let overlayID = existingIDs[i]
                regionOverlays[overlayID]?.orderOut(nil)
            }
        }
        
        if decisions.count > 0 {
            isActive = true
            // Only log if something actually changed, to reduce console spam
            if updatedCount > 0 {
                print("🎯 Applied \(decisions.count) region overlays (updated: \(updatedCount))")
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
        
        // Fade in to target dim level with smooth animation
        overlay.setDimLevel(decision.dimLevel, animated: true, duration: 0.3)
    }
    
    /**
     Removes all region overlays.
     
     Called before applying new region decisions, or when
     switching away from per-region mode.
     
     FIX (Jan 8, 2026): Uses safeCloseOverlay to prevent EXC_BAD_ACCESS crash.
     The crash was caused by race conditions where overlays were closed
     while Core Animation was still rendering.
     */
    private func removeAllRegionOverlays() {
        // Capture overlays to close
        let overlaysToClose = Array(regionOverlays.values)
        
        // Clear our references immediately
        regionOverlays.removeAll()
        regionToWindowID.removeAll()
        regionToOwnerPID.removeAll()
        regionCounter = 0
        
        // Use safe close for each overlay
        for overlay in overlaysToClose {
            safeCloseOverlay(overlay)
        }
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
     
     FIX (Jan 8, 2026): Completely reworked to prevent EXC_BAD_ACCESS crash.
     The crash was caused by race conditions:
     1. Multiple analysis cycles could overlap (timer + mouse clicks)
     2. Overlay was removed from dictionary, then close() scheduled with delay
     3. Core Animation was still animating when close() was called
     4. objc_release crashed on deallocated CA layer
     
     Solution:
     - Use weak references in async close blocks
     - Flush CA transactions before closing
     - Track overlays being closed to prevent double-close
     
     - Parameter decisions: Array of decay dimming decisions for all windows
     */
    func applyDecayDimming(_ decisions: [DecayDimmingDecision]) {
        // CRITICAL: Run synchronously on main thread to prevent race conditions
        // Don't use async dispatch - the caller already handles threading
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { [weak self] in
                self?.applyDecayDimming(decisions)
            }
            return
        }
        
        // Track which windows have decisions
        var decisionWindowIDs = Set<CGWindowID>()
        
        for decision in decisions {
            decisionWindowIDs.insert(decision.windowID)
            
            // Skip active windows - they don't get decay overlays
            if decision.isActive || decision.decayDimLevel <= 0 {
                // Remove existing decay overlay if any
                if let overlay = self.decayOverlays.removeValue(forKey: decision.windowID) {
                    safeCloseOverlay(overlay)
                }
                continue
            }
            
            // Update existing or create new decay overlay
            if let existing = self.decayOverlays[decision.windowID] {
                // Update position and dim level
                // FIX (Jan 8, 2026): Enable animation for decay overlays too for smooth
                // transitions when windows resize. Since analysis runs ~1x/sec, animation
                // won't cause "lag behind" issues like it would for drag operations.
                existing.updatePosition(to: decision.windowBounds, animated: true, duration: 0.3)
                existing.setDimLevel(decision.decayDimLevel, animated: true)
                existing.orderAboveWindow(decision.windowID)
            } else {
                // Create new decay overlay using factory method
                // FIX (Jan 8, 2026): Start at 0 opacity and FADE IN to target level
                // This prevents the jarring "pop-in" effect when decay overlays appear
                let overlayID = "decay-\(decision.windowID)"
                let overlay = DimOverlayWindow.create(
                    frame: decision.windowBounds,
                    dimLevel: 0.0,  // Start invisible
                    id: overlayID
                )
                overlay.level = .normal
                overlay.orderFront(nil)
                overlay.orderAboveWindow(decision.windowID)
                
                self.decayOverlays[decision.windowID] = overlay
                
                // Fade in to target dim level with smooth animation
                overlay.setDimLevel(decision.decayDimLevel, animated: true, duration: 0.3)
            }
        }
        
        // Remove decay overlays for windows that no longer exist
        let staleIDs = Set(self.decayOverlays.keys).subtracting(decisionWindowIDs)
        for staleID in staleIDs {
            if let overlay = self.decayOverlays.removeValue(forKey: staleID) {
                safeCloseOverlay(overlay)
            }
        }
    }
    
    /**
     Safely closes an overlay window, ensuring Core Animation has finished.
     
     FIX (Jan 8, 2026): Added to prevent EXC_BAD_ACCESS crash.
     The crash happened when close() was called while Core Animation
     was still animating the overlay. This method:
     1. Flushes any pending CA transactions
     2. Hides the window first
     3. Uses weak reference in delayed close to prevent over-retain
     4. Gives CA time to finish before actually closing
     
     - Parameter overlay: The overlay window to close
     */
    private func safeCloseOverlay(_ overlay: DimOverlayWindow) {
        // Step 1: Flush CA transactions to ensure animations are committed
        CATransaction.flush()
        
        // Step 2: Hide immediately
        overlay.orderOut(nil)
        
        // Step 3: Delayed close with WEAK reference
        // If overlay is already deallocated by the time this runs, it's fine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak overlay] in
            guard let overlay = overlay else {
                // Already deallocated - nothing to do
                return
            }
            
            // Flush again before close
            CATransaction.flush()
            overlay.close()
        }
    }
    
    /**
     Removes all decay overlays.
     
     FIX (Jan 8, 2026): Uses safeCloseOverlay to prevent EXC_BAD_ACCESS crash.
     */
    private func removeAllDecayOverlays() {
        let overlaysToClose = Array(decayOverlays.values)
        decayOverlays.removeAll()
        
        // Use safe close for each overlay
        for overlay in overlaysToClose {
            safeCloseOverlay(overlay)
        }
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
        // Remove window overlays
        for (_, overlay) in windowOverlays {
            overlay.close()
        }
        windowOverlays.removeAll()
        
        // Remove display overlays
        for (_, overlay) in displayOverlays {
            overlay.close()
        }
        displayOverlays.removeAll()
        
        // Remove region overlays (per-region mode)
        removeAllRegionOverlays()
        
        // Remove decay overlays
        removeAllDecayOverlays()
        
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
    
    /**
     Immediately re-orders all region overlays to be above their target windows.
     
     FIX (Jan 8, 2026): Called when window focus changes to prevent overlays
     from appearing behind windows after the user clicks. When a window is
     clicked and brought to front, its z-order changes but our overlays stay
     at their old position. This method immediately repositions all overlays.
     
     This is a fast operation - it just changes z-order, doesn't redraw anything.
     */
    func reorderAllRegionOverlays() {
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
     */
    func updateOverlayLevelsForFrontmostApp() {
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
        let disconnectedDisplays = Set(displayOverlays.keys).subtracting(currentDisplayIDs)
        for displayID in disconnectedDisplays {
            displayOverlays[displayID]?.close()
            displayOverlays.removeValue(forKey: displayID)
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
}
