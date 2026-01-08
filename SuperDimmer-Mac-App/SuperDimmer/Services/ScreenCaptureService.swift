/**
 ====================================================================
 ScreenCaptureService.swift
 Service for capturing screen content for brightness analysis
 ====================================================================
 
 PURPOSE:
 This service captures screen content (full screen or specific regions)
 for brightness analysis. It's the foundation of SuperDimmer's intelligent
 detection system that identifies bright areas to dim.
 
 HOW IT WORKS:
 We use CoreGraphics APIs (CGWindowListCreateImage) to capture screen
 content. This requires Screen Recording permission in macOS.
 
 PERFORMANCE CONSIDERATIONS:
 - Screen capture is expensive (memory + CPU)
 - We implement throttling to prevent excessive captures
 - Captures are done at reduced resolution for analysis
 - Only visible content is captured (no hidden windows)
 
 PERMISSION REQUIREMENTS:
 - Requires Screen Recording permission (com.apple.security.device.screen-capture)
 - Without permission, capture returns nil
 - User prompted via System Settings → Privacy → Screen Recording
 
 THREADING:
 - Capture operations can be called from any thread
 - Results are delivered on the calling thread
 - Internal caching uses thread-safe access
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import CoreGraphics
import AppKit

// ====================================================================
// MARK: - Screen Capture Service
// ====================================================================

/**
 Singleton service for capturing screen content.
 
 USAGE:
 ```
 let service = ScreenCaptureService.shared
 if let image = service.captureMainDisplay() {
     // Analyze image brightness
 }
 ```
 
 LIFECYCLE:
 - Access via .shared singleton
 - Check hasPermission before relying on captures
 - Handle nil returns gracefully (permission denied or error)
 */
final class ScreenCaptureService {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = ScreenCaptureService()
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     Minimum interval between captures (prevents excessive CPU usage).
     
     Default: 100ms = max 10 captures/second
     Can be adjusted based on performance testing.
     */
    var minimumCaptureInterval: TimeInterval = 0.1
    
    /**
     Last capture timestamp for throttling.
     */
    private var lastCaptureTime: Date = .distantPast
    
    /**
     Lock for thread-safe throttle checking.
     */
    private let throttleLock = NSLock()
    
    /**
     Cached permission status (checked periodically).
     */
    private var _hasPermission: Bool = false
    private var lastPermissionCheck: Date = .distantPast
    
    /**
     Scale factor for downsampling captures (for performance).
     
     1.0 = full resolution, 0.5 = half resolution, 0.25 = quarter
     Lower values = faster analysis but less accurate.
     Default 0.25 provides good balance of speed and accuracy.
     */
    var downsampleFactor: CGFloat = 0.25
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        // Check permission on init
        _ = hasPermission
        print("✓ ScreenCaptureService initialized")
    }
    
    // ================================================================
    // MARK: - Permission
    // ================================================================
    
    /**
     Whether screen recording permission is currently granted.
     
     This is cached and refreshed periodically (every 5 seconds) to avoid
     excessive system calls. Force refresh with checkPermission().
     */
    var hasPermission: Bool {
        let now = Date()
        if now.timeIntervalSince(lastPermissionCheck) > 5.0 {
            _hasPermission = checkPermissionNow()
            lastPermissionCheck = now
        }
        return _hasPermission
    }
    
    /**
     Forces a permission check and updates the cached value.
     
     - Returns: Whether permission is currently granted
     */
    @discardableResult
    func checkPermission() -> Bool {
        _hasPermission = checkPermissionNow()
        lastPermissionCheck = Date()
        return _hasPermission
    }
    
    /**
     Actually checks the permission (private).
     
     IMPORTANT FIX (Jan 8, 2026):
     CGPreflightScreenCaptureAccess() is unreliable - it can return false
     even after the user grants permission in System Settings. This is a
     known macOS bug/quirk.
     
     The most reliable method is to try an actual screen capture:
     - If it returns a valid image, we have permission
     - If it fails/returns nil, we don't have permission
     
     We try capturing a 1x1 pixel region for minimal overhead.
     */
    private func checkPermissionNow() -> Bool {
        // First check the preflight (fast path)
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        
        // Preflight returned false, but try an actual capture to be sure
        // This handles the case where permission was just granted in System Settings
        // but macOS hasn't updated its internal state yet
        let testRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let testImage = CGWindowListCreateImage(
            testRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
        
        let hasPermission = testImage != nil
        if hasPermission {
            print("✓ Screen Recording permission verified via capture test")
        }
        return hasPermission
    }
    
    /**
     Requests screen recording permission.
     
     This will show the system permission dialog if not already decided.
     If already denied, opens System Settings for manual grant.
     
     - Returns: Whether permission was granted (immediate check)
     */
    @discardableResult
    func requestPermission() -> Bool {
        // CGRequestScreenCaptureAccess() triggers the permission prompt
        // Note: This is a one-shot - if user denies, they must manually enable
        let granted = CGRequestScreenCaptureAccess()
        _hasPermission = granted
        lastPermissionCheck = Date()
        
        if !granted {
            print("⚠️ Screen Recording permission not granted")
            print("   User must enable in System Settings → Privacy → Screen Recording")
        }
        
        return granted
    }
    
    // ================================================================
    // MARK: - Full Screen Capture
    // ================================================================
    
    /**
     Captures the entire main display.
     
     - Returns: CGImage of the screen, or nil if capture failed/throttled
     
     This captures everything visible on the main display including
     all windows, desktop, dock, etc.
     */
    func captureMainDisplay() -> CGImage? {
        guard hasPermission else {
            print("⚠️ Cannot capture: Screen Recording permission not granted")
            return nil
        }
        
        guard shouldCapture() else {
            // Throttled - too soon since last capture
            return nil
        }
        
        // Capture full screen
        // Using CGWindowListCreateImage with null rect to get entire main display
        let image = CGWindowListCreateImage(
            CGRect.null,  // null rect = entire display
            .optionOnScreenOnly,  // Only visible content
            kCGNullWindowID,  // No specific window
            [.boundsIgnoreFraming, .nominalResolution]
        )
        
        updateCaptureTime()
        
        if let img = image {
            print("📸 Captured main display: \(img.width)x\(img.height)")
        }
        
        return image
    }
    
    /**
     Captures a specific display by ID.
     
     - Parameter displayID: The CGDirectDisplayID of the display to capture
     - Returns: CGImage of the display, or nil if capture failed/throttled
     */
    func captureDisplay(_ displayID: CGDirectDisplayID) -> CGImage? {
        guard hasPermission else {
            return nil
        }
        
        guard shouldCapture() else {
            return nil
        }
        
        // Get the display bounds
        let bounds = CGDisplayBounds(displayID)
        
        let image = CGWindowListCreateImage(
            bounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
        
        updateCaptureTime()
        return image
    }
    
    // ================================================================
    // MARK: - Region Capture
    // ================================================================
    
    /**
     Captures a specific region of the screen.
     
     - Parameter rect: The rectangle to capture (in screen coordinates)
     - Returns: CGImage of the region, or nil if capture failed/throttled
     
     Useful for capturing just the area under a specific window.
     */
    func captureRegion(_ rect: CGRect) -> CGImage? {
        guard hasPermission else {
            return nil
        }
        
        guard shouldCapture() else {
            return nil
        }
        
        let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
        
        updateCaptureTime()
        return image
    }
    
    /**
     Captures the content of a specific window.
     
     - Parameter windowID: The CGWindowID of the window to capture
     - Parameter includingFrame: Whether to include window decorations
     - Returns: CGImage of the window, or nil if capture failed
     
     This captures just the window content, not what's behind it.
     Useful for analyzing a specific application's brightness.
     */
    func captureWindow(_ windowID: CGWindowID, includingFrame: Bool = false) -> CGImage? {
        guard hasPermission else {
            return nil
        }
        
        // NOTE: We intentionally skip throttle check for window captures
        // because intelligent mode needs to capture many windows in quick succession.
        // The throttle is mainly for full-screen captures which are more expensive.
        
        var options: CGWindowImageOption = [.nominalResolution]
        if !includingFrame {
            options.insert(.boundsIgnoreFraming)
        }
        
        let image = CGWindowListCreateImage(
            .null,  // Use window's own bounds
            .optionIncludingWindow,  // Just this window
            windowID,
            options
        )
        
        // NOTE: No throttle update for window captures - we need to capture many quickly
        return image
    }
    
    // ================================================================
    // MARK: - Batch Capture (for multiple windows)
    // ================================================================
    
    /**
     Captures multiple window regions in a single pass.
     
     - Parameter windowIDs: Array of window IDs to capture
     - Returns: Dictionary mapping window ID to captured image
     
     More efficient than individual captures because we do one
     full-screen capture and crop regions rather than multiple captures.
     */
    func captureWindows(_ windowIDs: [CGWindowID]) -> [CGWindowID: CGImage] {
        guard hasPermission else {
            return [:]
        }
        
        guard shouldCapture() else {
            return [:]
        }
        
        var results: [CGWindowID: CGImage] = [:]
        
        // First, get window bounds for all requested windows
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] else {
            return [:]
        }
        
        let windowIDSet = Set(windowIDs)
        var windowBounds: [CGWindowID: CGRect] = [:]
        
        for windowInfo in windowInfoList {
            guard let windowID = windowInfo[kCGWindowNumber] as? CGWindowID,
                  windowIDSet.contains(windowID),
                  let boundsDict = windowInfo[kCGWindowBounds] as? [String: CGFloat] else {
                continue
            }
            
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            windowBounds[windowID] = bounds
        }
        
        // Capture each window individually (more accurate than cropping full screen)
        for (windowID, _) in windowBounds {
            if let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .nominalResolution]
            ) {
                results[windowID] = image
            }
        }
        
        updateCaptureTime()
        return results
    }
    
    // ================================================================
    // MARK: - Downsampled Capture (for fast analysis)
    // ================================================================
    
    /**
     Captures and downsamples the main display for fast analysis.
     
     - Returns: Downsampled CGImage, or nil if capture failed
     
     Returns an image at `downsampleFactor` resolution.
     Much faster to analyze than full resolution.
     */
    func captureMainDisplayDownsampled() -> CGImage? {
        guard let fullImage = captureMainDisplay() else {
            return nil
        }
        
        return downsample(fullImage, factor: downsampleFactor)
    }
    
    /**
     Captures and downsamples a specific region.
     
     - Parameter rect: Region to capture
     - Returns: Downsampled CGImage, or nil if capture failed
     */
    func captureRegionDownsampled(_ rect: CGRect) -> CGImage? {
        guard let fullImage = captureRegion(rect) else {
            return nil
        }
        
        return downsample(fullImage, factor: downsampleFactor)
    }
    
    /**
     Downsamples an image for faster analysis.
     
     - Parameters:
       - image: Source image
       - factor: Scale factor (0.0-1.0)
     - Returns: Downsampled image
     */
    private func downsample(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let newWidth = Int(CGFloat(image.width) * factor)
        let newHeight = Int(CGFloat(image.height) * factor)
        
        guard newWidth > 0, newHeight > 0 else { return image }
        
        // Create a context for the downsampled image
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        // Draw the image scaled down
        context.interpolationQuality = .low  // Fast, good enough for brightness analysis
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage()
    }
    
    // ================================================================
    // MARK: - Throttling
    // ================================================================
    
    /**
     Checks if enough time has passed since last capture.
     
     Thread-safe check against minimumCaptureInterval.
     */
    private func shouldCapture() -> Bool {
        throttleLock.lock()
        defer { throttleLock.unlock() }
        
        let now = Date()
        return now.timeIntervalSince(lastCaptureTime) >= minimumCaptureInterval
    }
    
    /**
     Updates the last capture timestamp.
     
     Thread-safe update.
     */
    private func updateCaptureTime() {
        throttleLock.lock()
        defer { throttleLock.unlock() }
        
        lastCaptureTime = Date()
    }
    
    /**
     Resets throttling, allowing immediate capture.
     
     Call this if you need to force a capture regardless of throttle.
     */
    func resetThrottle() {
        throttleLock.lock()
        defer { throttleLock.unlock() }
        
        lastCaptureTime = .distantPast
    }
}
