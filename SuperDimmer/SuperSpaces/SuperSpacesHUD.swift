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
///
/// PERSISTENCE ARCHITECTURE (Jan 22, 2026):
/// Font size multiplier is now persisted via SettingsManager.
/// The viewModel accesses it directly from SettingsManager.shared, which:
/// - Automatically saves to UserDefaults when changed
/// - Loads from UserDefaults on app launch
/// - Persists across app restarts
/// This ensures the user's text size preference is maintained between sessions.
final class SuperSpacesViewModel: ObservableObject {
    /// Current Space number (1-based)
    @Published var currentSpaceNumber: Int = 1
    
    /// All detected Spaces
    @Published var allSpaces: [SpaceDetector.SpaceInfo] = []
    
    /// Font size multiplier for HUD text (1.0 = default, 0.8 = minimum, 1.5 = maximum)
    /// This allows users to adjust text size with Cmd+/Cmd- shortcuts
    /// The multiplier is applied to all font sizes in the HUD for consistent scaling
    ///
    /// PERSISTENCE (Jan 22, 2026):
    /// This property now reads from and writes to SettingsManager.shared.superSpacesFontSizeMultiplier
    /// which automatically persists to UserDefaults. The user's text size preference is maintained
    /// across app launches.
    var fontSizeMultiplier: CGFloat {
        get {
            SettingsManager.shared.superSpacesFontSizeMultiplier
        }
        set {
            SettingsManager.shared.superSpacesFontSizeMultiplier = newValue
            // Trigger SwiftUI update by manually calling objectWillChange
            objectWillChange.send()
        }
    }
    
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
    
    /// Increases font size (Cmd+)
    /// Maximum multiplier is 1.5x (150% of default size)
    ///
    /// PERSISTENCE (Jan 22, 2026):
    /// Changes are automatically saved to UserDefaults via SettingsManager.
    /// The new size persists across app restarts.
    func increaseFontSize() {
        let newSize = min(fontSizeMultiplier + 0.1, 1.5)
        if newSize != fontSizeMultiplier {
            fontSizeMultiplier = newSize
            print("✓ SuperSpacesHUD: Font size increased to \(Int(fontSizeMultiplier * 100))% (persisted)")
        }
    }
    
    /// Decreases font size (Cmd-)
    /// Minimum multiplier is 0.8x (80% of default size)
    ///
    /// PERSISTENCE (Jan 22, 2026):
    /// Changes are automatically saved to UserDefaults via SettingsManager.
    /// The new size persists across app restarts.
    func decreaseFontSize() {
        let newSize = max(fontSizeMultiplier - 0.1, 0.8)
        if newSize != fontSizeMultiplier {
            fontSizeMultiplier = newSize
            print("✓ SuperSpacesHUD: Font size decreased to \(Int(fontSizeMultiplier * 100))% (persisted)")
        }
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
    
    /// Timer for debouncing window size saves
    /// Prevents excessive UserDefaults writes during window resizing
    private var sizeSaveTimer: Timer?
    
    /// Current display mode (tracked to know which size setting to save)
    /// Synced with SettingsManager.superSpacesDisplayMode
    private var currentDisplayMode: String = "compact"
    
    /// Local event monitor for keyboard shortcuts (Cmd+/Cmd-)
    /// Monitors key events when the HUD window is key (has focus)
    /// This allows text size adjustment with standard keyboard shortcuts
    private var keyboardMonitor: Any?
    
    /// Combine cancellables for settings observations
    /// Used to observe changes to settings like float on top
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Private initializer (singleton pattern)
    private init() {
        // Create panel with HUD style
        // PHASE 1.2 FIX: Use .borderless to remove title bar artifact
        // PHASE 1.3 FIX: Increased initial height to prevent clipping, window is resizable
        // CRITICAL FIX: Removed .nonactivatingPanel to allow TextEditor input
        // The panel MUST be able to become key window for text editing to work
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 450),
            styleMask: [
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
        setupKeyboardShortcuts()
        
        // Set delegate for position tracking
        self.delegate = self
        
        // Show HUD by default on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.show()
        }
        
        print("✓ SuperSpacesHUD: Initialized")
    }
    
    /// Cleanup on deinitialization
    /// Removes keyboard event monitor to prevent memory leaks
    deinit {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // MARK: - Setup Methods
    
    /// Configures panel appearance and behavior
    private func setupPanel() {
        // Window level based on user preference
        // Float on top (default): .floating level (above normal windows)
        // Normal: .normal level (can be covered by other windows)
        updateWindowLevel()
        
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
    
    // MARK: - Window Overrides (CRITICAL for TextEditor input)
    
    /// Allow panel to become key window so TextEditors can receive input
    /// Without this, text fields and editors cannot be edited
    override var canBecomeKey: Bool {
        return true
    }
    
    /// Allow panel to become main window
    /// This ensures proper first responder chain for text editing
    override var canBecomeMain: Bool {
        return true
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
        var hudView = SuperSpacesHUDView(viewModel: viewModel)
        
        // Set up mode change callback to handle window resizing
        hudView.onModeChange = { [weak self] mode in
            self?.handleModeChange(mode)
        }
        
        let finalView = hudView.environmentObject(SettingsManager.shared)
        
        // Wrap in NSHostingView
        let hostingView = NSHostingView(rootView: finalView)
        contentView = hostingView
        
        // Observe float on top setting changes
        SettingsManager.shared.$superSpacesFloatOnTop
            .sink { [weak self] _ in
                self?.updateWindowLevel()
            }
            .store(in: &cancellables)
        
        print("✓ SuperSpacesHUD: Content view created")
    }
    
    /// Handles display mode changes
    /// Restores the saved window size for the new mode
    private func handleModeChange(_ mode: SuperSpacesHUDView.DisplayMode) {
        let modeString: String
        switch mode {
        case .compact:
            modeString = "compact"
        case .note:
            modeString = "note"
        case .overview:
            modeString = "overview"
        }
        
        // Restore window size for the new mode
        restoreSizeForMode(modeString)
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
    
    /// Sets up keyboard shortcuts for text size adjustment
    /// Monitors Cmd+ and Cmd- key combinations to increase/decrease font size
    /// Uses local event monitor so shortcuts only work when HUD has focus
    private func setupKeyboardShortcuts() {
        // Local monitor for keyboard events (only when window is key)
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check for Command key modifier
            let hasCommand = event.modifierFlags.contains(.command)
            guard hasCommand else { return event }
            
            // Get the key character
            guard let characters = event.charactersIgnoringModifiers else { return event }
            
            // Handle Cmd+ (increase font size)
            // Both "=" and "+" keys work (since + requires Shift on US keyboards)
            if characters == "=" || characters == "+" {
                self.viewModel.increaseFontSize()
                return nil  // Consume the event
            }
            
            // Handle Cmd- (decrease font size)
            if characters == "-" {
                self.viewModel.decreaseFontSize()
                return nil  // Consume the event
            }
            
            // Pass through other events
            return event
        }
        
        print("✓ SuperSpacesHUD: Keyboard shortcuts configured (Cmd+/Cmd-)")
    }
    
    // MARK: - Space Management
    
    /// Refreshes Space information
    ///
    /// FEATURE: 5.5.8 - Dim to Indicate Order (Updated Jan 21, 2026)
    /// 
    /// BEHAVIOR CHANGE:
    /// - Previously: All Spaces were pre-initialized in visit order on first launch
    /// - Now: Only the current Space is added to visit order
    /// - Unvisited Spaces default to 50% opacity until actually visited
    /// - After being visited, they progressively dim based on recency
    ///
    /// WHY THIS CHANGE:
    /// - Provides clearer visual feedback: 50% = neutral/unvisited, 100% = current
    /// - Progressive dimming only applies to Spaces you've actually used
    /// - More intuitive: brightness indicates recent activity, not arbitrary order
    private func refreshSpaces() {
        viewModel.allSpaces = SpaceDetector.getAllSpaces()
        
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            viewModel.currentSpaceNumber = currentSpace.spaceNumber
            
            // Record the current Space as visited (5.5.8)
            // This ensures the current Space shows at 100% opacity
            // Other Spaces will remain at 50% until visited
            if SpaceVisitTracker.shared.visitOrder.isEmpty {
                SpaceVisitTracker.shared.recordVisit(to: currentSpace.spaceNumber)
            }
        }
    }
    
    /// Handles Space change notification
    ///
    /// FEATURE: 5.5.8 - Dim to Indicate Order
    /// When a Space changes, we:
    /// 1. Update the current Space number in the view model
    /// 2. Record the visit in SpaceVisitTracker for button dimming
    ///
    /// This ensures the HUD stays in sync with the current Space
    /// and the visit history is maintained for progressive button dimming.
    private func handleSpaceChange(_ spaceNumber: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.currentSpaceNumber = spaceNumber
            
            // Record visit for button dimming feature (5.5.8)
            // This updates the visit order so button opacity reflects recency
            SpaceVisitTracker.shared.recordVisit(to: spaceNumber)
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
    
    /// Updates window level based on float on top setting
    ///
    /// FEATURE: Float on Top Toggle (Jan 21, 2026)
    ///
    /// When superSpacesFloatOnTop is true:
    /// - Window level = .floating (above normal windows)
    /// - isFloatingPanel = true
    ///
    /// When superSpacesFloatOnTop is false:
    /// - Window level = .normal (can be covered by other windows)
    /// - isFloatingPanel = false
    ///
    /// This allows users to choose whether the HUD stays above everything
    /// or behaves like a normal window that can be covered.
    func updateWindowLevel() {
        let settings = SettingsManager.shared
        
        if settings.superSpacesFloatOnTop {
            isFloatingPanel = true
            level = .floating
            print("✓ SuperSpacesHUD: Window level set to .floating (always on top)")
        } else {
            isFloatingPanel = false
            level = .normal
            print("✓ SuperSpacesHUD: Window level set to .normal (can be covered)")
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
    
    /// Called when window resizes
    /// Saves size to UserDefaults per display mode (debounced)
    /// This allows each mode to remember the user's preferred window size
    func windowDidResize(_ notification: Notification) {
        // Cancel previous save timer
        sizeSaveTimer?.invalidate()
        
        // Schedule new save after delay (debounce)
        sizeSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let size = self.frame.size
            let mode = SettingsManager.shared.superSpacesDisplayMode
            
            // Save size to the appropriate mode setting
            switch mode {
            case "compact":
                SettingsManager.shared.hudSizeCompact = size
                print("💾 SuperSpacesHUD: Saved Compact mode size to \(size)")
            case "note":
                SettingsManager.shared.hudSizeNote = size
                print("💾 SuperSpacesHUD: Saved Note mode size to \(size)")
            case "overview":
                SettingsManager.shared.hudSizeOverview = size
                print("💾 SuperSpacesHUD: Saved Overview mode size to \(size)")
            default:
                break
            }
        }
    }
    
    /// Restores window size for the current display mode
    /// Called when switching modes to restore the user's preferred size for that mode
    func restoreSizeForMode(_ mode: String) {
        let savedSize: CGSize?
        let defaultSize: CGSize
        
        switch mode {
        case "compact":
            savedSize = SettingsManager.shared.hudSizeCompact
            defaultSize = CGSize(width: 480, height: 140)
        case "note":
            savedSize = SettingsManager.shared.hudSizeNote
            defaultSize = CGSize(width: 480, height: 400)
        case "overview":
            savedSize = SettingsManager.shared.hudSizeOverview
            defaultSize = CGSize(width: 600, height: 550)
        default:
            return
        }
        
        let targetSize = savedSize ?? defaultSize
        
        // Animate size change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Keep the window's top-left corner in the same position
            var newFrame = self.frame
            newFrame.size = targetSize
            
            // Adjust origin to keep top-left corner fixed
            // (NSWindow origin is bottom-left, so we need to adjust Y)
            let heightDiff = targetSize.height - self.frame.height
            newFrame.origin.y -= heightDiff
            
            self.animator().setFrame(newFrame, display: true)
        }
        
        print("✓ SuperSpacesHUD: Restored \(mode) mode size to \(targetSize)")
    }
}
