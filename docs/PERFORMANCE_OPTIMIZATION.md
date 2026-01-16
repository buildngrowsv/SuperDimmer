# SuperDimmer Performance Optimization Guide

## Overview

This document outlines performance optimization strategies for SuperDimmer, analyzing current CPU-intensive operations and proposing solutions for adaptive, system-aware performance management.

**Created:** January 16, 2026  
**Last Updated:** January 16, 2026

---

## Table of Contents

1. [Current Architecture](#current-architecture)
2. [CPU-Intensive Operations](#cpu-intensive-operations)
3. [Current Throttling Mechanisms](#current-throttling-mechanisms)
4. [macOS System APIs for Adaptive Performance](#macos-system-apis-for-adaptive-performance)
5. [Proposed Optimizations](#proposed-optimizations)
6. [Implementation Priority](#implementation-priority)
7. [Metrics & Profiling](#metrics--profiling)

---

## Current Architecture

### Timer-Based Analysis Loops

SuperDimmer uses two separate timer loops:

| Timer | Default Interval | Purpose | CPU Impact |
|-------|------------------|---------|------------|
| **analysisTimer** | 2.0 seconds | Brightness analysis (screenshots) | Heavy |
| **windowTrackingTimer** | 0.5 seconds | Position/z-order updates | Light |

### Processing Queue

```swift
private let analysisQueue = DispatchQueue(
    label: "com.superdimmer.analysis",
    qos: .userInitiated  // Currently high priority
)
```

**Issue:** `.userInitiated` QoS competes with user-facing operations. This could cause:
- UI lag during analysis
- Visible stuttering when user is actively working
- Battery drain from high-priority scheduling

---

## CPU-Intensive Operations

### 1. Screen Capture (`ScreenCaptureService`)

**Cost:** HIGH (GPU + Memory)

```swift
// Current implementation
CGWindowListCreateImage(bounds, [.optionOnScreenBelowWindow], windowID, .bestResolution)
```

**What happens:**
1. WindowServer captures pixel data from GPU framebuffer
2. Data is copied to CPU-accessible memory
3. CGImage is created (memory allocation)
4. Image data is processed for brightness analysis

**Typical timing:** 10-50ms per window depending on size

### 2. Brightness Analysis (`BrightnessAnalysisEngine`)

**Cost:** MEDIUM (CPU-bound, but uses SIMD)

```swift
// Uses Accelerate framework (vDSP) for SIMD operations
// Rec. 709 luminance: Y = 0.2126*R + 0.7152*G + 0.0722*B
```

**What happens:**
1. Extract pixel data from CGImage
2. Split into R, G, B channels
3. Apply luminance coefficients using vDSP
4. Calculate average

**Typical timing:** 5-20ms per window

### 3. Region Detection (`BrightRegionDetector`)

**Cost:** MEDIUM (CPU-bound)

```swift
// Downsamples to 80x80 pixels
// Flood-fill algorithm for connected components
// Bounding box calculation
```

**What happens:**
1. Downsample image to 80x80 (fast)
2. Create binary mask based on threshold
3. Find connected components (flood-fill)
4. Calculate bounding boxes
5. Merge overlapping regions

**Typical timing:** 5-15ms per window

### 4. Window Enumeration (`WindowTrackerService`)

**Cost:** LOW (API call)

```swift
CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
```

**What happens:**
1. Query WindowServer for window list
2. Parse returned dictionaries
3. Filter and transform to `TrackedWindow` structs

**Typical timing:** 1-5ms total

### 5. Overlay Updates (`OverlayManager`)

**Cost:** LOW (UI operations)

```swift
overlay.setFrame(newFrame, display: true)
overlay.orderWindow(.above, relativeTo: targetWindowNumber)
```

**What happens:**
1. Update NSWindow frame
2. Reorder in window stack
3. Compositor handles actual rendering

**Typical timing:** <1ms per overlay

---

## Current Throttling Mechanisms

### 1. Scan Interval (User Configurable)
```swift
// Settings: 0.5 - 5.0 seconds (default 2.0)
@Published var scanInterval: Double
```

### 2. Window Tracking Interval (User Configurable)
```swift
// Settings: 0.1 - 2.0 seconds (default 0.5)
@Published var windowTrackingInterval: Double
```

### 3. Minimum Capture Interval
```swift
// ScreenCaptureService.swift
var minimumCaptureInterval: TimeInterval = 0.1  // Max 10 captures/sec
```

### 4. Analysis Throttle
```swift
// Skip if we just ran analysis
if analysisStart - lastAnalysisTime < minAnalysisInterval * 0.5 {
    return
}
```

### 5. Click Debouncing
```swift
// Debounce mouse clicks (150ms delay before re-analysis)
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
```

---

## macOS System APIs for Adaptive Performance

### 1. Thermal State Monitoring

macOS provides real-time thermal state information:

```swift
import Foundation

// Current thermal state
let thermalState = ProcessInfo.processInfo.thermalState

// Possible values:
// .nominal  - System running normally
// .fair     - Slightly elevated, minor throttling may occur
// .serious  - Significant thermal pressure, should reduce work
// .critical - Maximum thermal pressure, must reduce work immediately

// Listen for changes:
NotificationCenter.default.addObserver(
    forName: ProcessInfo.thermalStateDidChangeNotification,
    object: nil,
    queue: .main
) { _ in
    let state = ProcessInfo.processInfo.thermalState
    handleThermalStateChange(state)
}
```

**Recommended response:**

| State | Action |
|-------|--------|
| `.nominal` | Normal operation |
| `.fair` | Increase scan interval by 1.5x |
| `.serious` | Increase scan interval by 2x, skip non-essential work |
| `.critical` | Increase scan interval by 4x, minimal operation mode |

### 2. Low Power Mode

```swift
// Check if Low Power Mode is enabled (laptops)
let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

// Listen for changes:
NotificationCenter.default.addObserver(
    forName: .NSProcessInfoPowerStateDidChange,
    object: nil,
    queue: .main
) { _ in
    let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    handlePowerModeChange(isLowPower)
}
```

### 3. Active Processor Count

```swift
// Number of active processors (may be reduced during thermal throttling)
let activeProcessors = ProcessInfo.processInfo.activeProcessorCount
let totalProcessors = ProcessInfo.processInfo.processorCount

// If activeProcessors < totalProcessors, system is throttling
let throttleRatio = Double(activeProcessors) / Double(totalProcessors)
```

### 4. Memory Pressure

```swift
import Dispatch

// Create memory pressure source
let memorySource = DispatchSource.makeMemoryPressureSource(
    eventMask: [.warning, .critical],
    queue: .main
)

memorySource.setEventHandler {
    let event = memorySource.data
    if event.contains(.critical) {
        // Critical memory pressure - clear all caches
        clearAllCaches()
    } else if event.contains(.warning) {
        // Warning - reduce memory usage
        clearNonEssentialCaches()
    }
}

memorySource.resume()
```

### 5. System Idle Time

```swift
import IOKit

// Get system idle time (how long since last user input)
func systemIdleTime() -> TimeInterval? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(
        kIOMasterPortDefault,
        IOServiceMatching("IOHIDSystem"),
        &iterator
    ) == KERN_SUCCESS else { return nil }
    
    let entry = IOIteratorNext(iterator)
    defer { IOObjectRelease(entry); IOObjectRelease(iterator) }
    
    var unmanagedDict: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(
        entry,
        &unmanagedDict,
        kCFAllocatorDefault,
        0
    ) == KERN_SUCCESS else { return nil }
    
    guard let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
          let idleTime = dict["HIDIdleTime"] as? Int64 else { return nil }
    
    return TimeInterval(idleTime) / 1_000_000_000  // Convert from nanoseconds
}
```

**Use case:** If system has been idle for a while, we can run more intensive analysis without impacting user experience.

---

## Proposed Optimizations

### Priority 1: QoS Adjustment

**Current:** `.userInitiated` (high priority)  
**Proposed:** `.utility` (lower priority, won't compete with UI)

```swift
private let analysisQueue = DispatchQueue(
    label: "com.superdimmer.analysis",
    qos: .utility  // Changed from .userInitiated
)
```

**Benefits:**
- Lets macOS prioritize user interactions
- Analysis happens "in the background" even though it's not truly background
- Battery efficiency improvements

### Priority 2: Thermal-Aware Scaling

```swift
class AdaptivePerformanceManager {
    static let shared = AdaptivePerformanceManager()
    
    private var baseScanInterval: Double = 2.0
    private var thermalMultiplier: Double = 1.0
    private var powerMultiplier: Double = 1.0
    
    var effectiveScanInterval: Double {
        baseScanInterval * thermalMultiplier * powerMultiplier
    }
    
    init() {
        setupThermalObserver()
        setupPowerObserver()
    }
    
    private func setupThermalObserver() {
        updateThermalMultiplier()
        
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThermalMultiplier()
        }
    }
    
    private func updateThermalMultiplier() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalMultiplier = 1.0
        case .fair:
            thermalMultiplier = 1.5
        case .serious:
            thermalMultiplier = 2.0
        case .critical:
            thermalMultiplier = 4.0
        @unknown default:
            thermalMultiplier = 1.0
        }
        
        notifyIntervalChanged()
    }
    
    private func setupPowerObserver() {
        updatePowerMultiplier()
        
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePowerMultiplier()
        }
    }
    
    private func updatePowerMultiplier() {
        powerMultiplier = ProcessInfo.processInfo.isLowPowerModeEnabled ? 2.0 : 1.0
        notifyIntervalChanged()
    }
    
    private func notifyIntervalChanged() {
        NotificationCenter.default.post(
            name: .scanIntervalShouldUpdate,
            object: nil,
            userInfo: ["interval": effectiveScanInterval]
        )
    }
}
```

### Priority 3: Smart Skip Conditions

```swift
func shouldSkipAnalysisCycle() -> Bool {
    // Skip if thermal state is critical
    if ProcessInfo.processInfo.thermalState == .critical {
        return true
    }
    
    // Skip if user is actively switching apps (high activity)
    let timeSinceLastAppSwitch = Date().timeIntervalSince(lastAppSwitchTime)
    if timeSinceLastAppSwitch < 0.3 {
        return true  // User is app-switching, wait
    }
    
    // Skip if window count changed dramatically (major UI rearrangement)
    let currentWindowCount = WindowTrackerService.shared.getVisibleWindows().count
    if abs(currentWindowCount - previousWindowCount) > 3 {
        previousWindowCount = currentWindowCount
        return true  // Major change, let things settle
    }
    
    // Skip if system is under memory pressure
    // (Would need memory pressure source setup)
    
    return false
}
```

### Priority 4: Incremental Analysis

Instead of analyzing all windows every cycle, analyze incrementally:

```swift
class IncrementalAnalyzer {
    private var windowAnalysisQueue: [CGWindowID] = []
    private var analysisResults: [CGWindowID: AnalysisResult] = [:]
    private var windowsPerCycle: Int = 2  // Analyze 2 windows per cycle
    
    func performIncrementalAnalysis() {
        // 1. Update window list
        let currentWindows = WindowTrackerService.shared.getVisibleWindows()
        let currentIDs = Set(currentWindows.map { $0.id })
        
        // 2. Remove stale results
        analysisResults = analysisResults.filter { currentIDs.contains($0.key) }
        
        // 3. Add new windows to queue (prioritize frontmost)
        let frontmostID = currentWindows.first(where: { $0.isActive })?.id
        for window in currentWindows {
            if !analysisResults.keys.contains(window.id) {
                if window.id == frontmostID {
                    windowAnalysisQueue.insert(window.id, at: 0)  // Prioritize
                } else {
                    windowAnalysisQueue.append(window.id)
                }
            }
        }
        
        // 4. Analyze a subset this cycle
        let windowsToAnalyze = Array(windowAnalysisQueue.prefix(windowsPerCycle))
        windowAnalysisQueue.removeFirst(min(windowsPerCycle, windowAnalysisQueue.count))
        
        for windowID in windowsToAnalyze {
            if let window = currentWindows.first(where: { $0.id == windowID }) {
                analyzeWindow(window)
            }
        }
        
        // 5. Apply all current results
        applyDimmingFromResults()
    }
}
```

**Benefits:**
- Spreads CPU load across multiple cycles
- Prioritizes active window
- More responsive feel even with slower total analysis

### Priority 5: Resolution Scaling

Reduce capture resolution based on system state:

```swift
func captureResolutionScale() -> CGFloat {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
        return 1.0      // Full resolution
    case .fair:
        return 0.75     // 75% resolution
    case .serious:
        return 0.5      // 50% resolution
    case .critical:
        return 0.25     // 25% resolution
    @unknown default:
        return 1.0
    }
}

// In ScreenCaptureService:
func captureWindow(_ windowID: CGWindowID) -> CGImage? {
    let scale = captureResolutionScale()
    // Apply scale to capture options...
}
```

### Priority 6: Caching Improvements

```swift
class AnalysisCache {
    struct CachedResult {
        let regions: [BrightRegion]
        let timestamp: Date
        let windowBounds: CGRect
        let windowContentHash: Int  // Hash of window content for change detection
    }
    
    private var cache: [CGWindowID: CachedResult] = [:]
    private let maxAge: TimeInterval = 5.0  // Results valid for 5 seconds
    
    func getCachedResult(for windowID: CGWindowID, currentBounds: CGRect) -> [BrightRegion]? {
        guard let cached = cache[windowID] else { return nil }
        
        // Check if cache is still valid
        let age = Date().timeIntervalSince(cached.timestamp)
        guard age < maxAge else { return nil }
        
        // Check if window moved/resized (invalidates cache)
        guard cached.windowBounds == currentBounds else { return nil }
        
        return cached.regions
    }
    
    func cacheResult(_ regions: [BrightRegion], for windowID: CGWindowID, bounds: CGRect) {
        cache[windowID] = CachedResult(
            regions: regions,
            timestamp: Date(),
            windowBounds: bounds,
            windowContentHash: 0  // Could compute content hash for smarter invalidation
        )
    }
}
```

---

## Implementation Priority

| Priority | Optimization | Effort | Impact | Risk |
|----------|--------------|--------|--------|------|
| **1** | Lower QoS to `.utility` | Low | Medium | Low |
| **2** | Thermal state monitoring | Medium | High | Low |
| **3** | Smart skip conditions | Medium | Medium | Low |
| **4** | Low power mode awareness | Low | Medium | Low |
| **5** | Incremental analysis | High | High | Medium |
| **6** | Resolution scaling | Medium | Medium | Low |
| **7** | Memory pressure response | Medium | Low | Low |

### Quick Wins (< 1 hour each)
1. Change QoS to `.utility`
2. Add thermal state observer
3. Add low power mode observer

### Medium Effort (1-4 hours each)
1. Implement `AdaptivePerformanceManager`
2. Add smart skip conditions
3. Add resolution scaling

### Larger Effort (4+ hours)
1. Implement incremental analysis
2. Content-aware caching with hash validation

---

## Metrics & Profiling

### Recommended Metrics to Track

```swift
struct PerformanceMetrics {
    // Timing
    var captureTimeMs: [Double] = []
    var analysisTimeMs: [Double] = []
    var overlayUpdateTimeMs: [Double] = []
    var totalCycleTimeMs: [Double] = []
    
    // Counts
    var cycleCount: Int = 0
    var skippedCycles: Int = 0
    var windowsAnalyzed: Int = 0
    var regionsDetected: Int = 0
    
    // System state
    var thermalState: ProcessInfo.ThermalState = .nominal
    var isLowPowerMode: Bool = false
    var activeProcessors: Int = 0
    
    // Computed
    var averageCaptureTime: Double {
        captureTimeMs.isEmpty ? 0 : captureTimeMs.reduce(0, +) / Double(captureTimeMs.count)
    }
    
    var averageCycleTime: Double {
        totalCycleTimeMs.isEmpty ? 0 : totalCycleTimeMs.reduce(0, +) / Double(totalCycleTimeMs.count)
    }
    
    var skipRate: Double {
        cycleCount == 0 ? 0 : Double(skippedCycles) / Double(cycleCount + skippedCycles)
    }
}
```

### Debug Mode Logging

```swift
func logPerformanceMetrics() {
    let metrics = PerformanceMetrics.shared
    
    print("""
    📊 Performance Metrics:
    ├─ Avg Capture Time: \(String(format: "%.1f", metrics.averageCaptureTime))ms
    ├─ Avg Analysis Time: \(String(format: "%.1f", metrics.averageAnalysisTime))ms
    ├─ Avg Cycle Time: \(String(format: "%.1f", metrics.averageCycleTime))ms
    ├─ Windows/Cycle: \(metrics.windowsAnalyzed / max(1, metrics.cycleCount))
    ├─ Regions/Cycle: \(metrics.regionsDetected / max(1, metrics.cycleCount))
    ├─ Skip Rate: \(String(format: "%.1f", metrics.skipRate * 100))%
    ├─ Thermal State: \(metrics.thermalState)
    └─ Low Power Mode: \(metrics.isLowPowerMode)
    """)
}
```

---

## References

- [Apple: Responding to Thermal State Changes](https://developer.apple.com/documentation/foundation/processinfo/1417480-thermalstate)
- [Apple: Energy Efficiency Guide for Mac Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/)
- [Apple: Dispatch QoS](https://developer.apple.com/documentation/dispatch/dispatchqos)
- [Apple: Memory Pressure](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureflags)
- [Apple: Accelerate Framework](https://developer.apple.com/documentation/accelerate)

---

## Changelog

- **2026-01-16:** Initial document created with research findings and optimization proposals
