/**
 ====================================================================
 MenuBarView.swift
 SwiftUI view displayed in the menu bar popover
 ====================================================================
 
 PURPOSE:
 This is the main UI that users interact with when clicking the menu bar icon.
 It provides quick access to all primary controls:
 - Master on/off toggle for dimming
 - Dim level slider
 - Brightness threshold slider
 - Color temperature controls
 - Access to preferences
 - Quit button
 
 DESIGN PHILOSOPHY:
 - Quick access to most-used controls
 - Clean, minimal interface that doesn't overwhelm
 - Matches macOS design language
 - Responsive to settings changes
 
 LAYOUT:
 The view is structured in sections:
 1. Header (app name, license status)
 2. Brightness controls (toggle, sliders)
 3. Color temperature controls (toggle, presets)
 4. Quick actions (preferences, quit)
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import SwiftUI

// ====================================================================
// MARK: - Menu Bar View
// ====================================================================

/**
 The main popover content view for SuperDimmer's menu bar presence.
 
 Uses @EnvironmentObject for SettingsManager to enable reactive updates
 when settings change (either here or in Preferences window).
 */
struct MenuBarView: View {
    
    // ================================================================
    // MARK: - Environment & State
    // ================================================================
    
    /**
     Shared settings manager - injected by parent view.
     All changes here are automatically persisted and reflected app-wide.
     */
    @EnvironmentObject var settings: SettingsManager
    
    /**
     Whether to show the permission needed banner.
     Updated based on actual permission status.
     */
    @State private var showPermissionBanner = false
    
    // ================================================================
    // MARK: - Body
    // ================================================================
    
    var body: some View {
        VStack(spacing: 0) {
            // ========================================================
            // Header Section
            // ========================================================
            headerSection
            
            Divider()
                .padding(.horizontal)
            
            // ========================================================
            // Permission Banner (if needed)
            // ========================================================
            if showPermissionBanner {
                permissionBanner
                Divider()
                    .padding(.horizontal)
            }
            
            // ========================================================
            // Brightness Controls
            // ========================================================
            brightnessSection
            
            Divider()
                .padding(.horizontal)
            
            // ========================================================
            // Color Temperature Controls
            // ========================================================
            colorTemperatureSection
            
            Divider()
                .padding(.horizontal)
            
            // ========================================================
            // Quick Actions Footer
            // ========================================================
            footerSection
        }
        .frame(width: 300)
        .padding(.vertical, 12)
        .onAppear {
            checkPermissions()
            // Refresh permission status every time popover appears
            PermissionManager.shared.checkAllPermissions()
            // Also refresh the screen capture service's cache
            ScreenCaptureService.shared.checkPermission()
        }
    }
    
    // ================================================================
    // MARK: - Header Section
    // ================================================================
    
    /**
     App name and license status display.
     */
    private var headerSection: some View {
        HStack {
            // App icon and name
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                Text("SuperDimmer")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // License status badge
            // TODO: Replace with actual license status
            Text("Free")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // ================================================================
    // MARK: - Permission Banner
    // ================================================================
    
    /**
     Banner shown when screen recording permission is not granted.
     */
    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Permission Required")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("Screen Recording access needed for brightness detection")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Grant") {
                openScreenRecordingSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
    }
    
    // ================================================================
    // MARK: - Brightness Section
    // ================================================================
    
    /**
     Controls for brightness detection and dimming.
     */
    private var brightnessSection: some View {
        VStack(spacing: 16) {
            // Master toggle
            HStack {
                Image(systemName: "eye")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                Text("Brightness Dimming")
                    .font(.subheadline)
                
                Spacer()
                
                Toggle("", isOn: $settings.isDimmingEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            
            // Dim level slider (only show when enabled)
            if settings.isDimmingEnabled {
                VStack(spacing: 8) {
                    // Dim amount slider
                    HStack {
                        Text("Dim Amount")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(settings.globalDimLevel * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(value: $settings.globalDimLevel, in: 0...0.8)
                        .tint(.orange)
                    
                    // Threshold slider
                    HStack {
                        Text("Brightness Threshold")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(Int(settings.brightnessThreshold * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.top, 8)
                    
                    Slider(value: $settings.brightnessThreshold, in: 0.5...1.0)
                        .tint(.yellow)
                    
                    // Explanation text
                    Text("Areas brighter than \(Int(settings.brightnessThreshold * 100))% will be dimmed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Intelligent dimming toggle
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.purple)
                            .font(.caption)
                        
                        Text("Intelligent Mode")
                            .font(.caption)
                        
                        Spacer()
                        
                        // FIX: Use DispatchQueue.main.async to defer state changes
                        // This prevents "AttributeGraph: cycle detected" warnings
                        // which occur when @Published properties are modified during view updates
                        Toggle("", isOn: Binding(
                            get: { settings.intelligentDimmingEnabled },
                            set: { newValue in
                                // Defer to next run loop to avoid cycle warnings
                                DispatchQueue.main.async {
                                    if newValue {
                                        // Request permission when enabling intelligent mode
                                        requestScreenRecordingAndEnable()
                                    } else {
                                        settings.intelligentDimmingEnabled = false
                                    }
                                }
                            }
                        ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    
                    if settings.intelligentDimmingEnabled {
                        // Simple description of what intelligent mode does
                        Text("Finds and dims bright areas within windows")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                        
                        // Debug toggle for developers/troubleshooting
                        debugSection
                        
                        // Show permission status with clickable button
                        // Check directly to avoid stale cache
                        if !CGPreflightScreenCaptureAccess() {
                            VStack(alignment: .leading, spacing: 4) {
                                Button(action: {
                                    openScreenRecordingSettings()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption2)
                                        Text("Grant Screen Recording →")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Text("After enabling, restart the app")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)
                                Text("Screen Recording enabled")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("Full-screen dimming mode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Excluded apps section - always visible when dimming enabled
                    Divider()
                        .padding(.vertical, 4)
                    
                    excludedAppsSection
                }
                .padding(.leading, 28) // Align with toggle text
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // ================================================================
    // MARK: - Edge Blur Section
    // ================================================================
    
    /**
     Debug controls section.
     */
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Debug Mode Toggle
            
            HStack {
                Image(systemName: "ladybug")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text("Debug Borders")
                    .font(.caption)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { settings.debugOverlayBorders },
                    set: { newValue in
                        settings.debugOverlayBorders = newValue
                        // Update existing overlays immediately
                        AppDelegate.shared?.dimmingCoordinator?.updateDebugBorders()
                    }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            
            if settings.debugOverlayBorders {
                Text("Shows red borders on overlays for positioning debug")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // ================================================================
    // MARK: - Excluded Apps Section
    // ================================================================
    
    /**
     Shows excluded apps count and button to manage them.
     Full management is in Preferences for space reasons.
     */
    private var excludedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
                    .font(.caption)
                
                Text("Excluded Apps")
                    .font(.caption)
                
                Spacer()
                
                let count = settings.excludedAppBundleIDs.count
                if count > 0 {
                    Text("\(count) app\(count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Button("Manage") {
                    openPreferences()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.blue)
            }
            
            if !settings.excludedAppBundleIDs.isEmpty {
                // Show first few excluded apps
                let displayApps = Array(settings.excludedAppBundleIDs.prefix(2))
                Text(displayApps.joined(separator: ", ") + (settings.excludedAppBundleIDs.count > 2 ? "..." : ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    // ================================================================
    // MARK: - Color Temperature Section
    // ================================================================
    
    /**
     Controls for color temperature (f.lux-style blue light filter).
     */
    private var colorTemperatureSection: some View {
        VStack(spacing: 16) {
            // Temperature toggle
            HStack {
                Image(systemName: "thermometer.sun")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                Text("Color Temperature")
                    .font(.subheadline)
                
                Spacer()
                
                Toggle("", isOn: $settings.colorTemperatureEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            
            // Temperature controls (only show when enabled)
            if settings.colorTemperatureEnabled {
                VStack(spacing: 12) {
                    // Temperature slider
                    HStack {
                        Image(systemName: "sun.max")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        
                        Slider(value: $settings.colorTemperature, in: 1900...6500)
                            .tint(temperatureColor)
                        
                        Image(systemName: "moon.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    
                    // Current temperature display
                    Text("\(Int(settings.colorTemperature))K")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    
                    // Quick presets
                    HStack(spacing: 8) {
                        ForEach(TemperaturePreset.allCases, id: \.self) { preset in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    settings.colorTemperature = Double(preset.kelvin)
                                }
                            }) {
                                Text(preset.shortName)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        isPresetSelected(preset) ?
                                        Color.orange.opacity(0.3) :
                                        Color.secondary.opacity(0.1)
                                    )
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 28) // Align with toggle text
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // ================================================================
    // MARK: - Footer Section
    // ================================================================
    
    /**
     Quick action buttons - preferences and quit.
     */
    private var footerSection: some View {
        HStack(spacing: 16) {
            // Preferences button
            Button(action: {
                openPreferences()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                    Text("Preferences")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            
            Spacer()
            
            // Quit button
            Button(action: {
                quitApp()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // ================================================================
    // MARK: - Helper Properties
    // ================================================================
    
    /**
     Color representing the current temperature setting.
     Warmer (lower K) = more orange, cooler (higher K) = more blue/white.
     */
    private var temperatureColor: Color {
        let normalizedTemp = (settings.colorTemperature - 1900) / (6500 - 1900)
        // Interpolate from orange (warm) to white (cool)
        return Color(
            red: 1.0,
            green: 0.6 + (normalizedTemp * 0.4),
            blue: 0.3 + (normalizedTemp * 0.7)
        )
    }
    
    /**
     Checks if a temperature preset is currently selected (within tolerance).
     */
    private func isPresetSelected(_ preset: TemperaturePreset) -> Bool {
        abs(Int(settings.colorTemperature) - preset.kelvin) < 100
    }
    
    // ================================================================
    // MARK: - Actions
    // ================================================================
    
    /**
     Checks permission status and updates banner visibility.
     */
    private func checkPermissions() {
        // TODO: Implement actual permission check
        // For now, assume granted
        showPermissionBanner = false
    }
    
    /**
     Opens System Settings to the Screen Recording privacy pane.
     */
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /**
     Requests Screen Recording permission and enables intelligent mode if granted.
     
     This is called when user toggles Intelligent Mode ON.
     If permission not granted, it will:
     1. Attempt a screen capture (forces macOS to add app to permission list)
     2. Open System Settings for manual grant
     
     NOTE: For unsigned dev builds, CGRequestScreenCaptureAccess alone doesn't
     add the app to System Settings. We need to actually attempt a capture.
     */
    private func requestScreenRecordingAndEnable() {
        // First check if already granted
        if PermissionManager.shared.screenRecordingGranted {
            settings.intelligentDimmingEnabled = true
            return
        }
        
        // Attempt an actual screen capture - this forces macOS to:
        // 1. Add the app to the Screen Recording list in System Settings
        // 2. Show a prompt (if not already denied)
        // Without this, unsigned apps won't appear in the list
        let _ = CGWindowListCreateImage(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            .optionOnScreenOnly,
            kCGNullWindowID,
            []
        )
        
        // Enable the setting - it will fall back to simple mode until permission granted
        settings.intelligentDimmingEnabled = true
        
        // Open System Settings so user can grant permission
        openScreenRecordingSettings()
    }
    
    /**
     Opens the Preferences window.
     
     FIX (Jan 8, 2026): Changed AppDelegate.shared to optional access
     to prevent crash when SwiftUI wraps the delegate.
     */
    private func openPreferences() {
        // Close the popover first (safe optional access)
        AppDelegate.shared?.menuBarController?.closePopover()
        
        // Open settings scene (defined in SuperDimmerApp)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    /**
     Quits the application.
     */
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// ====================================================================
// MARK: - Temperature Presets
// ====================================================================

/**
 Predefined color temperature presets for quick selection.
 
 Based on f.lux presets and common lighting scenarios.
 */
enum TemperaturePreset: String, CaseIterable {
    case daylight = "Daylight"
    case sunset = "Sunset"
    case night = "Night"
    case candle = "Candle"
    
    /// The Kelvin temperature for this preset
    var kelvin: Int {
        switch self {
        case .daylight: return 6500
        case .sunset: return 4100
        case .night: return 2700
        case .candle: return 1900
        }
    }
    
    /// Short name for compact display
    var shortName: String {
        switch self {
        case .daylight: return "Day"
        case .sunset: return "Sunset"
        case .night: return "Night"
        case .candle: return "Candle"
        }
    }
}

// ====================================================================
// MARK: - Preview
// ====================================================================

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView()
            .environmentObject(SettingsManager.shared)
            .frame(width: 320)
            .preferredColorScheme(.dark)
    }
}
#endif
