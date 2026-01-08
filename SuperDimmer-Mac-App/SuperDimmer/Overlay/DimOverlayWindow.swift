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
     Whether blurred/feathered edges are currently enabled.
     When enabled, the overlay has a soft gradient around the edges.
     */
    private var edgeBlurEnabled: Bool = false
    
    /**
     The radius of the edge blur effect in points.
     */
    private var edgeBlurRadius: CGFloat = 15.0
    
    /**
     The gradient mask layer for feathered edges.
     Stored so we can update it when settings change.
     */
    private var gradientMaskLayer: CAGradientLayer?
    
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
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Sets the dim level with optional animation.
     
     - Parameters:
       - level: The new dim level (0.0 = no dimming, 1.0 = full black)
       - animated: Whether to animate the transition (default: true)
       - duration: Animation duration in seconds (default: 0.25)
     */
    func setDimLevel(_ level: CGFloat, animated: Bool = true, duration: TimeInterval = 0.25) {
        guard let layer = dimView?.layer else {
            print("⚠️ DimOverlayWindow: No layer available for dim level change")
            return
        }
        
        let clampedLevel = max(0.0, min(1.0, level))
        guard abs(clampedLevel - dimLevel) > 0.01 else { return }
        
        let newColor = NSColor.black.withAlphaComponent(clampedLevel).cgColor
        
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
        
        self.dimLevel = clampedLevel
    }
    
    /**
     Updates the window's position and size.
     
     - Parameter rect: The new frame rectangle (in screen coordinates)
     - Parameter animated: Whether to animate the frame change
     */
    func updatePosition(to rect: CGRect, animated: Bool = false) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(rect, display: true)
            } completionHandler: { [weak self] in
                // Update feathered edge mask after animation completes
                self?.updateFeatheredEdgeMaskIfNeeded()
            }
        } else {
            self.setFrame(rect, display: true)
            // Update feathered edge mask for new size
            updateFeatheredEdgeMaskIfNeeded()
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
    
    // ================================================================
    // MARK: - Edge Blur (Feathered Edges)
    // ================================================================
    
    /**
     Enables or disables the blurred/feathered edge effect.
     
     When enabled, the overlay has a soft gradient around the edges that
     fades from the dim color to transparent. This creates a less jarring
     visual transition compared to hard rectangular cutoffs.
     
     IMPLEMENTATION:
     We use a radial gradient mask on the dim view's layer. The mask is
     fully opaque in the center and fades to transparent at the edges.
     This is more performant than blur filters and doesn't require
     expensive GPU operations.
     
     - Parameters:
       - enabled: Whether to enable the edge blur effect
       - radius: The blur radius in points (how far the fade extends)
     */
    func setEdgeBlur(enabled: Bool, radius: CGFloat = 15.0) {
        self.edgeBlurEnabled = enabled
        self.edgeBlurRadius = radius
        
        guard let layer = dimView?.layer else { return }
        
        if enabled {
            applyFeatheredEdgeMask(to: layer, radius: radius)
        } else {
            // Remove the mask for sharp edges
            layer.mask = nil
            gradientMaskLayer = nil
        }
    }
    
    /**
     Applies a feathered edge mask to the given layer.
     
     The mask creates a soft fade around all edges of the overlay.
     We use a special technique: draw a rectangle with rounded corners
     and apply a blur to the alpha channel.
     
     - Parameters:
       - layer: The layer to mask
       - radius: The feather radius in points
     */
    private func applyFeatheredEdgeMask(to layer: CALayer, radius: CGFloat) {
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        // Create a mask layer that's opaque in center, fades at edges
        // Using a shape with gradient fill to simulate feathered edges
        let maskLayer = CALayer()
        maskLayer.frame = bounds
        
        // Create an inner rect that's fully opaque
        // The area between inner rect and outer bounds will fade
        let inset = radius
        let innerRect = bounds.insetBy(dx: inset, dy: inset)
        
        // Use a gradient layer approach: 
        // We'll create a rectangular shape and add a shadow to simulate blur
        let shapeLayer = CAShapeLayer()
        shapeLayer.frame = bounds
        
        // Create a path for the inner opaque area
        let path = CGMutablePath()
        // Outer rect (full bounds) - we'll use this for the "shadow" area
        path.addRect(bounds)
        // Inner rect - this will be the opaque center
        path.addRoundedRect(in: innerRect, cornerWidth: radius * 0.5, cornerHeight: radius * 0.5)
        
        // Use the path as a mask but with a soft edge
        // We achieve this by drawing a white fill with a shadow
        shapeLayer.fillColor = NSColor.clear.cgColor
        
        // Actually, a simpler approach: use a CAGradientLayer as mask
        // with radial gradient to create soft edges
        // But CAGradientLayer doesn't support true radial fading on edges
        
        // Best approach for performant feathered edges:
        // Draw the mask image programmatically with CoreGraphics
        let maskImage = createFeatheredMaskImage(size: bounds.size, radius: radius)
        maskLayer.contents = maskImage
        
        layer.mask = maskLayer
        gradientMaskLayer = CAGradientLayer() // Keep reference for updates
    }
    
    /**
     Creates a mask image with feathered (soft) edges.
     
     This creates a grayscale mask where:
     - White (1.0) = fully visible (center area)
     - Black (0.0) = fully transparent (outer edge)
     - Gradient in between = fade
     
     The mask fades from the outer edge inward over the specified radius,
     creating a soft/blurred edge effect without expensive filters.
     
     FIX (Jan 8, 2026): Previous implementation was inverted and drew
     strokes instead of proper gradient fills. This version uses
     concentric filled rectangles with decreasing opacity from center
     to edge.
     
     - Parameters:
       - size: The size of the mask image
       - radius: The feather radius (how far the fade extends inward)
     - Returns: A CGImage suitable for use as a layer mask
     */
    private func createFeatheredMaskImage(size: CGSize, radius: CGFloat) -> CGImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let scaledRadius = radius * scale
        
        guard width > 0, height > 0 else { return nil }
        
        // Create grayscale bitmap context
        // In a mask: white = visible, black = invisible
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            print("⚠️ Failed to create mask context")
            return nil
        }
        
        // Start with black (fully transparent/invisible)
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw concentric rectangles from outside (black) to inside (white)
        // Each layer is slightly more opaque
        let steps = max(1, Int(scaledRadius))
        
        for i in 0...steps {
            // Progress from 0 (outer edge) to 1 (inner area)
            let progress = CGFloat(i) / CGFloat(steps)
            let inset = scaledRadius - (progress * scaledRadius)
            
            // Use smooth easing (ease-in) for more natural falloff
            let gray = progress * progress * progress // Cubic ease-in
            
            context.setFillColor(gray: gray, alpha: 1.0)
            
            let rect = CGRect(
                x: inset,
                y: inset,
                width: CGFloat(width) - inset * 2,
                height: CGFloat(height) - inset * 2
            )
            
            if rect.width > 0 && rect.height > 0 {
                // Fill with rounded corners for smoother appearance
                let cornerRadius = min(inset * 0.5, 10 * scale)
                let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                context.addPath(path)
                context.fillPath()
            }
        }
        
        // Fill center with white (fully visible)
        let centerInset = scaledRadius
        let centerRect = CGRect(
            x: centerInset,
            y: centerInset,
            width: CGFloat(width) - centerInset * 2,
            height: CGFloat(height) - centerInset * 2
        )
        if centerRect.width > 0 && centerRect.height > 0 {
            context.setFillColor(gray: 1.0, alpha: 1.0)
            context.fill(centerRect)
        }
        
        return context.makeImage()
    }
    
    /**
     Updates the feathered edge mask when the window is resized.
     Called internally when frame changes if edge blur is enabled.
     */
    private func updateFeatheredEdgeMaskIfNeeded() {
        guard edgeBlurEnabled, let layer = dimView?.layer else { return }
        applyFeatheredEdgeMask(to: layer, radius: edgeBlurRadius)
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
    
    deinit {
        print("📦 DimOverlayWindow destroyed: \(overlayID)")
    }
}
