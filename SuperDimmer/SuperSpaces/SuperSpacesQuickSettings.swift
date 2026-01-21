//
//  SuperSpacesQuickSettings.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Quick settings popover for Super Spaces HUD.
//  Provides fast access to common settings without opening full Preferences.
//
//  FEATURE: 5.5.4 - Settings Button Functionality
//
//  WHY QUICK SETTINGS:
//  - Users want to adjust HUD behavior without leaving their workflow
//  - Opening full Preferences is disruptive and slow
//  - Quick settings provide instant access to most-used controls
//  - Similar UX to Control Center, Spotlight settings, etc.
//
//  SETTINGS INCLUDED:
//  - Display mode (Mini/Compact/Expanded)
//  - Auto-hide toggle
//  - Position presets (4 corners)
//  - Link to full Preferences for advanced settings
//
//  UI DESIGN:
//  - Clean, minimal popover
//  - Segmented control for display mode
//  - Toggle for auto-hide
//  - 2x2 grid for position presets
//  - Button to open full Preferences
//

import SwiftUI

/// Quick settings popover for Super Spaces HUD
/// Provides fast access to common HUD settings without opening full Preferences
struct SuperSpacesQuickSettings: View {
    
    // MARK: - Properties
    
    /// View model for HUD state
    @ObservedObject var viewModel: SuperSpacesViewModel
    
    /// Settings manager for persisting changes
    @EnvironmentObject var settings: SettingsManager
    
    /// Callback to reposition HUD when position preset changes
    var onPositionChange: ((String) -> Void)?
    
    /// Display mode options
    enum DisplayMode: String, CaseIterable {
        case mini = "Mini"
        case compact = "Compact"
        case expanded = "Expanded"
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Super Spaces Settings")
                .font(.system(size: 13, weight: .semibold))
            
            Divider()
            
            // Display Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Mode")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $settings.superSpacesDisplayMode) {
                    Text("Compact").tag("compact")
                    Text("Note").tag("note")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            // Auto-Hide Toggle
            Toggle("Auto-hide after switch", isOn: $settings.superSpacesAutoHide)
                .font(.system(size: 12))
            
            Divider()
            
            // Position Presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Position")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // 2x2 grid of position buttons
                HStack(spacing: 8) {
                    // Top row
                    VStack(spacing: 8) {
                        positionButton("Top Left", position: "topLeft", icon: "arrow.up.left")
                        positionButton("Bottom Left", position: "bottomLeft", icon: "arrow.down.left")
                    }
                    
                    VStack(spacing: 8) {
                        positionButton("Top Right", position: "topRight", icon: "arrow.up.right")
                        positionButton("Bottom Right", position: "bottomRight", icon: "arrow.down.right")
                    }
                }
            }
            
            Divider()
            
            // Link to full Preferences
            Button(action: openPreferences) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Edit Space Names & Emojis...")
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(16)
        .frame(width: 260)
    }
    
    // MARK: - Helper Views
    
    /// Creates a position preset button
    private func positionButton(_ label: String, position: String, icon: String) -> some View {
        Button(action: {
            settings.superSpacesPosition = position
            onPositionChange?(position)
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label.replacingOccurrences(of: " ", with: "\n"))
                    .font(.system(size: 9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 70, height: 60)
            .background(
                settings.superSpacesPosition == position ?
                    Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        settings.superSpacesPosition == position ?
                            Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Move HUD to \(label.lowercased())")
    }
    
    // MARK: - Actions
    
    /// Opens full Preferences window
    private func openPreferences() {
        // TODO: Implement opening Preferences to Super Spaces tab
        // For now, just open Preferences
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

// MARK: - Preview

#if DEBUG
struct SuperSpacesQuickSettings_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SuperSpacesViewModel()
        SuperSpacesQuickSettings(viewModel: viewModel)
            .environmentObject(SettingsManager.shared)
    }
}
#endif
