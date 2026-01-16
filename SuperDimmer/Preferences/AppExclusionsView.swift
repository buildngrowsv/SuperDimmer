/**
 ====================================================================
 AppExclusionsView.swift
 Unified per-feature app exclusions management UI
 ====================================================================
 
 PURPOSE:
 This view provides a unified interface for managing app exclusions
 across all SuperDimmer features. Instead of separate exclusion lists,
 users see one table with checkboxes per feature.
 
 FEATURES THAT CAN BE EXCLUDED:
 - Dimming: Brightness overlay dimming (intelligent mode)
 - Decay: Inactivity-based progressive dimming
 - Auto-Hide: Automatically hide inactive apps
 - Auto-Minimize: Automatically minimize inactive windows
 
 UI LAYOUT:
 ┌──────────────────────────────────────────────────────────────┐
 │ App Name       │ Dimming │ Decay │ Auto-Hide │ Auto-Min │   │
 ├──────────────────────────────────────────────────────────────┤
 │ Safari         │   ☑     │  ☐    │    ☐      │    ☑     │ 🗑 │
 │ Finder         │   ☐     │  ☑    │    ☑      │    ☑     │ 🗑 │
 └──────────────────────────────────────────────────────────────┘
 │ [+ Add App]                                                  │
 └──────────────────────────────────────────────────────────────┘
 
 ====================================================================
 Created: January 16, 2026
 Version: 1.0.0
 ====================================================================
 */

import SwiftUI
import AppKit

// ====================================================================
// MARK: - App Exclusions View
// ====================================================================

/**
 Main view for managing per-feature app exclusions.
 
 Displays a table of excluded apps with checkboxes for each feature,
 and provides controls to add/remove apps.
 */
struct AppExclusionsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Binding var isPresented: Bool
    
    @State private var showAddAppSheet = false
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            if settings.appExclusions.isEmpty {
                emptyState
            } else {
                exclusionTable
            }
            
            Divider()
            
            // Footer with Add button
            footer
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showAddAppSheet) {
            AddAppSheet(isPresented: $showAddAppSheet)
                .environmentObject(settings)
        }
    }
    
    // ================================================================
    // MARK: - Header
    // ================================================================
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("App Exclusions")
                    .font(.headline)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            
            Text("Choose which features each app is excluded from. Checked = excluded from that feature.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // ================================================================
    // MARK: - Empty State
    // ================================================================
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Excluded Apps")
                .font(.headline)
            
            Text("Add apps to exclude them from specific SuperDimmer features.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Add App") {
                showAddAppSheet = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // ================================================================
    // MARK: - Exclusion Table
    // ================================================================
    
    private var exclusionTable: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("App")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(width: 180, alignment: .leading)
                
                Spacer()
                
                columnHeader("Dimming", tooltip: "Exclude from brightness overlay dimming")
                columnHeader("Decay", tooltip: "Exclude from inactivity fade dimming")
                columnHeader("Auto-Hide", tooltip: "Exclude from automatic app hiding")
                columnHeader("Auto-Min", tooltip: "Exclude from automatic window minimizing")
                
                // Delete column spacer
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            
            // App rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(settings.appExclusions) { exclusion in
                        ExclusionRow(exclusion: exclusion)
                            .environmentObject(settings)
                        
                        Divider()
                    }
                }
            }
        }
    }
    
    private func columnHeader(_ title: String, tooltip: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .frame(width: 70)
            .help(tooltip)
    }
    
    // ================================================================
    // MARK: - Footer
    // ================================================================
    
    private var footer: some View {
        HStack {
            Button(action: { showAddAppSheet = true }) {
                Label("Add App", systemImage: "plus")
            }
            
            Spacer()
            
            Text("\(settings.appExclusions.count) app\(settings.appExclusions.count == 1 ? "" : "s") excluded")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// ====================================================================
// MARK: - Exclusion Row
// ====================================================================

/**
 A single row in the exclusions table showing an app and its feature checkboxes.
 */
struct ExclusionRow: View {
    let exclusion: AppExclusion
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        HStack(spacing: 0) {
            // App info
            HStack(spacing: 8) {
                appIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exclusion.appName)
                        .font(.body)
                        .lineLimit(1)
                    
                    Text(exclusion.bundleID)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 180, alignment: .leading)
            
            Spacer()
            
            // Feature checkboxes
            checkbox(for: .dimming)
            checkbox(for: .decayDimming)
            checkbox(for: .autoHide)
            checkbox(for: .autoMinimize)
            
            // Delete button
            Button(action: deleteExclusion) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
    
    private var appIcon: some View {
        Group {
            if let icon = getAppIcon(for: exclusion.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
    }
    
    private func checkbox(for feature: ExclusionFeature) -> some View {
        let isChecked = isExcluded(from: feature)
        
        return Button(action: { toggleFeature(feature) }) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundColor(isChecked ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 70)
    }
    
    private func isExcluded(from feature: ExclusionFeature) -> Bool {
        switch feature {
        case .dimming:
            return exclusion.excludeFromDimming
        case .decayDimming:
            return exclusion.excludeFromDecayDimming
        case .autoHide:
            return exclusion.excludeFromAutoHide
        case .autoMinimize:
            return exclusion.excludeFromAutoMinimize
        }
    }
    
    private func toggleFeature(_ feature: ExclusionFeature) {
        settings.toggleExclusion(feature: feature, for: exclusion.bundleID, appName: exclusion.appName)
    }
    
    private func deleteExclusion() {
        settings.removeExclusion(for: exclusion.bundleID)
    }
    
    private func getAppIcon(for bundleID: String) -> NSImage? {
        guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}

// ====================================================================
// MARK: - Add App Sheet
// ====================================================================

/**
 Sheet for adding a new app to the exclusions list.
 Shows running apps for easy selection, plus manual entry option.
 */
struct AddAppSheet: View {
    @EnvironmentObject var settings: SettingsManager
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var manualBundleID = ""
    @State private var showManualEntry = false
    
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != nil }
            .filter { app in
                // Filter by search text
                if searchText.isEmpty { return true }
                let name = app.localizedName ?? ""
                let bundleID = app.bundleIdentifier ?? ""
                return name.localizedCaseInsensitiveContains(searchText) ||
                       bundleID.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App to Exclusions")
                    .font(.headline)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search running apps...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            Divider()
            
            // Running apps list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        AppSelectionRow(app: app, isAlreadyExcluded: isAlreadyExcluded(app)) {
                            addApp(app)
                        }
                        
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Manual entry section
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { showManualEntry.toggle() }) {
                    HStack {
                        Image(systemName: showManualEntry ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        
                        Text("Enter Bundle ID Manually")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                
                if showManualEntry {
                    HStack {
                        TextField("com.example.AppName", text: $manualBundleID)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            addManualApp()
                        }
                        .disabled(manualBundleID.isEmpty || isAlreadyExcludedByID(manualBundleID))
                    }
                }
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
    
    private func isAlreadyExcluded(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return settings.appExclusions.contains { $0.bundleID == bundleID }
    }
    
    private func isAlreadyExcludedByID(_ bundleID: String) -> Bool {
        return settings.appExclusions.contains { $0.bundleID == bundleID }
    }
    
    private func addApp(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        
        let exclusion = AppExclusion(
            bundleID: bundleID,
            appName: app.localizedName
        )
        settings.setExclusion(exclusion)
        isPresented = false
    }
    
    private func addManualApp() {
        guard !manualBundleID.isEmpty else { return }
        
        let exclusion = AppExclusion(bundleID: manualBundleID)
        settings.setExclusion(exclusion)
        isPresented = false
    }
}

/**
 Row showing a running app that can be added to exclusions.
 */
struct AppSelectionRow: View {
    let app: NSRunningApplication
    let isAlreadyExcluded: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app")
                        .font(.title)
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                
                // App info
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.localizedName ?? "Unknown")
                        .font(.body)
                    
                    Text(app.bundleIdentifier ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Status
                if isAlreadyExcluded {
                    Text("Already added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyExcluded)
        .opacity(isAlreadyExcluded ? 0.5 : 1.0)
    }
}

// ====================================================================
// MARK: - Preview
// ====================================================================

#if DEBUG
struct AppExclusionsView_Previews: PreviewProvider {
    static var previews: some View {
        AppExclusionsView(isPresented: .constant(true))
            .environmentObject(SettingsManager.shared)
    }
}
#endif
