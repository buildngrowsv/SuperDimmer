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
     Private initializer enforces singleton pattern.
     Sets up observers for settings and display changes.
     */
    private init() {
        setupDisplayChangeObserver()
        setupSettingsObservers()
        print("✓ OverlayManager initialized")
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
        print("📺 Creating NEW full-screen overlay for \(screen.localizedName)")
        print("📺 Screen frame: \(screen.frame)")
        let overlay = DimOverlayWindow.create(
            frame: screen.frame,
            dimLevel: dimLevel,
            id: "display-\(displayID)"
        )
        
        // Make sure the overlay is visible
        // Note: Don't use makeKeyAndOrderFront because canBecomeKey returns false
        overlay.orderFrontRegardless()  // Force to front
        
        // Store reference
        displayOverlays[displayID] = overlay
        
        print("📺 ✓ Created full-screen overlay for display \(displayID)")
        print("📺   Overlay frame: \(overlay.frame)")
        print("📺   Overlay isVisible: \(overlay.isVisible)")
        print("📺   Overlay level: \(overlay.level.rawValue)")
        print("📺   Overlay dimLevel: \(overlay.dimLevel)")
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
            // Update existing overlay
            existing.updatePosition(to: bounds)
            existing.setDimLevel(dimLevel, animated: true, duration: 0.15)
        } else {
            // Create new overlay using factory method
            let overlay = DimOverlayWindow.create(
                frame: bounds,
                dimLevel: dimLevel,
                id: "window-\(windowID)"
            )
            overlay.orderFrontRegardless()
            windowOverlays[windowID] = overlay
            print("🪟 Created overlay for window \(windowID)")
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
        // Strategy: Reuse existing overlays where possible
        // 1. If we have more overlays than decisions, hide extras
        // 2. If we have fewer overlays than decisions, create more
        // 3. Update existing overlays with new positions/levels
        
        let existingCount = regionOverlays.count
        let neededCount = decisions.count
        
        // Get edge blur settings (check every time for live updates)
        let edgeBlurEnabled = SettingsManager.shared.edgeBlurEnabled
        let edgeBlurRadius = CGFloat(SettingsManager.shared.edgeBlurRadius)
        
        // Get sorted list of existing overlay IDs for consistent ordering
        let existingIDs = Array(regionOverlays.keys).sorted()
        
        // Update or create overlays for each decision
        for (index, decision) in decisions.enumerated() {
            if index < existingIDs.count {
                // Reuse existing overlay - just update position and level
                let overlayID = existingIDs[index]
                if let overlay = regionOverlays[overlayID] {
                    overlay.setFrame(decision.regionRect, display: true)
                    overlay.setDimLevel(decision.dimLevel, animated: false)
                    // Update edge blur setting (in case user toggled it)
                    overlay.setEdgeBlur(enabled: edgeBlurEnabled, radius: edgeBlurRadius)
                    overlay.orderFront(nil)
                }
            } else {
                // Need to create a new overlay
                createRegionOverlay(for: decision)
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
            print("🎯 Applied \(decisions.count) region overlays (reused: \(min(existingCount, neededCount)), new: \(max(0, neededCount - existingCount)))")
        }
    }
    
    /**
     Creates an overlay for a specific bright region.
     
     - Parameter decision: The region dimming decision
     */
    private func createRegionOverlay(for decision: RegionDimmingDecision) {
        // Generate unique ID for this region
        regionCounter += 1
        let regionID = "region-\(decision.windowID)-\(regionCounter)"
        
        // Debug: Log the region details to our file-based debug log
        // (print/NSLog don't reliably appear in console for background apps)
        let logMessage = """
        🎯 Creating overlay: \(regionID)
           - Window: \(decision.windowName)
           - Rect: \(decision.regionRect)
           - Brightness: \(decision.brightness)
           - DimLevel: \(decision.dimLevel)
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
        let overlay = DimOverlayWindow.create(
            frame: decision.regionRect,
            dimLevel: decision.dimLevel,
            id: regionID
        )
        
        // Show the overlay
        overlay.orderFrontRegardless()
        
        // Store reference
        regionOverlays[regionID] = overlay
    }
    
    /**
     Removes all region overlays.
     
     Called before applying new region decisions, or when
     switching away from per-region mode.
     
     IMPORTANT: We defer the actual close() to the next run loop iteration
     to avoid crashes from Core Animation still rendering.
     The "Ignoring request to entangle context after pre-commit" error
     happens when we close windows while CA is mid-transaction.
     */
    private func removeAllRegionOverlays() {
        // Capture overlays to close
        let overlaysToClose = Array(regionOverlays.values)
        
        // Clear our references immediately
        regionOverlays.removeAll()
        regionCounter = 0
        
        // Defer actual close to next run loop to let Core Animation finish
        // This prevents EXC_BAD_ACCESS crashes
        DispatchQueue.main.async {
            for overlay in overlaysToClose {
                overlay.orderOut(nil)  // Hide first
            }
            // Give CA a moment to finish, then close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                for overlay in overlaysToClose {
                    overlay.close()
                }
            }
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
        isActive = false
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
    
    /// The region to dim (in screen coordinates)
    let regionRect: CGRect
    
    /// The brightness of this region (0.0-1.0)
    let brightness: Float
    
    /// The dim level to apply (0.0-1.0)
    let dimLevel: CGFloat
}
