/**
 ====================================================================
 DimmingCoordinator.swift
 Main controller orchestrating the dimming pipeline
 ====================================================================
 
 PURPOSE:
 This is the "brain" of SuperDimmer. It coordinates all the pieces:
 - Window tracking (what windows are visible)
 - Brightness analysis (which windows are bright)
 - Overlay management (creating/updating dim overlays)
 
 The coordinator runs a loop that:
 1. Gets list of visible windows
 2. Analyzes brightness of each window
 3. Makes dimming decisions based on threshold and rules
 4. Updates overlays accordingly
 
 ARCHITECTURE:
 The coordinator follows a clean architecture pattern:
 - Services provide data (WindowTrackerService, ScreenCaptureService)
 - Engine processes data (BrightnessAnalysisEngine)
 - Manager handles output (OverlayManager)
 - Coordinator orchestrates the flow
 
 This separation allows testing each component independently and
 makes the system easier to understand and maintain.
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import Combine

// MARK: - Debug Logging
// Writing to a file for reliable debugging since NSLog/print don't always appear
fileprivate func debugLog(_ message: String) {
    let logFile = "/tmp/superdimmer_debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
}

// ====================================================================
// MARK: - Dimming Coordinator
// ====================================================================

/**
 Orchestrates the brightness detection and dimming overlay system.
 
 LIFECYCLE:
 1. Create instance (via AppDelegate after permission granted)
 2. Call start() to begin the analysis loop
 3. Loop runs continuously at configured interval
 4. Call stop() when done (app quit or feature disabled)
 
 THREADING:
 The coordinator does analysis work on a background queue but
 updates UI (overlays) on the main queue.
 */
final class DimmingCoordinator: ObservableObject {
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     Timer that fires the brightness analysis loop at regular intervals.
     This is the "heavy" operation - screenshots and brightness detection.
     Runs at `scanInterval` (default 2.0 seconds).
     */
    private var analysisTimer: Timer?
    
    /**
     Timer that fires window tracking updates at regular intervals.
     This is "lightweight" - just window enumeration and overlay position updates.
     Runs at `windowTrackingInterval` (default 0.5 seconds).
     
     Handles:
     - Updating overlay positions as windows move
     - Z-order updates when focus changes
     - Removing overlays for hidden/minimized windows
     */
    private var windowTrackingTimer: Timer?
    
    /**
     Whether the coordinator is currently running.
     */
    private(set) var isRunning: Bool = false
    
    /**
     Current detection status - used by UI to show real-time feedback.
     Published so SwiftUI views can observe it.
     */
    @Published private(set) var detectionStatus = DetectionStatus()
    
    /**
     The overlay manager for creating/updating dim windows.
     */
    private let overlayManager: OverlayManager
    
    /**
     Current configuration (from settings).
     Cached for performance - updated when settings change.
     */
    private var configuration: DimmingConfiguration
    
    /**
     Combine subscriptions for settings observation.
     */
    private var cancellables = Set<AnyCancellable>()
    
    /**
     Background queue for brightness analysis.
     Analysis is CPU-intensive, so we offload it from main thread.
     Used in Phase 2 for intelligent per-window analysis.
     */
    private let analysisQueue = DispatchQueue(
        label: "com.superdimmer.analysis",
        qos: .userInitiated
    )
    
    /**
     Global mouse click monitor.
     
     FIX (Jan 8, 2026): We need to detect ALL mouse clicks, not just app switches.
     When user clicks anywhere - even within the same window - we need to reorder
     overlays because the click might have changed window z-order.
     
     NSWorkspace.didActivateApplicationNotification only fires when switching apps,
     not when clicking within the same app or reordering windows within an app.
     */
    private var mouseClickMonitor: Any?
    
    /**
     Debounce work item for mouse click analysis.
     
     FIX (Jan 8, 2026): Added to prevent EXC_BAD_ACCESS crash.
     Without debouncing, rapid mouse clicks would trigger multiple overlapping
     analysis cycles, causing race conditions in overlay management.
     Only the last click in a rapid series will trigger analysis.
     */
    private var pendingClickAnalysis: DispatchWorkItem?
    
    /**
     Timestamp of last analysis to prevent too-frequent runs.
     */
    private var lastAnalysisTime: CFAbsoluteTime = 0
    
    /**
     Minimum interval between analysis runs (in seconds).
     Prevents rapid analysis from mouse clicks causing overlay churn.
     */
    private let minAnalysisInterval: CFAbsoluteTime = 0.3
    
    // ================================================================
    // MARK: - Analysis Cache (Performance Optimization)
    // ================================================================
    
    /**
     Cached analysis result for a window.
     
     OPTIMIZATION (Jan 8, 2026): We cache analysis results to avoid re-analyzing
     windows that haven't changed. This significantly reduces CPU usage because
     screen capture is expensive.
     
     Re-analysis is triggered when:
     - Window bounds change (moved or resized)
     - Window becomes frontmost (user clicked it)
     - Cache expires (every 10 seconds, in case content changed)
     */
    private struct CachedAnalysis {
        /// The detected bright regions for this window
        let regions: [BrightRegionDetector.BrightRegion]
        
        /// Hash of window bounds when analyzed (for change detection)
        let boundsHash: Int
        
        /// Whether window was frontmost when analyzed
        let wasFrontmost: Bool
        
        /// When this cache entry was created
        let timestamp: Date
        
        /// Owner PID (for hybrid z-ordering)
        let ownerPID: pid_t
        
        /// Window name (for debugging)
        let windowName: String
        
        /// Check if cache is still valid for the given window state
        func isValid(for window: TrackedWindow, isFrontmost: Bool, maxAge: TimeInterval = 10.0) -> Bool {
            // Expired?
            if Date().timeIntervalSince(timestamp) > maxAge {
                return false
            }
            
            // Bounds changed? (window moved or resized)
            let currentBoundsHash = window.bounds.hashValue
            if currentBoundsHash != boundsHash {
                return false
            }
            
            // Frontmost status changed? (user clicked this window)
            // We re-analyze when window becomes frontmost in case content scrolled
            if isFrontmost && !wasFrontmost {
                return false
            }
            
            return true
        }
    }
    
    /// Cache of analysis results, keyed by window ID
    private var analysisCache: [CGWindowID: CachedAnalysis] = [:]
    
    /// How long to keep cache entries before forcing re-analysis (seconds)
    private let cacheMaxAge: TimeInterval = 10.0
    
    // NOTE: Thread safety for start/stop is handled via objc_sync_enter/exit
    // since these methods must run on main thread anyway (UI operations).
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Creates a new DimmingCoordinator.
     
     The coordinator is created but not started. Call start() to
     begin the analysis loop.
     */
    init() {
        // Load initial configuration from settings
        self.configuration = DimmingConfiguration.fromSettings()
        
        // Get the shared overlay manager
        self.overlayManager = OverlayManager.shared
        
        // Set up settings observers
        setupSettingsObservers()
        
        print("✓ DimmingCoordinator initialized")
    }
    
    deinit {
        stop()
        print("✓ DimmingCoordinator deallocated")
    }
    
    // ================================================================
    // MARK: - Start/Stop
    // ================================================================
    
    /**
     Starts the dimming analysis loop.
     
     This begins the continuous cycle of:
     1. Capturing screen/windows
     2. Analyzing brightness
     3. Creating/updating overlays
     
     The loop runs at the interval specified in settings (default 1 second).
     
     THREADING: Must be called from main thread (UI operations).
     
     FIX (Jan 7, 2026): We now SHOW existing overlays instead of creating new ones.
     Creating/destroying overlays on every toggle caused race conditions and crashes.
     The overlays are created once and then shown/hidden for performance and stability.
     */
    func start() {
        guard !isRunning else {
            print("⚠️ DimmingCoordinator already running")
            return
        }
        
        debugLog("▶️ Starting DimmingCoordinator...")
        isRunning = true
        
        // Check if we should use intelligent mode
        // If intelligent mode is enabled AND we have permission, don't create full-screen overlays
        // Instead, let the analysis loop create per-window or per-region overlays
        let intelligentEnabled = SettingsManager.shared.intelligentDimmingEnabled
        let hasPermission = ScreenCaptureService.shared.checkPermission()
        let useIntelligentMode = intelligentEnabled && hasPermission
        
        debugLog("▶️ Starting: intelligentEnabled=\(intelligentEnabled), hasPermission=\(hasPermission), useIntelligentMode=\(useIntelligentMode)")
        
        if useIntelligentMode {
            // INTELLIGENT MODE: Don't create full-screen overlays
            // The analysis loop will create per-window or per-region overlays
            print("▶️ Intelligent mode - overlays will be created by analysis loop")
            
            // Remove any existing full-screen overlays
            overlayManager.disableFullScreenDimming()
            
            // Run analysis immediately (don't wait for timer)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performAnalysisCycle()
            }
        } else {
            // SIMPLE MODE: Full-screen dimming
            print("▶️ Simple mode - creating full-screen overlays")
            
            // FIX (Jan 9, 2026): Read directly from SettingsManager for live updates
            let dimLevel = CGFloat(SettingsManager.shared.globalDimLevel)
            print("📺 Dim level: \(dimLevel)")
            
            // FIX: Check if overlays already exist (from previous toggle)
            // If they do, just show them. If not, create them.
            if overlayManager.overlayCount > 0 {
                print("📺 Showing existing overlays")
                overlayManager.showAllOverlays()
                overlayManager.updateAllOverlayLevels(dimLevel)
            } else {
                print("📺 Creating new full-screen overlays")
                overlayManager.enableFullScreenDimming(dimLevel: dimLevel)
            }
        }
        
        // Schedule the analysis timer (only if not already scheduled)
        // This is the "heavy" timer - screenshots and brightness analysis
        if analysisTimer == nil {
            analysisTimer = Timer.scheduledTimer(
                withTimeInterval: configuration.scanInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performAnalysisCycle()
            }
            RunLoop.current.add(analysisTimer!, forMode: .common)
        }
        
        // Schedule window tracking timer (lightweight, runs more frequently)
        // This handles overlay position/z-order updates without expensive screenshots
        if windowTrackingTimer == nil && useIntelligentMode {
            let trackingInterval = SettingsManager.shared.windowTrackingInterval
            windowTrackingTimer = Timer.scheduledTimer(
                withTimeInterval: trackingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performWindowTracking()
            }
            RunLoop.current.add(windowTrackingTimer!, forMode: .common)
            print("📍 Window tracking timer started (interval: \(trackingInterval)s)")
        }
        
        // ================================================================
        // INSTANT FOCUS DETECTION via Accessibility API (Jan 13, 2026)
        // ================================================================
        // Uses AXObserver to get INSTANT (<10ms) notification when window focus changes.
        // Much faster than the mouse click monitor which had 20-60ms delay.
        //
        // The AccessibilityFocusObserver watches kAXFocusedWindowChangedNotification
        // on all running apps, which fires immediately when any window gains focus.
        if useIntelligentMode {
            let focusObserver = AccessibilityFocusObserver.shared
            focusObserver.onFocusChanged = { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                
                // INSTANT z-order update - no async dispatch needed, already on main thread
                self.overlayManager.updateOverlayLevelsForFrontmostApp()
                
                // Debounced analysis (don't need to re-screenshot on every click)
                self.pendingClickAnalysis?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isRunning else { return }
                    let now = CFAbsoluteTimeGetCurrent()
                    guard now - self.lastAnalysisTime >= self.minAnalysisInterval else { return }
                    self.analysisQueue.async {
                        self.performPerRegionAnalysis()
                    }
                }
                self.pendingClickAnalysis = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            }
            focusObserver.startObserving()
            print("🔍 Accessibility focus observer started (instant window focus detection)")
        }
        
        // FALLBACK: Global mouse click monitor for apps that don't support AX
        // This is a backup - most focus changes will be caught by AccessibilityFocusObserver
        // but some edge cases (clicking within same window, etc.) might need this.
        if mouseClickMonitor == nil && useIntelligentMode {
            mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                
                // DEBOUNCE: Cancel any pending analysis from previous click
                self.pendingClickAnalysis?.cancel()
                
                // Z-order update (may be redundant with AX observer, but fast operation)
                self.overlayManager.updateOverlayLevelsForFrontmostApp()
                
                // DEBOUNCE: Schedule analysis with delay
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, self.isRunning else { return }
                    let now = CFAbsoluteTimeGetCurrent()
                    guard now - self.lastAnalysisTime >= self.minAnalysisInterval else { return }
                    self.analysisQueue.async {
                        self.performPerRegionAnalysis()
                    }
                }
                self.pendingClickAnalysis = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            }
            print("🖱️ Global mouse click monitor installed (fallback)")
        }
        
        print("▶️ DimmingCoordinator started (interval: \(configuration.scanInterval)s)")
    }
    
    /**
     Stops the dimming analysis loop.
     
     HIDES overlays (doesn't destroy them) and stops the timer.
     Called when:
     - User disables dimming
     
     For full cleanup (app quit), use cleanup() instead.
     
     THREADING: Must be called from main thread (UI operations).
     
     FIX (Jan 7, 2026): Changed from removeAllOverlays() to hideAllOverlays().
     This prevents race conditions when rapidly toggling - the windows stay alive
     and are just shown/hidden, which is much more stable.
     */
    func stop() {
        guard isRunning else {
            print("⚠️ DimmingCoordinator not running, nothing to stop")
            return
        }
        
        print("⏹️ Stopping DimmingCoordinator...")
        isRunning = false
        
        // Stop both timers
        analysisTimer?.invalidate()
        analysisTimer = nil
        
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = nil
        
        // Stop accessibility focus observer
        AccessibilityFocusObserver.shared.stopObserving()
        AccessibilityFocusObserver.shared.onFocusChanged = nil
        print("🔍 Accessibility focus observer stopped")
        
        // Remove mouse click monitor
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
            print("🖱️ Global mouse click monitor removed")
        }
        
        // FIX: HIDE overlays instead of destroying them
        // This allows quick re-enable without recreation overhead
        overlayManager.hideAllOverlays()
        
        // Clear analysis cache (will rebuild on next start)
        analysisCache.removeAll()
        
        print("⏹️ DimmingCoordinator stopped (overlays hidden, cache cleared)")
    }
    
    /**
     Full cleanup - destroys all overlays.
     Called only when app is quitting.
     */
    func cleanup() {
        print("🧹 DimmingCoordinator cleanup...")
        isRunning = false
        analysisTimer?.invalidate()
        analysisTimer = nil
        
        // Stop accessibility focus observer
        AccessibilityFocusObserver.shared.stopObserving()
        AccessibilityFocusObserver.shared.onFocusChanged = nil
        
        // Remove mouse click monitor
        if let monitor = mouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            mouseClickMonitor = nil
        }
        
        overlayManager.removeAllOverlays()
        print("🧹 DimmingCoordinator cleanup complete")
    }
    
    /**
     Updates debug borders on all existing overlays.
     
     Call this when the debugOverlayBorders setting changes to update
     all visible overlays without recreating them.
     */
    func updateDebugBorders() {
        overlayManager.updateAllDebugBorders()
    }
    
    // ================================================================
    // MARK: - Analysis Loop
    // ================================================================
    
    /**
     Performs one cycle of brightness analysis.
     
     This is called by the timer at regular intervals.
     
     MODES:
     - Simple mode: Full-screen overlay with global dim level (Phase 1)
     - Intelligent mode: Per-window analysis and targeted overlays (Phase 2)
     
     We use intelligent mode if:
     1. intelligentDimmingEnabled setting is true
     2. Screen Recording permission is granted
     
     Otherwise, we fall back to simple mode.
     */
    func performAnalysisCycle() {
        guard isRunning else { return }
        
        // Check if we should use intelligent mode
        let intelligentEnabled = SettingsManager.shared.intelligentDimmingEnabled
        let hasPermission = ScreenCaptureService.shared.checkPermission()  // Force fresh check
        let useIntelligentMode = intelligentEnabled && hasPermission
        
        // Debug output - writing to file for reliable capture
        debugLog("🔄 Analysis cycle: intelligent=\(intelligentEnabled), permission=\(hasPermission), mode=\(useIntelligentMode ? "INTELLIGENT" : "SIMPLE")")
        
        if useIntelligentMode {
            // Phase 2: Intelligent per-window dimming
            performIntelligentAnalysis()
        } else {
            // Phase 1: Simple mode (full-screen dimming)
            // If Auto mode is enabled, dim level adjusts based on screen brightness
            // Otherwise uses static globalDimLevel from settings
            let currentDimLevel = getEffectiveDimLevel()
            DispatchQueue.main.async { [weak self] in
                self?.overlayManager.updateAllOverlayLevels(currentDimLevel)
            }
        }
    }
    
    // ================================================================
    // MARK: - Simple Mode (MVP) - No longer needed, handled in start()
    // ================================================================
    
    // NOTE: startSimpleMode() and applySimpleDimming() were removed.
    // Overlay creation is now done synchronously in start() to prevent
    // race conditions. The timer's performAnalysisCycle() handles updates.
    
    // ================================================================
    // MARK: - Intelligent Mode (Phase 2)
    // ================================================================
    
    /**
     Performs full intelligent brightness analysis.
     
     DETECTION MODES:
     - perWindow: Analyzes entire window, dims whole window if bright
     - perRegion: Finds bright areas WITHIN windows, dims only those regions
     
     This is dispatched to analysisQueue for performance.
     
     FIX (Jan 8, 2026): Added throttling and lastAnalysisTime tracking
     to prevent rapid analysis from mouse clicks causing overlay churn.
     */
    private func performIntelligentAnalysis() {
        let analysisStart = CFAbsoluteTimeGetCurrent()
        
        // THROTTLE: Skip if we just ran analysis very recently
        // This prevents rapid calls from timer + mouse clicks overlapping
        if analysisStart - lastAnalysisTime < minAnalysisInterval * 0.5 {
            return
        }
        
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRunning else { return }
            
            // Track when analysis actually runs
            self.lastAnalysisTime = CFAbsoluteTimeGetCurrent()
            
            let detectionMode = SettingsManager.shared.detectionMode
            
            switch detectionMode {
            case .perWindow:
                self.performPerWindowAnalysis()
            case .perRegion:
                self.performPerRegionAnalysis()
            }
            
            let totalTime = (CFAbsoluteTimeGetCurrent() - analysisStart) * 1000
            if totalTime > 500 {
                // Only log if analysis is slow (>500ms)
                debugLog("⏱️ Analysis took \(String(format: "%.0f", totalTime))ms")
            }
        }
    }
    
    /**
     Per-Window mode: Analyzes entire window brightness.
     
     If a window's average brightness exceeds threshold, dim the whole window.
     This is simpler and faster but less precise.
     */
    private func performPerWindowAnalysis() {
        debugLog("🔍 Starting PerWindow analysis...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 1. Get visible windows
        let windows = WindowTrackerService.shared.getVisibleWindows()
        debugLog("🔍 Found \(windows.count) visible windows")
        
        guard !windows.isEmpty else {
            debugLog("⚠️ No visible windows found")
            return
        }
        
        // 2. Check screen capture permission
        guard ScreenCaptureService.shared.hasPermission else {
            debugLog("⚠️ No screen capture permission - using simple mode")
            return
        }
        
        // 3. Analyze brightness for each window
        var decisions: [DimmingDecision] = []
        let screenCapture = ScreenCaptureService.shared
        let analysisEngine = BrightnessAnalysisEngine.shared
        // FIX (Jan 9, 2026): Read directly from SettingsManager for live updates
        // Previously used cached self.configuration which didn't update when settings changed
        let threshold = Float(SettingsManager.shared.brightnessThreshold)
        debugLog("🔍 Using threshold: \(threshold)")
        
        for var window in windows {
            // Capture window content
            guard let windowImage = screenCapture.captureWindow(window.id) else {
                debugLog("⚠️ Could not capture window \(window.id) (\(window.ownerName))")
                continue
            }
            
            // Analyze brightness
            if let brightness = analysisEngine.averageLuminance(of: windowImage) {
                window.brightness = brightness
                
                let shouldDim = brightness > threshold
                debugLog("🔍 Window '\(window.ownerName)': brightness=\(brightness), threshold=\(threshold), shouldDim=\(shouldDim)")
                
                // Make dimming decision
                let decision = self.makeDimmingDecision(
                    for: window,
                    brightness: brightness,
                    threshold: threshold
                )
                decisions.append(decision)
            }
        }
        
        let analysisTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        debugLog("🔍 [PerWindow] Analyzed \(windows.count) windows in \(String(format: "%.1f", analysisTime))ms, \(decisions.count) decisions")
        
        // 4. Apply decisions on main thread
        DispatchQueue.main.async { [weak self] in
            guard self?.isRunning == true else { return }
            self?.overlayManager.applyDimmingDecisions(decisions)
        }
    }
    
    /**
     Per-Region mode: Finds bright areas WITHIN windows.
     
     This is the killer feature! Handles cases like:
     - Dark mode Mail with bright email content
     - Code editor with bright preview pane
     - Any app with mixed bright/dark areas
     
     Creates overlays for specific bright regions, not entire windows.
     
     UPDATE (Jan 8, 2026): Now analyzes ALL visible windows, not just the active one.
     The z-ordering challenge is handled by setting appropriate window levels on overlays.
     User reported that only one Mail window was being dimmed when multiple were visible.
     */
    private func performPerRegionAnalysis() {
        debugLog("🎯 Starting PerRegion analysis...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Update status to show we're analyzing
        DispatchQueue.main.async { [weak self] in
            self?.detectionStatus.isAnalyzing = true
        }
        
        // 1. Get visible windows
        let windows = WindowTrackerService.shared.getVisibleWindows()
        debugLog("🎯 Found \(windows.count) visible windows")
        
        guard !windows.isEmpty else {
            debugLog("⚠️ No visible windows found")
            DispatchQueue.main.async { [weak self] in
                self?.detectionStatus.isAnalyzing = false
            }
            return
        }
        
        // 2. Check screen capture permission
        guard ScreenCaptureService.shared.hasPermission else {
            debugLog("⚠️ No screen capture permission - using simple mode")
            DispatchQueue.main.async { [weak self] in
                self?.detectionStatus.isAnalyzing = false
            }
            return
        }
        
        // 3. Get frontmost app for cache invalidation
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        
        // 4. Detect bright regions within each window (with caching!)
        let screenCapture = ScreenCaptureService.shared
        let regionDetector = BrightRegionDetector.shared
        // FIX (Jan 9, 2026): Read directly from SettingsManager for live updates
        let threshold = Float(SettingsManager.shared.brightnessThreshold)
        let gridSize = SettingsManager.shared.regionGridSize
        
        var allRegionDecisions: [RegionDimmingDecision] = []
        var cacheHits = 0
        var cacheMisses = 0
        
        // Track which windows we're analyzing (for cache cleanup)
        let currentWindowIDs = Set(windows.map { $0.id })
        
        // Register windows with inactivity tracker for decay dimming
        let inactivityTracker = WindowInactivityTracker.shared
        
        for window in windows {
            let isFrontmost = window.ownerPID == frontmostPID
            
            // Register window for inactivity tracking
            inactivityTracker.registerWindow(window.id, ownerPID: window.ownerPID, ownerName: window.ownerName)
            
            // If this window is frontmost, mark it as active
            if window.isActive {
                inactivityTracker.windowBecameActive(window.id, ownerPID: window.ownerPID, ownerName: window.ownerName)
            }
            
            // OPTIMIZATION: Check cache first
            if let cached = analysisCache[window.id],
               cached.isValid(for: window, isFrontmost: isFrontmost, maxAge: cacheMaxAge) {
                // Cache hit! Use cached regions
                cacheHits += 1
                
                // Build decisions from cached regions
                for region in cached.regions {
                    let regionRect = region.rect(in: window.bounds)
                    let dimLevel = calculateRegionDimLevel(
                        brightness: region.brightness,
                        threshold: threshold,
                        isActiveWindow: window.isActive
                    )
                    
                    let decision = RegionDimmingDecision(
                        windowID: window.id,
                        windowName: cached.windowName,
                        ownerPID: cached.ownerPID,
                        isFrontmostWindow: window.isActive,
                        regionRect: regionRect,
                        brightness: region.brightness,
                        dimLevel: dimLevel
                    )
                    allRegionDecisions.append(decision)
                }
                continue
            }
            
            // Cache miss - need to capture and analyze
            cacheMisses += 1
            
            // Capture window content
            guard let windowImage = screenCapture.captureWindow(window.id) else {
                debugLog("⚠️ Could not capture window \(window.id) (\(window.ownerName))")
                continue
            }
            
            // Detect bright regions within this window
            var brightRegions = regionDetector.detectBrightRegions(
                in: windowImage,
                threshold: threshold,
                gridSize: gridSize,
                minRegionSize: 4
            )
            
            // Filter out regions that are too small in pixel terms
            brightRegions = regionDetector.filterByMinimumSize(brightRegions, windowBounds: window.bounds)
            
            // Cache the results for next cycle
            analysisCache[window.id] = CachedAnalysis(
                regions: brightRegions,
                boundsHash: window.bounds.hashValue,
                wasFrontmost: isFrontmost,
                timestamp: Date(),
                ownerPID: window.ownerPID,
                windowName: window.ownerName
            )
            
            debugLog("🎯 Window '\(window.ownerName)': found \(brightRegions.count) bright regions (fresh analysis)")
            
            // Create decisions for each bright region
            for region in brightRegions {
                let regionRect = region.rect(in: window.bounds)
                let dimLevel = calculateRegionDimLevel(
                    brightness: region.brightness,
                    threshold: threshold,
                    isActiveWindow: window.isActive
                )
                
                let decision = RegionDimmingDecision(
                    windowID: window.id,
                    windowName: window.ownerName,
                    ownerPID: window.ownerPID,
                    isFrontmostWindow: window.isActive,
                    regionRect: regionRect,
                    brightness: region.brightness,
                    dimLevel: dimLevel
                )
                allRegionDecisions.append(decision)
            }
        }
        
        // 5. Clean up cache entries for windows that no longer exist
        let staleWindowIDs = Set(analysisCache.keys).subtracting(currentWindowIDs)
        for staleID in staleWindowIDs {
            analysisCache.removeValue(forKey: staleID)
        }
        
        // Also clean up inactivity tracker
        inactivityTracker.cleanup(activeWindowIDs: currentWindowIDs)
        
        let analysisTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        debugLog("🎯 [PerRegion] Analysis complete: \(allRegionDecisions.count) regions in \(String(format: "%.1f", analysisTime))ms (cache: \(cacheHits) hits, \(cacheMisses) misses)")
        
        // 6. Apply region overlays on main thread and update status
        let regionCount = allRegionDecisions.count
        let windowsAnalyzed = windows.count
        
        // 7. Apply decay dimming to all inactive windows (full-window overlays)
        applyDecayDimmingToWindows(windows)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRunning else {
                debugLog("⚠️ Not running, skipping overlay application")
                return
            }
            
            self.overlayManager.applyRegionDimmingDecisions(allRegionDecisions)
            
            // Update detection status for UI feedback
            self.detectionStatus.isAnalyzing = false
            self.detectionStatus.windowCount = windowsAnalyzed
            self.detectionStatus.regionCount = regionCount
            self.detectionStatus.overlayCount = regionCount
            self.detectionStatus.lastAnalysisTime = Date()
        }
    }
    
    /**
     Calculates dim level for a specific bright region.
     
     NOTE: Decay dimming is handled separately via full-window overlays,
     not applied here to region overlays.
     */
    private func calculateRegionDimLevel(
        brightness: Float,
        threshold: Float,
        isActiveWindow: Bool
    ) -> CGFloat {
        // FIX (Jan 9, 2026): Read directly from SettingsManager for live updates
        let settings = SettingsManager.shared
        
        // How much above threshold
        let overage = brightness - threshold
        let overageRatio = overage / (1.0 - threshold)
        
        // Scale dim level based on overage
        // Use the user's global dim level as the base
        let baseDimLevel = CGFloat(settings.globalDimLevel)
        var dimLevel = baseDimLevel * CGFloat(0.5 + overageRatio * 0.5)
        
        // Apply active window reduction if enabled
        if isActiveWindow && settings.differentiateActiveInactive {
            dimLevel = min(dimLevel, CGFloat(settings.activeDimLevel))
        }
        
        // Ensure minimum visibility - if user set dim level > 10%, 
        // use at least 15% so overlays are visible
        let minimumDimLevel: CGFloat = max(0.15, baseDimLevel * 0.5)
        dimLevel = max(dimLevel, minimumDimLevel)
        
        return dimLevel
    }
    
    // ================================================================
    // MARK: - Super Dimming Auto Mode (2.2.1.2)
    // ================================================================
    
    /**
     Calculates the auto-adjusted dim level based on overall screen brightness.
     
     SUPER DIMMING AUTO MODE:
     Instead of using a fixed dim level, Auto mode dynamically adjusts based
     on how bright your screen content is. This provides a more comfortable
     experience without needing manual adjustments.
     
     CALCULATION:
     The dim level swings ±autoAdjustRange around the base globalDimLevel
     depending on screen brightness:
     
     adjustedDim = baseDim + (screenBrightness - 0.5) × range × 2
     
     - screenBrightness 1.0 (very bright) → baseDim + range
     - screenBrightness 0.5 (neutral) → baseDim (no change)
     - screenBrightness 0.0 (very dark) → baseDim - range
     
     For example, with baseDim=0.25 and range=0.15:
     - Bright screen (1.0) → 0.25 + 0.15 = 0.40 (40% dim)
     - Neutral (0.5) → 0.25 (25% dim)
     - Dark screen (0.0) → 0.25 - 0.15 = 0.10 (10% dim)
     
     - Parameter screenBrightness: Overall average brightness (0.0-1.0)
     - Returns: Auto-adjusted dim level
     */
    private func calculateAutoDimLevel(screenBrightness: Float) -> CGFloat {
        let settings = SettingsManager.shared
        let baseDimLevel = CGFloat(settings.globalDimLevel)
        let adjustRange = CGFloat(settings.autoAdjustRange)
        
        // Calculate adjustment: (brightness - 0.5) gives range [-0.5, 0.5]
        // Multiply by 2 to get [-1.0, 1.0], then by adjustRange
        let brightnessOffset = CGFloat(screenBrightness) - 0.5
        let adjustment = brightnessOffset * adjustRange * 2.0
        
        // Apply adjustment to base level
        var adjustedDimLevel = baseDimLevel + adjustment
        
        // Clamp to valid range [0.0, 1.0]
        adjustedDimLevel = max(0.0, min(1.0, adjustedDimLevel))
        
        debugLog("🌟 Auto dim: screen=\(String(format: "%.2f", screenBrightness)), base=\(String(format: "%.2f", baseDimLevel)), adj=\(String(format: "%.2f", adjustment)), final=\(String(format: "%.2f", adjustedDimLevel))")
        
        return adjustedDimLevel
    }
    
    /**
     Gets the effective dim level, considering Auto mode.
     
     If Super Dimming Auto mode is enabled:
     - Captures a small screen sample to measure brightness
     - Calculates auto-adjusted dim level
     
     Otherwise:
     - Returns the static globalDimLevel from settings
     
     - Returns: The dim level to use for full-screen/simple dimming
     */
    private func getEffectiveDimLevel() -> CGFloat {
        let settings = SettingsManager.shared
        
        // If Auto mode is disabled, just return the static level
        guard settings.superDimmingAutoEnabled else {
            return CGFloat(settings.globalDimLevel)
        }
        
        // Auto mode: Capture and analyze screen brightness
        // Use a small, fast capture for efficiency
        guard let screenImage = ScreenCaptureService.shared.captureMainDisplay() else {
            debugLog("⚠️ Auto mode: Could not capture screen, using static level")
            return CGFloat(settings.globalDimLevel)
        }
        
        // Analyze brightness of the capture
        guard let brightness = BrightnessAnalysisEngine.shared.averageLuminance(of: screenImage) else {
            debugLog("⚠️ Auto mode: Could not analyze brightness, using static level")
            return CGFloat(settings.globalDimLevel)
        }
        
        return calculateAutoDimLevel(screenBrightness: brightness)
    }
    
    // ================================================================
    // MARK: - Decay Dimming
    // ================================================================
    
    /// Timestamp of last decay dimming application (for throttling)
    private var lastDecayApplicationTime: CFAbsoluteTime = 0
    
    /// Minimum interval between decay dimming updates (seconds)
    private let minDecayInterval: CFAbsoluteTime = 1.0
    
    /**
     Generates and applies decay dimming for all inactive windows.
     
     This creates FULL-WINDOW overlays for inactive windows based on
     how long they've been inactive. Separate from region-based dimming.
     
     FIX (Jan 9, 2026): Added throttling to prevent rapid overlay updates.
     Decay dimming is gradual, so we don't need to update every analysis cycle.
     
     - Parameter windows: All visible windows to consider
     */
    private func applyDecayDimmingToWindows(_ windows: [TrackedWindow]) {
        guard SettingsManager.shared.inactivityDecayEnabled else {
            // If decay is disabled, clear any existing decay overlays
            overlayManager.applyDecayDimming([])
            return
        }
        
        // THROTTLE: Don't update decay overlays too frequently
        // Decay is gradual, updating every 1+ second is plenty
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDecayApplicationTime >= minDecayInterval else {
            return
        }
        lastDecayApplicationTime = now
        
        let settings = SettingsManager.shared
        let inactivityTracker = WindowInactivityTracker.shared
        
        var decayDecisions: [OverlayManager.DecayDimmingDecision] = []
        
        for window in windows {
            // Check if this app is excluded from decay dimming (2.2.1.12)
            if let bundleID = window.bundleID,
               settings.isAppExcluded(from: .decayDimming, bundleID: bundleID) {
                continue
            }
            
            // Calculate decay dim level for this window
            let inactivityDuration = inactivityTracker.getInactivityDuration(for: window.id)
            let delayedInactivity = max(0, inactivityDuration - settings.decayStartDelay)
            
            // Decay formula: rate × time since delay ended
            let decayDimLevel = CGFloat(settings.decayRate * delayedInactivity)
            
            // Clamp to max decay level
            let clampedDecayLevel = min(decayDimLevel, CGFloat(settings.maxDecayDimLevel))
            
            // Only log when there's meaningful decay happening
            if !window.isActive && clampedDecayLevel > 0.05 {
                debugLog("⏰ Decay: '\(window.ownerName)' ID:\(window.id) - " +
                         "inactive=\(String(format: "%.0f", inactivityDuration))s, " +
                         "level=\(String(format: "%.2f", clampedDecayLevel))")
            }
            
            let decision = OverlayManager.DecayDimmingDecision(
                windowID: window.id,
                windowName: window.ownerName,
                ownerPID: window.ownerPID,
                windowBounds: window.bounds,
                decayDimLevel: clampedDecayLevel,
                isActive: window.isActive
            )
            
            decayDecisions.append(decision)
        }
        
        // Apply decay overlays (this now uses async dispatch internally)
        overlayManager.applyDecayDimming(decayDecisions)
    }
    
    /**
     Makes a dimming decision for a specific window.
     
     - Parameters:
       - window: The window to evaluate
       - brightness: Measured brightness (0.0-1.0)
       - threshold: Brightness threshold for dimming
     - Returns: A DimmingDecision for this window
     */
    private func makeDimmingDecision(
        for window: TrackedWindow,
        brightness: Float,
        threshold: Float
    ) -> DimmingDecision {
        
        // Check if brightness exceeds threshold
        let shouldDim = brightness > threshold
        
        // Calculate dim level
        var dimLevel: CGFloat
        var reason: DimmingDecision.DimmingReason
        
        if shouldDim {
            // FIX (Jan 9, 2026): Read directly from SettingsManager for live updates
            let settings = SettingsManager.shared
            
            // How much above threshold determines intensity
            // Brightness of 1.0 with threshold 0.85 = 15% over = higher dim
            let overage = brightness - threshold
            let overageRatio = overage / (1.0 - threshold)  // 0.0-1.0
            
            // Scale dim level based on overage and settings
            let baseDimLevel = CGFloat(settings.globalDimLevel)
            dimLevel = baseDimLevel * CGFloat(0.5 + overageRatio * 0.5)
            
            // Reduce dimming for active window if that setting is enabled
            if window.isActive && settings.differentiateActiveInactive {
                dimLevel = CGFloat(settings.activeDimLevel)
                reason = .activeWindowReduced
            } else if !window.isActive && settings.differentiateActiveInactive {
                dimLevel = CGFloat(settings.inactiveDimLevel)
                reason = .inactiveWindowIncreased
            } else {
                reason = .aboveThreshold
            }
        } else {
            dimLevel = 0
            reason = .belowThreshold
        }
        
        return DimmingDecision(
            window: window,
            shouldDim: shouldDim,
            dimLevel: dimLevel,
            reason: reason
        )
    }
    
    // ================================================================
    // MARK: - Settings Observers
    // ================================================================
    
    /**
     Sets up observers for settings that affect dimming.
     */
    private func setupSettingsObservers() {
        // Observe dimming enabled changes
        NotificationCenter.default.publisher(for: .dimmingEnabledChanged)
            .sink { [weak self] notification in
                guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
                self?.handleDimmingEnabledChanged(enabled)
            }
            .store(in: &cancellables)
        
        // Observe scan interval changes
        SettingsManager.shared.$scanInterval
            .dropFirst()
            .sink { [weak self] newInterval in
                self?.updateScanInterval(newInterval)
            }
            .store(in: &cancellables)
        
        // Observe window tracking interval changes
        SettingsManager.shared.$windowTrackingInterval
            .dropFirst()
            .sink { [weak self] newInterval in
                self?.updateWindowTrackingInterval(newInterval)
            }
            .store(in: &cancellables)
        
        // HYBRID Z-ORDERING (Jan 8, 2026): Listen for application activation changes
        // When the frontmost app changes, we switch overlay window levels:
        // - New frontmost app's overlays → .floating (no flash when clicking within)
        // - Background app overlays → .normal + relative positioning
        //
        // This is the KEY to eliminating flash! Active app overlays stay on top
        // regardless of click ordering, while background overlays stay properly layered.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                // Update overlay levels based on new frontmost app
                DispatchQueue.main.async {
                    self?.overlayManager.updateOverlayLevelsForFrontmostApp()
                }
            }
            .store(in: &cancellables)
        
        // ================================================================
        // FIX (Jan 9, 2026): Remove overlays when apps are hidden or windows minimized
        // Without this, hidden/minimized windows would have orphaned overlays
        // floating on screen with nothing beneath them.
        // ================================================================
        
        // When an app is hidden (Cmd+H or auto-hide), remove all its overlays
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                DispatchQueue.main.async {
                    self?.overlayManager.removeOverlaysForApp(pid: app.processIdentifier)
                }
            }
            .store(in: &cancellables)
        
        // We also need to handle window minimization. Unfortunately, there's no
        // direct notification for this in NSWorkspace. However, our analysis loop
        // will naturally stop finding minimized windows (they're not in the visible
        // window list returned by CGWindowListCopyWindowInfo).
        //
        // The stale overlay cleanup in the analysis loop handles this:
        // - applyRegionDimmingDecisions() removes overlays for windows not in decisions
        // - applyDecayDimming() removes overlays for windows not in tracked list
        //
        // For immediate response to minimize, we could use AX APIs or NSWindow
        // observation, but the periodic cleanup is sufficient for good UX.
    }
    
    /**
     Handles changes to the dimming enabled setting.
     */
    private func handleDimmingEnabledChanged(_ enabled: Bool) {
        if enabled {
            if !isRunning {
                start()
            }
        } else {
            stop()
        }
    }
    
    /**
     Updates the analysis timer interval.
     */
    private func updateScanInterval(_ newInterval: Double) {
        guard isRunning else { return }
        
        // Recreate timer with new interval
        analysisTimer?.invalidate()
        analysisTimer = Timer.scheduledTimer(
            withTimeInterval: newInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performAnalysisCycle()
        }
        RunLoop.current.add(analysisTimer!, forMode: .common)
        
        print("⏱️ Scan interval updated to \(newInterval)s")
    }
    
    /**
     Updates the window tracking timer interval.
     */
    private func updateWindowTrackingInterval(_ newInterval: Double) {
        guard isRunning, windowTrackingTimer != nil else { return }
        
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = Timer.scheduledTimer(
            withTimeInterval: newInterval,
            repeats: true
        ) { [weak self] _ in
            self?.performWindowTracking()
        }
        RunLoop.current.add(windowTrackingTimer!, forMode: .common)
        
        print("📍 Window tracking interval updated to \(newInterval)s")
    }
    
    // ================================================================
    // MARK: - Window Tracking (Lightweight)
    // ================================================================
    
    /**
     Lightweight window tracking cycle.
     
     This runs FASTER than brightness analysis (every 0.5s vs 2.0s) because it:
     - Does NOT take screenshots (expensive)
     - Does NOT analyze brightness (expensive)
     - ONLY updates overlay positions and z-order
     
     Operations performed:
     1. Get current window list (fast - just CGWindowListCopyWindowInfo)
     2. Update overlay positions for moved windows
     3. Update z-order for focus changes
     4. Remove overlays for hidden/minimized windows
     */
    private func performWindowTracking() {
        guard isRunning else { return }
        
        // Only track in intelligent mode (region overlays need tracking)
        guard SettingsManager.shared.intelligentDimmingEnabled else { return }
        
        // Get current visible windows
        let windows = WindowTrackerService.shared.getVisibleWindows()
        let visibleWindowIDs = Set(windows.map { $0.id })
        
        // Update z-order for frontmost app
        overlayManager.updateOverlayLevelsForFrontmostApp()
        
        // Update overlay positions (without re-analyzing brightness)
        overlayManager.updateOverlayPositions(visibleWindowIDs: visibleWindowIDs, windows: windows)
        
        // Clean up overlays for windows that are no longer visible
        overlayManager.cleanupOrphanedOverlays(visibleWindowIDs: visibleWindowIDs)
    }
}

// ====================================================================
// MARK: - Dimming Configuration
// ====================================================================

/**
 Runtime configuration for the dimming system.
 
 This is a snapshot of relevant settings, cached for performance.
 Updated when settings change to avoid repeated UserDefaults lookups.
 */
struct DimmingConfiguration {
    /// Whether dimming is enabled
    var isEnabled: Bool
    
    /// Brightness threshold for triggering dimming (0.0-1.0)
    var brightnessThreshold: Float
    
    /// Global dim level when not differentiating active/inactive
    var globalDimLevel: CGFloat
    
    /// Dim level for active (frontmost) windows
    var activeDimLevel: CGFloat
    
    /// Dim level for inactive (background) windows
    var inactiveDimLevel: CGFloat
    
    /// Whether to apply different levels to active vs inactive windows
    var differentiateActiveInactive: Bool
    
    /// Interval between analysis cycles (seconds)
    var scanInterval: TimeInterval
    
    /**
     Creates configuration from current settings.
     */
    static func fromSettings() -> DimmingConfiguration {
        let settings = SettingsManager.shared
        return DimmingConfiguration(
            isEnabled: settings.isDimmingEnabled,
            brightnessThreshold: Float(settings.brightnessThreshold),
            globalDimLevel: CGFloat(settings.globalDimLevel),
            activeDimLevel: CGFloat(settings.activeDimLevel),
            inactiveDimLevel: CGFloat(settings.inactiveDimLevel),
            differentiateActiveInactive: settings.differentiateActiveInactive,
            scanInterval: settings.scanInterval
        )
    }
}

// ====================================================================
// MARK: - Detection Status
// ====================================================================

/**
 Real-time status of the detection system.
 
 Used by the UI to show feedback about what the system is doing.
 Updated after each analysis cycle.
 */
struct DetectionStatus {
    /// Number of windows currently being analyzed
    var windowCount: Int = 0
    
    /// Number of bright regions detected
    var regionCount: Int = 0
    
    /// Number of active overlays
    var overlayCount: Int = 0
    
    /// Last analysis timestamp
    var lastAnalysisTime: Date?
    
    /// Whether analysis is currently in progress
    var isAnalyzing: Bool = false
    
    /// Human-readable status string
    /// NOTE: Uses LIVE overlay count from OverlayManager, not cached analysis results
    var statusText: String {
        // Get actual current overlay count (not cached)
        let liveCount = OverlayManager.shared.currentRegionOverlayCount
        
        // NOTE: We don't use isAnalyzing here because:
        // 1. DetectionStatus is a struct, so @Published doesn't detect internal changes
        // 2. The "Scanning..." state is fleeting (< 100ms) anyway
        // 3. The live overlay count is more useful feedback
        
        if liveCount > 0 {
            return "\(liveCount) region\(liveCount == 1 ? "" : "s") dimmed"
        } else {
            return "No bright areas"
        }
    }
}
