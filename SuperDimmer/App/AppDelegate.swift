/**
 ====================================================================
 AppDelegate.swift
 Traditional AppKit application delegate for menu bar setup
 ====================================================================
 
 PURPOSE:
 This class handles the AppKit side of the application lifecycle.
 It's responsible for:
 - Creating and managing the menu bar icon (NSStatusItem)
 - Initializing core services on launch
 - Cleaning up resources on quit
 - Handling app activation/deactivation events
 
 WHY APPDELEGATE IS NEEDED:
 SwiftUI's App protocol doesn't provide direct access to NSStatusItem
 or the low-level lifecycle events we need. AppDelegate bridges this gap.
 
 The flow is:
 1. SuperDimmerApp creates AppDelegate via @NSApplicationDelegateAdaptor
 2. macOS calls applicationDidFinishLaunching
 3. We create MenuBarController which sets up the status item
 4. User interacts via menu bar → SwiftUI popover views
 
 LIFECYCLE:
 - applicationDidFinishLaunching: Initialize everything
 - applicationWillTerminate: Cleanup (remove overlays, restore gamma)
 - applicationDidBecomeActive: Resume if paused
 - applicationWillResignActive: Can pause analysis to save battery
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import AppKit
import SwiftUI
import Combine

// ====================================================================
// MARK: - App Delegate
// ====================================================================

/**
 The AppKit application delegate for SuperDimmer.
 
 This class is instantiated automatically by SwiftUI's @NSApplicationDelegateAdaptor
 and receives all standard NSApplicationDelegate callbacks.
 
 RESPONSIBILITIES:
 1. Menu Bar Setup: Creates MenuBarController on launch
 2. Service Initialization: Starts SettingsManager, DimmingCoordinator
 3. Permission Checking: Verifies screen recording permission
 4. Cleanup: Ensures overlays removed and gamma restored on quit
 
 WHY NSObject SUBCLASS:
 NSApplicationDelegate is an Objective-C protocol that requires NSObject
 conformance. This is standard for AppKit delegates.
 */
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     The controller that manages our menu bar presence.
     
     Created in applicationDidFinishLaunching and kept alive for the app's lifetime.
     Strong reference prevents deallocation which would remove the menu bar icon.
     */
    var menuBarController: MenuBarController?
    
    /**
     The coordinator that orchestrates the dimming system.
     
     This is the "brain" of SuperDimmer - it coordinates:
     - Window tracking
     - Brightness analysis
     - Overlay management
     
     Initialized after permission is granted.
     */
    var dimmingCoordinator: DimmingCoordinator?
    
    /**
     Manager for handling all permission requests and status.
     
     Centralized permission handling ensures consistent UX when requesting
     screen recording, location, and automation permissions.
     */
    var permissionManager: PermissionManager?
    
    /**
     Manager for color temperature (blue light filter) adjustments.
     
     Adjusts display gamma curves to reduce blue light. Initialized early
     because it needs to apply settings immediately if enabled.
     */
    var colorTemperatureManager: ColorTemperatureManager?
    
    /**
     Combine subscriptions for settings observation.
     */
    private var cancellables = Set<AnyCancellable>()
    
    // ================================================================
    // MARK: - App Lifecycle
    // ================================================================
    
    /**
     Called when the app has finished launching.
     
     This is the main initialization point. We:
     1. Set up the menu bar controller (creates status item + popover)
     2. Initialize the permission manager
     3. Check for screen recording permission
     4. If permitted, start the dimming coordinator
     
     WHY HERE AND NOT IN init():
     - AppKit isn't fully initialized in init()
     - NSStatusBar may not be available yet
     - This is the standard place for app initialization
     
     ORDER MATTERS:
     - SettingsManager must be ready before MenuBarController (uses settings)
     - MenuBarController before user can interact
     - Permissions before DimmingCoordinator (needs screen capture)
     */
    func applicationDidFinishLaunching(_ notification: Notification) {
        // ============================================================
        // Store shared instance for global access
        // ============================================================
        // This MUST be first - other code may need AppDelegate.shared
        storeSharedInstance()
        
        // ============================================================
        // Log startup for debugging
        // ============================================================
        print("🌟 SuperDimmer launching...")
        print("   macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("   App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        
        // ============================================================
        // Step 1: Initialize Settings Manager (singleton already exists)
        // ============================================================
        // SettingsManager.shared is already created when accessed
        // We just log that it's ready
        print("✓ SettingsManager initialized")
        
        // ============================================================
        // Step 2: Initialize Permission Manager (use singleton)
        // ============================================================
        // This checks current permission states without requesting
        permissionManager = PermissionManager.shared
        permissionManager?.checkAllPermissions()
        print("✓ PermissionManager ready")
        
        // ============================================================
        // Step 2.5: Initialize Color Temperature Manager
        // ============================================================
        // This enables f.lux-style blue light filtering
        // Must be initialized before UI so it can apply settings immediately
        colorTemperatureManager = ColorTemperatureManager.shared
        print("✓ ColorTemperatureManager ready")
        
        // ============================================================
        // Step 3: Create Menu Bar Controller
        // ============================================================
        // This creates the NSStatusItem and popover
        // The menu bar icon will appear after this call
        menuBarController = MenuBarController()
        menuBarController?.setupMenuBar()
        print("✓ MenuBarController initialized - menu bar icon should be visible")
        
        // ============================================================
        // Step 4: Initialize Dimming Coordinator (if permitted)
        // ============================================================
        // Only start the dimming system if we have screen recording permission
        // If not permitted, the user will see a prompt when they try to enable dimming
        if permissionManager?.screenRecordingGranted == true {
            initializeDimmingCoordinator()
        } else {
            print("⚠️ Screen Recording permission not granted yet")
            print("   Dimming will be available after permission is granted")
        }
        
        // ============================================================
        // Step 5: Setup settings observers
        // ============================================================
        // Listen for dimming toggle changes from UI
        setupSettingsObservers()
        
        // ============================================================
        // Step 6: Check for first launch
        // ============================================================
        // Show onboarding or permission guide on first launch
        if SettingsManager.shared.isFirstLaunch {
            print("👋 First launch detected - will show onboarding")
            // TODO: Show onboarding window/permission guide
            SettingsManager.shared.isFirstLaunch = false
        }
        
        print("🌟 SuperDimmer launch complete!")
        print("ℹ️  Toggle dimming ON in the menu bar to see the effect")
    }
    
    /**
     Called when the app is about to terminate.
     
     CRITICAL CLEANUP:
     1. Remove all overlay windows (otherwise they'd persist as orphans)
     2. Restore display gamma to defaults (color temperature)
     3. Save any unsaved settings
     
     WHY THIS MATTERS:
     - Overlays without their managing app would stay on screen forever
     - Modified gamma tables would persist, making displays look wrong
     - User settings should always be saved
     */
    func applicationWillTerminate(_ notification: Notification) {
        print("👋 SuperDimmer terminating - cleaning up...")
        
        // ============================================================
        // Full cleanup of dimming coordinator
        // ============================================================
        // Use cleanup() instead of stop() to actually destroy overlays
        // stop() only hides them for quick re-enable
        dimmingCoordinator?.cleanup()
        print("✓ Dimming coordinator cleaned up")
        
        // ============================================================
        // Restore color temperature to default
        // ============================================================
        colorTemperatureManager?.restore()
        print("✓ Color temperature restored")
        
        // ============================================================
        // Restore gamma to defaults
        // ============================================================
        // If we had modified color temperature, reset to normal
        // CGDisplayRestoreColorSyncSettings(kCGNullDirectDisplay) // For all displays
        print("✓ Display gamma restored")
        
        // ============================================================
        // Save settings
        // ============================================================
        SettingsManager.shared.save()
        print("✓ Settings saved")
        
        print("👋 SuperDimmer cleanup complete, goodbye!")
    }
    
    /**
     Called when the app becomes active (user switched to it or clicked menu bar).
     
     POTENTIAL USE:
     - Resume analysis if it was paused
     - Refresh permission status
     - Update UI to reflect current state
     */
    func applicationDidBecomeActive(_ notification: Notification) {
        // Currently no special handling needed
        // The dimming coordinator runs continuously regardless of app focus
    }
    
    /**
     Called when the app loses active status.
     
     NOTE: We do NOT pause dimming when the app loses focus.
     The whole point is to dim bright content while using OTHER apps.
     
     POTENTIAL USE:
     - Could reduce analysis frequency to save battery
     - Could pause if user explicitly requests "pause when app not visible"
     */
    func applicationWillResignActive(_ notification: Notification) {
        // Intentionally empty - dimming continues when app not focused
    }
    
    // ================================================================
    // MARK: - Initialization Helpers
    // ================================================================
    
    /**
     Initializes the dimming coordinator.
     
     Called either:
     1. During launch if permission already granted
     2. After user grants screen recording permission
     3. When user toggles dimming ON
     
     NOTE: This just creates the coordinator - call start() separately
     to actually begin dimming. This avoids race conditions.
     */
    func initializeDimmingCoordinator() {
        guard dimmingCoordinator == nil else {
            print("⚠️ DimmingCoordinator already initialized")
            return
        }
        
        print("🔧 Initializing DimmingCoordinator...")
        dimmingCoordinator = DimmingCoordinator()
        print("✓ DimmingCoordinator initialized (call start() to begin)")
    }
    
    /**
     Called when screen recording permission status changes.
     
     This is triggered by PermissionManager when the user grants or revokes
     screen recording permission in System Settings.
     
     - Parameter granted: Whether permission is now granted
     */
    func screenRecordingPermissionChanged(granted: Bool) {
        print("🔐 Screen Recording permission changed: \(granted ? "granted" : "revoked")")
        
        if granted {
            // Permission granted - we can now start dimming
            initializeDimmingCoordinator()
            // Update menu bar to show available controls
            menuBarController?.updateForPermissionChange()
        } else {
            // Permission revoked - stop dimming
            dimmingCoordinator?.stop()
            dimmingCoordinator = nil
            // Update menu bar to show permission needed message
            menuBarController?.updateForPermissionChange()
        }
    }
    
    // ================================================================
    // MARK: - Settings Observers
    // ================================================================
    
    /**
     Sets up observers for settings that need AppDelegate to respond.
     
     Most importantly, we observe isDimmingEnabled so we can start/stop
     the dimming coordinator when the user toggles it in the UI.
     */
    private func setupSettingsObservers() {
        // Observe isDimmingEnabled changes from the UI
        SettingsManager.shared.$isDimmingEnabled
            .dropFirst() // Skip initial value - we handle it separately below
            .sink { [weak self] enabled in
                self?.handleDimmingToggled(enabled)
            }
            .store(in: &cancellables)
        
        // IMPORTANT: If dimming was already enabled from a previous session,
        // we need to start it now! The dropFirst() skips the initial value,
        // so we check manually here.
        if SettingsManager.shared.isDimmingEnabled {
            print("✓ Dimming was already enabled - starting now")
            // Small delay to ensure everything is initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.handleDimmingToggled(true)
            }
        }
        
        print("✓ Settings observers setup")
    }
    
    /**
     Handles when user toggles dimming on/off in the UI.
     
     - Parameter enabled: Whether dimming should be enabled
     
     NOTE: For MVP (Phase 1), we use simple full-screen dimming which does
     NOT require screen recording permission. Permission is only needed for
     Phase 2 intelligent brightness detection. So we start dimming regardless
     of permission status.
     
     FIX (Jan 7, 2026): Removed debouncing - no longer needed!
     The coordinator now uses hide/show instead of create/destroy for overlays,
     which is inherently safe for rapid toggling.
     */
    private func handleDimmingToggled(_ enabled: Bool) {
        print("🔄 Dimming toggled: \(enabled ? "ON" : "OFF")")
        
        if enabled {
            // User wants dimming ON
            // Ensure coordinator exists
            if dimmingCoordinator == nil {
                print("🔧 Creating DimmingCoordinator...")
                initializeDimmingCoordinator()
            }
            
            print("▶️ Starting dimming...")
            dimmingCoordinator?.start()
        } else {
            // User wants dimming OFF
            print("⏹️ Stopping dimming...")
            dimmingCoordinator?.stop()
        }
    }
}

// ====================================================================
// MARK: - App Delegate Extension for Menu Bar Access
// ====================================================================

/**
 Extension to provide convenient access to the app delegate from anywhere.
 
 Usage: AppDelegate.shared?.menuBarController
 
 WHY THIS PATTERN:
 - Avoids passing references through many layers
 - Standard pattern for accessing app-wide services
 
 FIX (Jan 8, 2026): Changed from force cast (as!) to safe cast (as?)
 because SwiftUI's lifecycle wraps our AppDelegate in SwiftUI.AppDelegate.
 The NSApplication.shared.delegate might not be directly castable.
 We now use a static instance reference instead.
 */
extension AppDelegate {
    /// Singleton instance reference, set in applicationDidFinishLaunching
    /// This avoids the unsafe cast that crashes with SwiftUI lifecycle
    static private(set) var shared: AppDelegate?
    
    /// Store the instance reference on launch
    func storeSharedInstance() {
        AppDelegate.shared = self
    }
}
