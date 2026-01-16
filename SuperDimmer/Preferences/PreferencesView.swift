/**
 ====================================================================
 PreferencesView.swift
 Main preferences window with tabbed navigation
 ====================================================================
 
 PURPOSE:
 This is the main Preferences window for SuperDimmer, accessed via
 the menu bar popover's "Preferences" button or ⌘, keyboard shortcut.
 
 It provides a tabbed interface for all settings:
 - General: Launch at login, keyboard shortcuts
 - Brightness: Threshold, dim levels, scan interval
 - Color: Temperature, schedule, presets
 - Wallpaper: Light/dark pairs, auto-switch (future)
 - About: App info, version, license
 
 DESIGN:
 Following macOS design conventions:
 - Tabbed interface for different setting categories
 - Native controls (sliders, toggles, pickers)
 - Consistent with other system preferences
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import SwiftUI

// ====================================================================
// MARK: - Preferences View
// ====================================================================

/**
 Main preferences window container with tab navigation.
 
 Uses SwiftUI TabView for native macOS tab appearance.
 Each tab is a separate view for its category of settings.
 */
struct PreferencesView: View {
    
    // ================================================================
    // MARK: - Environment
    // ================================================================
    
    @EnvironmentObject var settings: SettingsManager
    
    // ================================================================
    // MARK: - State
    // ================================================================
    
    /// Currently selected preference section
    @State private var selectedSection: PreferenceSection = .general
    
    // ================================================================
    // MARK: - Preference Sections
    // ================================================================
    
    /// Available preference sections for sidebar navigation
    /// NOTE (2.2.1.12): Removed "Excluded Apps" tab - now unified in Window Management
    /// NOTE (2.2.1.6): Added Developer tab - only visible in dev mode
    enum PreferenceSection: String, CaseIterable, Identifiable {
        case general = "General"
        case brightness = "Brightness"
        case windowManagement = "Window Management"
        case color = "Color"
        case developer = "Developer"
        case about = "About"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .brightness: return "sun.max"
            case .windowManagement: return "macwindow.on.rectangle"
            case .color: return "thermometer.sun"
            case .developer: return "hammer.fill"
            case .about: return "info.circle"
            }
        }
    }
    
    /// Returns sections to display based on dev mode status (2.2.1.6)
    var visibleSections: [PreferenceSection] {
        if settings.isDevMode {
            return PreferenceSection.allCases
        } else {
            return PreferenceSection.allCases.filter { $0 != .developer }
        }
    }
    
    // ================================================================
    // MARK: - Body
    // ================================================================
    
    var body: some View {
        NavigationSplitView {
            // ========================================================
            // Sidebar - Navigation List (Filtered by dev mode - 2.2.1.6)
            // ========================================================
            List(visibleSections, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // ========================================================
            // Detail - Selected Section Content
            // ========================================================
            Group {
                switch selectedSection {
                case .general:
                    GeneralPreferencesTab()
                case .brightness:
                    BrightnessPreferencesTab()
                case .windowManagement:
                    WindowManagementPreferencesTab()
                case .color:
                    ColorPreferencesTab()
                case .developer:
                    DeveloperPreferencesTab()
                case .about:
                    AboutPreferencesTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        // Make window resizable with min/max constraints
        .frame(minWidth: 550, idealWidth: 700, maxWidth: 900,
               minHeight: 400, idealHeight: 500, maxHeight: 700)
    }
}

// ====================================================================
// MARK: - General Preferences Tab
// ====================================================================

/**
 General settings: launch at login, global behaviors, reset
 
 IMPLEMENTATION (2.2.1.7): Includes Reset to Defaults with confirmation dialog
 */
struct GeneralPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject var permissionManager = PermissionManager.shared
    
    @State private var showResetConfirmation = false
    
    var body: some View {
        Form {
            // ========================================================
            // Startup Section
            // ========================================================
            Section("Startup") {
                Toggle("Launch SuperDimmer at login", isOn: $settings.launchAtLogin)
                    .help("Start SuperDimmer automatically when you log in")
            }
            
            // ========================================================
            // Permissions Section
            // ========================================================
            Section("Permissions") {
                HStack {
                    Image(systemName: permissionManager.screenRecordingGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(permissionManager.screenRecordingGranted ? .green : .orange)
                    
                    VStack(alignment: .leading) {
                        Text("Screen Recording")
                            .font(.body)
                        Text(permissionManager.screenRecordingGranted ? "Permission granted" : "Required for brightness detection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !permissionManager.screenRecordingGranted {
                        Button("Grant") {
                            permissionManager.requestScreenRecordingPermission()
                        }
                    }
                }
                
                HStack {
                    Image(systemName: permissionManager.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(permissionManager.accessibilityGranted ? .green : .orange)
                    
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .font(.body)
                        Text(permissionManager.accessibilityGranted ? "Permission granted" : "Required for instant focus detection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !permissionManager.accessibilityGranted {
                        Button("Grant") {
                            permissionManager.requestAccessibilityPermission()
                        }
                    }
                }
                
                HStack {
                    Image(systemName: permissionManager.locationGranted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(permissionManager.locationGranted ? .green : .secondary)
                    
                    VStack(alignment: .leading) {
                        Text("Location")
                            .font(.body)
                        Text("Optional - for sunrise/sunset automation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if !permissionManager.locationGranted {
                        Button("Grant") {
                            permissionManager.requestLocationPermission()
                        }
                    }
                }
            }
            
            // ========================================================
            // Reset Section (2.2.1.7)
            // ========================================================
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundColor(.red)
                            Text("Reset All Settings to Defaults")
                                .foregroundColor(.red)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text("Resets all settings to their original values. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Reset", systemImage: "exclamationmark.triangle")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. Your exclusion lists, color temperature schedules, and all preferences will be lost. This action cannot be undone.")
        }
    }
}

// ====================================================================
// MARK: - Brightness Preferences Tab
// ====================================================================

/**
 Brightness detection and dimming settings
 
 Contains all the detailed dimming controls that were moved from
 the menu bar popover as part of the UI simplification (2.2.1.13).
 */
struct BrightnessPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        Form {
            // ========================================================
            // Super Dimming Section (2.2.1.2)
            // ========================================================
            Section {
                Toggle(isOn: $settings.isDimmingEnabled) {
                    VStack(alignment: .leading) {
                        Text("Super Dimming")
                            .font(.headline)
                        Text("Apply a comfortable dimming overlay to your screen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if settings.isDimmingEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Base Dim Level")
                            Spacer()
                            Text("\(Int(settings.globalDimLevel * 100))%")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.globalDimLevel, in: 0...0.8)
                        Text("How much to dim your screen content")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            } header: {
                Label("Core Feature", systemImage: "sun.max.fill")
            }
            
            // ========================================================
            // Auto Mode Section (2.2.1.2 + 2.2.1.8 polish)
            // ========================================================
            Section {
                Toggle(isOn: $settings.superDimmingAutoEnabled) {
                    VStack(alignment: .leading) {
                        Text("Auto Mode")
                        Text("Automatically adjust dimming based on screen brightness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .help("When enabled, SuperDimmer adapts to your screen content - dimming more when displaying bright content, less when displaying dark content.")
                
                if settings.superDimmingAutoEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Adjustment Range")
                            Spacer()
                            Text("±\(Int(settings.autoAdjustRange * 100))%")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoAdjustRange, in: 0.05...0.30)
                            .help("Controls how much Auto mode can increase or decrease the base dim level. Higher = more dynamic adjustment.")
                        Text("How much the dim level can vary from the base setting. Default is ±15%.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            } header: {
                Label("Adaptive Dimming", systemImage: "sparkles")
            } footer: {
                if settings.superDimmingAutoEnabled {
                    Text("Auto mode captures screenshots periodically to measure screen brightness and adjusts dimming dynamically for optimal comfort.")
                }
            }
            
            // ========================================================
            // Detection Section (2.2.1.8 - Enhanced explanations)
            // ========================================================
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Brightness Threshold")
                        Spacer()
                        Text("\(Int(settings.brightnessThreshold * 100))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.brightnessThreshold, in: 0.5...1.0)
                        .help("Lower = more areas dimmed (more sensitive). Higher = only brightest areas dimmed.")
                    Text("Areas brighter than this threshold will trigger dimming. Default is 85%.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Detection Sensitivity", systemImage: "lightbulb")
            } footer: {
                Text("Adjust how bright an area must be before dimming is applied. Lower values dim more content, higher values are more selective.")
            }
            
            // ========================================================
            // Per-Window Dimming Section (2.2.1.3)
            // ========================================================
            Section {
                // Master toggle for per-window dimming
                Toggle(isOn: $settings.intelligentDimmingEnabled) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Dim Windows Individually")
                            Text("(Beta)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text("Analyze each window and apply individual dimming based on content brightness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .help("Requires Screen Recording permission. May have higher CPU usage.")
                
                if settings.intelligentDimmingEnabled {
                    // ========================================================
                    // Per-Region Dimming Section (2.2.1.4 - Nested)
                    // ========================================================
                    Toggle(isOn: Binding(
                        get: { settings.detectionMode == .perRegion },
                        set: { isPerRegion in
                            settings.detectionMode = isPerRegion ? .perRegion : .perWindow
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text("Dim Bright Areas")
                                .font(.subheadline)
                            Text("Finds bright areas within windows (like white email backgrounds) and dims only those regions. Uses more resources.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                    .help("Per-region detection: more precise but higher CPU usage")
                    
                    // Show current mode description
                    VStack(alignment: .leading, spacing: 4) {
                        if settings.detectionMode == .perWindow {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Mode: Full Window Dimming")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Text("Dims entire windows based on their average brightness")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "square.split.2x2")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                Text("Mode: Region-Specific Dimming")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                            Text("Detects and dims only bright areas within each window")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    
                    // Active/Inactive differentiation
                    Toggle("Different levels for active/inactive windows", isOn: $settings.differentiateActiveInactive)
                        .padding(.leading, 20)
                        .help("Apply lighter dimming to the window you're working in")
                    
                    if settings.differentiateActiveInactive {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Active Window")
                                Spacer()
                                Text("\(Int(settings.activeDimLevel * 100))%")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.activeDimLevel, in: 0...0.5)
                        }
                        .padding(.leading, 40)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Inactive Windows")
                                Spacer()
                                Text("\(Int(settings.inactiveDimLevel * 100))%")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.inactiveDimLevel, in: 0...0.8)
                        }
                        .padding(.leading, 40)
                    }
                }
            } header: {
                Label("Advanced Detection", systemImage: "wand.and.stars")
            } footer: {
                if settings.intelligentDimmingEnabled {
                    Text("Per-window dimming analyzes each window separately. Enable 'Dim Bright Areas' for more precise region detection within windows.")
                }
            }
            
            // ========================================================
            // Performance Section (2.2.1.8 - Enhanced explanations)
            // ========================================================
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Brightness Analysis Interval (Heavy)
                    HStack {
                        Text("Brightness Scan Interval")
                        Spacer()
                        Text(String(format: "%.1f sec", settings.scanInterval))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.scanInterval, in: 0.5...5.0, step: 0.5)
                        .help("Lower = more frequent updates but higher CPU usage. Higher = less responsive but more efficient. Default: 2.0 seconds.")
                    Text("How often to capture screenshots and analyze brightness. Lower values are more responsive but use more CPU. Default: 2.0s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    // Window Tracking Interval (Lightweight)
                    HStack {
                        Text("Window Tracking Interval")
                        Spacer()
                        Text(String(format: "%.1f sec", settings.windowTrackingInterval))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.windowTrackingInterval, in: 0.1...2.0, step: 0.1)
                        .help("Controls how smoothly overlays follow window movement. Lower = smoother but slightly higher CPU. Default: 0.5 seconds.")
                    Text("How often to update overlay positions when windows move. This is lightweight and can run faster. Default: 0.5s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Performance Tuning", systemImage: "gauge.medium")
            } footer: {
                Text("Adjust these intervals to balance responsiveness and CPU usage. Brightness scanning is more intensive than window tracking.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// ====================================================================
// MARK: - Window Management Preferences Tab
// ====================================================================

/**
 Window Management settings: SuperFocus, Auto-Hide, and Auto-Minimize
 
 These features help manage window clutter and improve focus:
 - SuperFocus: One toggle to enable all productivity features
 - Inactivity Decay: Dims inactive windows to emphasize active work
 - Auto-Hide: Hides entire apps after inactivity (like Cmd+H)
 - Auto-Minimize: Minimizes excess windows per app to Dock
 */
struct WindowManagementPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject var autoHideManager = AutoHideManager.shared
    @ObservedObject var autoMinimizeManager = AutoMinimizeManager.shared
    
    var body: some View {
        Form {
            // ========================================================
            // SuperFocus Section (2.2.1.5 + 2.2.1.8 polish)
            // ========================================================
            Section {
                Toggle(isOn: $settings.superFocusEnabled) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("SuperFocus")
                                .font(.headline)
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                        }
                        Text("Enable all productivity features with one toggle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .help("SuperFocus helps you concentrate by de-emphasizing unused windows and apps. Turn this on to enable all focus features at once.")
                
                if settings.superFocusEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active features:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Label("Decay Dimming", systemImage: "circle.lefthalf.filled")
                            Label("Auto-Hide", systemImage: "eye.slash")
                            Label("Auto-Minimize", systemImage: "minus.rectangle")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
                
                if !settings.superFocusEnabled {
                    Text("Or configure individual features below")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            } header: {
                Label("Quick Setup", systemImage: "sparkles")
            } footer: {
                if settings.superFocusEnabled {
                    Text("SuperFocus automatically manages your workspace by dimming, hiding, and minimizing inactive content. Configure individual features below.")
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // ========================================================
            // Inactivity Decay Dimming Section
            // ========================================================
            Section {
                Toggle(isOn: $settings.inactivityDecayEnabled) {
                    VStack(alignment: .leading) {
                        Text("Inactivity Decay Dimming")
                        Text("Progressively dim windows you haven't used recently")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(settings.superFocusEnabled)  // Controlled by SuperFocus when enabled
                
                if settings.inactivityDecayEnabled || settings.superFocusEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Start dimming after:")
                                Spacer()
                                Text("\(Int(settings.decayStartDelay)) sec")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.decayStartDelay, in: 5...120, step: 5)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Decay rate:")
                                Spacer()
                                Text("\(Int(settings.decayRate * 100))% per sec")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.decayRate, in: 0.005...0.05, step: 0.005)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Maximum dim level:")
                                Spacer()
                                Text("\(Int(settings.maxDecayDimLevel * 100))%")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.maxDecayDimLevel, in: 0.3...1.0)
                        }
                    }
                    .padding(.leading, 20)
                }
            } header: {
                Label("Decay Dimming", systemImage: "circle.lefthalf.filled")
            }
            
            // ========================================================
            // Auto-Hide Inactive Apps Section
            // ========================================================
            Section {
                Toggle(isOn: $settings.autoHideEnabled) {
                    VStack(alignment: .leading) {
                        Text("Auto-Hide Inactive Apps")
                        Text("Hide apps that haven't been used for a while")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(settings.superFocusEnabled)  // Controlled by SuperFocus when enabled
                
                if settings.autoHideEnabled || settings.superFocusEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hide apps after:")
                            Spacer()
                            Text("\(Int(settings.autoHideDelay)) min")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoHideDelay, in: 5...120, step: 5)
                    }
                    .padding(.leading, 20)
                    
                    Toggle("Exclude system apps", isOn: $settings.autoHideExcludeSystemApps)
                        .padding(.leading, 20)
                        .help("Never auto-hide Finder, System Preferences, etc.")
                    
                    // Recently hidden apps
                    if !autoHideManager.recentlyHiddenApps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recently hidden:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(autoHideManager.recentlyHiddenApps.prefix(5), id: \.bundleID) { app in
                                HStack {
                                    Text(app.name)
                                        .font(.caption)
                                    Spacer()
                                    Button("Unhide") {
                                        autoHideManager.unhideApp(bundleID: app.bundleID)
                                    }
                                    .font(.caption)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 8)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "eye.slash")
                    Text("Auto-Hide Inactive Apps")
                }
            } footer: {
                Text("Apps will be hidden (like pressing ⌘H) after being inactive. They remain in the Dock and can be unhidden anytime.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // ========================================================
            // Auto-Minimize Inactive Windows Section
            // ========================================================
            Section {
                Toggle(isOn: $settings.autoMinimizeEnabled) {
                    VStack(alignment: .leading) {
                        Text("Auto-Minimize Inactive Windows")
                        Text("Minimize oldest windows when an app has too many")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(settings.superFocusEnabled)  // Controlled by SuperFocus when enabled
                
                if settings.autoMinimizeEnabled || settings.superFocusEnabled {
                    // Minimize delay (active time only)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimize after:")
                            Spacer()
                            Text("\(Int(settings.autoMinimizeDelay)) min of active use")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoMinimizeDelay, in: 5...60, step: 5)
                    }
                    .padding(.leading, 20)
                    
                    // Window threshold
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Keep at least:")
                            Spacer()
                            Text("\(settings.autoMinimizeWindowThreshold) window\(settings.autoMinimizeWindowThreshold == 1 ? "" : "s") per app")
                                .foregroundColor(.secondary)
                        }
                        Stepper("", value: $settings.autoMinimizeWindowThreshold, in: 1...10)
                            .labelsHidden()
                    }
                    .padding(.leading, 20)
                    
                    // Idle reset time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reset timers after idle:")
                            Spacer()
                            Text("\(Int(settings.autoMinimizeIdleResetTime)) min")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoMinimizeIdleResetTime, in: 2...30, step: 1)
                    }
                    .padding(.leading, 20)
                    
                    // Status
                    HStack {
                        Text("Tracking:")
                        Text("\(autoMinimizeManager.trackedWindowCount) windows")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.leading, 20)
                }
            } header: {
                HStack {
                    Image(systemName: "arrow.down.to.line")
                    Text("Auto-Minimize Inactive Windows")
                }
            } footer: {
                Text("Only counts active usage time (not idle). Timers reset when you return from breaks. Windows minimize to Dock when an app has more than the threshold.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // ========================================================
            // Per-Feature App Exclusions (2.2.1.12)
            // ========================================================
            Section {
                Button {
                    showAppExclusions = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage App Exclusions")
                            Text("Choose which features each app is excluded from")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(settings.appExclusions.count) apps")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Label("App Exclusions", systemImage: "app.badge.checkmark")
            } footer: {
                Text("Excluded apps can be exempted from dimming, decay dimming, auto-hide, and/or auto-minimize individually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showAppExclusions) {
            AppExclusionsView(isPresented: $showAppExclusions)
                .environmentObject(settings)
        }
    }
    
    // State for sheets
    @State private var showAppExclusions = false
}

// ====================================================================
// MARK: - Legacy Exclusion Lists (REMOVED)
// ====================================================================
// These have been replaced by the unified AppExclusionsView (2.2.1.12)
// which provides per-feature checkboxes for each app.

// ====================================================================
// MARK: - Color Preferences Tab
// ====================================================================

/**
 Color temperature and blue light filter settings
 */
struct ColorPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        Form {
            // ========================================================
            // Color Temperature Section
            // ========================================================
            Section("Color Temperature") {
                Toggle("Enable color temperature adjustment", isOn: $settings.colorTemperatureEnabled)
                    .help("Reduce blue light by warming the display colors")
                
                if settings.colorTemperatureEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text("\(Int(settings.colorTemperature))K")
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.white)
                            Slider(value: $settings.colorTemperature, in: 1900...6500)
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                        }
                        
                        Text("Lower values = warmer colors, less blue light")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    
                    // Presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Presets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            PresetButton(name: "Day", kelvin: 6500)
                            PresetButton(name: "Sunset", kelvin: 4100)
                            PresetButton(name: "Night", kelvin: 2700)
                            PresetButton(name: "Candle", kelvin: 1900)
                        }
                    }
                }
            }
            
            // ========================================================
            // Schedule Section
            // ========================================================
            Section("Schedule") {
                Toggle("Automatic scheduling", isOn: $settings.colorTemperatureScheduleEnabled)
                    .help("Automatically adjust color temperature based on time of day")
                
                if settings.colorTemperatureScheduleEnabled {
                    // Day/Night Temperatures
                    VStack(alignment: .leading, spacing: 12) {
                        // Day temperature
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "sun.max.fill")
                                    .foregroundColor(.yellow)
                                Text("Day Temperature")
                                Spacer()
                                Text("\(Int(settings.dayTemperature))K")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.dayTemperature, in: 4000...6500)
                        }
                        
                        // Night temperature
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "moon.fill")
                                    .foregroundColor(.orange)
                                Text("Night Temperature")
                                Spacer()
                                Text("\(Int(settings.nightTemperature))K")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.nightTemperature, in: 1900...4000)
                        }
                    }
                    .padding(.top, 4)
                    
                    Divider()
                    
                    // Schedule Type
                    Toggle("Use sunrise/sunset times", isOn: $settings.useLocationBasedSchedule)
                        .help("Automatically adjust based on your location")
                    
                    if !settings.useLocationBasedSchedule {
                        // Manual Schedule Times
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Manual Schedule")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 16) {
                                // Night starts (sunset equivalent)
                                VStack(alignment: .leading) {
                                    Text("Night starts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 2) {
                                        Picker("Hour", selection: $settings.scheduleStartHour) {
                                            ForEach(0..<24, id: \.self) { hour in
                                                Text(String(format: "%02d", hour)).tag(hour)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 60)
                                        
                                        Text(":")
                                        
                                        Picker("Minute", selection: $settings.scheduleStartMinute) {
                                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                                Text(String(format: "%02d", minute)).tag(minute)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 60)
                                    }
                                }
                                
                                Spacer()
                                
                                // Night ends (sunrise equivalent)
                                VStack(alignment: .leading) {
                                    Text("Day starts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 2) {
                                        Picker("Hour", selection: $settings.scheduleEndHour) {
                                            ForEach(0..<24, id: \.self) { hour in
                                                Text(String(format: "%02d", hour)).tag(hour)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 60)
                                        
                                        Text(":")
                                        
                                        Picker("Minute", selection: $settings.scheduleEndMinute) {
                                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                                Text(String(format: "%02d", minute)).tag(minute)
                                            }
                                        }
                                        .labelsHidden()
                                        .frame(width: 60)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        // Location-based info
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Schedule will follow local sunrise/sunset")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Divider()
                    
                    // Transition Duration
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Transition Duration")
                            Spacer()
                            Text(formatTransitionDuration(settings.transitionDuration))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.transitionDuration, in: 0...3600, step: 60)
                        Text("0 = instant change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    /**
     Formats transition duration in human-readable form.
     */
    private func formatTransitionDuration(_ seconds: TimeInterval) -> String {
        if seconds == 0 {
            return "Instant"
        } else if seconds < 60 {
            return "\(Int(seconds)) sec"
        } else {
            return "\(Int(seconds / 60)) min"
        }
    }
}

/**
 A button for quickly selecting a temperature preset
 */
struct PresetButton: View {
    let name: String
    let kelvin: Int
    
    @EnvironmentObject var settings: SettingsManager
    
    private var isSelected: Bool {
        abs(Int(settings.colorTemperature) - kelvin) < 100
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                settings.colorTemperature = Double(kelvin)
            }
        }) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// ====================================================================
// MARK: - Excluded Apps Preferences Tab (REMOVED)
// ====================================================================
// NOTE (2.2.1.12): This tab was removed in favor of the unified
// AppExclusionsView which is accessible from Window Management tab.
// The new unified exclusion system uses per-feature checkboxes instead
// of separate exclusion lists.

// ====================================================================
// MARK: - Developer Preferences Tab (2.2.1.6)
// ====================================================================

/**
 Developer tools and debug options.
 
 VISIBILITY (2.2.1.6):
 Only visible when:
 - Running a DEBUG build, OR
 - User has unlocked dev tools via hidden gesture
 
 This keeps the main UI clean for end users while providing
 developers with useful debugging tools.
 */
struct DeveloperPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @State private var overlayCount: String = "Loading..."
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ========================================================
                // Header
                // ========================================================
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        
                        Text("Developer Tools")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text("Debug features and diagnostic tools for development")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // ========================================================
                // Debug Borders
                // ========================================================
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { settings.debugOverlayBorders },
                            set: { newValue in
                                settings.debugOverlayBorders = newValue
                                // Update existing overlays immediately
                                AppDelegate.shared?.dimmingCoordinator?.updateDebugBorders()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Debug Borders")
                                    .font(.headline)
                                Text("Shows red borders on all dimming overlays for position debugging")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Visual Debugging", systemImage: "eye.fill")
                }
                
                // ========================================================
                // System Information
                // ========================================================
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: "Active Overlays", value: overlayCount)
                        InfoRow(label: "Scan Interval", value: String(format: "%.1fs", settings.scanInterval))
                        InfoRow(label: "Tracking Interval", value: String(format: "%.1fs", settings.windowTrackingInterval))
                        InfoRow(label: "Build Configuration", value: settings.isDevMode ? "DEBUG" : "RELEASE")
                        
                        Button("Refresh Stats") {
                            updateOverlayCount()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                } label: {
                    Label("System Information", systemImage: "info.circle.fill")
                }
                .onAppear {
                    updateOverlayCount()
                }
                
                // ========================================================
                // Force Actions
                // ========================================================
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Force Analysis Cycle") {
                            print("🔄 Forcing analysis cycle...")
                            // Trigger immediate analysis
                            NotificationCenter.default.post(name: NSNotification.Name("ForceAnalysisCycle"), object: nil)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear Analysis Cache") {
                            print("🗑️ Clearing analysis cache...")
                            // Clear cache
                            NotificationCenter.default.post(name: NSNotification.Name("ClearAnalysisCache"), object: nil)
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Force actions trigger immediate operations without waiting for timers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                } label: {
                    Label("Force Actions", systemImage: "bolt.fill")
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func updateOverlayCount() {
        let count = OverlayManager.shared.totalOverlayCount
        overlayCount = "\(count)"
    }
}

/**
 Helper view for displaying labeled information rows
 */
private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

// ====================================================================
// MARK: - About Preferences Tab
// ====================================================================

/**
 About section with app info, version, and links (2.2.1.8 - Enhanced)
 */
struct AboutPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @State private var devToolsClickCount = 0
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon and Name
            VStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                
                Text("SuperDimmer")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Version (with hidden dev tools unlock gesture)
                Button(action: {
                    devToolsClickCount += 1
                    if devToolsClickCount >= 5 {
                        settings.toggleDevTools()
                        devToolsClickCount = 0
                    }
                }) {
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(settings.isDevMode ? "Developer tools are unlocked" : "")
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Description
            Text("Intelligent screen dimming for macOS")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Text("Reduce eye strain and improve focus with adaptive brightness control")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            // Links (2.2.1.8 - Learn More added)
            VStack(spacing: 10) {
                Link(destination: URL(string: "https://superdimmer.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("Visit Website")
                    }
                    .font(.body)
                }
                
                Link(destination: URL(string: "https://superdimmer.com/docs")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                        Text("Documentation & Guides")
                    }
                    .font(.body)
                }
                .help("Learn more about SuperDimmer's features and how to use them effectively")
                
                Link(destination: URL(string: "mailto:support@superdimmer.com")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                        Text("Contact Support")
                    }
                    .font(.body)
                }
                
                Link(destination: URL(string: "https://github.com/superdimmer/superdimmer/issues")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Report an Issue")
                    }
                    .font(.body)
                }
            }
            .padding(.vertical, 10)
            
            Spacer()
            
            // Copyright and Dev Mode Indicator
            VStack(spacing: 4) {
                Text("© 2026 SuperDimmer. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settings.isDevMode {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer.fill")
                            .font(.caption2)
                        Text("Developer Mode Active")
                    }
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// ====================================================================
// MARK: - Preview
// ====================================================================

#if DEBUG
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .environmentObject(SettingsManager.shared)
            .frame(width: 500, height: 400)
    }
}
#endif
