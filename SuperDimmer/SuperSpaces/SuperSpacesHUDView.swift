//
//  SuperSpacesHUDView.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: SwiftUI view for the Super Spaces HUD interface.
//  Provides beautiful, responsive UI for Space navigation and switching.
//
//  UI DESIGN PHILOSOPHY:
//  - Clean, minimal, professional
//  - Inspired by Spotlight, Raycast, Mission Control
//  - macOS native look and feel
//  - Subtle animations and transitions
//
//  DISPLAY MODES:
//  1. Mini: Just current Space number with arrows (← 3 →)
//  2. Compact: Numbered buttons in a row ([1] [2] [●3] [4])
//  3. Expanded: Grid with Space names and thumbnails
//

import SwiftUI

/// SwiftUI view for Super Spaces HUD
/// Displays current Space and provides Space switching interface
struct SuperSpacesHUDView: View {
    
    // MARK: - Properties
    
    /// View model that provides Space data and callbacks
    @ObservedObject var viewModel: SuperSpacesViewModel
    
    /// Current display mode
    @State private var displayMode: DisplayMode = .compact
    
    /// Currently hovered Space (for hover effects)
    @State private var hoveredSpace: Int?
    
    /// Display modes for the HUD
    enum DisplayMode {
        case mini       // Minimal: Just arrows and current number
        case compact    // Compact: Numbered buttons in a row
        case expanded   // Expanded: Grid with Space names
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background blur
            VisualEffectView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .cornerRadius(12)
            
            // Content
            VStack(spacing: 0) {
                // Header: Current Space info and controls
                headerView
                
                Divider()
                    .padding(.vertical, 8)
                
                // Space grid/list (varies by display mode)
                spacesView
                
                // Footer: Space count and settings
                footerView
            }
            .padding(16)
        }
        .frame(
            width: calculateWidth(),
            height: calculateHeight()
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: displayMode)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Current Space indicator
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Space \(viewModel.currentSpaceNumber)")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if let spaceName = getSpaceName(viewModel.currentSpaceNumber) {
                        Text(spaceName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Display mode toggle button
            Button(action: cycleDisplayMode) {
                Image(systemName: displayMode == .expanded ?
                      "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle view mode")
            
            // Close button
            Button(action: { viewModel.closeHUD() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }
    
    // MARK: - Spaces View
    
    @ViewBuilder
    private var spacesView: some View {
        switch displayMode {
        case .mini:
            miniSpacesView
        case .compact:
            compactSpacesView
        case .expanded:
            expandedSpacesView
        }
    }
    
    /// Mini display mode: Just arrows and current number
    private var miniSpacesView: some View {
        HStack(spacing: 16) {
            Button(action: { switchToPreviousSpace() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentSpaceNumber <= 1)
            .help("Previous Space")
            
            Text("\(viewModel.currentSpaceNumber)/\(viewModel.allSpaces.count)")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 60)
            
            Button(action: { switchToNextSpace() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentSpaceNumber >= viewModel.allSpaces.count)
            .help("Next Space")
        }
    }
    
    /// Compact display mode: Numbered buttons in a row
    private var compactSpacesView: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.allSpaces, id: \.index) { space in
                Button(action: { viewModel.switchToSpace(space.index) }) {
                    Text("\(space.index)")
                        .font(.system(size: 14, weight: space.index == viewModel.currentSpaceNumber ? .bold : .regular))
                        .frame(width: 32, height: 32)
                        .background(
                            space.index == viewModel.currentSpaceNumber ?
                                Color.accentColor : Color.secondary.opacity(0.2)
                        )
                        .foregroundColor(
                            space.index == viewModel.currentSpaceNumber ? .white : .primary
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Switch to Space \(space.index)")
            }
        }
    }
    
    /// Expanded display mode: Grid with Space names
    private var expandedSpacesView: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            ForEach(viewModel.allSpaces, id: \.index) { space in
                Button(action: { viewModel.switchToSpace(space.index) }) {
                    VStack(spacing: 6) {
                        // Space number with current indicator
                        HStack(spacing: 4) {
                            if space.index == viewModel.currentSpaceNumber {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                            Text("\(space.index)")
                                .font(.system(size: 20, weight: .bold))
                        }
                        
                        // Space name
                        Text(getSpaceName(space.index) ?? "Desktop")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                space.index == viewModel.currentSpaceNumber ?
                                    Color.accentColor.opacity(0.2) :
                                    (hoveredSpace == space.index ?
                                        Color.secondary.opacity(0.1) :
                                        Color.clear)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                space.index == viewModel.currentSpaceNumber ?
                                    Color.accentColor :
                                    Color.clear,
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Switch to Space \(space.index)")
                .onHover { hovering in
                    hoveredSpace = hovering ? space.index : nil
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text("\(viewModel.allSpaces.count) Spaces")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { /* TODO: Open preferences */ }) {
                Text("Settings")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculates appropriate width based on display mode and number of Spaces
    private func calculateWidth() -> CGFloat {
        switch displayMode {
        case .mini:
            return 200
        case .compact:
            // Each Space button is ~40pt wide, add padding
            let buttonWidth: CGFloat = 40
            let spacing: CGFloat = 8
            let padding: CGFloat = 32
            let spaceCount = CGFloat(viewModel.allSpaces.count)
            return min(max(spaceCount * buttonWidth + (spaceCount - 1) * spacing + padding, 300), 600)
        case .expanded:
            return 400
        }
    }
    
    /// Calculates appropriate height based on display mode
    private func calculateHeight() -> CGFloat {
        switch displayMode {
        case .mini:
            return 100
        case .compact:
            return 140
        case .expanded:
            // Calculate rows needed for grid (3 columns)
            let rows = ceil(Double(viewModel.allSpaces.count) / 3.0)
            let rowHeight: CGFloat = 82
            let baseHeight: CGFloat = 180
            return baseHeight + CGFloat(rows) * rowHeight
        }
    }
    
    /// Gets custom name for a Space
    private func getSpaceName(_ spaceNumber: Int) -> String? {
        // TODO: Get custom Space names from SettingsManager
        let defaultNames: [Int: String] = [
            1: "Email",
            2: "Browse",
            3: "Development",
            4: "Design",
            5: "Music",
            6: "Chat"
        ]
        return defaultNames[spaceNumber]
    }
    
    /// Cycles through display modes
    private func cycleDisplayMode() {
        switch displayMode {
        case .mini:
            displayMode = .compact
        case .compact:
            displayMode = .expanded
        case .expanded:
            displayMode = .mini
        }
    }
    
    /// Switches to previous Space
    private func switchToPreviousSpace() {
        if viewModel.currentSpaceNumber > 1 {
            viewModel.switchToSpace(viewModel.currentSpaceNumber - 1)
        }
    }
    
    /// Switches to next Space
    private func switchToNextSpace() {
        if viewModel.currentSpaceNumber < viewModel.allSpaces.count {
            viewModel.switchToSpace(viewModel.currentSpaceNumber + 1)
        }
    }
}

// MARK: - Visual Effect View

/// NSVisualEffectView wrapper for SwiftUI
/// Provides native macOS blur effect for HUD look
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview

#if DEBUG
struct SuperSpacesHUDView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SuperSpacesViewModel()
        viewModel.currentSpaceNumber = 3
        viewModel.allSpaces = [
            SpaceDetector.SpaceInfo(index: 1, uuid: "1", displayUUID: "display", isCurrent: false, type: 0),
            SpaceDetector.SpaceInfo(index: 2, uuid: "2", displayUUID: "display", isCurrent: false, type: 0),
            SpaceDetector.SpaceInfo(index: 3, uuid: "3", displayUUID: "display", isCurrent: true, type: 0),
            SpaceDetector.SpaceInfo(index: 4, uuid: "4", displayUUID: "display", isCurrent: false, type: 0),
            SpaceDetector.SpaceInfo(index: 5, uuid: "5", displayUUID: "display", isCurrent: false, type: 0),
            SpaceDetector.SpaceInfo(index: 6, uuid: "6", displayUUID: "display", isCurrent: false, type: 0)
        ]
        
        return SuperSpacesHUDView(viewModel: viewModel)
            .frame(width: 400, height: 300)
    }
}
#endif
