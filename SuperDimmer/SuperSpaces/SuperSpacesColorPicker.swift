//
//  SuperSpacesColorPicker.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/22/26.
//
//  PURPOSE: Color picker for Space customization.
//  Allows users to assign colors to Spaces for visual identification and theming.
//
//  FEATURE: 5.5.9 - Space Color Customization (Jan 22, 2026)
//
//  WHY COLORS:
//  - Provides instant visual feedback about which Space you're on
//  - Color-coding helps with mental organization and context switching
//  - Creates a more personalized and visually rich experience
//  - Reduces cognitive load by associating colors with specific contexts
//
//  UI DESIGN:
//  - Grid of curated, professional colors
//  - Organized by color family (blues, greens, purples, etc.)
//  - "Remove Color" button to clear selection (returns to default blue)
//  - Simple, focused interface matching emoji picker style
//
//  COLOR APPLICATION:
//  When a Space has a custom color:
//  - HUD background tints with the color when on that Space
//  - Active card shows a stronger version of the color
//  - Top bar or header can show the color accent
//  - Other cards show faded versions of their colors or remain neutral
//

import SwiftUI

/// Color picker for Space customization
/// Provides a grid of curated colors for visual Space identification and theming
struct SuperSpacesColorPicker: View {
    
    // MARK: - Properties
    
    /// Space number being customized
    let spaceNumber: Int
    
    /// Current color hex (if any)
    @Binding var selectedColorHex: String?
    
    /// Callback when color is selected
    var onColorSelected: ((String?) -> Void)?
    
    /// Access to settings for color palette
    @EnvironmentObject var settings: SettingsManager
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Choose Color for Space \(spaceNumber)")
                .font(.system(size: 13, weight: .semibold))
            
            Divider()
            
            // Color grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Blues
                    colorSection(title: "Blues", colors: Array(settings.spaceColorPalette.prefix(3)))
                    
                    // Greens
                    colorSection(title: "Greens", colors: Array(settings.spaceColorPalette.dropFirst(3).prefix(3)))
                    
                    // Purples
                    colorSection(title: "Purples", colors: Array(settings.spaceColorPalette.dropFirst(6).prefix(3)))
                    
                    // Reds/Pinks
                    colorSection(title: "Reds & Pinks", colors: Array(settings.spaceColorPalette.dropFirst(9).prefix(3)))
                    
                    // Oranges/Yellows
                    colorSection(title: "Oranges & Yellows", colors: Array(settings.spaceColorPalette.dropFirst(12).prefix(3)))
                    
                    // Neutrals
                    colorSection(title: "Neutrals", colors: Array(settings.spaceColorPalette.dropFirst(15).prefix(3)))
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            // Remove color button (shows default color preview)
            Button(action: removeColor) {
                HStack(spacing: 8) {
                    // Default color preview swatch
                    Circle()
                        .fill(settings.hexToColor(settings.getDefaultSpaceColor(for: spaceNumber)))
                        .frame(width: 16, height: 16)
                    
                    Image(systemName: "xmark.circle")
                    Text("Remove Color (Use Default)")
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
        .frame(width: 280)
    }
    
    // MARK: - Helper Views
    
    /// Creates a color section with title and color swatches
    private func colorSection(title: String, colors: [(name: String, hex: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            // Color grid for this section
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 80), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(colors, id: \.hex) { colorInfo in
                    colorButton(name: colorInfo.name, hex: colorInfo.hex)
                }
            }
        }
    }
    
    /// Creates a color button with name and swatch
    private func colorButton(name: String, hex: String) -> some View {
        let isDefaultColor = hex == settings.getDefaultSpaceColor(for: spaceNumber)
        
        return Button(action: {
            selectColor(hex)
        }) {
            VStack(spacing: 4) {
                // Color swatch
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.hexToColor(hex))
                    .frame(height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedColorHex == hex ?
                                    Color.primary : Color.secondary.opacity(0.2),
                                lineWidth: selectedColorHex == hex ? 3 : 1
                            )
                    )
                    .overlay(
                        // Show "Default" badge for the default color
                        Group {
                            if isDefaultColor {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Text("Default")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(4)
                                    }
                                }
                            }
                        }
                    )
                
                // Color name
                Text(name)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(isDefaultColor ? "\(name) (Default for Space \(spaceNumber))" : "Use \(name)")
    }
    
    // MARK: - Actions
    
    /// Selects a color
    private func selectColor(_ hex: String) {
        selectedColorHex = hex
        onColorSelected?(hex)
    }
    
    /// Removes the current color (returns to default)
    private func removeColor() {
        selectedColorHex = nil
        onColorSelected?(nil)
    }
}

// MARK: - Preview

#if DEBUG
struct SuperSpacesColorPicker_Previews: PreviewProvider {
    static var previews: some View {
        SuperSpacesColorPicker(
            spaceNumber: 3,
            selectedColorHex: .constant("#3B82F6")
        )
        .environmentObject(SettingsManager.shared)
    }
}
#endif
