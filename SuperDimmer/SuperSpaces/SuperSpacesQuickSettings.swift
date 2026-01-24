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
//  - Auto-hide toggle (global setting)
//  - Float on top toggle (per-HUD setting as of Jan 23, 2026)
//  - Button dimming (dim to indicate order) toggle
//  - Button fade slider (when dimming enabled)
//
//  UI DESIGN:
//  - Clean, minimal popover
//  - Toggles for key features
//  - Slider for button fade intensity
//  - Reset visit history button
//
//  ARCHITECTURE NOTE (Jan 23, 2026):
//  Float on top is now a per-HUD setting, not global. Each HUD instance
//  can have its own independent float on top preference. The toggle in
//  this quick settings view controls the specific HUD it belongs to.
//  Other settings like auto-hide remain global (affecting all HUDs).
//

import SwiftUI

/// Quick settings popover for Super Spaces HUD
/// Provides fast access to common HUD settings without opening full Preferences
struct SuperSpacesQuickSettings: View {
    
    // MARK: - Properties
    
    /// View model for HUD state
    /// Contains per-HUD settings like floatOnTop (Jan 23, 2026)
    @ObservedObject var viewModel: SuperSpacesViewModel
    
    /// Settings manager for global settings (auto-hide, button dimming, etc.)
    @EnvironmentObject var settings: SettingsManager
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Super Spaces Settings")
                .font(.system(size: 13, weight: .semibold))
            
            Divider()
            
            // Auto-Hide Toggle (global setting - affects all HUDs)
            Toggle("Auto-hide after switch", isOn: $settings.superSpacesAutoHide)
                .font(.system(size: 12))
                .help("Automatically hide HUD after switching to a Space")
            
            // Float on Top Toggle (per-HUD setting as of Jan 23, 2026)
            // This controls only THIS specific HUD, not all HUDs
            // Uses Binding to viewModel.floatOnTop which triggers onFloatOnTopChange callback
            Toggle("Float on top", isOn: floatOnTopBinding)
                .font(.system(size: 12))
                .help("Keep THIS HUD above all other windows (per-HUD setting)")
            
            Divider()
            
            // Button Dimming Section
            VStack(alignment: .leading, spacing: 12) {
                // Dimming Toggle
                Toggle("Dim to indicate order", isOn: $settings.spaceOrderDimmingEnabled)
                    .font(.system(size: 12))
                    .help("Dim Space buttons based on visit recency")
                
                // Fade Slider (only shown when dimming is enabled)
                if settings.spaceOrderDimmingEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Button Fade")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(settings.spaceOrderMaxDimLevel * 100))%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        Slider(
                            value: $settings.spaceOrderMaxDimLevel,
                            in: 0.1...0.8,
                            step: 0.05
                        )
                        .help("Maximum dimming for least recently visited Spaces")
                        
                        HStack {
                            Text("Subtle")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Strong")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Oldest Space: \(Int((1.0 - settings.spaceOrderMaxDimLevel) * 100))% visible")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)
                    
                    // Reset Visit History Button
                    Button(action: resetVisitHistory) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Visit History")
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    .help("Clear visit order and reset all buttons to equal opacity")
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
    
    // MARK: - Bindings
    
    /// Custom binding for float on top toggle (per-HUD setting)
    /// This binding updates the viewModel and triggers the onFloatOnTopChange callback
    /// which updates the actual window level for this specific HUD
    ///
    /// ARCHITECTURE (Jan 23, 2026):
    /// Float on top is now per-HUD, not global. Each HUD has its own setting.
    /// When user toggles this, only THIS HUD's window level changes.
    private var floatOnTopBinding: Binding<Bool> {
        Binding(
            get: { viewModel.floatOnTop },
            set: { newValue in
                viewModel.floatOnTop = newValue
                viewModel.onFloatOnTopChange?(newValue)
            }
        )
    }
    
    // MARK: - Actions
    
    /// Resets the Space visit history
    ///
    /// BEHAVIOR:
    /// - Clears the visit order tracked by SpaceVisitTracker
    /// - All Space buttons will have no dimming overlay until visited again
    /// - Useful for starting fresh or debugging
    ///
    /// DESIGN NOTE (Jan 22, 2026):
    /// After reset, buttons use dark overlay dimming instead of transparency.
    /// This provides better visibility while maintaining visual hierarchy.
    private func resetVisitHistory() {
        SpaceVisitTracker.shared.resetVisitOrder()
        print("✓ SuperSpacesQuickSettings: Visit history reset by user")
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
