/**
 ====================================================================
 DimOverlayWindow.swift
 Transparent overlay window for dimming screen content
 ====================================================================
 
 PURPOSE:
 This NSWindow subclass creates a transparent, click-through window
 that dims the content beneath it. It's the fundamental building block
 of SuperDimmer's dimming system.
 
 KEY CHARACTERISTICS:
 - Borderless: No title bar, shadow, or chrome
 - Transparent: Background is clear, only the dim layer shows
 - Click-through: Mouse events pass to windows beneath
 - High z-order: Appears above most content but below system UI
 - Multi-space: Appears on all virtual desktops
 - Fullscreen-aware: Works with fullscreen apps
 
 TECHNICAL IMPLEMENTATION:
 Based on analysis of MonitorControlLite and Lunar which use similar
 overlay techniques. The critical settings are:
 - ignoresMouseEvents = true (CRITICAL - allows click-through)
 - level = .screenSaver (high enough to be visible, not blocking UI)
 - collectionBehavior with canJoinAllSpaces and fullScreenAuxiliary
 
 ANIMATION:
 Dim level changes are animated using Core Animation for smooth
 transitions. Instant changes would be visually jarring.
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import AppKit
import QuartzCore

// ====================================================================
// MARK: - Dim Overlay Window
// ====================================================================

/**
 A transparent window that dims content beneath it.
 
 USAGE:
 1. Create with factory method: DimOverlayWindow.create(...)
 2. Call orderFront() to show
 3. Use setDimLevel() to adjust opacity
 4. Call close() to remove
 
 The window is configured to:
 - Pass through all mouse events
 - Appear on all Spaces
 - Work with fullscreen apps
 - Animate opacity changes smoothly
 */
final class DimOverlayWindow: NSWindow {
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     The current dim level (0.0 = no dim, 1.0 = full black).
     */
    private(set) var dimLevel: CGFloat = 0.0
    
    /**
     The view that provides the actual dimming effect.
     */
    private var dimView: NSView?
    
    /**
     Unique identifier for this overlay.
     */
    private(set) var overlayID: String = UUID().uuidString
    
    /**
     Flag to prevent double-close crashes.
     
     FIX (Jan 8, 2026): Added to prevent EXC_BAD_ACCESS crash.
     The crash could happen when close() was called multiple times on the same
     window (due to race conditions in overlay management). NSWindow.close()
     is not idempotent - calling it twice on the same window can crash.
     */
    private var isClosing: Bool = false
    
    // ================================================================
    // MARK: - Factory Methods
    // ================================================================
    
    /**
     Creates a new dim overlay window configured for screen dimming.
     
     - Parameters:
       - frame: The frame rectangle for the window (in screen coordinates)
       - dimLevel: Initial dimming intensity (0.0-1.0)
       - id: Unique identifier for this overlay
     - Returns: Configured overlay window ready to display
     
     This factory method creates the window and configures all necessary
     properties for overlay behavior.
     */
    static func create(frame: CGRect, dimLevel: CGFloat, id: String = UUID().uuidString) -> DimOverlayWindow {
        // Create the window with borderless style
        let window = DimOverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Store the ID
        window.overlayID = id
        
        // Configure window properties
        window.configureForOverlay()
        
        // Setup the dim view with initial level
        window.setupDimView(initialDimLevel: dimLevel)
        
        print("📦 DimOverlayWindow created: \(id) at \(frame)")
        return window
    }
    
    /**
     Creates a full-screen overlay for a specific screen.
     
     - Parameters:
       - screen: The screen to cover
       - dimLevel: Initial dim level
     - Returns: Configured overlay window covering the entire screen
     */
    static func fullScreen(for screen: NSScreen, dimLevel: CGFloat) -> DimOverlayWindow {
        let window = create(
            frame: screen.frame,
            dimLevel: dimLevel,
            id: "fullscreen-\(screen.localizedName)"
        )
        return window
    }
    
    /**
     Creates an overlay for a specific window.
     
     - Parameters:
       - windowFrame: The frame of the target window
       - dimLevel: Initial dim level
       - windowID: The target window's ID (for tracking)
     - Returns: Configured overlay window matching the target
     */
    static func forWindow(frame windowFrame: CGRect, dimLevel: CGFloat, windowID: CGWindowID) -> DimOverlayWindow {
        return create(
            frame: windowFrame,
            dimLevel: dimLevel,
            id: "window-\(windowID)"
        )
    }
    
    // ================================================================
    // MARK: - Configuration
    // ================================================================
    
    /**
     Configures the window for overlay behavior.
     
     Sets all the critical properties that make this window behave
     as a transparent, click-through overlay.
     */
    private func configureForOverlay() {
        // Make the window transparent
        self.isOpaque = false
        self.backgroundColor = .clear
        
        // No shadow
        self.hasShadow = false
        
        // CRITICAL: Click-through behavior
        // Without this, the overlay would block all mouse interaction!
        self.ignoresMouseEvents = true
        
        // Z-order: Same level as normal windows
        // FIX (Jan 8, 2026): Changed from .floating to .normal
        // This allows us to position the overlay DIRECTLY above the target window
        // using orderWindow(.above, relativeTo:) without being above ALL windows.
        // 
        // For full-screen dimming, we'll set .screenSaver separately.
        // For per-region mode, we use .normal and position relatively.
        self.level = .normal
        
        // Collection behavior for Spaces and fullscreen
        self.collectionBehavior = [
            .canJoinAllSpaces,          // Appear on all virtual desktops
            .fullScreenAuxiliary,       // Work alongside fullscreen apps
            .stationary,                // Don't move when other windows are dragged
            .ignoresCycle               // Not included in Cmd+Tab or Cmd+`
        ]
        
        // Don't hide on deactivate
        self.hidesOnDeactivate = false
    }
    
    // ================================================================
    // MARK: - Dim View Setup
    // ================================================================
    
    /**
     Creates and configures the view that provides the dimming effect.
     
     - Parameter initialDimLevel: The starting opacity (0.0-1.0)
     */
    private func setupDimView(initialDimLevel: CGFloat) {
        let view = NSView(frame: self.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        
        // Enable layer-backing for Core Animation
        view.wantsLayer = true
        
        // Set the background color with initial alpha
        let clampedLevel = max(0.0, min(1.0, initialDimLevel))
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(clampedLevel).cgColor
        
        // FEATURE 2.8.2b: Apply corner radius for rounded edges
        // This provides a softer, more polished look than hard rectangular edges.
        // Uses GPU-accelerated layer.cornerRadius for performance.
        // The radius is configurable in settings (default 8pt, can be 0 for sharp edges).
        applyCornerRadius()
        
        // DEBUG MODE: Add visible borders when enabled
        // This helps diagnose positioning issues - shows exactly where overlays are
        updateDebugBorders()
        
        // Store reference and add to window
        self.dimView = view
        self.contentView?.addSubview(view)
        self.dimLevel = clampedLevel
        
        print("📦 DimView setup with level: \(clampedLevel)")
    }
    
    // ================================================================
    // MARK: - Z-Ordering
    // ================================================================
    
    /**
     Positions this overlay directly above a target window.
     
     This is the key to proper Z-ordering! Instead of being above ALL windows
     (like .floating or .screenSaver level), this positions the overlay just
     above the specific window it's dimming.
     
     If another window is in front of the target, it won't be covered by
     this overlay - the overlay stays at the same Z-order as its target.
     
     - Parameter windowID: The CGWindowID of the target window to appear above
     
     FIX (Jan 8, 2026): Added to solve the "overlay covers windows above target" bug
     */
    func orderAboveWindow(_ windowID: CGWindowID) {
        // CRASH FIX (Jan 9, 2026): Protect against accessing closed window
        guard !isClosing else {
            print("⚠️ DimOverlayWindow: Ignoring orderAboveWindow on closing window: \(overlayID)")
            return
        }
        
        // Position this window directly above the target window
        // The Int(windowID) is the window number that macOS uses
        self.order(.above, relativeTo: Int(windowID))
    }
    
    // ================================================================
    // MARK: - Debug Mode
    // ================================================================
    
    /**
     Updates debug borders on the overlay.
     
     Call this when the debugOverlayBorders setting changes to update
     the visual appearance of existing overlays without recreating them.
     */
    func updateDebugBorders() {
        guard let layer = dimView?.layer else { return }
        
        if SettingsManager.shared.debugOverlayBorders {
            layer.borderWidth = 4.0
            layer.borderColor = NSColor.red.cgColor
            print("🔴 Debug borders ENABLED for \(overlayID)")
        } else {
            layer.borderWidth = 0.0
            layer.borderColor = nil
        }
    }
    
    /**
     Applies corner radius to the overlay for rounded edges.
     
     FEATURE 2.8.2b: Rounded Corners for Overlays
     
     This provides a softer, more polished look compared to hard rectangular edges.
     The corner radius is configurable in settings (default 8pt).
     
     IMPLEMENTATION:
     - Uses CALayer.cornerRadius (GPU-accelerated, no performance impact)
     - Works perfectly with debug borders
     - No visual artifacts during animations or window resize
     - Setting radius to 0 gives sharp corners for users who prefer that
     
     Call this when:
     - Creating a new overlay (in setupDimView)
     - Corner radius setting changes (via notification observer)
     */
    func applyCornerRadius() {
        guard let layer = dimView?.layer else { return }
        
        let radius = CGFloat(SettingsManager.shared.overlayCornerRadius)
        layer.cornerRadius = radius
        layer.masksToBounds = true  // Required to clip content to rounded corners
        
        print("🔘 Applied corner radius: \(radius)pt to \(overlayID)")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Sets the dim level with optional animation.
     
     - Parameters:
       - level: The new dim level (0.0 = no dimming, 1.0 = full black)
       - animated: Whether to animate the transition (default: true)
       - duration: Animation duration in seconds (default: 0.35 for smooth transitions)
     
     FIX (Jan 8, 2026): Increased default duration from 0.25s to 0.35s for smoother
     transitions, especially when switching between active/inactive windows.
     Uses .easeInEaseOut timing for natural, non-linear animation.
     */
    func setDimLevel(_ level: CGFloat, animated: Bool = true, duration: TimeInterval = 0.35) {
        // CRASH FIX (Jan 9, 2026): Protect against accessing closed window
        // The EXC_BAD_ACCESS was happening in autorelease pool drain after CA operations.
        // This guard prevents operating on windows that are being/have been closed.
        guard !isClosing else {
            print("⚠️ DimOverlayWindow: Ignoring setDimLevel on closing window: \(overlayID)")
            return
        }
        
        guard let layer = dimView?.layer else {
            print("⚠️ DimOverlayWindow: No layer available for dim level change")
            return
        }
        
        let clampedLevel = max(0.0, min(1.0, level))
        guard abs(clampedLevel - dimLevel) > 0.01 else { return }
        
        let newColor = NSColor.black.withAlphaComponent(clampedLevel).cgColor
        
        // CRASH FIX (Jan 9, 2026): Wrap CA operations in autoreleasepool
        // This ensures any autoreleased objects from CA are drained immediately,
        // not left for the run loop's pool which can crash if objects are freed early.
        autoreleasepool {
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(duration)
                CATransaction.setAnimationTimingFunction(
                    CAMediaTimingFunction(name: .easeInEaseOut)
                )
                layer.backgroundColor = newColor
                CATransaction.commit()
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.backgroundColor = newColor
                CATransaction.commit()
            }
        }
        
        self.dimLevel = clampedLevel
    }
    
    /**
     Updates the window's position and size with smooth animation.
     
     - Parameter rect: The new frame rectangle (in screen coordinates)
     - Parameter animated: Whether to animate the frame change (default: true)
     - Parameter duration: Animation duration in seconds (default: 0.3)
     
     FIX (Jan 8, 2026): Changed default from false to true for smooth transitions
     when overlays resize (e.g., bright region grows/shrinks, aspect ratio changes).
     Uses .easeInEaseOut for consistency with dim level animations.
     
     NOTE: For rapidly changing frames (window being dragged), callers can pass
     animated: false to avoid "lag behind" effect.
     */
    func updatePosition(to rect: CGRect, animated: Bool = true, duration: TimeInterval = 0.3) {
        // CRASH FIX (Jan 9, 2026): Protect against accessing closed window
        guard !isClosing else {
            print("⚠️ DimOverlayWindow: Ignoring updatePosition on closing window: \(overlayID)")
            return
        }
        
        // Skip animation if frame hasn't changed significantly (avoids micro-jitter)
        let currentFrame = self.frame
        let tolerance: CGFloat = 1.0
        let significantChange = abs(currentFrame.origin.x - rect.origin.x) > tolerance ||
                                abs(currentFrame.origin.y - rect.origin.y) > tolerance ||
                                abs(currentFrame.width - rect.width) > tolerance ||
                                abs(currentFrame.height - rect.height) > tolerance
        
        guard significantChange else { return }
        
        // CRASH FIX (Jan 9, 2026): Wrap animation in autoreleasepool
        autoreleasepool {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.animator().setFrame(rect, display: true)
                }
            } else {
                self.setFrame(rect, display: true)
            }
        }
    }
    
    /**
     Fades out and closes the window.
     
     - Parameter duration: Fade out duration (default: 0.2 seconds)
     - Parameter completion: Called after window is closed
     */
    func fadeOutAndClose(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        setDimLevel(0.0, animated: true, duration: duration)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.close()
            completion?()
        }
    }
    
    // NOTE: Feathered edges feature removed (Jan 8, 2026)
    // The mask-based approach was unreliable. Sharp edges work fine for dimming.
    // If soft edges are needed in future, consider using NSVisualEffectView
    // with .behindWindow material instead.
    
    /// Stub for API compatibility - does nothing
    func setEdgeBlur(enabled: Bool, radius: CGFloat = 15.0) {
        // Feature removed - sharp edges only
    }
    
    // ================================================================
    // MARK: - Window Overrides
    // ================================================================
    
    /**
     Prevent the window from becoming key (focused).
     */
    override var canBecomeKey: Bool {
        return false
    }
    
    /**
     Prevent the window from becoming main.
     */
    override var canBecomeMain: Bool {
        return false
    }
    
    /**
     Safe close that prevents double-close crashes.
     
     FIX (Jan 8, 2026): Added to prevent EXC_BAD_ACCESS crash.
     NSWindow.close() is not idempotent - calling it twice can crash.
     This override:
     1. Checks if already closing (prevents double-close)
     2. Flushes Core Animation transactions before closing
     3. Clears layer references to help avoid use-after-free
     */
    override func close() {
        // Prevent double-close
        guard !isClosing else {
            print("⚠️ DimOverlayWindow close() called but already closing: \(overlayID)")
            return
        }
        isClosing = true
        
        // Flush any pending Core Animation transactions
        // This helps ensure animations are committed before we tear down
        CATransaction.flush()
        
        // Clear the dim view's layer to help avoid CA use-after-free
        if let layer = dimView?.layer {
            layer.removeAllAnimations()
        }
        dimView = nil
        
        // Now actually close
        super.close()
    }
    
    deinit {
        // Only log deinit if we weren't in the middle of closing
        // (reduces log noise from normal cleanup)
        if !isClosing {
            print("📦 DimOverlayWindow destroyed (unexpected): \(overlayID)")
        }
    }
}
