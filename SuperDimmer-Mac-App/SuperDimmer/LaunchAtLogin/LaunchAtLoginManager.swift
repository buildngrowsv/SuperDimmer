/**
 ====================================================================
 LaunchAtLoginManager.swift
 Manages launch at login functionality via ServiceManagement
 ====================================================================
 
 PURPOSE:
 This class handles adding/removing SuperDimmer as a login item
 so it can automatically start when the user logs in.
 
 IMPLEMENTATION:
 Uses the modern SMAppService API (macOS 13+) which is the recommended
 approach for registering login items without a helper app.
 
 PRIOR TO macOS 13:
 Login items required a helper app bundle using SMLoginItemSetEnabled.
 This is deprecated in favor of SMAppService.
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import ServiceManagement

// ====================================================================
// MARK: - Launch At Login Manager
// ====================================================================

/**
 Manages the app's login item registration.
 
 USAGE:
 - LaunchAtLoginManager.shared.isEnabled to check status
 - LaunchAtLoginManager.shared.setEnabled(true) to enable
 - LaunchAtLoginManager.shared.setEnabled(false) to disable
 */
final class LaunchAtLoginManager {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = LaunchAtLoginManager()
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /**
     Whether launch at login is currently enabled.
     
     Reads the actual state from the system, not just our settings.
     This handles cases where user manually removed the login item.
     */
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older macOS, we'd need to check login items differently
            // This is a fallback that just returns what we last set
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }
    
    // ================================================================
    // MARK: - Methods
    // ================================================================
    
    /**
     Sets whether the app should launch at login.
     
     - Parameter enabled: Whether to enable launch at login
     - Returns: Whether the operation succeeded
     
     On macOS 13+, uses SMAppService which handles everything.
     On older macOS, would need a helper app approach (not implemented).
     */
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    // Register as login item
                    try SMAppService.mainApp.register()
                    print("✓ Registered as login item")
                    return true
                } else {
                    // Unregister as login item
                    try SMAppService.mainApp.unregister()
                    print("✓ Unregistered as login item")
                    return true
                }
            } catch {
                print("❌ Failed to \(enabled ? "register" : "unregister") login item: \(error)")
                return false
            }
        } else {
            // Fallback for older macOS (not fully implemented)
            // Would need SMLoginItemSetEnabled with helper bundle
            print("⚠️ Launch at login requires macOS 13+")
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
            return false
        }
    }
    
    /**
     Toggles the launch at login state.
     
     - Returns: The new enabled state
     */
    @discardableResult
    func toggle() -> Bool {
        let newState = !isEnabled
        setEnabled(newState)
        return newState
    }
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        print("✓ LaunchAtLoginManager initialized, current state: \(isEnabled ? "enabled" : "disabled")")
    }
}
