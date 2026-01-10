/**
 ====================================================================
 MenuBarController.swift
 Manages the menu bar icon (NSStatusItem) and popover
 ====================================================================
 
 PURPOSE:
 This class creates and manages SuperDimmer's presence in the macOS menu bar.
 It handles:
 - Creating the status item (menu bar icon)
 - Showing/hiding the popover when clicked
 - Updating the icon based on app state
 - Handling global click-away to close popover
 
 TECHNICAL APPROACH:
 We use NSStatusItem with a button that shows an NSPopover containing
 SwiftUI views. This is the standard pattern used by:
 - MonitorControlLite
 - BetterDisplay
 - Umbra
 
 ALTERNATIVE CONSIDERED:
 macOS 13+ offers MenuBarExtra in SwiftUI, but it has limitations:
 - Less control over popover behavior
 - Harder to customize sizing and animation
 - Less flexible for complex UIs
 
 So we use the traditional NSStatusItem + NSPopover approach which gives
 us full control and is battle-tested by reference apps.
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import AppKit
import SwiftUI
import Combine

// ====================================================================
// MARK: - Menu Bar Controller
// ====================================================================

/**
 Controls the menu bar presence of SuperDimmer.
 
 This is an NSObject subclass because:
 1. We need to be a target for NSStatusBarButton actions
 2. We need to observe notifications (NSPopover close, etc.)
 3. Standard pattern for AppKit controllers
 
 LIFECYCLE:
 - Created by AppDelegate in applicationDidFinishLaunching
 - Lives for the entire app lifetime
 - If deallocated, the menu bar icon disappears (we prevent this)
 */
final class MenuBarController: NSObject {
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     The status item that appears in the menu bar.
     
     WHY OPTIONAL:
     - Created in setupMenuBar(), not init
     - Allows checking if setup has occurred
     
     WHY STRONG:
     - If status item is deallocated, it disappears from menu bar
     - Must keep strong reference for app lifetime
     */
    private var statusItem: NSStatusItem?
    
    /**
     The popover that shows when the menu bar icon is clicked.
     
     Contains SwiftUI MenuBarView with all controls.
     Created once and reused to preserve state.
     */
    private var popover: NSPopover?
    
    /**
     Event monitor for clicks outside the popover.
     
     Used to close the popover when user clicks elsewhere.
     This is standard macOS behavior for menu bar popovers.
     */
    private var eventMonitor: Any?
    
    /**
     Manages the menu bar icon appearance based on app state.
     
     Listens to settings changes and updates icon accordingly.
     */
    private var iconStateManager: MenuBarIconStateManager?
    
    /**
     Combine subscriptions for reactive updates.
     
     We subscribe to settings changes to update the icon state.
     */
    private var cancellables = Set<AnyCancellable>()
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Creates a new MenuBarController.
     
     NOTE: Doesn't create the status item yet - call setupMenuBar() for that.
     This separation allows for testing and ensures proper initialization order.
     */
    override init() {
        super.init()
        print("📍 MenuBarController initialized")
    }
    
    deinit {
        // Remove event monitor if still active
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        print("📍 MenuBarController deallocated")
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    /**
     Creates and configures the menu bar status item and popover.
     
     This should be called once during app launch (from AppDelegate).
     
     WHAT THIS DOES:
     1. Creates NSStatusItem with variable length (auto-sizes to content)
     2. Configures the button with icon and action
     3. Creates popover with SwiftUI content
     4. Sets up icon state manager for reactive updates
     */
    func setupMenuBar() {
        // ============================================================
        // Step 1: Create Status Item
        // ============================================================
        // NSStatusBar.system is the system's single menu bar
        // .variableLength means the item sizes based on its content
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem else {
            print("❌ Failed to create status item")
            return
        }
        
        // ============================================================
        // Step 2: Configure the Button
        // ============================================================
        // The button is what the user clicks in the menu bar
        if let button = statusItem.button {
            // Set initial icon - sun symbol for a dimming app
            // Using SF Symbols for crisp rendering on all displays
            button.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "SuperDimmer")
            
            // Make it a template image so it adapts to light/dark menu bar
            button.image?.isTemplate = true
            
            // Set the action when clicked
            button.action = #selector(togglePopover)
            button.target = self
            
            // Accessibility
            button.toolTip = "SuperDimmer - Click to adjust screen dimming"
        }
        
        // ============================================================
        // Step 3: Create Popover
        // ============================================================
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient // Closes when clicking outside
        popover?.animates = true
        
        // Wrap SwiftUI view in hosting controller for popover content
        // Using AnyView to type-erase the environmentObject modifier result
        let menuBarView = MenuBarView()
            .environmentObject(SettingsManager.shared)
        let hostingController = NSHostingController(rootView: AnyView(menuBarView))
        popover?.contentViewController = hostingController
        
        // ============================================================
        // Step 4: Setup Icon State Manager
        // ============================================================
        iconStateManager = MenuBarIconStateManager()
        setupIconStateObserver()
        
        // ============================================================
        // Step 5: Update Initial Icon State
        // ============================================================
        updateIconForCurrentState()
        
        print("✓ Menu bar setup complete")
    }
    
    // ================================================================
    // MARK: - Popover Control
    // ================================================================
    
    /**
     Toggles the popover visibility when menu bar icon is clicked.
     
     This is the action triggered by clicking the status item button.
     
     BEHAVIOR:
     - If popover is showing → close it
     - If popover is hidden → show it anchored to the status item
     
     WHY @objc:
     - Required for Objective-C selector mechanism used by NSButton
     */
    @objc func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else {
            return
        }
        
        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }
    
    /**
     Shows the popover anchored to the given button.
     
     - Parameter button: The NSStatusBarButton to anchor the popover to
     
     BEHAVIOR:
     1. Shows popover below the menu bar icon
     2. Makes the popover's window key (focused)
     3. Sets up event monitor to close on click-away
     */
    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover = popover else { return }
        
        // Show popover below the button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Make popover window key so it receives keyboard events
        popover.contentViewController?.view.window?.makeKey()
        
        // Setup event monitor to close popover when clicking outside
        setupEventMonitor()
        
        print("📍 Popover shown")
    }
    
    /**
     Closes the popover.
     
     BEHAVIOR:
     1. Performs close animation (per NSPopover.animates setting)
     2. Removes the click-away event monitor
     */
    func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
        print("📍 Popover closed")
    }
    
    // ================================================================
    // MARK: - Event Monitor
    // ================================================================
    
    /**
     Sets up global event monitor to close popover when clicking outside.
     
     This creates a monitor for mouse-down events. When user clicks
     anywhere outside the popover, we close it.
     
     WHY GLOBAL MONITOR:
     - .transient behavior should handle this, but can be unreliable
     - Explicit monitor ensures consistent behavior
     - Standard pattern used by other menu bar apps
     */
    private func setupEventMonitor() {
        // Remove existing monitor if any
        removeEventMonitor()
        
        // Create new monitor for left and right mouse down events
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            // Close popover when clicking outside
            if self?.popover?.isShown == true {
                self?.closePopover()
            }
        }
    }
    
    /**
     Removes the global event monitor.
     
     Called when popover closes to stop monitoring.
     Important to prevent memory leaks and unnecessary event processing.
     */
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    // ================================================================
    // MARK: - Icon State Management
    // ================================================================
    
    /**
     Sets up observation of settings changes to update icon state.
     
     When dimming is enabled/disabled or other relevant settings change,
     the icon should update to reflect the current state.
     
     Uses Combine publishers for reactive updates.
     */
    private func setupIconStateObserver() {
        // Observe isDimmingEnabled changes
        SettingsManager.shared.$isDimmingEnabled
            .sink { [weak self] _ in
                self?.updateIconForCurrentState()
            }
            .store(in: &cancellables)
        
        // Observe colorTemperatureEnabled changes
        SettingsManager.shared.$colorTemperatureEnabled
            .sink { [weak self] _ in
                self?.updateIconForCurrentState()
            }
            .store(in: &cancellables)
        
        // Observe temporary disable state changes
        // When user pauses dimming, the icon should change to indicate paused state
        TemporaryDisableManager.shared.$isTemporarilyDisabled
            .sink { [weak self] _ in
                self?.updateIconForCurrentState()
            }
            .store(in: &cancellables)
    }
    
    /**
     Updates the menu bar icon based on current app state.
     
     ICON STATES:
     - Disabled: Outline sun (dimming off)
     - Active: Filled sun (dimming on)
     - Paused: Pause circle (temporary disable active)
     - Color temp: Sun with warm tint (color temperature active)
     
     DESIGN DECISION (Jan 9, 2026):
     When temporarily disabled, we show a distinct "pause" icon so users
     can see at a glance that dimming is paused and will resume.
     This is more informative than just showing the "off" state.
     */
    func updateIconForCurrentState() {
        guard let button = statusItem?.button else { return }
        
        let isDimmingEnabled = SettingsManager.shared.isDimmingEnabled
        let isColorTempEnabled = SettingsManager.shared.colorTemperatureEnabled
        let isTemporarilyDisabled = TemporaryDisableManager.shared.isTemporarilyDisabled
        
        // Choose icon based on state
        // Using SF Symbols for crisp rendering
        let iconName: String
        
        // Priority: Temporary disable state takes precedence for icon display
        // This shows users that dimming is PAUSED (not off) and will resume
        if isTemporarilyDisabled {
            // Paused state - shows pause symbol so user knows dimming will resume
            iconName = "pause.circle"
        } else if isDimmingEnabled || isColorTempEnabled {
            // Active state - filled icon
            iconName = "sun.max.fill"
        } else {
            // Disabled state - outline icon
            iconName = "sun.max"
        }
        
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SuperDimmer")
        button.image?.isTemplate = true // Adapt to menu bar appearance
        
        // Update tooltip with current state
        // Include remaining time if temporarily disabled
        if isTemporarilyDisabled {
            let remainingTime = TemporaryDisableManager.shared.remainingTimeFormatted
            button.toolTip = "SuperDimmer - Paused (\(remainingTime) remaining)"
        } else if isDimmingEnabled && isColorTempEnabled {
            button.toolTip = "SuperDimmer - Dimming and color temperature active"
        } else if isDimmingEnabled {
            button.toolTip = "SuperDimmer - Dimming active"
        } else if isColorTempEnabled {
            button.toolTip = "SuperDimmer - Color temperature active"
        } else {
            button.toolTip = "SuperDimmer - Click to enable"
        }
    }
    
    /**
     Called when permission status changes to update UI accordingly.
     
     Used by AppDelegate when screen recording permission changes.
     Updates the popover content to show appropriate controls or messages.
     */
    func updateForPermissionChange() {
        // Force popover content to refresh by recreating the hosting controller
        // The SwiftUI view will read permission state and update accordingly
        let menuBarView = MenuBarView()
            .environmentObject(SettingsManager.shared)
        let hostingController = NSHostingController(rootView: AnyView(menuBarView))
        popover?.contentViewController = hostingController
        
        print("📍 Menu bar updated for permission change")
    }
}

// ====================================================================
// MARK: - Menu Bar Icon State Manager
// ====================================================================

/**
 Manages the logic for determining which icon to display.
 
 Separated from MenuBarController for cleaner code organization
 and easier testing of icon state logic.
 
 WHY SEPARATE CLASS:
 - Icon state logic may become complex with multiple states
 - Easier to test independently
 - Follows single responsibility principle
 */
final class MenuBarIconStateManager {
    
    /**
     Determines the appropriate icon name for the current state.
     
     - Returns: SF Symbol name for the current state
     
     ICON STATES (in priority order):
     - "pause.circle": Temporary disable active - dimming paused
     - "sun.max.fill": Active dimming or color temp
     - "sun.min.fill": Color temperature active only (warmer)
     - "sun.max": Default/disabled state - nothing active
     
     DESIGN DECISION (Jan 9, 2026):
     Temporary disable takes highest priority so users can see at a glance
     that the app is paused and will resume automatically.
     */
    func currentIconName() -> String {
        let isDimmingEnabled = SettingsManager.shared.isDimmingEnabled
        let isColorTempEnabled = SettingsManager.shared.colorTemperatureEnabled
        let isTemporarilyDisabled = TemporaryDisableManager.shared.isTemporarilyDisabled
        
        // Temporary disable has highest priority
        if isTemporarilyDisabled {
            return "pause.circle" // Paused state
        } else if isDimmingEnabled && isColorTempEnabled {
            return "sun.max.fill" // Both active
        } else if isDimmingEnabled {
            return "sun.max.fill" // Just dimming
        } else if isColorTempEnabled {
            return "sun.min.fill" // Just color temp (smaller sun = warmer)
        } else {
            return "sun.max" // Everything off
        }
    }
}
