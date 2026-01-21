//
//  SuperSpacesHUD.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Floating HUD panel that shows current Space and allows quick Space switching.
//  This is the main "Super Spaces" feature - a Spotlight/Raycast-style overlay for Space navigation.
//
//  WHY THIS FEATURE:
//  - macOS Mission Control requires 3-finger swipe or F3 to see Spaces
//  - No built-in way to see current Space number/name at a glance
//  - Switching to specific Space requires multiple gestures
//  - Super Spaces provides instant visual feedback and one-click switching
//
//  TECHNICAL ARCHITECTURE:
//  - Single NSPanel window (not multiple apps per Space)
//  - Appears on all Spaces via .canJoinAllSpaces
//  - Always on top via .floating level
//  - Auto-updates via SpaceChangeMonitor
//  - SwiftUI content for beautiful, responsive UI
//  - SuperSpacesViewModel ObservableObject bridges panel and view
//
//  WINDOW BEHAVIOR:
//  - Floating panel (doesn't steal focus)
//  - HUD style (transparent titlebar, blur background)
//  - Movable by dragging background
//  - Doesn't hide when app deactivates
//  - Works in fullscreen mode
//

import AppKit
import SwiftUI
import Combine

// MARK: - View Model

/// ObservableObject that bridges the NSPanel and SwiftUI view
/// This allows @Published properties to work correctly with SwiftUI bindings
final class SuperSpacesViewModel: ObservableObject {
    /// Current Space number (1-based)
    @Published var currentSpaceNumber: Int = 1
    
    /// All detected Spaces
    @Published var allSpaces: [SpaceDetector.SpaceInfo] = []
    
    /// Callback for Space switching
    var onSpaceSwitch: ((Int) -> Void)?
    
    /// Callback for closing HUD
    var onClose: (() -> Void)?
    
    /// Callback for position changes
    var onPositionChange: ((String) -> Void)?
    
    func switchToSpace(_ spaceNumber: Int) {
        onSpaceSwitch?(spaceNumber)
    }
    
    func closeHUD() {
        onClose?()
    }
}

// MARK: - HUD Panel

/// Floating HUD panel for Space navigation and switching
/// Provides visual feedback about current Space and quick switching interface
final class SuperSpacesHUD: NSPanel, NSWindowDelegate {
    
    // MARK: - Singleton
    
    /// Shared instance (singleton pattern)
    /// Only one HUD should exist at a time
    static let shared = SuperSpacesHUD()
    
    // MARK: - Properties
    
    /// View model shared with SwiftUI view
    private let viewModel = SuperSpacesViewModel()
    
    /// Space change monitor for auto-updates
    /// Detects when user switches Spaces and updates UI
    private var spaceMonitor: SpaceChangeMonitor?
    
    /// Whether HUD is currently visible
    /// Used to prevent duplicate show/hide calls
    private var isCurrentlyVisible: Bool = false
    
    /// Timer for debouncing position saves
    /// Prevents excessive UserDefaults writes during window dragging
    private var positionSaveTimer: Timer?
    
    // MARK: - Initialization
    
    /// Private initializer (singleton pattern)
    private init() {
        // Create panel with HUD style
        // PHASE 1.2 FIX: Use .borderless to remove title bar artifact
        // PHASE 1.3 FIX: Increased initial height to prevent clipping, window is resizable
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 450),
            styleMask: [
                .nonactivatingPanel,  // Doesn't steal focus from other apps
                .borderless,          // No title bar or borders (fixes artifact)
                .fullSizeContentView, // Content extends to edges
                .resizable            // Allow user to resize if needed
            ],
            backing: .buffered,       // Double-buffered for smooth rendering
            defer: false              // Create window immediately
        )
        
        setupPanel()
        setupContent()
        setupSpaceMonitoring()
        
        // Set delegate for position tracking
        self.delegate = self
        
        // Show HUD by default on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.show()
        }
        
        print("✓ SuperSpacesHUD: Initialized")
    }
    
    // MARK: - Setup Methods
    
    /// Configures panel appearance and behavior
    private func setupPanel() {
        // Always on top of normal windows
        isFloatingPanel = true
        level = .floating
        
        // Appear on all Spaces (including fullscreen)
        collectionBehavior = [
            .canJoinAllSpaces,        // Shows on every Space
            .fullScreenAuxiliary      // Works in fullscreen mode
        ]
        
        // HUD style appearance
        // PHASE 1.2: Borderless window, no title bar artifacts
        // PHASE 1.3: Added resizable capability for user flexibility
        isMovableByWindowBackground = true       // Drag anywhere to move
        backgroundColor = .clear                 // Clear (content has blur)
        
        // Don't hide when app loses focus
        hidesOnDeactivate = false
        
        // Utility window animations (faster, lighter)
        animationBehavior = .utilityWindow
        
        // Set minimum and maximum size constraints
        // Minimum: Enough for compact mode
        // Maximum: Reasonable upper bound for note mode
        minSize = NSSize(width: 400, height: 120)
        maxSize = NSSize(width: 800, height: 600)
        
        // Position in top-right corner
        positionInTopRight()
        
        print("✓ SuperSpacesHUD: Panel configured")
    }
    
    /// Creates and sets SwiftUI content view
    private func setupContent() {
        // Set up callbacks
        viewModel.onSpaceSwitch = { [weak self] spaceNumber in
            self?.switchToSpace(spaceNumber)
        }
        viewModel.onClose = { [weak self] in
            self?.hide()
        }
        viewModel.onPositionChange = { [weak self] position in
            self?.moveToPosition(position)
        }
        
        // Create SwiftUI view with view model and inject settings
        let hudView = SuperSpacesHUDView(viewModel: viewModel)
            .environmentObject(SettingsManager.shared)
        
        // Wrap in NSHostingView
        let hostingView = NSHostingView(rootView: hudView)
        contentView = hostingView
        
        print("✓ SuperSpacesHUD: Content view created")
    }
    
    /// Sets up Space change monitoring
    private func setupSpaceMonitoring() {
        // Detect initial state
        refreshSpaces()
        
        // Start monitoring for changes
        spaceMonitor = SpaceChangeMonitor()
        spaceMonitor?.startMonitoring { [weak self] spaceNumber in
            self?.handleSpaceChange(spaceNumber)
        }
        
        print("✓ SuperSpacesHUD: Monitoring started")
    }
    
    // MARK: - Space Management
    
    /// Refreshes Space information
    private func refreshSpaces() {
        viewModel.allSpaces = SpaceDetector.getAllSpaces()
        
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            viewModel.currentSpaceNumber = currentSpace.spaceNumber
        }
    }
    
    /// Handles Space change notification
    private func handleSpaceChange(_ spaceNumber: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.currentSpaceNumber = spaceNumber
        }
    }
    
    /// Switches to specified Space via AppleScript
    private func switchToSpace(_ spaceNumber: Int) {
        print("→ SuperSpacesHUD: Switching to Space \(spaceNumber)...")
        
        // Calculate how many Spaces to move (left or right)
        let currentSpace = viewModel.currentSpaceNumber
        let steps = spaceNumber - currentSpace
        
        if steps == 0 {
            print("✓ SuperSpacesHUD: Already on Space \(spaceNumber)")
            return
        }
        
        // Determine direction
        let direction = steps > 0 ? "right" : "left"
        let keyCode = direction == "right" ? "124" : "123"  // Arrow key codes
        let count = abs(steps)
        
        // Build AppleScript to simulate Control+Arrow key presses
        // NOTE: There's no public API to jump directly to a Space number
        // We have to simulate arrow keys multiple times
        // Using shorter delay (0.15s) for faster switching
        let script = """
        tell application "System Events"
            repeat \(count) times
                key code \(keyCode) using {control down}
                delay 0.15
            end repeat
        end tell
        """
        
        // Execute AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                print("⚠️ SuperSpacesHUD: AppleScript error: \(error)")
                showPermissionAlert()
            } else {
                print("✓ SuperSpacesHUD: Space switch initiated")
            }
        }
    }
    
    /// Shows alert about Automation permission
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Automation Permission Required"
        alert.informativeText = """
        SuperDimmer needs Automation permission to switch between Spaces.
        
        Please grant permission in:
        System Settings > Privacy & Security > Automation
        
        Then try switching Spaces again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
    
    // MARK: - Positioning
    
    /// Positions HUD in top-right corner of main screen
    private func positionInTopRight() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = frame
        
        let x = screenFrame.maxX - windowFrame.width - 20
        let y = screenFrame.maxY - windowFrame.height - 20
        
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    /// Moves HUD to specified position preset
    /// Called when user selects a position in quick settings
    func moveToPosition(_ position: String) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowFrame = frame
        let margin: CGFloat = 20
        
        let origin: NSPoint
        
        switch position {
        case "topLeft":
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.maxY - windowFrame.height - margin
            )
        case "topRight":
            origin = NSPoint(
                x: screenFrame.maxX - windowFrame.width - margin,
                y: screenFrame.maxY - windowFrame.height - margin
            )
        case "bottomLeft":
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + margin
            )
        case "bottomRight":
            origin = NSPoint(
                x: screenFrame.maxX - windowFrame.width - margin,
                y: screenFrame.minY + margin
            )
        default:
            // Unknown position, don't move
            return
        }
        
        // Animate the move
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrameOrigin(origin)
        }
        
        print("✓ SuperSpacesHUD: Moved to \(position)")
    }
    
    // MARK: - Public Interface
    
    /// Shows the HUD
    func show() {
        guard !isCurrentlyVisible else {
            print("⚠️ SuperSpacesHUD: Already visible")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Restore last position if available and valid
            self.restorePosition()
            
            // Refresh Space data
            self.refreshSpaces()
            
            // Show window
            self.orderFront(nil)
            self.isCurrentlyVisible = true
            
            print("✓ SuperSpacesHUD: Shown")
        }
    }
    
    /// Hides the HUD
    func hide() {
        guard isCurrentlyVisible else {
            print("⚠️ SuperSpacesHUD: Already hidden")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.orderOut(nil)
            self.isCurrentlyVisible = false
            
            print("✓ SuperSpacesHUD: Hidden")
        }
    }
    
    /// Toggles HUD visibility
    func toggle() {
        if isCurrentlyVisible {
            hide()
        } else {
            show()
        }
    }
    
    // MARK: - Position Persistence (Phase 1.1)
    
    /// Restores HUD position from saved location
    /// Validates position is on-screen before applying
    private func restorePosition() {
        guard let savedPosition = SettingsManager.shared.lastHUDPosition else {
            // No saved position, use default
            positionToDefaultLocation()
            return
        }
        
        // Validate position is on-screen
        if isPositionValid(savedPosition) {
            setFrameOrigin(savedPosition)
            print("✓ SuperSpacesHUD: Restored position to \(savedPosition)")
        } else {
            // Invalid position (e.g., monitor disconnected), use default
            positionToDefaultLocation()
            print("⚠️ SuperSpacesHUD: Saved position invalid, using default")
        }
    }
    
    /// Checks if a position is valid (on-screen)
    /// Accounts for multi-monitor setups and screen changes
    private func isPositionValid(_ position: CGPoint) -> Bool {
        // Check if position is within any screen's visible frame
        for screen in NSScreen.screens {
            let visibleFrame = screen.visibleFrame
            
            // Check if top-left corner is within screen bounds
            // Allow some tolerance (at least 50px of window must be visible)
            let testRect = NSRect(origin: position, size: CGSize(width: 50, height: 50))
            if visibleFrame.intersects(testRect) {
                return true
            }
        }
        
        return false
    }
    
    /// Positions HUD to default location (top-right of main screen)
    private func positionToDefaultLocation() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = frame.size
        
        // Top-right corner with padding
        let padding: CGFloat = 20
        let x = screenFrame.maxX - windowSize.width - padding
        let y = screenFrame.maxY - windowSize.height - padding
        
        setFrameOrigin(CGPoint(x: x, y: y))
    }
    
    // MARK: - NSWindowDelegate (Phase 1.1)
    
    /// Called when window moves
    /// Saves position to UserDefaults (debounced)
    func windowDidMove(_ notification: Notification) {
        // Cancel previous save timer
        positionSaveTimer?.invalidate()
        
        // Schedule new save after delay (debounce)
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let position = self.frame.origin
            SettingsManager.shared.lastHUDPosition = position
            
            print("💾 SuperSpacesHUD: Saved position to \(position)")
        }
    }
}
