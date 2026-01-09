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
     Timer that fires the analysis loop at regular intervals.
     */
    private var analysisTimer: Timer?
    
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
            
            let dimLevel = configuration.globalDimLevel
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
        if analysisTimer == nil {
            analysisTimer = Timer.scheduledTimer(
                withTimeInterval: configuration.scanInterval,
                repeats: true
            ) { [weak self] _ in
                self?.performAnalysisCycle()
            }
            RunLoop.current.add(analysisTimer!, forMode: .common)
        }
        
        // FIX (Jan 8, 2026): Set up global mouse click monitor
        // This catches ALL mouse clicks (not just app switches) to immediately
        // reorder overlays when window z-order might have changed.
        // Without this, overlays fall behind windows when user clicks.
        if mouseClickMonitor == nil && useIntelligentMode {
            mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                // Small delay to let the window come to front first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard let self = self, self.isRunning else { return }
                    
                    // HYBRID Z-ORDERING: Update overlay levels based on frontmost app
                    // This catches clicks that might change the frontmost window/app
                    self.overlayManager.updateOverlayLevelsForFrontmostApp()
                    
                    // OPTIMIZATION: Trigger immediate re-analysis for clicked window
                    // The cache will detect that the frontmost status changed and
                    // re-analyze only that window, keeping the experience responsive
                    self.analysisQueue.async {
                        self.performPerRegionAnalysis()
                    }
                }
            }
            print("🖱️ Global mouse click monitor installed (hybrid z-order + immediate analysis)")
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
        
        // Stop the timer
        analysisTimer?.invalidate()
        analysisTimer = nil
        
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
            // Phase 1: Simple mode - just update dim level from current settings
            let currentDimLevel = CGFloat(SettingsManager.shared.globalDimLevel)
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
     */
    private func performIntelligentAnalysis() {
        let analysisStart = CFAbsoluteTimeGetCurrent()
        
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRunning else { return }
            
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
        let threshold = Float(self.configuration.brightnessThreshold)
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
            return
        }
        
        // 2. Check screen capture permission
        guard ScreenCaptureService.shared.hasPermission else {
            debugLog("⚠️ No screen capture permission - using simple mode")
            return
        }
        
        // 3. Get frontmost app for cache invalidation
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        
        // 4. Detect bright regions within each window (with caching!)
        let screenCapture = ScreenCaptureService.shared
        let regionDetector = BrightRegionDetector.shared
        let threshold = Float(self.configuration.brightnessThreshold)
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
        // How much above threshold
        let overage = brightness - threshold
        let overageRatio = overage / (1.0 - threshold)
        
        // Scale dim level based on overage
        // Use the user's global dim level as the base
        let baseDimLevel = configuration.globalDimLevel
        var dimLevel = baseDimLevel * CGFloat(0.5 + overageRatio * 0.5)
        
        // Apply active window reduction if enabled
        if isActiveWindow && configuration.differentiateActiveInactive {
            dimLevel = min(dimLevel, configuration.activeDimLevel)
        }
        
        // Ensure minimum visibility - if user set dim level > 10%, 
        // use at least 15% so overlays are visible
        let minimumDimLevel: CGFloat = max(0.15, baseDimLevel * 0.5)
        dimLevel = max(dimLevel, minimumDimLevel)
        
        return dimLevel
    }
    
    // ================================================================
    // MARK: - Decay Dimming
    // ================================================================
    
    /**
     Generates and applies decay dimming for all inactive windows.
     
     This creates FULL-WINDOW overlays for inactive windows based on
     how long they've been inactive. Separate from region-based dimming.
     
     - Parameter windows: All visible windows to consider
     */
    private func applyDecayDimmingToWindows(_ windows: [TrackedWindow]) {
        guard SettingsManager.shared.inactivityDecayEnabled else {
            // If decay is disabled, clear any existing decay overlays
            overlayManager.applyDecayDimming([])
            return
        }
        
        let settings = SettingsManager.shared
        let inactivityTracker = WindowInactivityTracker.shared
        
        var decayDecisions: [OverlayManager.DecayDimmingDecision] = []
        
        for window in windows {
            // Calculate decay dim level for this window
            let inactivityDuration = inactivityTracker.getInactivityDuration(for: window.id)
            let delayedInactivity = max(0, inactivityDuration - settings.decayStartDelay)
            
            // Decay formula: rate × time since delay ended
            let decayDimLevel = CGFloat(settings.decayRate * delayedInactivity)
            
            // Clamp to max decay level
            let clampedDecayLevel = min(decayDimLevel, CGFloat(settings.maxDecayDimLevel))
            
            // Debug: Log each window's decay calculation
            if inactivityDuration > 0 || window.isActive {
                print("⏰ Decay calc for '\(window.ownerName)' (ID:\(window.id)): " +
                      "isActive=\(window.isActive), " +
                      "inactivity=\(String(format: "%.1f", inactivityDuration))s, " +
                      "delayedInactivity=\(String(format: "%.1f", delayedInactivity))s, " +
                      "decayLevel=\(String(format: "%.2f", clampedDecayLevel))")
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
        
        // Apply decay overlays
        overlayManager.applyDecayDimming(decayDecisions)
        
        let decayingCount = decayDecisions.filter { !$0.isActive && $0.decayDimLevel > 0 }.count
        let totalInactive = decayDecisions.filter { !$0.isActive }.count
        debugLog("⏰ Applied decay dimming: \(decayingCount) with visible dim, \(totalInactive) total inactive")
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
            // How much above threshold determines intensity
            // Brightness of 1.0 with threshold 0.85 = 15% over = higher dim
            let overage = brightness - threshold
            let overageRatio = overage / (1.0 - threshold)  // 0.0-1.0
            
            // Scale dim level based on overage and settings
            let baseDimLevel = configuration.globalDimLevel
            dimLevel = baseDimLevel * CGFloat(0.5 + overageRatio * 0.5)
            
            // Reduce dimming for active window if that setting is enabled
            if window.isActive && configuration.differentiateActiveInactive {
                dimLevel = configuration.activeDimLevel
                reason = .activeWindowReduced
            } else if !window.isActive && configuration.differentiateActiveInactive {
                dimLevel = configuration.inactiveDimLevel
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
    var statusText: String {
        if !isAnalyzing && overlayCount == 0 && windowCount == 0 {
            return "Idle"
        } else if isAnalyzing {
            return "Scanning..."
        } else if overlayCount > 0 {
            return "\(overlayCount) region\(overlayCount == 1 ? "" : "s") dimmed"
        } else {
            return "No bright areas detected"
        }
    }
}
