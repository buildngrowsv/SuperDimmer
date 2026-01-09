/**
 ====================================================================
 SuperDimmerApp.swift
 Main entry point for the SuperDimmer application
 ====================================================================
 
 PURPOSE:
 This is the @main entry point for the SwiftUI application lifecycle.
 It sets up the app as a menu bar utility with no main window.
 
 ARCHITECTURE DECISION:
 We use NSApplicationDelegateAdaptor to bridge SwiftUI's @main with
 traditional AppKit's NSApplicationDelegate. This is necessary because:
 - Menu bar apps require NSStatusItem which is an AppKit component
 - SwiftUI alone cannot create menu bar presence
 - We need AppKit lifecycle events (applicationDidFinishLaunching, etc.)
 
 The empty `body` is intentional - all UI is in the menu bar popover,
 not in a traditional window. The Settings scene is for macOS
 standard preferences support.
 
 DEPENDENCIES:
 - AppDelegate: Handles app lifecycle and initializes MenuBarController
 - SettingsManager: Injected as environment object for SwiftUI views
 
 SIMILAR TO:
 - f.lux: Menu bar app with no dock icon
 - Umbra: Menu bar app with popover controls
 - MonitorControlLite: Menu bar app with SwiftUI popover
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import SwiftUI

// ====================================================================
// MARK: - Main App Entry Point
// ====================================================================

/**
 The main entry point for SuperDimmer.
 
 This struct conforms to the App protocol which is SwiftUI's way of defining
 an application. The @main attribute tells the Swift compiler this is where
 execution begins.
 
 WHY SWIFTUI APP + APPKIT DELEGATE:
 SwiftUI's App protocol is great for modern macOS apps, but menu bar apps
 are a special case. NSStatusItem (the menu bar icon) is an AppKit-only
 feature, so we need the AppDelegate to set it up. The NSApplicationDelegateAdaptor
 property wrapper bridges these two worlds.
 
 The body being essentially empty is intentional - SuperDimmer has no
 main window. All user interaction happens through:
 1. The menu bar icon (NSStatusItem)
 2. The popover dropdown (SwiftUI view in NSPopover)
 3. The preferences window (standard macOS settings)
 */
@main
struct SuperDimmerApp: App {
    
    // ================================================================
    // MARK: - AppKit Bridge
    // ================================================================
    
    /**
     Bridges the SwiftUI app lifecycle with AppKit's NSApplicationDelegate.
     
     WHY THIS IS NEEDED:
     - NSStatusItem (menu bar icon) requires AppKit
     - We need applicationDidFinishLaunching to set up the menu bar
     - We need applicationWillTerminate to clean up overlays and restore gamma
     
     The AppDelegate instance is created automatically by this property wrapper
     and receives all standard NSApplicationDelegate callbacks.
     */
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // ================================================================
    // MARK: - Environment Objects
    // ================================================================
    
    /**
     Shared settings manager instance for the entire app.
     
     WHY STATEOBJECT:
     - Settings need to persist for the app's lifetime
     - Changes should trigger UI updates (ObservableObject)
     - Single source of truth for all settings
     
     This is passed to SwiftUI views via .environmentObject()
     */
    @StateObject private var settingsManager = SettingsManager.shared
    
    // ================================================================
    // MARK: - App Body
    // ================================================================
    
    /**
     The app's scene configuration.
     
     WHY THIS IS MINIMAL:
     SuperDimmer is a menu bar app - there is no main window. The only
     "scene" we define is Settings, which macOS uses for the standard
     Preferences menu item (⌘,).
     
     The actual UI (menu bar popover) is created by AppDelegate using
     AppKit's NSStatusItem and NSPopover, not through SwiftUI scenes.
     
     ALTERNATIVE CONSIDERED:
     We could use MenuBarExtra (macOS 13+) but it's limited compared to
     custom NSStatusItem + NSPopover approach. MenuBarExtra doesn't support:
     - Custom popover sizing
     - Animation control
     - Complex interaction patterns
     */
    var body: some Scene {
        // ============================================================
        // Settings Scene
        // ============================================================
        // This creates the standard macOS Preferences window
        // Accessed via menu bar: SuperDimmer > Preferences (⌘,)
        // Also accessible via "Preferences..." button in popover
        Settings {
            PreferencesView()
                .environmentObject(settingsManager)
        }
        
        // ============================================================
        // NO MAIN WINDOW
        // ============================================================
        // Intentionally empty - SuperDimmer has no traditional window.
        // All UI is delivered through:
        // 1. Menu bar popover (created by MenuBarController)
        // 2. Preferences window (Settings scene above)
        // 3. Permission request sheets (system dialogs)
    }
}

// ====================================================================
// MARK: - Preview Provider
// ====================================================================

/**
 SwiftUI Preview for development purposes.
 
 NOTE: Since SuperDimmerApp has no visual body, this preview shows
 the preferences view instead for development convenience.
 */
#if DEBUG
struct SuperDimmerApp_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .environmentObject(SettingsManager.shared)
            .frame(width: 500, height: 400)
    }
}
#endif
