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
    
    /// Current display mode (synced with settings)
    @State private var displayMode: DisplayMode = .compact
    
    /// Converts string to DisplayMode
    private func displayModeFromString(_ string: String) -> DisplayMode {
        switch string {
        case "mini": return .mini
        case "compact": return .compact
        case "expanded": return .expanded
        case "note": return .note
        default: return .compact
        }
    }
    
    /// Converts DisplayMode to string
    private func displayModeToString(_ mode: DisplayMode) -> String {
        switch mode {
        case .mini: return "mini"
        case .compact: return "compact"
        case .expanded: return "expanded"
        case .note: return "note"
        }
    }
    
    /// Currently hovered Space (for hover effects)
    @State private var hoveredSpace: Int?
    
    /// Settings manager for accessing Space customizations
    @EnvironmentObject var settings: SettingsManager
    
    /// Display modes for the HUD
    enum DisplayMode {
        case mini       // Minimal: Just arrows and current number
        case compact    // Compact: Numbered buttons in a row
        case expanded   // Expanded: Grid with Space names
        case note       // Note mode: Persistent note editor with Space selector
    }
    
    /// Space whose note is currently being viewed/edited in note mode
    @State private var selectedNoteSpace: Int?
    
    /// Note text being edited in note mode
    @State private var noteText: String = ""
    
    /// Timer for debounced note saving
    @State private var noteSaveTimer: Timer?
    
    /// Show quick settings popover
    @State private var showQuickSettings = false
    
    /// Show emoji picker popover
    @State private var showEmojiPicker = false
    @State private var emojiPickerForSpace: Int?
    
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
        .onAppear {
            // Load display mode from settings
            displayMode = displayModeFromString(settings.superSpacesDisplayMode)
        }
        .onChange(of: settings.superSpacesDisplayMode) { newValue in
            // Sync when settings change
            displayMode = displayModeFromString(newValue)
        }
        .onChange(of: displayMode) { newValue in
            // Save to settings when mode changes
            settings.superSpacesDisplayMode = displayModeToString(newValue)
        }
        // Emoji picker popover
        .popover(
            isPresented: $showEmojiPicker,
            arrowEdge: .bottom
        ) {
            if let spaceNumber = emojiPickerForSpace {
                SuperSpacesEmojiPicker(
                    spaceNumber: spaceNumber,
                    selectedEmoji: Binding(
                        get: { getSpaceEmoji(spaceNumber) },
                        set: { newEmoji in
                            if let emoji = newEmoji {
                                settings.spaceEmojis[spaceNumber] = emoji
                            } else {
                                settings.spaceEmojis.removeValue(forKey: spaceNumber)
                            }
                        }
                    ),
                    onEmojiSelected: { emoji in
                        if let emoji = emoji {
                            settings.spaceEmojis[spaceNumber] = emoji
                        } else {
                            settings.spaceEmojis.removeValue(forKey: spaceNumber)
                        }
                        showEmojiPicker = false
                    }
                )
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Current Space indicator with emoji (or selected note space in note mode)
            HStack(spacing: 8) {
                let displaySpace = displayMode == .note ? (selectedNoteSpace ?? viewModel.currentSpaceNumber) : viewModel.currentSpaceNumber
                
                // Emoji if set
                if let emoji = getSpaceEmoji(displaySpace) {
                    Text(emoji)
                        .font(.system(size: 16))
                } else {
                    Image(systemName: displayMode == .note ? "note.text" : "square.grid.3x3")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Space \(displaySpace)")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if let spaceName = getSpaceName(displaySpace) {
                        Text(spaceName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Display mode toggle button
            Button(action: cycleDisplayMode) {
                Image(systemName: getDisplayModeIcon())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle view mode: \(getNextDisplayModeName())")
            
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
        case .note:
            noteDisplayView
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
                spaceButton(for: space, compact: true)
            }
        }
    }
    
    /// Creates a Space button (handles both modes and interactions)
    private func spaceButton(for space: SpaceDetector.SpaceInfo, compact: Bool) -> some View {
        Button(action: {
            handleSpaceClick(space.index)
        }) {
            if compact {
                // Compact mode: Number with optional emoji overlay
                ZStack(alignment: .topTrailing) {
                    // Main button content
                    VStack(spacing: 2) {
                        if let emoji = getSpaceEmoji(space.index) {
                            Text(emoji)
                                .font(.system(size: 14))
                        } else {
                            Text("\(space.index)")
                                .font(.system(size: 14, weight: space.index == viewModel.currentSpaceNumber ? .bold : .regular))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(
                        space.index == viewModel.currentSpaceNumber ?
                            Color.accentColor : Color.secondary.opacity(0.2)
                    )
                    .foregroundColor(
                        space.index == viewModel.currentSpaceNumber ? .white : .primary
                    )
                    .cornerRadius(8)
                    
                    // Note indicator
                    if hasNote(space.index) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            } else {
                // Expanded mode handled separately
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .help(getSpaceTooltip(space.index))
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
                Button(action: {
                    handleSpaceClick(space.index)
                }) {
                    VStack(spacing: 6) {
                        // Emoji and Space number with current indicator
                        HStack(spacing: 4) {
                            if space.index == viewModel.currentSpaceNumber {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                            
                            if let emoji = getSpaceEmoji(space.index) {
                                Text(emoji)
                                    .font(.system(size: 20))
                            } else {
                                Text("\(space.index)")
                                    .font(.system(size: 20, weight: .bold))
                            }
                            
                            // Note indicator
                            if hasNote(space.index) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
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
                .help(getSpaceTooltip(space.index))
                .onHover { hovering in
                    hoveredSpace = hovering ? space.index : nil
                }
                .contextMenu {
                    // Right-click menu for customization
                    Button("Edit Name & Emoji...") {
                        showEmojiPickerForSpace(space.index)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    /// Note display mode: Persistent note editor with Space selector
    private var noteDisplayView: some View {
        VStack(spacing: 12) {
            // Space selector row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.allSpaces, id: \.index) { space in
                        noteSpaceButton(for: space)
                    }
                }
            }
            
            Divider()
            
            // Note editor
            VStack(alignment: .leading, spacing: 8) {
                // Note header
                HStack {
                    Text("Note")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Character count
                    Text("\(noteText.count)/500")
                        .font(.system(size: 10))
                        .foregroundColor(noteText.count > 500 ? .red : .secondary)
                }
                
                // Text editor
                TextEditor(text: $noteText)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .onChange(of: noteText) { newValue in
                        debouncedNoteSave(newValue)
                    }
                
                // Placeholder when empty
                if noteText.isEmpty {
                    Text("Add notes, reminders, or tasks for this Space...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, -112)
                        .allowsHitTesting(false)
                }
                
                // Action buttons
                HStack {
                    Button(action: {
                        if let space = selectedNoteSpace {
                            viewModel.switchToSpace(space)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                            Text("Switch to Space")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    if !noteText.isEmpty {
                        Button(action: clearCurrentNote) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            // Initialize with current Space when entering note mode
            if selectedNoteSpace == nil {
                selectedNoteSpace = viewModel.currentSpaceNumber
                loadNoteForSpace(viewModel.currentSpaceNumber)
            }
        }
    }
    
    /// Creates a Space button for note mode selector
    private func noteSpaceButton(for space: SpaceDetector.SpaceInfo) -> some View {
        Button(action: {
            // Single click: Load note for this Space
            selectNoteSpace(space.index)
        }) {
            HStack(spacing: 4) {
                // Emoji or number
                if let emoji = getSpaceEmoji(space.index) {
                    Text(emoji)
                        .font(.system(size: 14))
                } else {
                    Text("\(space.index)")
                        .font(.system(size: 12, weight: .medium))
                }
                
                // Note indicator
                if hasNote(space.index) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 36, height: 32)
            .background(
                selectedNoteSpace == space.index ?
                    Color.accentColor : Color.secondary.opacity(0.2)
            )
            .foregroundColor(
                selectedNoteSpace == space.index ? .white : .primary
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(getSpaceName(space.index) ?? "Space \(space.index)")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // Double-click: Switch to this Space
                viewModel.switchToSpace(space.index)
            }
        )
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text("\(viewModel.allSpaces.count) Spaces")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                showQuickSettings.toggle()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showQuickSettings, arrowEdge: .bottom) {
                SuperSpacesQuickSettings(viewModel: viewModel) { position in
                    // Handle position change
                    viewModel.onPositionChange?(position)
                }
                .environmentObject(settings)
            }
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
        case .note:
            return 420
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
        case .note:
            return 320
        }
    }
    
    /// Gets custom name for a Space
    private func getSpaceName(_ spaceNumber: Int) -> String? {
        return settings.spaceNames[spaceNumber]
    }
    
    /// Gets custom emoji for a Space
    private func getSpaceEmoji(_ spaceNumber: Int) -> String? {
        return settings.spaceEmojis[spaceNumber]
    }
    
    /// Checks if a Space has a note
    private func hasNote(_ spaceNumber: Int) -> Bool {
        guard let note = settings.spaceNotes[spaceNumber] else { return false }
        return !note.isEmpty
    }
    
    /// Gets tooltip text for a Space button
    private func getSpaceTooltip(_ spaceNumber: Int) -> String {
        return "Switch to Space \(spaceNumber)"
    }
    
    /// Handles Space button click (always switches Space in mini/compact/expanded modes)
    private func handleSpaceClick(_ spaceNumber: Int) {
        viewModel.switchToSpace(spaceNumber)
    }
    
    /// Shows emoji picker for a Space
    private func showEmojiPickerForSpace(_ spaceNumber: Int) {
        emojiPickerForSpace = spaceNumber
        showEmojiPicker = true
    }
    
    // MARK: - Note Mode Helpers
    
    /// Selects a Space to view/edit its note
    private func selectNoteSpace(_ spaceNumber: Int) {
        // Save current note before switching
        if let currentSpace = selectedNoteSpace {
            saveNoteForSpace(currentSpace, text: noteText)
        }
        
        // Load new Space's note
        selectedNoteSpace = spaceNumber
        loadNoteForSpace(spaceNumber)
    }
    
    /// Loads note for a specific Space
    private func loadNoteForSpace(_ spaceNumber: Int) {
        noteText = settings.spaceNotes[spaceNumber] ?? ""
    }
    
    /// Saves note for a specific Space
    private func saveNoteForSpace(_ spaceNumber: Int, text: String) {
        if text.isEmpty {
            settings.spaceNotes.removeValue(forKey: spaceNumber)
        } else {
            settings.spaceNotes[spaceNumber] = text
        }
    }
    
    /// Debounced note save to avoid saving on every keystroke
    private func debouncedNoteSave(_ text: String) {
        // Cancel previous timer
        noteSaveTimer?.invalidate()
        
        // Schedule new save after delay
        noteSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [self] _ in
            if let space = selectedNoteSpace {
                saveNoteForSpace(space, text: text)
            }
        }
    }
    
    /// Clears the current Space's note
    private func clearCurrentNote() {
        noteText = ""
        if let space = selectedNoteSpace {
            saveNoteForSpace(space, text: "")
        }
    }
    
    /// Cycles through display modes
    private func cycleDisplayMode() {
        switch displayMode {
        case .mini:
            displayMode = .compact
        case .compact:
            displayMode = .expanded
        case .expanded:
            displayMode = .note
        case .note:
            displayMode = .mini
        }
    }
    
    /// Gets the icon for the current display mode toggle button
    private func getDisplayModeIcon() -> String {
        switch displayMode {
        case .mini:
            return "rectangle.expand.vertical"
        case .compact:
            return "rectangle.expand.vertical"
        case .expanded:
            return "note.text"
        case .note:
            return "rectangle.compress.vertical"
        }
    }
    
    /// Gets the name of the next display mode for tooltip
    private func getNextDisplayModeName() -> String {
        switch displayMode {
        case .mini:
            return "Compact"
        case .compact:
            return "Expanded"
        case .expanded:
            return "Note"
        case .note:
            return "Mini"
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
