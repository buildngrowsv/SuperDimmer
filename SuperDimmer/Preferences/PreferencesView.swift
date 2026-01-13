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
    enum PreferenceSection: String, CaseIterable, Identifiable {
        case general = "General"
        case brightness = "Brightness"
        case windowManagement = "Window Management"
        case color = "Color"
        case excludedApps = "Excluded Apps"
        case about = "About"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .brightness: return "sun.max"
            case .windowManagement: return "macwindow.on.rectangle"
            case .color: return "thermometer.sun"
            case .excludedApps: return "minus.circle"
            case .about: return "info.circle"
            }
        }
    }
    
    // ================================================================
    // MARK: - Body
    // ================================================================
    
    var body: some View {
        NavigationSplitView {
            // ========================================================
            // Sidebar - Navigation List
            // ========================================================
            List(PreferenceSection.allCases, selection: $selectedSection) { section in
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
                case .excludedApps:
                    ExcludedAppsPreferencesTab()
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
 General settings: launch at login, global behaviors
 */
struct GeneralPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject var permissionManager = PermissionManager.shared
    
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
            // Reset Section
            // ========================================================
            Section("Reset") {
                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
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
            // Auto Mode Section (2.2.1.2)
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
                        Text("How much the dim level can swing based on content brightness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                }
            } header: {
                Label("Adaptive Dimming", systemImage: "sparkles")
            }
            
            // ========================================================
            // Detection Section
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
                    Text("Areas brighter than this percentage will trigger dimming")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Detection Sensitivity", systemImage: "lightbulb")
            }
            
            // ========================================================
            // Intelligent Mode Section
            // ========================================================
            Section {
                Toggle(isOn: $settings.intelligentDimmingEnabled) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Intelligent Mode")
                            Text("(Beta)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text("Analyze and dim individual windows/areas instead of full screen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .help("Requires Screen Recording permission")
                
                if settings.intelligentDimmingEnabled {
                    // Detection mode picker
                    Picker("Detection Mode", selection: $settings.detectionMode) {
                        Text("Per Window").tag(DetectionMode.perWindow)
                        Text("Per Region").tag(DetectionMode.perRegion)
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 20)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if settings.detectionMode == .perWindow {
                            Text("Dims entire windows based on their average brightness")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Finds and dims bright areas within windows (e.g., white email content)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                    
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
            }
            
            // ========================================================
            // Performance Section
            // ========================================================
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scan Interval")
                        Spacer()
                        Text(String(format: "%.1f seconds", settings.scanInterval))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.scanInterval, in: 0.5...5.0, step: 0.5)
                    Text("How often to analyze screen content. Lower = more responsive but higher CPU usage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Performance", systemImage: "gauge.medium")
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
            // SuperFocus Section (2.2.1.5)
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
            // Excluded Apps Section (for both features)
            // ========================================================
            Section("Exclusions") {
                Button {
                    showAutoHideExclusions = true
                } label: {
                    HStack {
                        Text("Auto-Hide Exclusions")
                        Spacer()
                        Text("\(settings.autoHideExcludedApps.count)")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    showAutoMinimizeExclusions = true
                } label: {
                    HStack {
                        Text("Auto-Minimize Exclusions")
                        Spacer()
                        Text("\(settings.autoMinimizeExcludedApps.count)")
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(isPresented: $showAutoHideExclusions) {
            AutoHideExclusionsList(isPresented: $showAutoHideExclusions)
        }
        .sheet(isPresented: $showAutoMinimizeExclusions) {
            AutoMinimizeExclusionsList(isPresented: $showAutoMinimizeExclusions)
        }
    }
    
    // State for sheets
    @State private var showAutoHideExclusions = false
    @State private var showAutoMinimizeExclusions = false
}

// ====================================================================
// MARK: - Auto-Hide Exclusions List
// ====================================================================

struct AutoHideExclusionsList: View {
    @EnvironmentObject var settings: SettingsManager
    @Binding var isPresented: Bool
    @State private var newBundleID: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack {
                Text("Apps excluded from Auto-Hide")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            
            Text("These apps will never be automatically hidden, regardless of inactivity.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach(settings.autoHideExcludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button(role: .destructive) {
                            settings.autoHideExcludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 150)
            
            HStack {
                TextField("Bundle ID (e.g., com.apple.mail)", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addBundleID()
                    }
                
                Button("Add") {
                    addBundleID()
                }
                .disabled(newBundleID.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
    
    private func addBundleID() {
        if !newBundleID.isEmpty && !settings.autoHideExcludedApps.contains(newBundleID) {
            settings.autoHideExcludedApps.append(newBundleID)
            newBundleID = ""
        }
    }
}

// ====================================================================
// MARK: - Auto-Minimize Exclusions List
// ====================================================================

struct AutoMinimizeExclusionsList: View {
    @EnvironmentObject var settings: SettingsManager
    @Binding var isPresented: Bool
    @State private var newBundleID: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack {
                Text("Apps excluded from Auto-Minimize")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            
            Text("These apps will never have their windows automatically minimized.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach(settings.autoMinimizeExcludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button(role: .destructive) {
                            settings.autoMinimizeExcludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 150)
            
            HStack {
                TextField("Bundle ID (e.g., com.apple.Safari)", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addBundleID()
                    }
                
                Button("Add") {
                    addBundleID()
                }
                .disabled(newBundleID.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
    
    private func addBundleID() {
        if !newBundleID.isEmpty && !settings.autoMinimizeExcludedApps.contains(newBundleID) {
            settings.autoMinimizeExcludedApps.append(newBundleID)
            newBundleID = ""
        }
    }
}

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
// MARK: - Excluded Apps Preferences Tab
// ====================================================================

/**
 Manage apps that should never be dimmed.
 
 Users can add apps by:
 1. Selecting from currently running apps
 2. Manually entering a bundle ID
 3. Browsing for an .app file
 
 This is useful for:
 - Design apps that need accurate colors
 - Video players
 - Apps with their own dark mode
 */
struct ExcludedAppsPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    @State private var newBundleID: String = ""
    @State private var showingAppPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // ========================================================
            // Header
            // ========================================================
            HStack {
                VStack(alignment: .leading) {
                    Text("Excluded Applications")
                        .font(.headline)
                    Text("These apps will never have their windows dimmed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            
            Divider()
            
            // ========================================================
            // List of Excluded Apps
            // ========================================================
            if settings.excludedAppBundleIDs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No apps excluded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add apps that should never be dimmed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            // Try to get app icon and name
                            if let appInfo = getAppInfo(for: bundleID) {
                                if let icon = appInfo.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                
                                VStack(alignment: .leading) {
                                    Text(appInfo.name)
                                        .font(.body)
                                    Text(bundleID)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Image(systemName: "app")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                                
                                Text(bundleID)
                                    .font(.body)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                removeExcludedApp(bundleID)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            Divider()
            
            // ========================================================
            // Add New App Section
            // ========================================================
            VStack(spacing: 12) {
                Text("Add Application")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 8) {
                    // Quick add from running apps
                    Menu {
                        ForEach(getRunningApps(), id: \.bundleIdentifier) { app in
                            Button(action: {
                                if let bundleID = app.bundleIdentifier {
                                    addExcludedApp(bundleID)
                                }
                            }) {
                                HStack {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                    }
                                    Text(app.localizedName ?? "Unknown")
                                }
                            }
                            .disabled(settings.excludedAppBundleIDs.contains(app.bundleIdentifier ?? ""))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "app.badge.fill")
                            Text("Running Apps")
                        }
                    }
                    .frame(width: 150)
                    
                    // Manual bundle ID entry
                    TextField("Bundle ID (e.g., com.apple.Safari)", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        if !newBundleID.isEmpty {
                            addExcludedApp(newBundleID)
                            newBundleID = ""
                        }
                    }
                    .disabled(newBundleID.isEmpty)
                }
            }
            .padding()
        }
    }
    
    // ================================================================
    // MARK: - Helper Methods
    // ================================================================
    
    /**
     Gets currently running user applications (excluding system processes).
     */
    private func getRunningApps() -> [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    /**
     Gets app name and icon for a bundle ID.
     */
    private func getAppInfo(for bundleID: String) -> (name: String, icon: NSImage?)? {
        // Try to find app in running apps first
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return (runningApp.localizedName ?? bundleID, runningApp.icon)
        }
        
        // Try to find app bundle in Applications
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let appName = FileManager.default.displayName(atPath: appURL.path)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return (appName, icon)
        }
        
        return nil
    }
    
    /**
     Adds an app to the exclusion list.
     */
    private func addExcludedApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !settings.excludedAppBundleIDs.contains(bundleID) else { return }
        settings.excludedAppBundleIDs.append(bundleID)
    }
    
    /**
     Removes an app from the exclusion list.
     */
    private func removeExcludedApp(_ bundleID: String) {
        settings.excludedAppBundleIDs.removeAll { $0 == bundleID }
    }
}

// ====================================================================
// MARK: - About Preferences Tab
// ====================================================================

/**
 About section with app info, version, and links
 */
struct AboutPreferencesTab: View {
    
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
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                
                Text("SuperDimmer")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            // Description
            Text("Intelligent region-specific screen dimming for macOS")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            // Links
            VStack(spacing: 8) {
                Link("Visit Website", destination: URL(string: "https://superdimmer.com")!)
                    .font(.body)
                
                Link("Report an Issue", destination: URL(string: "mailto:support@superdimmer.com")!)
                    .font(.body)
            }
            
            Spacer()
            
            // Copyright
            Text("© 2026 SuperDimmer. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
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
