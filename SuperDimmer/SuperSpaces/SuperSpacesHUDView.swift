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
        case "note": return .note
        default: return .compact
        }
    }
    
    /// Converts DisplayMode to string
    private func displayModeToString(_ mode: DisplayMode) -> String {
        switch mode {
        case .compact: return "compact"
        case .note: return "note"
        }
    }
    
    /// Currently hovered Space (for hover effects)
    @State private var hoveredSpace: Int?
    
    /// Settings manager for accessing Space customizations
    @EnvironmentObject var settings: SettingsManager
    
    /// Display modes for the HUD
    enum DisplayMode {
        case compact    // Compact: Numbered buttons with emoji/name in a row
        case note       // Note mode: Persistent note editor with Space selector and inline editing
    }
    
    /// Space whose note is currently being viewed/edited in note mode
    @State private var selectedNoteSpace: Int?
    
    /// Note text being edited in note mode
    @State private var noteText: String = ""
    
    /// Timer for debounced note saving
    @State private var noteSaveTimer: Timer?
    
    /// Editing state for inline Space name/emoji editing
    @State private var isEditingSpaceName = false
    @State private var editingSpaceNameText: String = ""
    @State private var editingSpaceEmoji: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isEmojiFieldFocused: Bool
    
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
            minWidth: calculateMinWidth(),
            idealWidth: calculateWidth(),
            maxWidth: .infinity,
            minHeight: calculateMinHeight(),
            idealHeight: calculateHeight(),
            maxHeight: .infinity
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
        case .compact:
            compactSpacesView
        case .note:
            noteDisplayView
        }
    }
    
    /// Compact display mode: Numbered buttons with emoji and name in a scrollable row
    private var compactSpacesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.allSpaces, id: \.index) { space in
                    compactSpaceButton(for: space)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    /// Creates a compact Space button with number, emoji, and name
    private func compactSpaceButton(for space: SpaceDetector.SpaceInfo) -> some View {
        Button(action: {
            handleSpaceClick(space.index)
        }) {
            HStack(spacing: 6) {
                // Number
                Text("\(space.index)")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20)
                
                // Emoji if set
                if let emoji = getSpaceEmoji(space.index) {
                    Text(emoji)
                        .font(.system(size: 14))
                }
                
                // Name if set
                if let name = getSpaceName(space.index), !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                
                // Note indicator
                if hasNote(space.index) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
        .help(getSpaceTooltip(space.index))
    }
    
    /// Note display mode: Persistent note editor with Space selector and inline editing
    private var noteDisplayView: some View {
        VStack(spacing: 12) {
            // Space selector row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.allSpaces, id: \.index) { space in
                        noteSpaceButton(for: space)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            Divider()
            
            // Space name and emoji editor (inline, above note)
            if let spaceNumber = selectedNoteSpace {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space \(spaceNumber)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if isEditingSpaceName {
                        // Editing mode with character counter
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                // Emoji field
                                TextField("Emoji", text: $editingSpaceEmoji)
                                    .font(.system(size: 20))
                                    .frame(width: 50, height: 36)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.plain)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    )
                                    .focused($isEmojiFieldFocused)
                                
                                // Name field
                                TextField("Space Name", text: $editingSpaceNameText)
                                    .font(.system(size: 14))
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                editingSpaceNameText.count > settings.maxSpaceNameLength ? Color.red : Color.accentColor,
                                                lineWidth: 2
                                            )
                                    )
                                    .focused($isNameFieldFocused)
                                    .onSubmit {
                                        saveSpaceNameAndEmoji()
                                    }
                                    .onChange(of: editingSpaceNameText) { newValue in
                                        // Enforce character limit
                                        if newValue.count > settings.maxSpaceNameLength {
                                            editingSpaceNameText = String(newValue.prefix(settings.maxSpaceNameLength))
                                        }
                                    }
                                
                                // Save button
                                Button(action: saveSpaceNameAndEmoji) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Save (Enter)")
                                
                                // Cancel button
                                Button(action: cancelSpaceNameEditing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Cancel (Esc)")
                            }
                            
                            // Character counter (PHASE 2.2)
                            HStack {
                                Spacer()
                                Text("\(editingSpaceNameText.count)/\(settings.maxSpaceNameLength)")
                                    .font(.system(size: 10))
                                    .foregroundColor(
                                        editingSpaceNameText.count > settings.maxSpaceNameLength - 5 ?
                                            (editingSpaceNameText.count >= settings.maxSpaceNameLength ? .red : .orange) :
                                            .secondary
                                    )
                            }
                        }
                    } else {
                        // Display mode (double-click to edit)
                        HStack(spacing: 8) {
                            // Emoji display
                            if let emoji = getSpaceEmoji(spaceNumber), !emoji.isEmpty {
                                Text(emoji)
                                    .font(.system(size: 20))
                            } else {
                                Text("➕")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                            
                            // Name display
                            Text(getSpaceName(spaceNumber) ?? "Unnamed Space")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(getSpaceName(spaceNumber) == nil ? .secondary : .primary)
                            
                            Spacer()
                            
                            // Edit hint
                            Text("Double-click to edit")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        .onTapGesture(count: 2) {
                            startEditingSpaceName()
                        }
                    }
                }
                
                Divider()
            }
            
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
                    .frame(height: 100)
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
                        .padding(.top, -92)
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
    
    /// Calculates minimum width based on display mode
    private func calculateMinWidth() -> CGFloat {
        return 400
    }
    
    /// Calculates ideal width based on display mode and number of Spaces
    private func calculateWidth() -> CGFloat {
        switch displayMode {
        case .compact:
            // Wider to accommodate number + emoji + name
            return 480
        case .note:
            // Wider for note editing and inline name/emoji editing
            return 480
        }
    }
    
    /// Calculates minimum height based on display mode
    /// This ensures content is never clipped
    private func calculateMinHeight() -> CGFloat {
        switch displayMode {
        case .compact:
            return 120
        case .note:
            // Minimum height for note mode to prevent clipping
            return 360
        }
    }
    
    /// Calculates ideal height based on display mode
    /// This is the preferred height that gives comfortable spacing
    private func calculateHeight() -> CGFloat {
        switch displayMode {
        case .compact:
            return 140  // Slightly taller for better spacing
        case .note:
            // Taller to accommodate Space selector + name/emoji editor + note
            // Added extra padding to prevent any clipping
            return isEditingSpaceName ? 420 : 400
        }
    }
    
    /// Gets custom name for a Space
    /// Gets Space name (custom or default)
    /// PHASE 2.2: Returns default "Desktop X" if no custom name set
    private func getSpaceName(_ spaceNumber: Int) -> String? {
        // Check for custom name first
        if let customName = settings.spaceNames[spaceNumber] {
            return customName
        }
        // Return default name
        return settings.generateDefaultSpaceName(for: spaceNumber)
    }
    
    /// Gets Space emoji (custom or default)
    /// PHASE 2.3: Returns preset emoji if no custom emoji set
    private func getSpaceEmoji(_ spaceNumber: Int) -> String? {
        // Check for custom emoji first
        if let customEmoji = settings.spaceEmojis[spaceNumber] {
            return customEmoji
        }
        // Return default emoji (for Spaces 1-16)
        return settings.getDefaultEmoji(for: spaceNumber)
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
    
    // MARK: - Inline Space Name/Emoji Editing
    
    /// Starts editing the Space name and emoji
    private func startEditingSpaceName() {
        guard let spaceNumber = selectedNoteSpace else { return }
        
        isEditingSpaceName = true
        editingSpaceNameText = getSpaceName(spaceNumber) ?? ""
        editingSpaceEmoji = getSpaceEmoji(spaceNumber) ?? ""
        
        // Focus the name field after a short delay to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    /// Saves the edited Space name and emoji
    /// PHASE 2.2: Validates and enforces character limit
    private func saveSpaceNameAndEmoji() {
        guard let spaceNumber = selectedNoteSpace else { return }
        
        // Validate and save name with character limit
        let trimmedName = editingSpaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            // Empty name: remove custom name, will show default
            settings.spaceNames.removeValue(forKey: spaceNumber)
        } else {
            // Validate and truncate to character limit
            let validatedName = settings.validateSpaceName(trimmedName)
            settings.spaceNames[spaceNumber] = validatedName
        }
        
        // Save emoji (limit to first 2 characters to handle multi-byte emojis)
        let trimmedEmoji = String(editingSpaceEmoji.prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmoji.isEmpty {
            // Empty emoji: remove custom emoji, will show default
            settings.spaceEmojis.removeValue(forKey: spaceNumber)
        } else {
            settings.spaceEmojis[spaceNumber] = trimmedEmoji
        }
        
        isEditingSpaceName = false
    }
    
    /// Cancels Space name/emoji editing
    private func cancelSpaceNameEditing() {
        isEditingSpaceName = false
        editingSpaceNameText = ""
        editingSpaceEmoji = ""
    }
    
    /// Cycles through display modes (only 2 modes now)
    private func cycleDisplayMode() {
        switch displayMode {
        case .compact:
            displayMode = .note
        case .note:
            displayMode = .compact
        }
    }
    
    /// Gets the icon for the current display mode toggle button
    private func getDisplayModeIcon() -> String {
        switch displayMode {
        case .compact:
            return "note.text"
        case .note:
            return "list.bullet"
        }
    }
    
    /// Gets the name of the next display mode for tooltip
    private func getNextDisplayModeName() -> String {
        switch displayMode {
        case .compact:
            return "Note Mode"
        case .note:
            return "Compact Mode"
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
