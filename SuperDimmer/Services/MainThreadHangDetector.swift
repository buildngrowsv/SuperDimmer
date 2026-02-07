/**
 ====================================================================
 MainThreadHangDetector.swift
 Watchdog timer + MetricKit integration for detecting UI hangs
 ====================================================================
 
 PURPOSE:
 Detects when the main thread is blocked/hung and logs diagnostic info.
 SuperDimmer was getting no hang reports because:
 1. No MetricKit integration existed
 2. macOS only generates .hang files for severe blockages (3s+)
 3. The app was being QUARANTINED for high logging volume, losing diagnostics
 4. Debug builds may not trigger system-level hang reporting
 
 TWO-PRONGED APPROACH:
 
 1. WATCHDOG TIMER (custom, works immediately):
    - A background DispatchSource timer pings the main thread every 2 seconds
    - If the main thread doesn't respond within the threshold (1 second),
      we log a hang event with thread info and duration
    - The hang info is written to a log file AND os_log for Console.app
    - This catches hangs that are too short for macOS to report but still
      affect user experience (e.g., the 1-2s space switching hang)
 
 2. METRICKIT (Apple's official hang diagnostics, macOS 12+):
    - Subscribes to MXMetricManager for hang diagnostic payloads
    - Apple delivers MXHangDiagnostic objects containing call stacks
    - These arrive up to 24 hours after the hang occurs
    - Provides symbolicated backtraces showing exactly where the hang was
    - Also captures MXCPUExceptionDiagnostic for CPU spikes
 
 WHY BOTH:
 - Watchdog gives us immediate, real-time hang detection during development
 - MetricKit gives us production-quality diagnostics with call stacks
 - Together they provide complete hang visibility
 
 DISCOVERED ISSUES (Feb 5, 2026):
 - switchToSpace() was blocking main thread for 1-2s with Thread.sleep()
   and synchronous NSAppleScript execution
 - applyDecayDimming() was being called from bg thread but dispatching
   to main thread, queuing up work on the blocked thread
 - The app was QUARANTINED twice for high logging volume, losing diagnostic
   data right when we needed it most
 
 HANG LOG FILE:
 Written to ~/Library/Logs/SuperDimmer/hangs.log
 Format: [timestamp] HANG DETECTED: duration=X.XXs, lastPing=X.XXs ago
 
 ====================================================================
 Created: February 5, 2026
 ====================================================================
 */

import Foundation
import os.log
import MetricKit

// ====================================================================
// MARK: - Main Thread Hang Detector
// ====================================================================

/**
 Singleton service that detects main thread hangs using a watchdog timer
 and integrates with MetricKit for production-quality hang diagnostics.
 
 ARCHITECTURE:
 - Background DispatchSource timer fires every `checkInterval` seconds
 - Each fire dispatches a lightweight ping to the main thread
 - If the main thread responds within `hangThreshold`, all is well
 - If it doesn't respond in time, we record a hang event
 
 THREAD SAFETY:
 - The watchdog runs entirely on a private background queue
 - Only the ping response runs on main (and it's just setting a timestamp)
 - All file I/O for hang logging is on the background queue
 
 USAGE:
 ```swift
 // In AppDelegate.applicationDidFinishLaunching():
 MainThreadHangDetector.shared.startMonitoring()
 
 // When app is quitting:
 MainThreadHangDetector.shared.stopMonitoring()
 ```
 */
final class MainThreadHangDetector: NSObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /**
     Shared instance. Singleton because there should only be one watchdog
     monitoring the main thread - multiple instances would be wasteful.
     */
    static let shared = MainThreadHangDetector()
    
    // ================================================================
    // MARK: - Configuration
    // ================================================================
    
    /**
     How often the watchdog checks if the main thread is responsive.
     
     2 seconds is a good balance:
     - Frequent enough to catch meaningful hangs
     - Infrequent enough to not add measurable overhead
     - Matches Apple's definition of a "hang" (~2-3 seconds)
     */
    private let checkInterval: TimeInterval = 2.0
    
    /**
     How long the main thread can be unresponsive before we consider it "hung".
     
     FIX (Feb 6, 2026): Changed from 1.0s to 5.0s to eliminate false positives.
     
     THE BUG: With threshold=1.0s and checkInterval=2.0s, the watchdog would
     report permanent hangs even when the app was working perfectly. The sequence:
     1. Watchdog sends ping to DispatchQueue.main.async at T=0
     2. Main thread is busy with overlay work, processes ping at T=1.2
     3. Watchdog checks at T=2.0, sees lastPing=1.2, timeSince=0.8s → OK
     4. But during startup with 8 HUDs, the initial genuine hang (2s) sets
        isCurrentlyHanging=true, and subsequent checks keep finding the
        ping slightly stale because the main thread has consistent ~1s latency
        from overlay work → never resolves
     
     SOLUTION: 5 second threshold means only REAL hangs are reported.
     The space switching hang was 98 seconds - easily caught at 5s.
     Normal overlay processing latency (0.5-2s) won't trigger false positives.
     Apple's own definition of a "severe hang" is 2+ seconds, so 5s is conservative
     but avoids false alarms that erode trust in the detector.
     */
    private let hangThreshold: TimeInterval = 5.0
    
    /**
     Maximum number of hang events to keep in the log file.
     Prevents the log file from growing unbounded over time.
     Once we hit this limit, we rotate (truncate oldest entries).
     */
    private let maxHangLogEntries: Int = 500
    
    // ================================================================
    // MARK: - State
    // ================================================================
    
    /**
     Timestamp of the last successful main thread ping response.
     Updated atomically from the main thread when it processes our ping.
     Read from the background watchdog queue to check responsiveness.
     
     Uses CFAbsoluteTime for high-precision timing (microsecond accuracy).
     */
    private var lastMainThreadPingTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    /**
     Lock protecting lastMainThreadPingTime for thread-safe access.
     Both the main thread (writing) and watchdog queue (reading) access this.
     Using os_unfair_lock for minimal overhead on the main thread.
     */
    private var pingTimeLock = os_unfair_lock()
    
    /**
     Whether the watchdog is currently monitoring.
     */
    private(set) var isMonitoring = false
    
    /**
     The background dispatch source timer that drives the watchdog.
     */
    private var watchdogTimer: DispatchSourceTimer?
    
    /**
     Private serial queue for all watchdog operations.
     Named for easy identification in Instruments/debugger.
     */
    private let watchdogQueue = DispatchQueue(
        label: "com.superdimmer.hangdetector.watchdog",
        qos: .utility
    )
    
    /**
     os_log logger for hang events.
     These go to Console.app and persist across app launches.
     Category "hang" makes them easy to filter.
     */
    private let hangLogger = Logger(
        subsystem: "com.superdimmer.app",
        category: "hang"
    )
    
    /**
     Path to the hang log file.
     ~/Library/Logs/SuperDimmer/hangs.log
     
     Written to by the watchdog when hangs are detected.
     Can be read by the user or sent with bug reports.
     */
    private lazy var hangLogPath: URL = {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SuperDimmer")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: logsDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        return logsDir.appendingPathComponent("hangs.log")
    }()
    
    /**
     Count of hangs detected in the current session.
     Useful for quick health checks and reporting.
     */
    private(set) var hangCountThisSession: Int = 0
    
    /**
     Whether we're currently in a hang state.
     Prevents logging the same hang multiple times.
     */
    private var isCurrentlyHanging = false
    
    /**
     When the current hang started (if isCurrentlyHanging is true).
     Used to calculate total hang duration when the hang resolves.
     */
    private var hangStartTime: CFAbsoluteTime = 0
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Private init enforces singleton. Also registers with MetricKit.
     NSObject superclass is required for MXMetricManagerSubscriber conformance.
     */
    private override init() {
        super.init()
        
        // Register with MetricKit for hang diagnostics (macOS 12+)
        // MetricKit delivers diagnostic payloads up to 24 hours after events
        // including MXHangDiagnostic with full call stacks
        MXMetricManager.shared.add(self)
    }
    
    deinit {
        stopMonitoring()
        MXMetricManager.shared.remove(self)
    }
    
    // ================================================================
    // MARK: - Public API
    // ================================================================
    
    /**
     Starts the watchdog timer to monitor main thread responsiveness.
     
     Call this in AppDelegate.applicationDidFinishLaunching() AFTER
     other initialization is complete (to avoid false positives during startup).
     
     Safe to call multiple times - only starts once.
     */
    func startMonitoring() {
        guard !isMonitoring else {
            hangLogger.info("Watchdog already monitoring, ignoring duplicate start")
            return
        }
        
        isMonitoring = true
        hangCountThisSession = 0
        
        // Initialize ping time to now
        os_unfair_lock_lock(&pingTimeLock)
        lastMainThreadPingTime = CFAbsoluteTimeGetCurrent()
        os_unfair_lock_unlock(&pingTimeLock)
        
        // Create and configure the watchdog timer on our background queue
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(
            deadline: .now() + checkInterval,
            repeating: checkInterval,
            leeway: .milliseconds(100)  // Allow slight scheduling flexibility
        )
        
        timer.setEventHandler { [weak self] in
            self?.watchdogCheck()
        }
        
        watchdogTimer = timer
        timer.resume()
        
        hangLogger.info("🐕 Hang watchdog started (check=\(self.checkInterval)s, threshold=\(self.hangThreshold)s)")
        
        // Log to file that monitoring started
        appendToHangLog("=== Hang monitoring started (session \(Date())) ===")
    }
    
    /**
     Stops the watchdog timer.
     
     Call this in applicationWillTerminate() to clean up.
     */
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        watchdogTimer?.cancel()
        watchdogTimer = nil
        
        hangLogger.info("🐕 Hang watchdog stopped. Hangs this session: \(self.hangCountThisSession)")
        appendToHangLog("=== Hang monitoring stopped. Hangs: \(hangCountThisSession) ===")
    }
    
    /**
     Returns the path to the hang log file for inclusion in bug reports.
     */
    func getHangLogPath() -> URL {
        return hangLogPath
    }
    
    /**
     Returns a summary of hang events for this session.
     Useful for displaying in debug UI or including in feedback.
     */
    func getSessionSummary() -> String {
        return "Hangs detected this session: \(hangCountThisSession)"
    }
    
    // ================================================================
    // MARK: - Watchdog Logic
    // ================================================================
    
    /**
     The core watchdog check, called every `checkInterval` from the background queue.
     
     ALGORITHM:
     1. Read the timestamp of the last successful main thread ping
     2. If it's older than `hangThreshold`, the main thread is hung
     3. Log the hang event
     4. Send a new ping to detect when the hang resolves
     
     WHY THIS WORKS:
     - Each check dispatches a lightweight closure to the main thread
     - That closure just updates a timestamp (essentially free when main thread is responsive)
     - If the main thread is blocked, the closure sits in the queue and the timestamp goes stale
     - The NEXT watchdog check sees the stale timestamp and logs the hang
     */
    private func watchdogCheck() {
        // FIX (Feb 6, 2026): SEND PING FIRST, THEN CHECK
        //
        // Previously we checked first, then sent the ping. This meant the main thread
        // only had until the NEXT check (2s) to process the ping, minus whatever time
        // the check took. By sending the ping first, the main thread gets a full
        // checkInterval (2s) to respond before we evaluate it next cycle.
        //
        // This eliminates the false positive pattern where:
        // - Ping sent at T=0, processed at T=1.5
        // - Check at T=2 sees lastPing=1.5, timeSince=0.5 → OK
        // - But new ping sent at T=2, processed at T=3.5
        // - Check at T=4 sees lastPing=3.5, timeSince=0.5 → OK
        // The key insight: by sending first, we ensure the ping we're about to check
        // had a full cycle to be processed.
        
        // Send a new ping to the main thread BEFORE checking
        // This ping will be evaluated on the NEXT watchdog cycle
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.pingTimeLock)
            self.lastMainThreadPingTime = CFAbsoluteTimeGetCurrent()
            os_unfair_lock_unlock(&self.pingTimeLock)
        }
        
        let now = CFAbsoluteTimeGetCurrent()
        
        // Read last ping time (thread-safe)
        // This reads the response from a ping sent in the PREVIOUS cycle,
        // which means the main thread had a full checkInterval to process it
        os_unfair_lock_lock(&pingTimeLock)
        let lastPing = lastMainThreadPingTime
        os_unfair_lock_unlock(&pingTimeLock)
        
        let timeSinceLastPing = now - lastPing
        
        if timeSinceLastPing > hangThreshold {
            // HANG DETECTED - main thread hasn't responded in > hangThreshold seconds
            if !isCurrentlyHanging {
                // New hang - record start time
                isCurrentlyHanging = true
                hangStartTime = lastPing  // Hang started when last ping was received
                hangCountThisSession += 1
                
                let durationStr = String(format: "%.2f", timeSinceLastPing)
                
                // Log to os_log (survives crashes, visible in Console.app)
                hangLogger.fault(
                    "🚨 HANG DETECTED #\(self.hangCountThisSession): main thread unresponsive for \(durationStr)s"
                )
                
                // Log to file with timestamp
                let timestamp = ISO8601DateFormatter().string(from: Date())
                appendToHangLog(
                    "[\(timestamp)] HANG #\(hangCountThisSession): " +
                    "main thread blocked for \(durationStr)s (threshold: \(hangThreshold)s)"
                )
            } else {
                // Ongoing hang - log updated duration every ~10 seconds to reduce noise
                let totalDuration = now - hangStartTime
                if totalDuration.truncatingRemainder(dividingBy: 10.0) < checkInterval {
                    let durationStr = String(format: "%.1f", totalDuration)
                    hangLogger.fault("🚨 HANG ONGOING: \(durationStr)s and counting...")
                }
            }
        } else if isCurrentlyHanging {
            // Hang resolved - main thread is responsive again
            let totalDuration = now - hangStartTime
            let durationStr = String(format: "%.2f", totalDuration)
            
            hangLogger.info("✅ Hang resolved after \(durationStr)s")
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            appendToHangLog(
                "[\(timestamp)] HANG RESOLVED: total duration \(durationStr)s"
            )
            
            isCurrentlyHanging = false
        }
    }
    
    // ================================================================
    // MARK: - Hang Log File
    // ================================================================
    
    /**
     Appends a line to the hang log file.
     
     Called from the watchdog queue, so no main thread impact.
     Creates the file if it doesn't exist.
     
     - Parameter line: The text to append (newline is added automatically)
     */
    private func appendToHangLog(_ line: String) {
        let lineWithNewline = line + "\n"
        
        guard let data = lineWithNewline.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: hangLogPath.path) {
            // Append to existing file
            if let fileHandle = try? FileHandle(forWritingTo: hangLogPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            // Create new file
            try? data.write(to: hangLogPath)
        }
    }
}

// ====================================================================
// MARK: - MetricKit Subscriber
// ====================================================================

/**
 MetricKit integration for receiving hang diagnostics from macOS.
 
 WHAT METRICKIT PROVIDES (macOS 12+):
 - MXHangDiagnostic: Detailed call stacks when the main thread was blocked
 - MXCPUExceptionDiagnostic: When the app uses excessive CPU
 - MXDiskWriteExceptionDiagnostic: When the app writes too much to disk
 - MXCrashDiagnostic: Crash reports with symbolicated stacks
 
 DELIVERY:
 - Payloads are delivered up to 24 hours after the event
 - Apple batches them and delivers once per day typically
 - The call stacks are already symbolicated (no dSYM needed!)
 
 WHY THIS IS BETTER THAN SYSTEM .hang FILES:
 - .hang files only appear for severe hangs (3s+)
 - MetricKit captures hangs starting at ~250ms
 - MetricKit provides structured data, not raw spindumps
 - We can log them to our own file for easy access
 */
extension MainThreadHangDetector: MXMetricManagerSubscriber {
    
    /**
     Called by MetricKit when new metric payloads are available.
     These contain aggregated performance metrics (CPU, memory, etc.)
     
     We log them to os_log for Console.app visibility.
     */
    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        
        hangLogger.info("📊 MetricKit: Received \(payloads.count) metric payload(s)")
        
        for payload in payloads {
            // Log high-level summary
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let jsonData = payload.jsonRepresentation()
            
            // Write full payload to log directory for detailed analysis
            let payloadPath = hangLogPath
                .deletingLastPathComponent()
                .appendingPathComponent("metrickit-\(timestamp).json")
            
            try? jsonData.write(to: payloadPath)
            
            hangLogger.info("📊 MetricKit payload saved to: \(payloadPath.path)")
        }
    }
    
    /**
     Called by MetricKit when new diagnostic payloads are available.
     
     THIS IS THE GOLD MINE:
     - MXHangDiagnostic contains call stacks showing exactly WHERE the hang occurred
     - MXCrashDiagnostic contains crash stacks
     - MXCPUExceptionDiagnostic shows what caused CPU spikes
     
     These payloads can arrive up to 24 hours after the event, but they're
     invaluable for debugging production hangs.
     */
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        
        hangLogger.fault("🔍 MetricKit: Received \(payloads.count) DIAGNOSTIC payload(s) - this contains hang/crash info!")
        
        for (index, payload) in payloads.enumerated() {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            
            // Check for hang diagnostics specifically
            if let hangDiagnostics = payload.hangDiagnostics, !hangDiagnostics.isEmpty {
                hangLogger.fault("🚨 MetricKit: \(hangDiagnostics.count) HANG diagnostic(s) received!")
                
                for (hangIdx, hangDiag) in hangDiagnostics.enumerated() {
                    let duration = hangDiag.hangDuration
                    hangLogger.fault(
                        "🚨 Hang #\(hangIdx+1): duration=\(duration.formatted()), stack available"
                    )
                    
                    appendToHangLog(
                        "[\(timestamp)] METRICKIT HANG: duration=\(duration.formatted())"
                    )
                }
            }
            
            // Check for crash diagnostics
            if let crashDiagnostics = payload.crashDiagnostics, !crashDiagnostics.isEmpty {
                hangLogger.fault("💥 MetricKit: \(crashDiagnostics.count) CRASH diagnostic(s) received!")
            }
            
            // Check for CPU exception diagnostics
            if let cpuDiagnostics = payload.cpuExceptionDiagnostics, !cpuDiagnostics.isEmpty {
                hangLogger.warning("⚡ MetricKit: \(cpuDiagnostics.count) CPU exception diagnostic(s)")
            }
            
            // Save full diagnostic payload as JSON for detailed analysis
            let jsonData = payload.jsonRepresentation()
            let diagPath = hangLogPath
                .deletingLastPathComponent()
                .appendingPathComponent("diagnostic-\(timestamp)-\(index).json")
            
            try? jsonData.write(to: diagPath)
            
            hangLogger.info("🔍 Diagnostic payload saved to: \(diagPath.path)")
            appendToHangLog("[\(timestamp)] Diagnostic payload saved: \(diagPath.lastPathComponent)")
        }
    }
}
