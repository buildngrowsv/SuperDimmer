/**
====================================================================
AppLogger.swift
Centralized logging system for SuperDimmer using os_log
====================================================================

PURPOSE:
Provides structured logging that integrates with macOS Console.app
for production debugging. Unlike print(), these logs:
- Persist to system logs (survive crashes/freezes)
- Are filterable by category
- Include timestamps and thread info
- Have minimal performance overhead
- Can be viewed in Console.app

USAGE:
```swift
AppLogger.overlay.info("Created overlay for window \(windowID)")
AppLogger.overlay.debug("Overlay count: \(count)")
AppLogger.overlay.warning("High overlay count: \(count)")
AppLogger.overlay.error("Failed to create overlay: \(error)")
```

CATEGORIES:
- overlay: Overlay creation/destruction
- dimming: Dimming calculations and decisions
- capture: Screen capture operations
- tracking: Window/app tracking
- performance: Performance measurements
- lifecycle: App lifecycle events

VIEWING LOGS:
In Console.app:
1. Open Console.app
2. Select your Mac in sidebar
3. Search: subsystem:com.superdimmer.app
4. Or filter by category: category:overlay

In Terminal:
```bash
# Stream live logs
log stream --predicate 'subsystem == "com.superdimmer.app"'

# Show last 5 minutes
log show --predicate 'subsystem == "com.superdimmer.app"' --last 5m

# Filter by category
log show --predicate 'subsystem == "com.superdimmer.app" AND category == "overlay"' --last 5m
```

PERFORMANCE:
os_log is highly optimized:
- Debug logs are stripped in release builds
- Info/warning/error have minimal overhead
- No string formatting unless log is actually captured
- Async writing to disk

====================================================================
Created: January 26, 2026
Version: 1.0.0
====================================================================
*/

import Foundation
import os.log

/**
Centralized logging system for SuperDimmer.

This uses Apple's Unified Logging System (os_log) which provides:
- Structured logging with categories
- Automatic persistence to system logs
- Integration with Console.app and Instruments
- Minimal performance overhead
- Privacy-preserving (can redact sensitive data)

Each category represents a major subsystem of the app.
*/
struct AppLogger {
    
    // ================================================================
    // MARK: - Subsystem
    // ================================================================
    
    /**
     The subsystem identifier for SuperDimmer.
     
     This is used to filter logs in Console.app and command-line tools.
     Use your actual bundle identifier in production.
     */
    private static let subsystem = "com.superdimmer.app"
    
    // ================================================================
    // MARK: - Category Loggers
    // ================================================================
    
    /**
     Overlay management logging.
     
     Use for:
     - Overlay creation/destruction
     - Overlay state changes
     - Overlay count tracking
     - Overlay cleanup operations
     */
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    
    /**
     Dimming calculations and decisions.
     
     Use for:
     - Brightness analysis
     - Dimming level calculations
     - Mode changes (Auto/Intelligent/Manual)
     - Dimming application
     */
    static let dimming = Logger(subsystem: subsystem, category: "dimming")
    
    /**
     Screen capture operations.
     
     Use for:
     - Screen capture requests
     - Capture failures
     - Permission issues
     - Performance metrics
     */
    static let capture = Logger(subsystem: subsystem, category: "capture")
    
    /**
     Window and app tracking.
     
     Use for:
     - Window list updates
     - Window state changes
     - App activation/deactivation
     - Space changes
     */
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
    
    /**
     Performance measurements.
     
     Use for:
     - Operation timing
     - Resource usage
     - Throttling events
     - Performance warnings
     */
    static let performance = Logger(subsystem: subsystem, category: "performance")
    
    /**
     App lifecycle events.
     
     Use for:
     - App launch/termination
     - Service initialization
     - Configuration changes
     - Critical state changes
     */
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    
    /**
     Idle/activity tracking.
     
     Use for:
     - User idle detection
     - Activity state changes
     - Timer pause/resume
     - Idle threshold events
     */
    static let activity = Logger(subsystem: subsystem, category: "activity")
    
    /**
     Auto-hide and auto-minimize features.
     
     Use for:
     - Auto-hide decisions
     - Window minimization
     - Timer management
     - Accumulation tracking
     */
    static let autoHide = Logger(subsystem: subsystem, category: "autoHide")
    
    // ================================================================
    // MARK: - Signposting (Performance Intervals)
    // ================================================================
    
    /**
     Signposter for performance interval tracking.
     
     Use to measure time intervals:
     ```swift
     let signpostID = AppLogger.signposter.makeSignpostID()
     let state = AppLogger.signposter.beginInterval("operationName", id: signpostID)
     // ... do work ...
     AppLogger.signposter.endInterval("operationName", state)
     ```
     
     View in Instruments or Console.app to see timing data.
     */
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
    
    // ================================================================
    // MARK: - Helper Methods
    // ================================================================
    
    /**
     Logs a performance interval with automatic timing.
     
     Usage:
     ```swift
     AppLogger.measurePerformance("applyDecayDimming") {
         // ... code to measure ...
     }
     ```
     
     - Parameters:
       - name: Name of the operation
       - operation: Closure to execute and measure
     - Returns: Result of the operation
     */
    static func measurePerformance<T>(_ name: StaticString, operation: () throws -> T) rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        defer {
            signposter.endInterval(name, state)
        }
        return try operation()
    }
    
    /**
     Logs a performance interval with automatic timing (async version).
     
     Usage:
     ```swift
     await AppLogger.measurePerformanceAsync("captureScreen") {
         await screenCapture()
     }
     ```
     
     - Parameters:
       - name: Name of the operation
       - operation: Async closure to execute and measure
     - Returns: Result of the operation
     */
    static func measurePerformanceAsync<T>(_ name: StaticString, operation: () async throws -> T) async rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: signpostID)
        defer {
            signposter.endInterval(name, state)
        }
        return try await operation()
    }
}

// ================================================================
// MARK: - Usage Examples
// ================================================================

/*
 
 EXAMPLE 1: Basic Logging
 -------------------------
 
 import os.log
 
 func createOverlay(for windowID: CGWindowID) {
     AppLogger.overlay.info("Creating overlay for window \(windowID)")
     
     // ... create overlay ...
     
     AppLogger.overlay.debug("Overlay created successfully")
 }
 
 
 EXAMPLE 2: Performance Measurement
 ----------------------------------
 
 func applyDecayDimming(_ decisions: [DecayDimmingDecision]) {
     AppLogger.measurePerformance("applyDecayDimming") {
         AppLogger.dimming.info("Applying decay dimming to \(decisions.count) windows")
         
         // ... apply dimming ...
         
         AppLogger.dimming.debug("Decay dimming applied, overlay count: \(overlays.count)")
     }
 }
 
 
 EXAMPLE 3: Error Logging
 ------------------------
 
 func captureScreen() -> CGImage? {
     guard hasPermission else {
         AppLogger.capture.error("Screen capture failed: Permission denied")
         return nil
     }
     
     // ... capture ...
 }
 
 
 EXAMPLE 4: Warning for Unusual Conditions
 -----------------------------------------
 
 func checkOverlayCount() {
     let count = overlays.count
     if count > 50 {
         AppLogger.overlay.warning("High overlay count detected: \(count)")
     }
 }
 
 
 EXAMPLE 5: Manual Signposting
 -----------------------------
 
 func complexOperation() {
     let signpostID = AppLogger.signposter.makeSignpostID()
     let state = AppLogger.signposter.beginInterval("complexOperation", id: signpostID)
     
     // ... do work ...
     
     AppLogger.signposter.endInterval("complexOperation", state)
 }
 
 
 VIEWING LOGS:
 ------------
 
 # In Console.app:
 1. Open Console.app
 2. Select your Mac in sidebar
 3. Search bar: subsystem:com.superdimmer.app
 4. Or: category:overlay
 
 # In Terminal:
 # Stream live logs
 log stream --predicate 'subsystem == "com.superdimmer.app"'
 
 # Show last 5 minutes
 log show --predicate 'subsystem == "com.superdimmer.app"' --last 5m
 
 # Filter by category
 log show --predicate 'subsystem == "com.superdimmer.app" AND category == "overlay"' --last 5m
 
 # Show only errors/warnings
 log show --predicate 'subsystem == "com.superdimmer.app" AND messageType >= "Error"' --last 5m
 
 */
