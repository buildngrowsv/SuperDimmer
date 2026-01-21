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
final class SuperSpacesHUD: NSPanel {
    
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
    
    // MARK: - Initialization
    
    /// Private initializer (singleton pattern)
    private init() {
        // Create panel with HUD style
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [
                .nonactivatingPanel,  // Doesn't steal focus from other apps
                .titled,              // Has title bar (we'll hide it)
                .resizable,           // User can resize if desired
                .closable,            // Can be closed
                .fullSizeContentView  // Content extends under titlebar
            ],
            backing: .buffered,       // Double-buffered for smooth rendering
            defer: false              // Create window immediately
        )
        
        setupPanel()
        setupContent()
        setupSpaceMonitoring()
        
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
        titleVisibility = .hidden                // No title text
        titlebarAppearsTransparent = true        // Transparent titlebar
        isMovableByWindowBackground = true       // Drag anywhere to move
        backgroundColor = .clear                 // Clear (content has blur)
        
        // Don't hide when app loses focus
        hidesOnDeactivate = false
        
        // Hide traffic light buttons (close/minimize/zoom)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        
        // Utility window animations (faster, lighter)
        animationBehavior = .utilityWindow
        
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
        
        // Create SwiftUI view with view model
        let hudView = SuperSpacesHUDView(viewModel: viewModel)
        
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
    
    // MARK: - Public Interface
    
    /// Shows the HUD
    func show() {
        guard !isCurrentlyVisible else {
            print("⚠️ SuperSpacesHUD: Already visible")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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
}
