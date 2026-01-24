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
    
    /// Font size multiplier for HUD text (1.0 = default, 0.8 = minimum, 3.0 = maximum)
    /// This allows users to adjust text size with Cmd+/Cmd- shortcuts
    /// The multiplier is applied to all font sizes in the HUD for consistent scaling
    ///
    /// RANGE UPDATE (Jan 22, 2026):
    /// Increased maximum from 1.5x to 3.0x (300% of default size) to support users
    /// who need much larger text for accessibility or preference reasons.
    /// All adaptive thresholds (column counts, spacing) scale with this multiplier
    /// to maintain proper layout at all text sizes.
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
    
    /// Callback for duplicating HUD
    var onDuplicate: (() -> Void)?
    
    /// Callback for display mode changes
    var onDisplayModeChange: ((String) -> Void)?
    
    /// Callback for float on top setting changes (per-HUD)
    /// Called when user toggles the float on top setting for this specific HUD
    var onFloatOnTopChange: ((Bool) -> Void)?
    
    /// Current display mode string for this HUD instance
    /// This is per-HUD, not global
    @Published var currentDisplayModeString: String = "compact"
    
    /// Whether this specific HUD floats on top of other windows
    /// This is now a per-HUD setting (Jan 23, 2026) instead of global
    /// Each HUD instance can have its own independent float on top setting
    @Published var floatOnTop: Bool = true
    
    func switchToSpace(_ spaceNumber: Int) {
        onSpaceSwitch?(spaceNumber)
    }
    
    func closeHUD() {
        onClose?()
    }
    
    func duplicateHUD() {
        onDuplicate?()
    }
    
    /// Increases font size (Cmd+)
    /// Maximum multiplier is 3.0x (300% of default size)
    ///
    /// RANGE UPDATE (Jan 22, 2026):
    /// Increased maximum from 1.5x to 3.0x to support users who need much larger text
    /// for accessibility or preference reasons. All adaptive layout features scale
    /// appropriately with this larger range.
    ///
    /// PERSISTENCE (Jan 22, 2026):
    /// Changes are automatically saved to UserDefaults via SettingsManager.
    /// The new size persists across app restarts.
    func increaseFontSize() {
        let newSize = min(fontSizeMultiplier + 0.1, 3.0)
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

// MARK: - HUD Configuration

/// Configuration structure for persisting HUD state
/// Each HUD instance has its own configuration that is saved to UserDefaults
///
/// PERSISTENCE ARCHITECTURE (Jan 23, 2026):
/// - Each HUD has independent settings (mode, position, size, floatOnTop)
/// - Configurations are saved as JSON array in UserDefaults
/// - On app launch, HUDs are restored from saved configurations
/// - Changes to any HUD automatically trigger save
///
/// INDEPENDENT FLOAT ON TOP (Jan 23, 2026):
/// Each HUD now has its own floatOnTop setting, allowing users to:
/// - Have one HUD that floats above all windows
/// - Have another HUD that can be covered by other windows
/// - Mix and match based on workflow needs
struct HUDConfiguration: Codable {
    /// Unique identifier for this HUD
    let id: String
    
    /// Display mode: "compact", "note", or "overview"
    var displayMode: String
    
    /// Window position (top-left corner)
    var position: CGPoint
    
    /// Window size
    var size: CGSize
    
    /// Whether the HUD is currently visible
    var isVisible: Bool
    
    /// Whether this specific HUD should float on top of other windows
    /// This is now a per-HUD setting (Jan 23, 2026) instead of global
    /// - true: Window level = .floating (above normal windows)
    /// - false: Window level = .normal (can be covered by other windows)
    var floatOnTop: Bool
    
    /// Creates a default configuration
    /// - Parameter id: Unique identifier for the HUD
    init(id: String) {
        self.id = id
        self.displayMode = "compact"
        self.position = CGPoint(x: 0, y: 0)  // Will be set to default position
        self.size = CGSize(width: 480, height: 140)
        self.isVisible = true
        self.floatOnTop = true  // Default to floating on top (original behavior)
    }
}

// MARK: - HUD Manager

/// Manager class for handling multiple HUD instances
/// Allows users to create and manage multiple Super Spaces HUD windows
///
/// ARCHITECTURE (Jan 23, 2026):
/// - Manages an array of HUD instances
/// - Each HUD has a unique ID for tracking
/// - Persists HUD configurations (position, size, mode) to UserDefaults
/// - Provides methods to create, duplicate, and close HUDs
///
/// WHY MULTIPLE HUDS:
/// - Users may want to monitor multiple Spaces at once
/// - Different HUDs can show different display modes (compact, note, overview)
/// - Each HUD can be positioned independently on screen
/// - Useful for multi-monitor setups
///
/// PERSISTENCE (Jan 23, 2026):
/// - Each HUD's configuration is saved independently
/// - Configurations stored as JSON array in UserDefaults
/// - On launch, HUDs are restored from saved configurations
/// - Changes automatically trigger save
final class SuperSpacesHUDManager {
    
    // MARK: - Singleton
    
    /// Shared manager instance
    static let shared = SuperSpacesHUDManager()
    
    // MARK: - Properties
    
    /// Array of active HUD instances
    /// Each HUD is tracked with a unique ID
    private var hudInstances: [String: SuperSpacesHUD] = [:]
    
    /// Counter for generating unique HUD IDs
    private var nextHUDID: Int = 1
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted HUD configurations on startup
        loadPersistedHUDs()
    }
    
    // MARK: - Public Methods
    
    /// Creates a new HUD instance
    /// - Returns: The newly created HUD instance
    @discardableResult
    func createHUD() -> SuperSpacesHUD {
        let hudID = "hud_\(nextHUDID)"
        nextHUDID += 1
        
        let hud = SuperSpacesHUD(id: hudID, manager: self)
        hudInstances[hudID] = hud
        
        print("✓ HUDManager: Created new HUD with ID: \(hudID)")
        return hud
    }
    
    /// Duplicates an existing HUD
    /// Creates a new HUD with the same settings but offset position
    /// - Parameter sourceHUD: The HUD to duplicate
    /// - Returns: The newly created duplicate HUD
    @discardableResult
    func duplicateHUD(_ sourceHUD: SuperSpacesHUD) -> SuperSpacesHUD {
        let newHUD = createHUD()
        
        // Copy settings from source HUD
        newHUD.copySettings(from: sourceHUD)
        
        // Offset position slightly so it's visible
        var newFrame = newHUD.frame
        newFrame.origin.x += 30
        newFrame.origin.y -= 30
        newHUD.setFrameOrigin(newFrame.origin)
        
        // Show the new HUD
        newHUD.show()
        
        print("✓ HUDManager: Duplicated HUD \(sourceHUD.hudID) -> \(newHUD.hudID)")
        return newHUD
    }
    
    /// Closes a specific HUD instance
    /// - Parameter hudID: The ID of the HUD to close
    func closeHUD(withID hudID: String) {
        guard let hud = hudInstances[hudID] else {
            print("⚠️ HUDManager: No HUD found with ID: \(hudID)")
            return
        }
        
        hud.close()
        hudInstances.removeValue(forKey: hudID)
        
        print("✓ HUDManager: Closed HUD with ID: \(hudID)")
    }
    
    /// Toggles visibility of the primary HUD (for backward compatibility)
    /// If no HUDs exist, creates one
    func togglePrimaryHUD() {
        // If we have at least one HUD, toggle the first one
        if let firstHUD = hudInstances.values.first {
            firstHUD.toggle()
            return
        }
        
        // No HUDs exist, create and show one
        let hud = createHUD()
        hud.show()
    }
    
    /// Returns all active HUD instances
    var allHUDs: [SuperSpacesHUD] {
        return Array(hudInstances.values)
    }
    
    /// Returns the number of active HUDs
    var hudCount: Int {
        return hudInstances.count
    }
    
    // MARK: - Persistence
    
    /// UserDefaults key for storing HUD configurations
    private let hudConfigsKey = "superdimmer.hudConfigurations"
    
    /// Loads persisted HUD configurations from UserDefaults
    /// Called on app startup to restore HUDs from previous session
    ///
    /// PERSISTENCE BEHAVIOR (Jan 23, 2026):
    /// - Reads JSON array of HUD configurations from UserDefaults
    /// - Creates HUD instances with saved settings (mode, position, size)
    /// - If no saved configurations exist, creates one default HUD
    /// - Restores visibility state for each HUD
    private func loadPersistedHUDs() {
        guard let data = UserDefaults.standard.data(forKey: hudConfigsKey),
              let configs = try? JSONDecoder().decode([HUDConfiguration].self, from: data),
              !configs.isEmpty else {
            // No saved configurations, create default HUD
            print("ℹ️ HUDManager: No saved configurations, creating default HUD")
            let hud = createHUD()
            
            // Show HUD by default on launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hud.show()
            }
            return
        }
        
        print("✓ HUDManager: Loading \(configs.count) saved HUD configuration(s)")
        
        // Restore HUDs from saved configurations
        for config in configs {
            let hud = createHUD(withConfiguration: config)
            
            // Show HUD if it was visible when saved
            if config.isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hud.show()
                }
            }
        }
    }
    
    /// Saves all HUD configurations to UserDefaults
    /// Called when HUDs are modified (position, size, mode changes)
    ///
    /// PERSISTENCE BEHAVIOR (Jan 23, 2026):
    /// - Collects configuration from all active HUDs
    /// - Encodes as JSON array
    /// - Saves to UserDefaults
    /// - Automatically called when HUDs change
    func saveHUDConfigurations() {
        let configs = hudInstances.values.map { $0.getConfiguration() }
        
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: hudConfigsKey)
            print("💾 HUDManager: Saved \(configs.count) HUD configuration(s)")
        } else {
            print("⚠️ HUDManager: Failed to encode HUD configurations")
        }
    }
    
    /// Creates a HUD with a specific configuration
    /// Used when restoring HUDs from saved state
    /// - Parameter config: The configuration to apply
    /// - Returns: The newly created HUD instance
    private func createHUD(withConfiguration config: HUDConfiguration) -> SuperSpacesHUD {
        // Use the saved ID to maintain consistency
        let hud = SuperSpacesHUD(id: config.id, manager: self, configuration: config)
        hudInstances[config.id] = hud
        
        // Update nextHUDID if necessary to avoid conflicts
        if let idNumber = Int(config.id.replacingOccurrences(of: "hud_", with: "")),
           idNumber >= nextHUDID {
            nextHUDID = idNumber + 1
        }
        
        print("✓ HUDManager: Restored HUD with ID: \(config.id), mode: \(config.displayMode)")
        return hud
    }
}

// MARK: - HUD Panel

/// Floating HUD panel for Space navigation and switching
/// Provides visual feedback about current Space and quick switching interface
///
/// MULTI-INSTANCE ARCHITECTURE (Jan 23, 2026):
/// - No longer a singleton - managed by SuperSpacesHUDManager
/// - Each instance has a unique ID for tracking
/// - Can be duplicated via copy button in header
/// - Settings and position are persisted per-instance
final class SuperSpacesHUD: NSPanel, NSWindowDelegate {
    
    // MARK: - Properties
    
    /// Unique identifier for this HUD instance
    let hudID: String
    
    /// Reference to the HUD manager
    private weak var manager: SuperSpacesHUDManager?
    
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
    
    /// Current display mode for this HUD instance (per-HUD setting)
    /// Each HUD can have its own independent display mode
    /// Values: "compact", "note", "overview"
    ///
    /// ARCHITECTURE CHANGE (Jan 23, 2026):
    /// Previously this was synced with global SettingsManager.superSpacesDisplayMode
    /// Now each HUD maintains its own mode independently
    /// This allows multiple HUDs to show different modes simultaneously
    private var currentDisplayMode: String = "compact"
    
    /// Whether this specific HUD floats on top of other windows (per-HUD setting)
    /// Each HUD can have its own independent float on top setting
    ///
    /// ARCHITECTURE CHANGE (Jan 23, 2026):
    /// Previously this was synced with global SettingsManager.superSpacesFloatOnTop
    /// Now each HUD maintains its own float on top setting independently
    /// This allows users to have one HUD floating above everything and another
    /// that can be covered by other windows - useful for different workflows
    ///
    /// BEHAVIOR:
    /// - true: Window level = .floating (above normal windows)
    /// - false: Window level = .normal (can be covered by other windows)
    private var isFloatOnTop: Bool = true
    
    /// Stored configuration for this HUD instance (per-HUD persistence)
    /// When a HUD is restored from saved state, this holds its configuration
    /// Used to restore position and size on show() instead of global settings
    ///
    /// ARCHITECTURE (Jan 23, 2026):
    /// Each HUD stores its own configuration so that:
    /// - Position is restored per-HUD, not from global lastHUDPosition
    /// - Size is restored per-HUD, not from global mode-specific sizes
    /// - Multiple HUDs can have different positions/sizes simultaneously
    private var storedConfiguration: HUDConfiguration?
    
    /// Local event monitor for keyboard shortcuts (Cmd+/Cmd-)
    /// Monitors key events when the HUD window is key (has focus)
    /// This allows text size adjustment with standard keyboard shortcuts
    private var keyboardMonitor: Any?
    
    /// Combine cancellables for future settings observations
    /// NOTE (Jan 23, 2026): Float on top is now per-HUD, so the global observer was removed.
    /// This property is kept for potential future Combine observers.
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializer for HUD instances
    /// - Parameters:
    ///   - id: Unique identifier for this HUD instance
    ///   - manager: Reference to the HUD manager
    ///   - configuration: Optional configuration to restore saved state
    init(id: String, manager: SuperSpacesHUDManager, configuration: HUDConfiguration? = nil) {
        self.hudID = id
        self.manager = manager
        
        // Store configuration for per-HUD persistence (Jan 23, 2026)
        // This is used in show() to restore position/size instead of global settings
        self.storedConfiguration = configuration
        
        // Apply configuration if provided
        // Each HUD has independent settings: displayMode, floatOnTop, position, size
        if let config = configuration {
            self.currentDisplayMode = config.displayMode
            self.isFloatOnTop = config.floatOnTop
        }
        
        // Determine initial size based on display mode
        let initialSize: CGSize
        if let config = configuration {
            initialSize = config.size
        } else {
            // Default size for compact mode
            initialSize = CGSize(width: 480, height: 140)
        }
        
        // Create panel with HUD style
        // PHASE 1.2 FIX: Use .borderless to remove title bar artifact
        // PHASE 1.3 FIX: Increased initial height to prevent clipping, window is resizable
        // CRITICAL FIX: Removed .nonactivatingPanel to allow TextEditor input
        // The panel MUST be able to become key window for text editing to work
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        
        // Apply position if provided in configuration
        if let config = configuration {
            setFrameOrigin(config.position)
        }
        
        print("✓ SuperSpacesHUD: Initialized with ID: \(hudID), mode: \(currentDisplayMode)")
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
        // Set initial display mode in view model
        viewModel.currentDisplayModeString = currentDisplayMode
        
        // Set initial float on top value in view model (per-HUD setting)
        // This is now independent for each HUD instance (Jan 23, 2026)
        viewModel.floatOnTop = isFloatOnTop
        
        // Set up callbacks
        viewModel.onSpaceSwitch = { [weak self] spaceNumber in
            self?.switchToSpace(spaceNumber)
        }
        viewModel.onClose = { [weak self] in
            self?.manager?.closeHUD(withID: self?.hudID ?? "")
        }
        viewModel.onPositionChange = { [weak self] position in
            self?.moveToPosition(position)
        }
        viewModel.onDuplicate = { [weak self] in
            guard let self = self else { return }
            self.manager?.duplicateHUD(self)
        }
        viewModel.onDisplayModeChange = { [weak self] mode in
            self?.setDisplayMode(mode)
        }
        
        // Handle float on top changes (per-HUD setting)
        // When user toggles float on top in quick settings, update this HUD's window level
        viewModel.onFloatOnTopChange = { [weak self] newValue in
            self?.setFloatOnTop(newValue)
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
        
        // NOTE: Removed Combine observer for global superSpacesFloatOnTop (Jan 23, 2026)
        // Float on top is now a per-HUD setting, not global
        // Each HUD tracks its own isFloatOnTop property and updates via onFloatOnTopChange callback
        
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
    /// FEATURE: 5.5.8 - Dim to Indicate Order (Updated Jan 22, 2026)
    /// 
    /// DESIGN CHANGE (Jan 22, 2026):
    /// Changed from transparency-based to overlay-based dimming.
    /// Instead of making buttons/cards transparent, we now apply a dark overlay.
    /// This keeps elements fully visible but darker, matching SuperDimmer's core functionality.
    /// 
    /// BEHAVIOR:
    /// - Previously: All Spaces were pre-initialized in visit order on first launch
    /// - Now: Only the current Space is added to visit order
    /// - Unvisited Spaces default to 50% dark overlay until actually visited
    /// - After being visited, they progressively dim based on recency
    ///
    /// WHY THIS APPROACH:
    /// - Better visibility: Dimmed elements remain clear and readable (vs transparent)
    /// - More on-brand: Matches SuperDimmer's core dimming functionality
    /// - Clearer visual feedback: darkness indicates less recent visits
    /// - Progressive dimming only applies to Spaces you've actually used
    /// - More intuitive: brightness indicates recent activity, not arbitrary order
    private func refreshSpaces() {
        viewModel.allSpaces = SpaceDetector.getAllSpaces()
        
        if let currentSpace = SpaceDetector.getCurrentSpace() {
            viewModel.currentSpaceNumber = currentSpace.spaceNumber
            
            // Record the current Space as visited (5.5.8)
            // This ensures the current Space shows at full brightness (no overlay)
            // Other Spaces will have dark overlay until visited
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
    
    /// Switches to specified Space using hybrid approach
    ///
    /// HYBRID APPROACH (Jan 22, 2026):
    /// 1. Try Control+Number shortcut (instant if user has enabled it)
    /// 2. Wait 1 second to see if it worked
    /// 3. If still on same Space, fall back to Control+Arrow cycling
    ///
    /// PERMISSIONS REQUIRED (Jan 22, 2026):
    /// - Accessibility: Required to send synthetic keyboard events
    /// - Automation (System Events): Required to execute AppleScript
    /// Both permissions must be granted for Space switching to work.
    ///
    /// RATIONALE:
    /// - macOS has built-in shortcuts: Control+1, Control+2, etc.
    /// - These are instant (no cycling) but only work if user enabled them
    /// - System Settings > Keyboard > Keyboard Shortcuts > Mission Control
    /// - Most users don't enable these, so we need a fallback
    ///
    /// PERFORMANCE:
    /// - With shortcuts enabled: < 0.5s (instant switch + verification)
    /// - Without shortcuts: 0.15s × steps (cycling fallback)
    ///
    /// WHY NOT CGS PRIVATE API:
    /// - Investigated CGSSetActiveSpace and CGSManagedDisplaySetCurrentSpace
    /// - These functions either don't exist or have unclear/undocumented signatures
    /// - dlsym() fails to find them in CoreGraphics framework
    /// - Even Hammerspoon doesn't use direct CGS switching - it uses Accessibility API
    ///   to programmatically open Mission Control and click on Spaces
    private func switchToSpace(_ spaceNumber: Int) {
        print("→ SuperSpacesHUD: Switching to Space \(spaceNumber)...")
        
        // Check if already on target Space
        let currentSpace = viewModel.currentSpaceNumber
        if spaceNumber == currentSpace {
            print("✓ SuperSpacesHUD: Already on Space \(spaceNumber)")
            return
        }
        
        // Check for Accessibility permission (required for sending keystrokes)
        if !AXIsProcessTrusted() {
            print("⚠️ SuperSpacesHUD: Accessibility permission not granted - cannot send keystrokes")
            showAccessibilityPermissionAlert()
            return
        }
        
        // Try direct Control+Number shortcut first (instant if enabled)
        let directSuccess = tryDirectSpaceShortcut(spaceNumber)
        
        if directSuccess {
            print("✓ SuperSpacesHUD: Space switch via Control+\(spaceNumber) shortcut (instant)")
            return
        }
        
        // Double-check we're not already on target Space
        // (shortcut might have worked but we didn't detect it in time)
        if let currentSpaceInfo = SpaceDetector.getCurrentSpace(),
           currentSpaceInfo.spaceNumber == spaceNumber {
            print("✓ SuperSpacesHUD: Already on Space \(spaceNumber) (shortcut worked)")
            return
        }
        
        // Get CURRENT space number (may have changed during shortcut attempt)
        let actualCurrentSpace = SpaceDetector.getCurrentSpace()?.spaceNumber ?? currentSpace
        
        // Fallback to cycling method
        print("⚠️ SuperSpacesHUD: Direct shortcut not enabled, falling back to cycling")
        print("   Current: \(actualCurrentSpace), Target: \(spaceNumber)")
        switchToSpaceViaAppleScript(spaceNumber, from: actualCurrentSpace)
    }
    
    /// Tries to switch to Space using Control+Number shortcut
    ///
    /// macOS has built-in keyboard shortcuts for switching to specific Spaces:
    /// - Control+1 → Desktop 1
    /// - Control+2 → Desktop 2
    /// - etc.
    ///
    /// These shortcuts must be enabled by the user in:
    /// System Settings > Keyboard > Keyboard Shortcuts > Mission Control
    ///
    /// APPROACH:
    /// 1. Simulate Control+Number key press
    /// 2. Wait 1 second for Space change to occur
    /// 3. Check if we're now on the target Space
    /// 4. Return true if successful, false if shortcut not enabled
    ///
    /// - Parameter spaceNumber: The Space number to switch to (1-9)
    /// - Returns: true if shortcut worked, false if not enabled or failed
    private func tryDirectSpaceShortcut(_ spaceNumber: Int) -> Bool {
        // Only works for Spaces 1-9 (macOS limitation)
        guard spaceNumber >= 1 && spaceNumber <= 9 else {
            return false
        }
        
        // Key codes for number keys 1-9 (top row of keyboard)
        // These are NOT sequential! macOS uses a non-linear mapping:
        // 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
        let keyCodes: [Int: Int] = [
            1: 18,
            2: 19,
            3: 20,
            4: 21,
            5: 23,  // Note: 5 and 6 are swapped!
            6: 22,
            7: 26,
            8: 28,
            9: 25
        ]
        
        guard let keyCode = keyCodes[spaceNumber] else {
            return false
        }
        
        // Build AppleScript to simulate Control+Number
        let script = """
        tell application "System Events"
            key code \(keyCode) using {control down}
        end tell
        """
        
        // Execute AppleScript
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                print("⚠️ SuperSpacesHUD: Direct shortcut AppleScript error: \(error)")
                return false
            }
        } else {
            return false
        }
        
        // Wait 1 second to see if Space changed
        // This gives macOS time to switch Spaces if the shortcut is enabled
        let startTime = Date()
        let timeout: TimeInterval = 1.0
        
        while Date().timeIntervalSince(startTime) < timeout {
            // Check if we're now on the target Space
            if let currentSpaceInfo = SpaceDetector.getCurrentSpace(),
               currentSpaceInfo.spaceNumber == spaceNumber {
                // Success! The shortcut worked
                return true
            }
            
            // Small delay before checking again
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Timeout reached and we're not on target Space
        // This means the shortcut is not enabled
        return false
    }
    
    /// Fallback method: Switches to Space by simulating Control+Arrow key presses
    ///
    /// This is the OLD method that we keep as a fallback in case CGS API fails.
    /// It's slower but more compatible with different macOS configurations.
    ///
    /// WHEN THIS IS USED:
    /// - CGSSetActiveSpace fails (rare, but possible on some macOS versions)
    /// - User has custom Space switching shortcuts configured
    /// - System security settings block CGS API calls
    ///
    /// HOW IT WORKS:
    /// - Calculate how many Spaces to move (left or right)
    /// - Simulate Control+Arrow key presses via AppleScript
    /// - 0.15s delay between each press to allow animation
    ///
    /// - Parameters:
    ///   - targetSpace: The Space number to switch to
    ///   - currentSpace: The current Space number
    private func switchToSpaceViaAppleScript(_ targetSpace: Int, from currentSpace: Int) {
        let steps = targetSpace - currentSpace
        
        // Determine direction
        let direction = steps > 0 ? "right" : "left"
        let keyCode = direction == "right" ? "124" : "123"  // Arrow key codes
        let count = abs(steps)
        
        // Build AppleScript to simulate Control+Arrow key presses
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
                
                // Check error type to show appropriate alert
                if let errorNumber = error[NSAppleScript.errorNumber] as? Int {
                    if errorNumber == 1002 {
                        // Error 1002: Not allowed to send keystrokes (Accessibility)
                        showAccessibilityPermissionAlert()
                    } else if errorNumber == -1743 {
                        // Error -1743: Not authorized (Automation)
                        showAutomationPermissionAlert()
                    } else {
                        // Other error
                        showAutomationPermissionAlert()
                    }
                }
            } else {
                print("✓ SuperSpacesHUD: Space switch initiated via AppleScript (slow)")
            }
        }
    }
    
    /// Shows alert about Accessibility permission (required for sending keystrokes)
    ///
    /// PERMISSION CONTEXT (Jan 22, 2026):
    /// macOS requires BOTH Accessibility and Automation permissions for Space switching:
    ///
    /// 1. ACCESSIBILITY: Required to send synthetic keyboard events
    ///    - Without this, AppleScript cannot simulate keypresses
    ///    - Error: "SuperDimmer is not allowed to send keystrokes" (1002)
    ///
    /// 2. AUTOMATION: Required to control "System Events" app
    ///    - Without this, AppleScript cannot talk to System Events
    ///    - Error: "Not authorized" (-1743)
    ///
    /// WHY BOTH ARE NEEDED:
    /// - AppleScript tells "System Events" to press keys (needs Automation)
    /// - System Events sends the actual keystrokes (needs Accessibility)
    /// - Both must be granted for Space switching to work
    private func showAccessibilityPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        SuperDimmer needs Accessibility permission to send keyboard shortcuts for Space switching.
        
        Please enable it in:
        System Settings > Privacy & Security > Accessibility
        
        Then check the box next to "SuperDimmer".
        
        Note: You also need Automation permission for "System Events" (which you already have ✓).
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    /// Shows alert about Automation permission
    ///
    /// PERMISSION CONTEXT (Jan 22, 2026):
    /// macOS Automation permissions are per-target-app, not global.
    /// SuperSpaces needs permission to control "System Events" specifically
    /// to simulate keyboard shortcuts (Control+Arrow, Control+Number).
    ///
    /// WHY THIS IS NEEDED:
    /// - macOS doesn't provide a direct API to switch Spaces programmatically
    /// - We use AppleScript to simulate keyboard shortcuts as a workaround
    /// - This requires "SuperDimmer → System Events" automation permission
    ///
    /// USER EXPERIENCE:
    /// - First time: macOS shows a permission dialog automatically
    /// - If denied: User must manually enable in System Settings
    /// - Cannot be reset programmatically - must be done in Settings
    private func showAutomationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Automation Permission Required"
        alert.informativeText = """
        SuperDimmer needs permission to control "System Events" to switch between Spaces.
        
        Please enable it in:
        System Settings > Privacy & Security > Automation > SuperDimmer
        
        Then check the box next to "System Events".
        
        Note: If you don't see this option, try clicking a Space button again to trigger the permission request.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
    
    /// Updates window level based on per-HUD float on top setting
    ///
    /// FEATURE: Float on Top Toggle (Jan 21, 2026)
    /// ARCHITECTURE CHANGE (Jan 23, 2026): Now uses per-HUD setting instead of global
    ///
    /// When isFloatOnTop is true (for THIS HUD):
    /// - Window level = .floating (above normal windows)
    ///
    /// When isFloatOnTop is false (for THIS HUD):
    /// - Window level = .normal (can be covered by other windows)
    ///
    /// This allows users to choose whether EACH HUD stays above everything
    /// or behaves like a normal window that can be covered.
    /// Different HUDs can have different settings simultaneously.
    ///
    /// BUG FIX (Jan 22, 2026):
    /// The issue was that NSPanel.isFloatingPanel property overrides the window level.
    /// When isFloatingPanel = true, the panel ALWAYS stays at .floating level,
    /// ignoring any attempts to set level = .normal.
    ///
    /// SOLUTION:
    /// We do NOT use isFloatingPanel at all. Instead, we only control the window level
    /// directly using the .level property. This gives us full control over whether
    /// the panel floats above other windows or not.
    ///
    /// TECHNICAL NOTES:
    /// - NSPanel inherits from NSWindow and has the same .level property
    /// - .floating level = 3 (above normal windows)
    /// - .normal level = 0 (regular window behavior)
    /// - Setting level directly works as expected when isFloatingPanel is not used
    func updateWindowLevel() {
        print("→ SuperSpacesHUD (\(hudID)): updateWindowLevel() called, isFloatOnTop = \(isFloatOnTop)")
        print("   Current level before change: \(level.rawValue)")
        
        if isFloatOnTop {
            // Set window level to floating (above normal windows)
            level = .floating
            print("✓ SuperSpacesHUD (\(hudID)): Window level set to .floating (always on top)")
            print("   Level after change: \(level.rawValue)")
        } else {
            // Set window level to normal (can be covered by other windows)
            level = .normal
            print("✓ SuperSpacesHUD (\(hudID)): Window level set to .normal (can be covered)")
            print("   Level after change: \(level.rawValue)")
        }
    }
    
    /// Sets the float on top setting for this specific HUD
    /// Called when user toggles the setting in quick settings
    ///
    /// ARCHITECTURE (Jan 23, 2026):
    /// This is a per-HUD setting, not global. Each HUD instance can have
    /// its own independent float on top preference. This allows users to:
    /// - Have one HUD always floating (for quick reference)
    /// - Have another HUD that can be covered (less intrusive)
    ///
    /// - Parameter newValue: true to float on top, false to allow covering
    func setFloatOnTop(_ newValue: Bool) {
        guard newValue != isFloatOnTop else { return }
        
        isFloatOnTop = newValue
        updateWindowLevel()
        
        print("✓ SuperSpacesHUD (\(hudID)): Float on top changed to \(newValue)")
        
        // Trigger save of all HUD configurations
        manager?.saveHUDConfigurations()
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
            
            // Restore window size for the current display mode
            // This ensures the HUD appears with the user's preferred size after app restart
            // ARCHITECTURE CHANGE (Jan 23, 2026):
            // Now uses per-HUD currentDisplayMode instead of global setting
            // We use animated: false here because the window isn't visible yet,
            // so there's no need to animate the initial size restoration
            self.restoreSizeForMode(self.currentDisplayMode, animated: false)
            
            // Refresh Space data
            self.refreshSpaces()
            
            // Show window first
            self.orderFront(nil)
            self.isCurrentlyVisible = true
            
            // Set window level AFTER showing
            // This is critical because NSPanel may reset the level during orderFront()
            // Setting it after ensures our desired level is applied and sticks
            self.updateWindowLevel()
            
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
    
    /// Copies settings from another HUD
    /// Used when duplicating a HUD to preserve user preferences
    /// - Parameter sourceHUD: The HUD to copy settings from
    ///
    /// SETTINGS COPIED (Jan 23, 2026):
    /// - Display mode (compact, note, overview)
    /// - Float on top setting (per-HUD)
    /// - Window size
    func copySettings(from sourceHUD: SuperSpacesHUD) {
        // Copy display mode (per-HUD setting)
        self.currentDisplayMode = sourceHUD.currentDisplayMode
        
        // Copy float on top setting (per-HUD setting)
        // Each HUD can have its own independent float on top preference
        self.isFloatOnTop = sourceHUD.isFloatOnTop
        updateWindowLevel()
        
        // Copy window size
        let sourceSize = sourceHUD.frame.size
        var newFrame = self.frame
        newFrame.size = sourceSize
        setFrame(newFrame, display: true)
        
        // Notify view to update mode and float on top
        viewModel.currentDisplayModeString = self.currentDisplayMode
        viewModel.floatOnTop = self.isFloatOnTop
        
        print("✓ SuperSpacesHUD: Copied settings from \(sourceHUD.hudID), mode: \(currentDisplayMode), floatOnTop: \(isFloatOnTop)")
    }
    
    /// Returns the current configuration for this HUD
    /// Used for persistence
    /// - Returns: HUDConfiguration with current state
    ///
    /// SETTINGS PERSISTED (Jan 23, 2026):
    /// - id: Unique identifier for the HUD
    /// - displayMode: compact, note, or overview
    /// - position: Window position on screen
    /// - size: Window dimensions
    /// - isVisible: Whether HUD is currently shown
    /// - floatOnTop: Per-HUD float on top setting (independent for each HUD)
    func getConfiguration() -> HUDConfiguration {
        var config = HUDConfiguration(id: hudID)
        config.displayMode = currentDisplayMode
        config.position = frame.origin
        config.size = frame.size
        config.isVisible = isCurrentlyVisible
        config.floatOnTop = isFloatOnTop
        return config
    }
    
    /// Updates the display mode for this HUD instance
    /// Called when user changes mode in the UI
    /// - Parameter mode: The new display mode string ("compact", "note", "overview")
    func setDisplayMode(_ mode: String) {
        guard mode != currentDisplayMode else { return }
        
        currentDisplayMode = mode
        print("✓ SuperSpacesHUD (\(hudID)): Display mode changed to \(mode)")
        
        // Trigger save of all HUD configurations
        manager?.saveHUDConfigurations()
    }
    
    /// Returns the current display mode for this HUD
    /// - Returns: The display mode string ("compact", "note", "overview")
    func getDisplayMode() -> String {
        return currentDisplayMode
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
    /// Saves all HUD configurations (debounced)
    ///
    /// PERSISTENCE (Jan 23, 2026):
    /// Now triggers save of all HUD configurations via manager
    /// instead of saving to global lastHUDPosition
    func windowDidMove(_ notification: Notification) {
        // Cancel previous save timer
        positionSaveTimer?.invalidate()
        
        // Schedule new save after delay (debounce)
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let position = self.frame.origin
            print("💾 SuperSpacesHUD (\(self.hudID)): Position changed to \(position)")
            
            // Trigger save of all HUD configurations
            self.manager?.saveHUDConfigurations()
        }
    }
    
    /// Called when window resizes
    /// Saves all HUD configurations (debounced)
    ///
    /// PERSISTENCE (Jan 23, 2026):
    /// Now triggers save of all HUD configurations via manager
    /// Each HUD's size is saved independently per-instance
    func windowDidResize(_ notification: Notification) {
        // Cancel previous save timer
        sizeSaveTimer?.invalidate()
        
        // Schedule new save after delay (debounce)
        sizeSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let size = self.frame.size
            print("💾 SuperSpacesHUD (\(self.hudID)): Size changed to \(size)")
            
            // Trigger save of all HUD configurations
            self.manager?.saveHUDConfigurations()
        }
    }
    
    /// Restores window size for the current display mode
    /// Called when switching modes to restore the user's preferred size for that mode
    /// Also called on initial show to restore the saved size after app restart
    ///
    /// - Parameters:
    ///   - mode: The display mode ("compact", "note", or "overview")
    ///   - animated: Whether to animate the size change (default: true)
    ///               Set to false for instant resize (e.g., on initial load)
    func restoreSizeForMode(_ mode: String, animated: Bool = true) {
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
        
        // Calculate new frame
        var newFrame = self.frame
        newFrame.size = targetSize
        
        // Adjust origin to keep top-left corner fixed
        // (NSWindow origin is bottom-left, so we need to adjust Y)
        let heightDiff = targetSize.height - self.frame.height
        newFrame.origin.y -= heightDiff
        
        if animated {
            // Animate size change
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            // Instant resize (no animation)
            self.setFrame(newFrame, display: true)
        }
        
        print("✓ SuperSpacesHUD: Restored \(mode) mode size to \(targetSize) (animated: \(animated))")
    }
}
