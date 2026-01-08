/**
 ====================================================================
 WindowTrackerService.swift
 Service for tracking visible windows on screen
 ====================================================================
 
 PURPOSE:
 This service provides information about visible windows on screen.
 It's used by the DimmingCoordinator to identify windows that need
 brightness analysis and potential dimming.
 
 HOW IT WORKS:
 We use CGWindowListCopyWindowInfo to get a list of all windows.
 This is the same API used by screen sharing and recording tools.
 
 WINDOW FILTERING:
 Not all windows should be tracked:
 - Dock: Always visible but managed by system
 - Menu bar: System UI
 - Desktop: Background
 - Other system overlays: Control Center, Notification Center
 - Our own overlays: Must not dim our own dim windows!
 
 We filter windows based on:
 - Window layer (normal user windows are layer 0)
 - Owner application bundle ID
 - Window alpha (fully transparent = not visible)
 
 DATA PROVIDED:
 For each window, we track:
 - Window ID (for capture targeting)
 - Owner PID and app name
 - Bundle ID (for per-app rules)
 - Window bounds (for overlay positioning)
 - Whether it's the frontmost/active window
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import CoreGraphics

// ====================================================================
// MARK: - Window Tracker Service
// ====================================================================

/**
 Service for tracking and querying visible windows.
 
 USAGE:
 ```
 let tracker = WindowTrackerService.shared
 let windows = tracker.getVisibleWindows()
 for window in windows {
     print("Window: \(window.ownerName) - \(window.title)")
 }
 ```
 
 THREAD SAFETY:
 All methods are thread-safe and return fresh data from the system.
 Results are not cached to ensure accuracy.
 */
final class WindowTrackerService {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = WindowTrackerService()
    
    // ================================================================
    // MARK: - Configuration
    // ================================================================
    
    /**
     Bundle IDs to always exclude from tracking.
     These are system apps or our own app that shouldn't be dimmed.
     This is separate from user-configurable excluded apps.
     */
    private let systemExcludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.SystemUIServer",
        "com.superdimmer.app",  // Our own app!
    ]
    
    /**
     Gets the combined set of excluded bundle IDs (system + user-configured).
     This is computed each time to reflect the latest user settings.
     */
    private var excludedBundleIDs: Set<String> {
        var excluded = systemExcludedBundleIDs
        // Add user-configured exclusions from settings
        let userExcluded = SettingsManager.shared.excludedAppBundleIDs
        excluded.formUnion(userExcluded)
        return excluded
    }
    
    /**
     Window layers to include.
     Layer 0 = normal windows
     Layer 3 = dock
     Layer 25 = menu bar, notification center
     */
    private let includedLayers: Set<Int> = [0]
    
    /**
     Minimum window size to track (pixels).
     Very small windows are often invisible UI elements.
     */
    private let minimumWindowSize: CGFloat = 50
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        print("✓ WindowTrackerService initialized")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Gets all visible windows on screen.
     
     - Returns: Array of TrackedWindow structs for visible user windows
     
     Filters out:
     - System UI (Dock, Menu Bar, Control Center)
     - Our own overlay windows
     - Minimized/hidden windows
     - Very small windows
     */
    func getVisibleWindows() -> [TrackedWindow] {
        // Get window list from system
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            print("⚠️ WindowTrackerService: Failed to get window list")
            return []
        }
        
        // Get frontmost app for determining active window
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApp?.processIdentifier ?? 0
        
        // Get frontmost window ID (first window of frontmost app)
        var frontmostWindowID: CGWindowID = 0
        for info in windowInfoList {
            if let pid = info[kCGWindowOwnerPID] as? pid_t,
               pid == frontmostPID,
               let windowID = info[kCGWindowNumber] as? CGWindowID {
                frontmostWindowID = windowID
                break
            }
        }
        
        var windows: [TrackedWindow] = []
        
        for info in windowInfoList {
            guard let window = parseWindowInfo(info, frontmostWindowID: frontmostWindowID) else {
                continue
            }
            
            // Apply filters
            if shouldTrackWindow(window) {
                windows.append(window)
            }
        }
        
        return windows
    }
    
    /**
     Gets windows for a specific application.
     
     - Parameter bundleID: The bundle identifier of the app
     - Returns: Array of TrackedWindow structs for that app's windows
     */
    func getWindows(forApp bundleID: String) -> [TrackedWindow] {
        return getVisibleWindows().filter { $0.bundleID == bundleID }
    }
    
    /**
     Gets the frontmost (active) window.
     
     - Returns: The active window, or nil if none found
     */
    func getFrontmostWindow() -> TrackedWindow? {
        return getVisibleWindows().first { $0.isActive }
    }
    
    /**
     Gets windows sorted by z-order (frontmost first).
     
     - Returns: Array of TrackedWindow sorted by z-order
     
     Windows are naturally returned in z-order from CGWindowListCopyWindowInfo,
     so we preserve that order.
     */
    func getWindowsByZOrder() -> [TrackedWindow] {
        return getVisibleWindows()  // Already in z-order
    }
    
    /**
     Gets window info for a specific window ID.
     
     - Parameter windowID: The CGWindowID to look up
     - Returns: TrackedWindow if found, nil otherwise
     */
    func getWindow(byID windowID: CGWindowID) -> TrackedWindow? {
        return getVisibleWindows().first { $0.id == windowID }
    }
    
    /**
     Checks if a window still exists and is visible.
     
     - Parameter windowID: The CGWindowID to check
     - Returns: true if window exists and is on screen
     */
    func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return false
        }
        
        return windowInfoList.contains { info in
            info[kCGWindowNumber] as? CGWindowID == windowID
        }
    }
    
    // ================================================================
    // MARK: - Observation
    // ================================================================
    
    /**
     Observes window changes using accessibility APIs.
     
     - Parameter handler: Called when windows change
     - Returns: Token to stop observation
     
     Note: This requires Accessibility permission for full functionality.
     Without it, we fall back to polling.
     */
    func observeWindowChanges(handler: @escaping ([TrackedWindow]) -> Void) -> Any {
        // For now, we'll implement this as a timer-based poll
        // Full accessibility-based observation requires more setup
        // and is implemented in Phase 2.4
        
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let windows = self.getVisibleWindows()
            handler(windows)
        }
        
        return timer
    }
    
    /**
     Stops observing window changes.
     
     - Parameter token: The token returned by observeWindowChanges
     */
    func stopObserving(_ token: Any) {
        if let timer = token as? Timer {
            timer.invalidate()
        }
    }
    
    // ================================================================
    // MARK: - Private Helpers
    // ================================================================
    
    /**
     Parses a CGWindowListCopyWindowInfo dictionary into a TrackedWindow.
     
     - Parameters:
       - info: The window info dictionary
       - frontmostWindowID: ID of the frontmost window for isActive flag
     - Returns: TrackedWindow if parsing succeeded, nil otherwise
     */
    private func parseWindowInfo(_ info: [CFString: Any], frontmostWindowID: CGWindowID) -> TrackedWindow? {
        // Required fields
        guard let windowID = info[kCGWindowNumber] as? CGWindowID,
              let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
              let ownerName = info[kCGWindowOwnerName] as? String,
              let boundsDict = info[kCGWindowBounds] as? [String: CGFloat],
              let layer = info[kCGWindowLayer] as? Int else {
            return nil
        }
        
        // Parse bounds from Quartz coordinates (top-left origin)
        let quartzBounds = CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
        
        // IMPORTANT: Convert from Quartz coordinates (top-left origin) to
        // Cocoa/NSWindow coordinates (bottom-left origin)
        // Formula: cocoaY = screenHeight - quartzY - windowHeight
        let bounds = convertQuartzToCocoa(quartzBounds)
        
        // Optional fields
        let title = info[kCGWindowName] as? String ?? ""
        let alpha = info[kCGWindowAlpha] as? CGFloat ?? 1.0
        
        // Get bundle ID from running app
        let bundleID = getBundleID(for: ownerPID)
        
        return TrackedWindow(
            id: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bundleID: bundleID,
            bounds: bounds,
            layer: layer,
            title: title,
            isActive: windowID == frontmostWindowID,
            brightness: nil,
            alpha: alpha
        )
    }
    
    /**
     Converts a rect from Quartz screen coordinates to Cocoa screen coordinates.
     
     COORDINATE SYSTEMS:
     - Quartz (CGWindowListCopyWindowInfo): Origin at TOP-LEFT of primary display
       Y increases downward
     - Cocoa (NSWindow, NSScreen): Origin at BOTTOM-LEFT of primary display
       Y increases upward
     
     The primary screen's height is the reference for conversion.
     
     - Parameter quartzRect: Rectangle in Quartz coordinates
     - Returns: Rectangle in Cocoa coordinates
     */
    private func convertQuartzToCocoa(_ quartzRect: CGRect) -> CGRect {
        // Get the primary screen height (screen with menu bar)
        // In Cocoa, screens are ordered with primary first
        guard let primaryScreen = NSScreen.screens.first else {
            // Fallback: return as-is if no screens
            return quartzRect
        }
        
        let primaryHeight = primaryScreen.frame.height
        
        // Convert Y coordinate
        // Cocoa Y = primaryScreenHeight - quartzY - rectHeight
        let cocoaY = primaryHeight - quartzRect.origin.y - quartzRect.height
        
        return CGRect(
            x: quartzRect.origin.x,
            y: cocoaY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }
    
    /**
     Gets the bundle ID for a process.
     
     - Parameter pid: Process ID
     - Returns: Bundle identifier, or nil if not found
     */
    private func getBundleID(for pid: pid_t) -> String? {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.first { $0.processIdentifier == pid }?.bundleIdentifier
    }
    
    /**
     Determines if a window should be tracked.
     
     - Parameter window: The TrackedWindow to check
     - Returns: true if this window should be tracked for dimming
     */
    private func shouldTrackWindow(_ window: TrackedWindow) -> Bool {
        // Check layer
        guard includedLayers.contains(window.layer) else {
            return false
        }
        
        // Check bundle ID exclusion
        if let bundleID = window.bundleID,
           excludedBundleIDs.contains(bundleID) {
            return false
        }
        
        // Check minimum size
        guard window.bounds.width >= minimumWindowSize,
              window.bounds.height >= minimumWindowSize else {
            return false
        }
        
        // Check alpha (skip fully transparent)
        guard window.alpha > 0.01 else {
            return false
        }
        
        return true
    }
}

// ====================================================================
// MARK: - TrackedWindow Model
// ====================================================================

/**
 Represents a window being tracked for dimming.
 
 Contains all metadata needed to make dimming decisions and
 create overlays for the window.
 
 NOTE: This is defined here but also referenced in OverlayManager.
 In a production app, we'd put models in their own file.
 */
struct TrackedWindow: Identifiable, Equatable {
    /// Unique window ID from CGWindowListCopyWindowInfo
    let id: CGWindowID
    
    /// Process ID of the owning application
    let ownerPID: pid_t
    
    /// Application name (e.g., "Safari")
    let ownerName: String
    
    /// Bundle ID if available (e.g., "com.apple.Safari")
    let bundleID: String?
    
    /// Window frame in screen coordinates
    /// Note: Y is inverted from AppKit (0 at top in CG, 0 at bottom in AppKit)
    let bounds: CGRect
    
    /// Window layer (z-order category)
    /// 0 = normal windows, higher = system overlays
    let layer: Int
    
    /// Window title if available
    let title: String
    
    /// Whether this window belongs to the frontmost app
    var isActive: Bool
    
    /// The measured brightness of this window (0.0-1.0)
    /// Set by BrightnessAnalysisEngine during analysis cycle
    var brightness: Float?
    
    /// Window alpha/opacity (0.0-1.0)
    /// Fully transparent windows should be skipped
    let alpha: CGFloat
    
    // Equatable conformance
    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        return lhs.id == rhs.id
    }
}

// ====================================================================
// MARK: - TrackedWindow Extensions
// ====================================================================

extension TrackedWindow {
    
    /**
     Converts CG bounds to AppKit coordinate system.
     
     CG uses top-left origin, AppKit uses bottom-left.
     Call this when positioning NSWindows.
     */
    var appKitBounds: CGRect {
        guard let screen = NSScreen.main else { return bounds }
        let screenHeight = screen.frame.height
        return CGRect(
            x: bounds.origin.x,
            y: screenHeight - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }
    
    /**
     A display-friendly description of the window.
     */
    var displayName: String {
        if !title.isEmpty {
            return "\(ownerName): \(title)"
        }
        return ownerName
    }
    
    /**
     Whether this window is considered "bright" based on measured brightness.
     
     - Parameter threshold: Brightness threshold (default: from settings)
     - Returns: true if brightness exceeds threshold
     */
    func isBright(threshold: Float? = nil) -> Bool {
        guard let brightness = brightness else { return false }
        let thresh = threshold ?? Float(SettingsManager.shared.brightnessThreshold)
        return brightness > thresh
    }
}
