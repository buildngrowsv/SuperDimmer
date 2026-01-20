/**
 ====================================================================
 PermissionManager.swift
 Centralized permission handling for all system permissions
 ====================================================================
 
 PURPOSE:
 This class manages all permission requests and status checks for
 SuperDimmer. It provides:
 - Unified interface for checking permission states
 - Methods to request each permission type
 - Deep links to System Settings for manual grant
 - Observable state for SwiftUI integration
 
 PERMISSIONS NEEDED:
 1. Screen Recording - CRITICAL for brightness detection
 2. Accessibility - CRITICAL for instant focus detection (AXObserver)
 3. Location - Optional for sunrise/sunset automation
 4. Automation - Optional for wallpaper/appearance switching
 
 STRATEGY:
 - Request permissions just-in-time, not at launch
 - Provide clear explanations before requesting
 - Gracefully degrade if permission denied
 - Show deep link to Settings for manual grant
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import AppKit
import CoreLocation
import Combine

// ====================================================================
// MARK: - Permission Manager
// ====================================================================

/**
 Manages system permission requests and status for SuperDimmer.
 
 USAGE:
 - Access via PermissionManager.shared or inject as dependency
 - Check permission status with isXXXGranted properties
 - Request permission with requestXXX() methods
 - Subscribe to @Published properties for reactive updates
 */
final class PermissionManager: NSObject, ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /// Shared singleton instance
    static let shared = PermissionManager()
    
    // ================================================================
    // MARK: - Published State
    // ================================================================
    
    /**
     Whether Screen Recording permission is granted.
     
     CRITICAL: This is required for SuperDimmer's core functionality.
     Without this, we can only capture our own windows, not other apps.
     
     Checked via CGPreflightScreenCaptureAccess() on macOS 10.15+
     */
    @Published private(set) var screenRecordingGranted: Bool = false
    
    /**
     Whether Location permission is granted.
     
     OPTIONAL: Only needed for sunrise/sunset based scheduling.
     App works without it, user just sets times manually.
     */
    @Published private(set) var locationGranted: Bool = false
    
    /**
     Whether Accessibility permission is granted.
     
     CRITICAL for instant focus detection (AXObserver).
     Without this, window focus notifications won't fire and overlays
     may have delayed z-order updates when switching windows.
     
     Checked via AXIsProcessTrusted()
     */
    @Published private(set) var accessibilityGranted: Bool = false
    
    /**
     Whether Automation/AppleEvents permission is granted.
     
     OPTIONAL: Only needed for wallpaper switching and appearance toggle.
     These features are disabled if permission not granted.
     */
    @Published private(set) var automationGranted: Bool = false
    
    // ================================================================
    // MARK: - Private Properties
    // ================================================================
    
    /// Location manager for location permission
    private var locationManager: CLLocationManager?
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    override init() {
        super.init()
        
        // Check initial states
        checkAllPermissions()
        
        print("✓ PermissionManager initialized")
    }
    
    // ================================================================
    // MARK: - Check All Permissions
    // ================================================================
    
    /**
     Checks and updates the status of all permissions.
     
     Called at launch and after returning from System Settings.
     Updates the @Published properties which trigger UI updates.
     */
    func checkAllPermissions() {
        screenRecordingGranted = checkScreenRecordingPermission()
        accessibilityGranted = checkAccessibilityPermission()
        locationGranted = checkLocationPermission()
        automationGranted = checkAutomationPermission()
        
        print("📋 Permission Status:")
        print("   Screen Recording: \(screenRecordingGranted ? "✓" : "✗")")
        print("   Accessibility: \(accessibilityGranted ? "✓" : "✗")")
        print("   Location: \(locationGranted ? "✓" : "✗")")
        print("   Automation: \(automationGranted ? "✓" : "✗")")
    }
    
    // ================================================================
    // MARK: - Accessibility Permission
    // ================================================================
    
    /**
     Checks if Accessibility permission is granted.
     
     REQUIRED FOR:
     - AXObserver to receive focus change notifications
     - Instant window focus detection (<10ms vs 20-60ms without)
     
     Without this permission, the app falls back to the mouse click
     monitor which has higher latency.
     */
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    /**
     Requests Accessibility permission.
     
     BEHAVIOR:
     AXIsProcessTrustedWithOptions can show a system prompt. However,
     like Screen Recording, the user must manually enable it in System Settings.
     
     The `kAXTrustedCheckOptionPrompt` option will show a dialog directing
     the user to System Settings.
     */
    func requestAccessibilityPermission() {
        // Show system prompt and open settings
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Also open settings directly for convenience
        openAccessibilitySettings()
    }
    
    /**
     Opens System Settings to the Accessibility privacy pane.
     */
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        print("🔗 Opened Accessibility settings")
    }
    
    // ================================================================
    // MARK: - Screen Recording Permission
    // ================================================================
    
    /**
     Checks if Screen Recording permission is granted.
     
     IMPLEMENTATION FIX (Jan 19, 2026):
     CGPreflightScreenCaptureAccess() is UNRELIABLE - it can return false
     even after the user grants permission in System Settings. This is a
     known macOS bug/quirk documented in ScreenCaptureService.
     
     SOLUTION:
     Use ScreenCaptureService.shared.hasPermission which does an actual
     capture test (1x1 pixel) to verify permission. This is the most
     reliable method.
     
     WHY THIS APPROACH:
     ScreenCaptureService already implements the reliable permission check
     with caching (checks every 5 seconds). We should use that instead of
     duplicating the logic here.
     */
    func checkScreenRecordingPermission() -> Bool {
        // Use ScreenCaptureService's reliable permission check
        // It does an actual capture test if CGPreflightScreenCaptureAccess() returns false
        return ScreenCaptureService.shared.hasPermission
    }
    
    /**
     Requests Screen Recording permission.
     
     BEHAVIOR:
     On macOS 10.15+, CGRequestScreenCaptureAccess() shows the system
     dialog asking user to grant permission. However, the user must
     manually enable it in System Settings - the dialog just shows
     a "Open System Settings" button.
     
     WHY IT'S COMPLEX:
     Apple made Screen Recording permission require manual enabling
     as a security measure. The app can request, but can't programmatically
     get the permission - user must go to Settings.
     */
    func requestScreenRecordingPermission() {
        if #available(macOS 10.15, *) {
            // This shows the system dialog which directs to Settings
            CGRequestScreenCaptureAccess()
        }
        
        // Open System Settings directly for convenience
        openScreenRecordingSettings()
        
        // Note: Permission status won't update until user grants it
        // and we check again (e.g., when they return to the app)
    }
    
    /**
     Opens System Settings to the Screen Recording privacy pane.
     */
    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        print("🔗 Opened Screen Recording settings")
    }
    
    /**
     Tests if screen capture actually works.
     
     Used as a fallback to determine permission status on older macOS.
     Also useful for verifying permission after grant.
     */
    private func testScreenCapture() -> Bool {
        // Try to capture a small region of the main display
        let captureRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
        let image = CGWindowListCreateImage(
            captureRegion,
            .optionOnScreenOnly,
            kCGNullWindowID,
            []
        )
        return image != nil
    }
    
    // ================================================================
    // MARK: - Location Permission
    // ================================================================
    
    /**
     Checks if Location permission is granted.
     
     IMPLEMENTATION:
     Uses CLLocationManager.authorizationStatus() to check.
     We only need "when in use" permission, not always.
     */
    func checkLocationPermission() -> Bool {
        let status = CLLocationManager.authorizationStatus()
        return status == .authorized || status == .authorizedAlways
    }
    
    /**
     Requests Location permission.
     
     Shows the system dialog asking user to allow location access.
     Used for sunrise/sunset based color temperature scheduling.
     */
    func requestLocationPermission() {
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
        }
        
        locationManager?.requestWhenInUseAuthorization()
        print("📍 Requested location permission")
    }
    
    /**
     Opens System Settings to the Location privacy pane.
     */
    func openLocationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
        print("🔗 Opened Location settings")
    }
    
    // ================================================================
    // MARK: - Automation Permission
    // ================================================================
    
    /**
     Checks if Automation (AppleEvents) permission is granted.
     
     IMPLEMENTATION:
     There's no direct API to check Automation permission.
     We try to send a simple AppleScript command and see if it fails.
     */
    func checkAutomationPermission() -> Bool {
        // Try a harmless AppleScript to test permission
        let script = NSAppleScript(source: "tell application \"Finder\" to return name")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        
        // If no error, permission is granted
        // Error -1743 means permission denied
        if let error = error, let errorNumber = error[NSAppleScript.errorNumber] as? Int {
            return errorNumber != -1743
        }
        return true
    }
    
    /**
     Requests Automation permission by triggering an AppleScript.
     
     BEHAVIOR:
     macOS will show a permission dialog when an app tries to
     control another app via AppleScript for the first time.
     */
    func requestAutomationPermission() {
        // Trigger the permission dialog by trying to control Finder
        let script = NSAppleScript(source: "tell application \"Finder\" to return name")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        
        // Update status after attempt
        automationGranted = checkAutomationPermission()
        print("🤖 Requested automation permission")
    }
    
    /**
     Opens System Settings to the Automation privacy pane.
     */
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
        print("🔗 Opened Automation settings")
    }
    
    // ================================================================
    // MARK: - Public Interface
    // ================================================================
    
    /**
     Permission types that SuperDimmer uses.
     */
    enum Permission {
        case screenRecording
        case location
        case automation
    }
    
    /**
     Checks if a specific permission is granted.
     
     - Parameter permission: The permission to check
     - Returns: Whether the permission is granted
     */
    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .screenRecording: return screenRecordingGranted
        case .location: return locationGranted
        case .automation: return automationGranted
        }
    }
    
    /**
     Requests a specific permission.
     
     - Parameter permission: The permission to request
     */
    func request(_ permission: Permission) {
        switch permission {
        case .screenRecording: requestScreenRecordingPermission()
        case .location: requestLocationPermission()
        case .automation: requestAutomationPermission()
        }
    }
    
    /**
     Opens System Settings to the pane for a specific permission.
     
     - Parameter permission: The permission whose settings to open
     */
    func openSettings(for permission: Permission) {
        switch permission {
        case .screenRecording: openScreenRecordingSettings()
        case .location: openLocationSettings()
        case .automation: openAutomationSettings()
        }
    }
}

// ====================================================================
// MARK: - CLLocationManager Delegate
// ====================================================================

extension PermissionManager: CLLocationManagerDelegate {
    
    /**
     Called when location authorization status changes.
     */
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationGranted = checkLocationPermission()
        print("📍 Location authorization changed: \(locationGranted ? "granted" : "denied")")
        
        // Notify interested parties
        NotificationCenter.default.post(
            name: .locationPermissionChanged,
            object: nil,
            userInfo: ["granted": locationGranted]
        )
    }
    
    // For older macOS versions
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        locationGranted = (status == .authorized || status == .authorizedAlways)
        print("📍 Location authorization changed: \(locationGranted ? "granted" : "denied")")
    }
}

// ====================================================================
// MARK: - Notification Names
// ====================================================================

extension Notification.Name {
    /// Posted when location permission changes
    static let locationPermissionChanged = Notification.Name("superdimmer.locationPermissionChanged")
    
    /// Posted when screen recording permission changes
    static let screenRecordingPermissionChanged = Notification.Name("superdimmer.screenRecordingPermissionChanged")
}
