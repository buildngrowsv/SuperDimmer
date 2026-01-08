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
    
    @State private var selectedTab = 0
    
    // ================================================================
    // MARK: - Body
    // ================================================================
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // ========================================================
            // General Tab
            // ========================================================
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            // ========================================================
            // Brightness Tab
            // ========================================================
            BrightnessPreferencesTab()
                .tabItem {
                    Label("Brightness", systemImage: "sun.max")
                }
                .tag(1)
            
            // ========================================================
            // Color Tab
            // ========================================================
            ColorPreferencesTab()
                .tabItem {
                    Label("Color", systemImage: "thermometer.sun")
                }
                .tag(2)
            
            // ========================================================
            // Excluded Apps Tab
            // ========================================================
            ExcludedAppsPreferencesTab()
                .tabItem {
                    Label("Excluded Apps", systemImage: "minus.circle")
                }
                .tag(3)
            
            // ========================================================
            // About Tab
            // ========================================================
            AboutPreferencesTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(4)
        }
        .frame(width: 500, height: 400)
        .padding()
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
 */
struct BrightnessPreferencesTab: View {
    
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        Form {
            // ========================================================
            // Detection Section
            // ========================================================
            Section("Brightness Detection") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        Text("\(Int(settings.brightnessThreshold * 100))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.brightnessThreshold, in: 0.5...1.0)
                    Text("Areas brighter than this will be dimmed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // ========================================================
            // Dimming Levels Section
            // ========================================================
            Section("Dimming Levels") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Global Dim Amount")
                        Spacer()
                        Text("\(Int(settings.globalDimLevel * 100))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.globalDimLevel, in: 0...0.8)
                }
                
                Divider()
                
                Toggle("Different levels for active/inactive windows", isOn: $settings.differentiateActiveInactive)
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
                    .padding(.leading)
                    
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
                    .padding(.leading)
                }
            }
            
            // ========================================================
            // Performance Section
            // ========================================================
            Section("Performance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Scan Interval")
                        Spacer()
                        Text(String(format: "%.1f seconds", settings.scanInterval))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $settings.scanInterval, in: 0.5...5.0, step: 0.5)
                    Text("Lower = more responsive but uses more CPU")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
            // Schedule Section (placeholder for Phase 3)
            // ========================================================
            Section("Schedule") {
                Toggle("Automatic scheduling", isOn: $settings.colorTemperatureScheduleEnabled)
                    .help("Automatically adjust color temperature based on time")
                
                if settings.colorTemperatureScheduleEnabled {
                    Text("Schedule settings coming in a future update")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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
                Link("Visit Website", destination: URL(string: "https://superdimmer.app")!)
                    .font(.body)
                
                Link("Report an Issue", destination: URL(string: "mailto:support@superdimmer.app")!)
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
