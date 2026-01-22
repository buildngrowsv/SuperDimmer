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
    
    /// Callback for mode changes (to trigger window resize)
    /// Called when user switches display modes so the HUD can resize appropriately
    var onModeChange: ((DisplayMode) -> Void)?
    
    /// Current display mode (synced with settings)
    @State private var displayMode: DisplayMode = .compact
    
    /// Converts string to DisplayMode
    private func displayModeFromString(_ string: String) -> DisplayMode {
        switch string {
        case "note": return .note
        case "overview": return .overview  // PHASE 4
        default: return .compact
        }
    }
    
    /// Converts DisplayMode to string
    private func displayModeToString(_ mode: DisplayMode) -> String {
        switch mode {
        case .compact: return "compact"
        case .note: return "note"
        case .overview: return "overview"  // PHASE 4
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
        case overview   // Overview: Grid showing all Spaces with notes, all editable (PHASE 4)
    }
    
    /// Space whose note is currently being viewed/edited in note mode
    @State private var selectedNoteSpace: Int?
    
    /// Note text being edited in note mode
    @State private var noteText: String = ""
    
    /// Timer for debounced note saving
    @State private var noteSaveTimer: Timer?
    
    /// Editing state for inline Space name/emoji/color editing
    @State private var isEditingSpaceName = false
    @State private var editingSpaceNameText: String = ""
    @State private var editingSpaceEmoji: String = ""
    @State private var editingSpaceColor: String = ""  // FEATURE 5.5.9 - Color editing
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isEmojiFieldFocused: Bool
    
    /// Maximum button width for equal-width buttons (PHASE 2.1)
    @State private var maxButtonWidth: CGFloat = 100
    
    /// Available width for note mode space selector buttons (adaptive sizing)
    /// This tracks the container width to determine button expansion level
    @State private var noteSelectorWidth: CGFloat = 0
    
    /// Show quick settings popover
    @State private var showQuickSettings = false
    
    /// Show emoji picker popover (for context menu)
    @State private var showEmojiPicker = false
    @State private var emojiPickerForSpace: Int?
    
    /// Show inline emoji picker (for note mode editing) - PHASE 3.1
    @State private var showInlineEmojiPicker = false
    
    /// Show color picker popover (for inline editing) - FEATURE 5.5.9
    @State private var showColorPicker = false
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background blur with color tint (FEATURE 5.5.9)
            // Tints the HUD with the current Space's color for visual feedback
            ZStack {
                VisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow
                )
                
                // Color overlay tint (subtle, 5% opacity)
                getCurrentSpaceAccentColor()
                    .opacity(0.05)
            }
            .cornerRadius(12)
            
            // Content
            VStack(spacing: 0) {
                // Header: Current Space info and controls
                headerView
                
                Divider()
                    .padding(.vertical, 8)
                
                // Space grid/list (varies by display mode)
                spacesView
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
            
            // Calculate initial button width (PHASE 2.1)
            updateButtonWidth()
        }
        .onChange(of: settings.superSpacesDisplayMode) { newValue in
            // Sync when settings change
            displayMode = displayModeFromString(newValue)
        }
        .onChange(of: displayMode) { newValue in
            // Save to settings when mode changes
            settings.superSpacesDisplayMode = displayModeToString(newValue)
        }
        .onChange(of: settings.spaceNames) { _ in
            // Recalculate button width when names change (PHASE 2.1)
            updateButtonWidth()
        }
        .onChange(of: settings.spaceEmojis) { _ in
            // Recalculate button width when emojis change (PHASE 2.1)
            updateButtonWidth()
        }
        .onChange(of: viewModel.allSpaces) { _ in
            // Recalculate button width when Spaces change (PHASE 2.1)
            updateButtonWidth()
        }
        // Emoji picker popover (context menu)
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
        // Inline emoji picker popover (PHASE 3.1: Note mode editing)
        .popover(
            isPresented: $showInlineEmojiPicker,
            arrowEdge: .bottom
        ) {
            if let spaceNumber = selectedNoteSpace {
                SuperSpacesEmojiPicker(
                    spaceNumber: spaceNumber,
                    selectedEmoji: Binding(
                        get: { editingSpaceEmoji.isEmpty ? nil : editingSpaceEmoji },
                        set: { newEmoji in
                            editingSpaceEmoji = newEmoji ?? ""
                        }
                    ),
                    onEmojiSelected: { emoji in
                        editingSpaceEmoji = emoji ?? ""
                        showInlineEmojiPicker = false
                        // Auto-focus name field after emoji selection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isNameFieldFocused = true
                        }
                    }
                )
            }
        }
        // Inline color picker popover (FEATURE 5.5.9: Color customization)
        .popover(
            isPresented: $showColorPicker,
            arrowEdge: .bottom
        ) {
            if let spaceNumber = selectedNoteSpace {
                SuperSpacesColorPicker(
                    spaceNumber: spaceNumber,
                    selectedColorHex: Binding(
                        get: { editingSpaceColor.isEmpty ? nil : editingSpaceColor },
                        set: { newColor in
                            editingSpaceColor = newColor ?? ""
                        }
                    ),
                    onColorSelected: { color in
                        editingSpaceColor = color ?? ""
                        showColorPicker = false
                        // Auto-focus name field after color selection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isNameFieldFocused = true
                        }
                    }
                )
                .environmentObject(settings)
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
                        .font(.system(size: scaledFontSize(16)))
                } else {
                    Image(systemName: displayMode == .note ? "note.text" : "square.grid.3x3")
                        .font(.system(size: scaledFontSize(16)))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Space \(displaySpace)")
                        .font(.system(size: scaledFontSize(14), weight: .semibold))
                    
                    if let spaceName = getSpaceName(displaySpace) {
                        Text(spaceName)
                            .font(.system(size: scaledFontSize(11)))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Display mode buttons (3 separate buttons instead of toggle)
            // FEATURE: Per-mode window size persistence
            // Each button switches to that mode and restores the saved window size
            // FEATURE 5.5.9: Uses current Space's color for active button
            HStack(spacing: 4) {
                // Compact mode button
                Button(action: { switchToMode(.compact) }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: scaledFontSize(11)))
                        .foregroundColor(displayMode == .compact ? .white : .secondary)
                        .frame(width: 24, height: 20)
                        .background(displayMode == .compact ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Compact Mode")
                
                // Note mode button
                Button(action: { switchToMode(.note) }) {
                    Image(systemName: "note.text")
                        .font(.system(size: scaledFontSize(11)))
                        .foregroundColor(displayMode == .note ? .white : .secondary)
                        .frame(width: 24, height: 20)
                        .background(displayMode == .note ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Note Mode")
                
                // Overview mode button
                Button(action: { switchToMode(.overview) }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: scaledFontSize(11)))
                        .foregroundColor(displayMode == .overview ? .white : .secondary)
                        .frame(width: 24, height: 20)
                        .background(displayMode == .overview ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Overview Mode")
            }
            .padding(3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            
            // Settings button (moved from footer)
            Button(action: {
                showQuickSettings.toggle()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: scaledFontSize(14)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $showQuickSettings, arrowEdge: .bottom) {
                SuperSpacesQuickSettings(viewModel: viewModel)
                    .environmentObject(settings)
            }
            
            // Close button
            Button(action: { viewModel.closeHUD() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: scaledFontSize(14)))
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
        case .overview:
            overviewDisplayView  // PHASE 4
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
    /// PHASE 2.1: Uses fixed width for all buttons (equal-width sizing)
    private func compactSpaceButton(for space: SpaceDetector.SpaceInfo) -> some View {
        Button(action: {
            handleSpaceClick(space.index)
        }) {
            HStack(spacing: 6) {
                // Number
                Text("\(space.index)")
                    .font(.system(size: scaledFontSize(12), weight: .semibold))
                    .frame(width: 20)
                
                // Emoji if set
                if let emoji = getSpaceEmoji(space.index) {
                    Text(emoji)
                        .font(.system(size: scaledFontSize(14)))
                }
                
                // Name if set
                if let name = getSpaceName(space.index), !name.isEmpty {
                    Text(name)
                        .font(.system(size: scaledFontSize(12)))
                        .lineLimit(1)
                }
                
                // Note indicator
                if hasNote(space.index) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: maxButtonWidth)  // PHASE 2.1: Fixed width for all buttons
            .padding(.vertical, 8)
            .background(
                // FEATURE 5.5.9: Use Space's custom color or default
                space.index == viewModel.currentSpaceNumber ?
                    (getSpaceColor(space.index).map { settings.hexToColor($0) } ?? Color.accentColor) :
                    Color.secondary.opacity(0.2)
            )
            .foregroundColor(
                space.index == viewModel.currentSpaceNumber ? .white : .primary
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(getSpaceTooltip(space.index))
        .opacity(getSpaceOpacity(space.index))  // FEATURE: 5.5.8 - Dim to Indicate Order
    }
    
    /// Note display mode: Persistent note editor with Space selector and inline editing
    /// RESPONSIVE DESIGN: Text editor expands vertically with window size (with minimum height)
    private var noteDisplayView: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                // Space selector row with adaptive button sizing
                // Buttons expand to show number + emoji + name as window width increases
                GeometryReader { selectorGeometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.allSpaces, id: \.index) { space in
                                noteSpaceButton(for: space, availableWidth: selectorGeometry.size.width)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .onAppear {
                        noteSelectorWidth = selectorGeometry.size.width
                    }
                    .onChange(of: selectorGeometry.size.width) { newWidth in
                        noteSelectorWidth = newWidth
                    }
                }
                .frame(height: 40)  // Fixed height for the selector row
                
                Divider()
                
                // Space name and emoji editor (inline, above note)
                if let spaceNumber = selectedNoteSpace {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Space \(spaceNumber)")
                            .font(.system(size: scaledFontSize(10), weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if isEditingSpaceName {
                            // Editing mode with character counter
                            // PHASE 3.1: Emoji button instead of text field
                            // FEATURE 5.5.9: Added color picker button
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    // Emoji button (PHASE 3.1: Visual picker instead of text field)
                                    Button(action: {
                                        showInlineEmojiPicker = true
                                    }) {
                                        HStack {
                                            if editingSpaceEmoji.isEmpty {
                                                Image(systemName: "face.smiling")
                                                    .font(.system(size: scaledFontSize(18)))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text(editingSpaceEmoji)
                                                    .font(.system(size: scaledFontSize(20)))
                                            }
                                        }
                                        .frame(width: 50, height: 36)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(showInlineEmojiPicker ? getCurrentSpaceAccentColor() : Color.secondary.opacity(0.3), lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Click to choose emoji")
                                    
                                    // Color button (FEATURE 5.5.9: Color picker)
                                    Button(action: {
                                        showColorPicker = true
                                    }) {
                                        HStack {
                                            if editingSpaceColor.isEmpty {
                                                Image(systemName: "paintpalette")
                                                    .font(.system(size: scaledFontSize(18)))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                // Show color swatch
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(settings.hexToColor(editingSpaceColor))
                                                    .frame(width: 24, height: 24)
                                            }
                                        }
                                        .frame(width: 50, height: 36)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(showColorPicker ? getCurrentSpaceAccentColor() : Color.secondary.opacity(0.3), lineWidth: 2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Click to choose color")
                                    
                                    // Name field
                                    TextField("Space Name", text: $editingSpaceNameText)
                                        .font(.system(size: scaledFontSize(14)))
                                        .textFieldStyle(.plain)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    editingSpaceNameText.count > settings.maxSpaceNameLength ? Color.red : getCurrentSpaceAccentColor(),
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
                                        .onChange(of: isNameFieldFocused) { isFocused in
                                            // FEATURE: Auto-save when clicking off the name field
                                            // When the field loses focus (isFocused becomes false), save the changes
                                            // This provides a more intuitive UX where users don't need to explicitly
                                            // click the save button - just clicking elsewhere saves automatically
                                            if !isFocused && isEditingSpaceName {
                                                saveSpaceNameAndEmoji()
                                            }
                                        }
                                    
                                    // Save button
                                    Button(action: saveSpaceNameAndEmoji) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: scaledFontSize(18)))
                                            .foregroundColor(.green)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Save (Enter)")
                                    
                                    // Cancel button
                                    Button(action: cancelSpaceNameEditing) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: scaledFontSize(18)))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Cancel (Esc)")
                                }
                                
                                // Character counter (PHASE 2.2)
                                HStack {
                                    Spacer()
                                    Text("\(editingSpaceNameText.count)/\(settings.maxSpaceNameLength)")
                                        .font(.system(size: scaledFontSize(10)))
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
                                        .font(.system(size: scaledFontSize(20)))
                                } else {
                                    Text("➕")
                                        .font(.system(size: scaledFontSize(16)))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Name display
                                Text(getSpaceName(spaceNumber) ?? "Unnamed Space")
                                    .font(.system(size: scaledFontSize(14), weight: .medium))
                                    .foregroundColor(getSpaceName(spaceNumber) == nil ? .secondary : .primary)
                                
                                Spacer()
                                
                                // Edit hint
                                Text("Double-click to edit")
                                    .font(.system(size: scaledFontSize(9)))
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
                
                // Note editor - RESPONSIVE: Expands to fill available vertical space
                VStack(alignment: .leading, spacing: 8) {
                    // Note header
                    HStack {
                        Text("Note")
                            .font(.system(size: scaledFontSize(11), weight: .medium))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Character count
                        Text("\(noteText.count)/500")
                            .font(.system(size: scaledFontSize(10)))
                            .foregroundColor(noteText.count > 500 ? .red : .secondary)
                    }
                    
                    // Text editor with ZStack for proper placeholder positioning
                    // RESPONSIVE: Calculate height based on available space
                    // Minimum 100pt, expands to fill remaining vertical space
                    let availableHeight = geometry.size.height
                    let usedHeight: CGFloat = 40 + 12 + (selectedNoteSpace != nil ? (isEditingSpaceName ? 120 : 80) : 0) + 12 + 20 + 8 + 40
                    let noteEditorHeight = max(100, availableHeight - usedHeight)
                    
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $noteText)
                            .font(.system(size: scaledFontSize(12)))
                            .frame(height: noteEditorHeight)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onChange(of: noteText) { newValue in
                                debouncedNoteSave(newValue)
                            }
                        
                        // Placeholder when empty - positioned to match TextEditor cursor
                        if noteText.isEmpty {
                            Text("Add notes, reminders, or tasks for this Space...")
                                .font(.system(size: scaledFontSize(12)))
                                .foregroundColor(.secondary)
                                .padding(.leading, 13)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
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
                            .font(.system(size: scaledFontSize(11)))
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
                                .font(.system(size: scaledFontSize(11)))
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
        }
        .onAppear {
            // Initialize with current Space when entering note mode
            if selectedNoteSpace == nil {
                selectedNoteSpace = viewModel.currentSpaceNumber
                loadNoteForSpace(viewModel.currentSpaceNumber)
            }
        }
    }
    
    /// Creates a Space button for note mode selector with adaptive sizing
    /// ADAPTIVE SIZING: Button expands to show more content as window width increases
    /// ALWAYS shows number (user requirement), expands to show emoji and name as width allows
    /// User preference: "I rather have to scroll than not" - aggressive expansion
    /// - Compact (narrow): Number only (44pt)
    /// - Medium (moderate): Number + emoji (60pt)
    /// - Expanded (wide): Number + emoji + name (80pt+, names can clip)
    private func noteSpaceButton(for space: SpaceDetector.SpaceInfo, availableWidth: CGFloat) -> some View {
        // Determine what to show based on available width (calculate once outside button)
        let buttonMode = getNoteButtonMode(availableWidth: availableWidth)
        
        return Button(action: {
            // Single click: Load note for this Space
            selectNoteSpace(space.index)
        }) {
            HStack(spacing: 4) {
                // NUMBER: Always shown (user requirement - "keep the number there all the time")
                Text("\(space.index)")
                    .font(.system(size: scaledFontSize(11), weight: .semibold))
                    .frame(width: 16)
                
                // EMOJI: Show when we have medium or more space
                if buttonMode != .compact, let emoji = getSpaceEmoji(space.index) {
                    Text(emoji)
                        .font(.system(size: scaledFontSize(14)))
                }
                
                // NAME: Show when we have expanded space (even if it clips)
                // User preference: "I rather have to scroll than not" - show names aggressively
                if buttonMode == .expanded, let name = getSpaceName(space.index) {
                    Text(name)
                        .font(.system(size: scaledFontSize(11)))
                        .lineLimit(1)
                }
                
                // Note indicator (always shown)
                if hasNote(space.index) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, buttonMode == .expanded ? 8 : 6)
            .frame(minWidth: getNoteButtonWidth(mode: buttonMode))
            .frame(height: 32)
            .background(
                // FEATURE 5.5.9: Use Space's custom color or default
                selectedNoteSpace == space.index ?
                    (getSpaceColor(space.index).map { settings.hexToColor($0) } ?? Color.accentColor) :
                    Color.secondary.opacity(0.2)
            )
            .foregroundColor(
                selectedNoteSpace == space.index ? .white : .primary
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(getSpaceName(space.index) ?? "Space \(space.index)")
        .opacity(getSpaceOpacity(space.index))  // FEATURE: 5.5.8 - Dim to Indicate Order
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // Double-click: Switch to this Space
                viewModel.switchToSpace(space.index)
            }
        )
    }
    
    /// Button display modes for note selector
    /// Determines what content to show based on available width
    /// UPDATED: More aggressive expansion, always show number
    private enum NoteButtonMode {
        case compact    // Number only (44pt) - no emoji
        case medium     // Number + emoji (60pt)
        case expanded   // Number + emoji + name (80pt+, names can clip)
    }
    
    /// Determines button mode based on available width
    /// Calculates per-button space to decide expansion level
    /// UPDATED: More generous thresholds - prefer expansion over compactness
    /// User wants to scroll rather than see less info
    private func getNoteButtonMode(availableWidth: CGFloat) -> NoteButtonMode {
        let spaceCount = CGFloat(viewModel.allSpaces.count)
        guard spaceCount > 0 else { return .compact }
        
        // Calculate approximate space per button (accounting for spacing and padding)
        let spacing: CGFloat = 8
        let padding: CGFloat = 8
        let totalSpacing = (spaceCount - 1) * spacing + padding * 2
        let availableForButtons = availableWidth - totalSpacing
        let spacePerButton = availableForButtons / spaceCount
        
        // UPDATED: More aggressive thresholds - prefer showing more info
        // Lowered from 100→70 and 60→50 to expand sooner
        if spacePerButton >= 70 {
            return .expanded  // Show number + emoji + name (names can clip, user will scroll)
        } else if spacePerButton >= 50 {
            return .medium    // Show number + emoji
        } else {
            return .compact   // Show number only
        }
    }
    
    /// Gets minimum width for note button based on mode
    /// UPDATED: Adjusted widths for new always-show-number approach
    private func getNoteButtonWidth(mode: NoteButtonMode) -> CGFloat {
        switch mode {
        case .compact:
            return 44  // Number only (increased from 36 to accommodate number)
        case .medium:
            return 60  // Number + emoji
        case .expanded:
            return 80  // Number + emoji + name (minimum, will expand with name)
        }
    }
    
    // MARK: - Overview Display Mode (Phase 4)
    
    /// Overview display mode: Grid showing all Spaces with their notes, all editable
    /// Single click on any Space button switches to that Space
    /// RESPONSIVE DESIGN: 2-5 columns based on window width, cards expand vertically with window
    private var overviewDisplayView: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: getOverviewColumns(for: geometry.size.width), spacing: 12) {
                    ForEach(viewModel.allSpaces, id: \.index) { space in
                        overviewSpaceCard(for: space, availableHeight: geometry.size.height)
                    }
                }
                .padding(12)
            }
        }
    }
    
    /// Determines the number of columns for overview mode based on window width
    /// RESPONSIVE THRESHOLDS (scale with font size):
    /// - < 450pt: 1 column (narrow window, single column for better readability)
    /// - 450-700pt: 2 columns
    /// - 700-1000pt: 3 columns
    /// - 1000-1300pt: 4 columns
    /// - >= 1300pt: 5 columns
    /// Beyond 5 columns, cards just get wider
    ///
    /// DESIGN RATIONALE:
    /// Single column mode ensures cards have maximum width for comfortable note editing
    /// when the window is narrow. This prevents cramped text boxes and improves UX.
    ///
    /// FONT SIZE ADAPTATION:
    /// Thresholds scale with fontSizeMultiplier so that larger text triggers fewer columns
    /// at the same window width. This ensures cards remain readable and don't become cramped
    /// when text size increases. For example, at 1.5x text size, the 2-column threshold
    /// increases from 450pt to 675pt (450 * 1.5).
    private func getOverviewColumns(for width: CGFloat) -> [GridItem] {
        let columnCount: Int
        
        // Scale thresholds by font size multiplier
        // Larger text = higher thresholds = fewer columns at same width
        let multiplier = viewModel.fontSizeMultiplier
        let threshold1 = 450 * multiplier  // 1 column threshold
        let threshold2 = 700 * multiplier  // 2 column threshold
        let threshold3 = 1000 * multiplier // 3 column threshold
        let threshold4 = 1300 * multiplier // 4 column threshold
        
        if width < threshold1 {
            columnCount = 1  // Single column for narrow windows
        } else if width < threshold2 {
            columnCount = 2
        } else if width < threshold3 {
            columnCount = 3
        } else if width < threshold4 {
            columnCount = 4
        } else {
            columnCount = 5
        }
        
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }
    
    /// Creates a card for each Space in overview mode
    /// RESPONSIVE: Cards expand vertically with window height
    private func overviewSpaceCard(for space: SpaceDetector.SpaceInfo, availableHeight: CGFloat) -> some View {
        OverviewSpaceCardView(
            space: space,
            viewModel: viewModel,
            settings: settings,
            getSpaceEmoji: getSpaceEmoji,
            getSpaceName: getSpaceName,
            getSpaceOpacity: getSpaceOpacity,  // FEATURE: 5.5.8 - Pass opacity calculator
            availableHeight: availableHeight
        )
    }
    
    // MARK: - Helper Methods
    
    /// Scales a font size by the current font size multiplier
    /// This ensures consistent text scaling across the entire HUD
    /// - Parameter baseSize: The default font size (at 1.0x multiplier)
    /// - Returns: The scaled font size based on current multiplier
    private func scaledFontSize(_ baseSize: CGFloat) -> CGFloat {
        return baseSize * viewModel.fontSizeMultiplier
    }
    
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
        case .overview:
            // PHASE 4: Wide enough for 2-column grid
            return 600
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
        case .overview:
            // PHASE 4: Minimum for grid view
            return 400
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
        case .overview:
            // PHASE 4: Dynamic height based on number of Spaces
            // Each card can be 200-400pt tall (with generous note editor), 2 columns default, plus padding
            // Increased from 150pt to accommodate larger note editors (min 100pt + header/padding)
            let rows = CGFloat((viewModel.allSpaces.count + 1) / 2)
            let cardHeight: CGFloat = 250  // Increased to accommodate larger note editors
            let spacing: CGFloat = 12
            let padding: CGFloat = 24
            return min(rows * cardHeight + (rows - 1) * spacing + padding, 700)  // Increased max from 550 to 700
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
    
    /// Gets Space color (custom or nil for default)
    /// FEATURE 5.5.9: Returns custom color hex if set
    private func getSpaceColor(_ spaceNumber: Int) -> String? {
        return settings.spaceColors[spaceNumber]
    }
    
    /// Gets the accent color for the current Space
    /// FEATURE 5.5.9: Returns custom color or default blue
    private func getCurrentSpaceAccentColor() -> Color {
        let currentSpace = displayMode == .note ? (selectedNoteSpace ?? viewModel.currentSpaceNumber) : viewModel.currentSpaceNumber
        if let colorHex = getSpaceColor(currentSpace) {
            return settings.hexToColor(colorHex)
        }
        return Color.accentColor  // Default blue
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
    
    /// Gets opacity for a Space button based on visit recency
    ///
    /// FEATURE: 5.5.8 - Dim to Indicate Order (Visit Recency Visualization)
    ///
    /// When spaceOrderDimmingEnabled is true, buttons are dimmed based on
    /// how recently each Space was visited. This creates a visual "heat map"
    /// of your workflow.
    ///
    /// CALCULATION:
    /// - Current Space: 100% opacity (fully bright)
    /// - Last visited: Slightly dimmed (e.g., 95% opacity)
    /// - Older Spaces: Progressively more dimmed (down to minimum opacity)
    /// - Maximum dimming controlled by spaceOrderMaxDimLevel setting
    ///
    /// WHEN DISABLED:
    /// - All buttons have 100% opacity (no dimming)
    ///
    /// - Parameter spaceNumber: The Space number to get opacity for
    /// - Returns: Opacity value (0.0-1.0) where 1.0 is fully visible
    private func getSpaceOpacity(_ spaceNumber: Int) -> Double {
        // If dimming is disabled, return full opacity
        guard settings.spaceOrderDimmingEnabled else {
            return 1.0
        }
        
        // Get opacity from visit tracker
        let totalSpaces = viewModel.allSpaces.count
        return SpaceVisitTracker.shared.getOpacity(
            for: spaceNumber,
            maxDimLevel: settings.spaceOrderMaxDimLevel,
            totalSpaces: totalSpaces
        )
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
    
    /// Starts editing the Space name, emoji, and color
    /// FEATURE 5.5.9: Added color editing support
    private func startEditingSpaceName() {
        guard let spaceNumber = selectedNoteSpace else { return }
        
        isEditingSpaceName = true
        editingSpaceNameText = getSpaceName(spaceNumber) ?? ""
        editingSpaceEmoji = getSpaceEmoji(spaceNumber) ?? ""
        editingSpaceColor = getSpaceColor(spaceNumber) ?? ""  // Load current color
        
        // Focus the name field after a short delay to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    /// Saves the edited Space name, emoji, and color
    /// PHASE 2.2: Validates and enforces character limit
    /// FEATURE 5.5.9: Added color saving
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
        
        // Save color (FEATURE 5.5.9)
        let trimmedColor = editingSpaceColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            // Empty color: remove custom color, will use default blue
            settings.spaceColors.removeValue(forKey: spaceNumber)
        } else {
            settings.spaceColors[spaceNumber] = trimmedColor
        }
        
        isEditingSpaceName = false
    }
    
    /// Cancels Space name/emoji/color editing
    /// FEATURE 5.5.9: Added color clearing
    private func cancelSpaceNameEditing() {
        isEditingSpaceName = false
        editingSpaceNameText = ""
        editingSpaceEmoji = ""
        editingSpaceColor = ""  // Clear color editing state
    }
    
    /// Switches to a specific display mode
    /// FEATURE: Per-mode window size persistence
    /// Triggers window resize to restore the saved size for the target mode
    private func switchToMode(_ mode: DisplayMode) {
        guard displayMode != mode else { return }
        
        // Update display mode
        displayMode = mode
        
        // Trigger callback to resize window
        onModeChange?(mode)
    }
    
    /// Cycles through display modes (PHASE 4: Now 3 modes)
    /// DEPRECATED: Replaced by separate mode buttons, but kept for keyboard shortcuts if needed
    private func cycleDisplayMode() {
        switch displayMode {
        case .compact:
            switchToMode(.note)
        case .note:
            switchToMode(.overview)
        case .overview:
            switchToMode(.compact)
        }
    }
    
    /// Gets the icon for the current display mode toggle button
    private func getDisplayModeIcon() -> String {
        switch displayMode {
        case .compact:
            return "note.text"
        case .note:
            return "square.grid.2x2"
        case .overview:
            return "list.bullet"
        }
    }
    
    /// Gets the name of the next display mode for tooltip
    private func getNextDisplayModeName() -> String {
        switch displayMode {
        case .compact:
            return "Note Mode"
        case .note:
            return "Overview Mode"
        case .overview:
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
    
    // MARK: - Button Sizing (Phase 2.1)
    
    /// Calculates maximum button width based on longest Space name
    /// Ensures all buttons have equal width for clean, aligned appearance
    private func calculateMaxButtonWidth() -> CGFloat {
        var maxWidth: CGFloat = 100  // Minimum width
        
        // Iterate through all Spaces and measure their content
        for space in viewModel.allSpaces {
            let spaceNumber = space.index
            
            // Get name (custom or default)
            guard let name = getSpaceName(spaceNumber) else { continue }
            
            // Calculate width components:
            // - Number: ~20pt
            // - Emoji: ~20pt (if present)
            // - Name text: measured
            // - Note indicator: ~10pt (if present)
            // - Spacing: 6pt between each element
            // - Horizontal padding: removed (using frame width directly)
            
            let numberWidth: CGFloat = 20
            let emojiWidth: CGFloat = getSpaceEmoji(spaceNumber) != nil ? 20 : 0
            let noteWidth: CGFloat = hasNote(spaceNumber) ? 10 : 0
            let spacing: CGFloat = 6
            
            // Measure text width using NSString
            let font = NSFont.systemFont(ofSize: 12)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (name as NSString).size(withAttributes: attributes)
            let textWidth = ceil(textSize.width)
            
            // Calculate total width for this Space
            let totalWidth = numberWidth + emojiWidth + textWidth + noteWidth + (spacing * 3) + 20  // +20 for padding
            
            // Update max if this is wider
            if totalWidth > maxWidth {
                maxWidth = totalWidth
            }
        }
        
        // Cap at reasonable maximum
        return min(maxWidth, 200)
    }
    
    /// Updates button width when Space names or emojis change
    private func updateButtonWidth() {
        maxButtonWidth = calculateMaxButtonWidth()
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

// MARK: - Overview Space Card View (Separate component for proper state management)

/// Separate view for each Space card in overview mode
/// This ensures each TextEditor has its own stable state
///
/// CRITICAL FIX: Each card maintains its own @State for noteText and syncs with settings
/// This prevents SwiftUI from confusing state between multiple TextEditors in the LazyVGrid
/// RESPONSIVE DESIGN: Note editor expands vertically with window height (with minimum)
///
/// FEATURE: Double-click to edit Space name and emoji
/// Users can double-click the name/emoji area to enter edit mode with inline editing UI
struct OverviewSpaceCardView: View {
    let space: SpaceDetector.SpaceInfo
    @ObservedObject var viewModel: SuperSpacesViewModel
    @ObservedObject var settings: SettingsManager
    let getSpaceEmoji: (Int) -> String?
    let getSpaceName: (Int) -> String?
    let getSpaceOpacity: (Int) -> Double  // FEATURE: 5.5.8 - Opacity calculator
    let availableHeight: CGFloat
    
    // Local state for this card's note - this is the source of truth for the TextEditor
    @State private var noteText: String = ""
    @State private var saveTimer: Timer?
    
    // Track if we've initialized from settings
    @State private var hasInitialized = false
    
    // Editing state for Space name/emoji/color (FEATURE: Double-click to edit)
    // FEATURE 5.5.9: Added color editing
    @State private var isEditingSpaceName = false
    @State private var editingSpaceNameText: String = ""
    @State private var editingSpaceEmoji: String = ""
    @State private var editingSpaceColor: String = ""  // Color editing state
    @FocusState private var isNameFieldFocused: Bool
    
    // Show emoji and color picker popovers
    @State private var showEmojiPicker = false
    @State private var showColorPicker = false  // FEATURE 5.5.9
    
    /// Scales a font size by the current font size multiplier
    /// This ensures consistent text scaling across the entire HUD
    private func scaledFontSize(_ baseSize: CGFloat) -> CGFloat {
        return baseSize * viewModel.fontSizeMultiplier
    }
    
    /// Gets the Space color (FEATURE 5.5.9)
    private func getSpaceColor() -> String? {
        return settings.spaceColors[space.index]
    }
    
    /// Gets the accent color for this Space (FEATURE 5.5.9)
    private func getSpaceAccentColor() -> Color {
        if let colorHex = getSpaceColor() {
            return settings.hexToColor(colorHex)
        }
        return Color.accentColor  // Default blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Emoji, name, switch button
            // FEATURE: Double-click to edit name and emoji
            // DESIGN CHANGE: Desktop number moved to note background watermark
            if isEditingSpaceName {
                // EDITING MODE: Inline editor for name and emoji
                editingHeaderView
            } else {
                // DISPLAY MODE: Show name/emoji with double-click to edit
                displayHeaderView
            }
            
            Divider()
            
            // Note editor (inline, always visible)
            // RESPONSIVE: Expands vertically with window height
            // DESIGN: Desktop number displayed as large watermark in background
            VStack(alignment: .leading, spacing: 4) {
                Text("Note")
                    .font(.system(size: scaledFontSize(9), weight: .medium))
                    .foregroundColor(.secondary)
                
                // Use ZStack for proper placeholder positioning
                // RESPONSIVE: Calculate height based on available space
                // Minimum 100pt, max 300pt, expands to fill available vertical space in the grid
                // Account for header (40pt) + divider (9pt) + note label (13pt) + padding (20pt) + card padding (20pt)
                //
                // DESIGN RATIONALE:
                // - Minimum 100pt ensures comfortable multi-line note editing
                // - Maximum 300pt prevents cards from becoming too tall and unwieldy
                // - Generous max height allows for longer notes without scrolling
                let minNoteHeight: CGFloat = 100
                let maxNoteHeight: CGFloat = 300
                let fixedCardHeight: CGFloat = 40 + 9 + 13 + 20 + 20
                let calculatedHeight = min(maxNoteHeight, max(minNoteHeight, (availableHeight / 2) - fixedCardHeight))
                
                ZStack(alignment: .topLeading) {
                    // BACKGROUND WATERMARK: Large desktop number
                    // Positioned behind the text editor as a subtle visual indicator
                    // This replaces the number badge in the header for a cleaner look
                    Text("\(space.index)")
                        .font(.system(size: scaledFontSize(80), weight: .black))
                        .foregroundColor(.secondary.opacity(0.08))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.top, 10)
                    
                    // TextEditor with local state
                    // CRITICAL: Using id() to force SwiftUI to create a unique TextEditor instance
                    TextEditor(text: $noteText)
                        .font(.system(size: scaledFontSize(11)))
                        .frame(height: calculatedHeight)
                        .padding(6)  // Internal padding for text content
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)  // Transparent to show watermark
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .id("note-editor-\(space.index)")  // Unique ID per Space
                        .onChange(of: noteText) { newValue in
                            // Debounced save to settings
                            saveTimer?.invalidate()
                            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                if newValue.isEmpty {
                                    settings.spaceNotes.removeValue(forKey: space.index)
                                } else {
                                    settings.spaceNotes[space.index] = newValue
                                }
                            }
                        }
                    
                    // Placeholder when empty
                    // Position to match TextEditor's cursor position
                    if noteText.isEmpty {
                        Text("Add note...")
                            .font(.system(size: scaledFontSize(11)))
                            .foregroundColor(.secondary)
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    // FEATURE 5.5.9: Use Space's custom color or default
                    space.index == viewModel.currentSpaceNumber ?
                        getSpaceAccentColor().opacity(0.1) : Color.secondary.opacity(0.05)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    // FEATURE 5.5.9: Use Space's custom color for border
                    space.index == viewModel.currentSpaceNumber ?
                        getSpaceAccentColor().opacity(0.3) : Color.clear,
                    lineWidth: 2
                )
        )
        .onAppear {
            // Load note from settings when card appears (only once)
            if !hasInitialized {
                noteText = settings.spaceNotes[space.index] ?? ""
                hasInitialized = true
            }
        }
        .onChange(of: settings.spaceNotes[space.index]) { newValue in
            // Sync from settings if changed externally (but not during our own saves)
            if hasInitialized && noteText != (newValue ?? "") {
                noteText = newValue ?? ""
            }
        }
        .opacity(getSpaceOpacity(space.index))  // FEATURE: 5.5.8 - Dim to Indicate Order
        // Emoji picker popover
        .popover(
            isPresented: $showEmojiPicker,
            arrowEdge: .bottom
        ) {
            SuperSpacesEmojiPicker(
                spaceNumber: space.index,
                selectedEmoji: Binding(
                    get: { editingSpaceEmoji.isEmpty ? nil : editingSpaceEmoji },
                    set: { newEmoji in
                        editingSpaceEmoji = newEmoji ?? ""
                    }
                ),
                onEmojiSelected: { emoji in
                    editingSpaceEmoji = emoji ?? ""
                    showEmojiPicker = false
                    // Auto-focus name field after emoji selection
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNameFieldFocused = true
                    }
                }
            )
        }
        // Color picker popover (FEATURE 5.5.9)
        .popover(
            isPresented: $showColorPicker,
            arrowEdge: .bottom
        ) {
            SuperSpacesColorPicker(
                spaceNumber: space.index,
                selectedColorHex: Binding(
                    get: { editingSpaceColor.isEmpty ? nil : editingSpaceColor },
                    set: { newColor in
                        editingSpaceColor = newColor ?? ""
                    }
                ),
                onColorSelected: { color in
                    editingSpaceColor = color ?? ""
                    showColorPicker = false
                    // Auto-focus name field after color selection
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNameFieldFocused = true
                    }
                }
            )
            .environmentObject(settings)
        }
    }
    
    // MARK: - Header Views
    
    /// Display mode header: Shows name/emoji with click to switch, edit button to edit
    /// DESIGN: Desktop number removed from header, now shown as watermark in note background
    /// UX IMPROVEMENT: Single click on name/emoji bar switches to that Space (larger clickable area)
    /// Arrow button becomes an edit button to enter editing mode
    private var displayHeaderView: some View {
        HStack(spacing: 8) {
            // Emoji and Name - CLICKABLE BAR to switch to this Space
            // DESIGN: Expanded to fill more space since number badge is removed
            // UX: Entire bar is clickable for easy Space switching
            Button(action: {
                viewModel.switchToSpace(space.index)
            }) {
                HStack(spacing: 6) {
                    // Emoji
                    if let emoji = getSpaceEmoji(space.index), !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: scaledFontSize(18)))
                    } else {
                        Text("➕")
                            .font(.system(size: scaledFontSize(16)))
                            .foregroundColor(.secondary)
                    }
                    
                    // Name
                    Text(getSpaceName(space.index) ?? "Unnamed")
                        .font(.system(size: scaledFontSize(13), weight: .medium))
                        .foregroundColor(getSpaceName(space.index) == nil ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .contentShape(Rectangle())  // Make entire area clickable
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    // Highlight current Space with accent color
                    space.index == viewModel.currentSpaceNumber ?
                        Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05)
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Click to switch to Space \(space.index)")
            
            // Edit button (replaces arrow button)
            // DESIGN: Pencil icon clearly indicates editing functionality
            Button(action: {
                startEditingSpaceName()
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: scaledFontSize(18)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit name and emoji")
        }
    }
    
    /// Editing mode header: Inline editor for name and emoji
    /// DESIGN: Desktop number visible in note background watermark during editing
    private var editingHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Editing label and cancel button
            HStack {
                Text("Editing")
                    .font(.system(size: scaledFontSize(11), weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Cancel button
                Button(action: cancelSpaceNameEditing) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scaledFontSize(16)))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel (Esc)")
            }
            
            // Emoji, color, and name editing fields
            // FEATURE 5.5.9: Added color picker button
            HStack(spacing: 6) {
                // Emoji button (visual picker)
                Button(action: {
                    showEmojiPicker = true
                }) {
                    HStack {
                        if editingSpaceEmoji.isEmpty {
                            Image(systemName: "face.smiling")
                                .font(.system(size: scaledFontSize(16)))
                                .foregroundColor(.secondary)
                        } else {
                            Text(editingSpaceEmoji)
                                .font(.system(size: scaledFontSize(18)))
                        }
                    }
                    .frame(width: 44, height: 32)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showEmojiPicker ? getSpaceAccentColor() : Color.secondary.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .help("Click to choose emoji")
                
                // Color button (FEATURE 5.5.9: Color picker)
                Button(action: {
                    showColorPicker = true
                }) {
                    HStack {
                        if editingSpaceColor.isEmpty {
                            Image(systemName: "paintpalette")
                                .font(.system(size: scaledFontSize(16)))
                                .foregroundColor(.secondary)
                        } else {
                            // Show color swatch
                            RoundedRectangle(cornerRadius: 4)
                                .fill(settings.hexToColor(editingSpaceColor))
                                .frame(width: 24, height: 24)
                        }
                    }
                    .frame(width: 44, height: 32)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showColorPicker ? getSpaceAccentColor() : Color.secondary.opacity(0.3), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .help("Click to choose color")
                
                // Name field
                TextField("Space Name", text: $editingSpaceNameText)
                    .font(.system(size: scaledFontSize(12)))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                editingSpaceNameText.count > settings.maxSpaceNameLength ? Color.red : getSpaceAccentColor(),
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
                    .onChange(of: isNameFieldFocused) { isFocused in
                        // FEATURE: Auto-save when clicking off the name field
                        // When the field loses focus (isFocused becomes false), save the changes
                        // This provides a more intuitive UX where users don't need to explicitly
                        // click the save button - just clicking elsewhere saves automatically
                        if !isFocused && isEditingSpaceName {
                            saveSpaceNameAndEmoji()
                        }
                    }
                
                // Save button
                Button(action: saveSpaceNameAndEmoji) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: scaledFontSize(16)))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Save (Enter)")
            }
            
            // Character counter
            HStack {
                Spacer()
                Text("\(editingSpaceNameText.count)/\(settings.maxSpaceNameLength)")
                    .font(.system(size: scaledFontSize(9)))
                    .foregroundColor(
                        editingSpaceNameText.count > settings.maxSpaceNameLength - 5 ?
                            (editingSpaceNameText.count >= settings.maxSpaceNameLength ? .red : .orange) :
                            .secondary
                    )
            }
        }
    }
    
    // MARK: - Editing Actions
    
    /// Starts editing the Space name, emoji, and color
    /// FEATURE 5.5.9: Added color editing support
    private func startEditingSpaceName() {
        isEditingSpaceName = true
        editingSpaceNameText = getSpaceName(space.index) ?? ""
        editingSpaceEmoji = getSpaceEmoji(space.index) ?? ""
        editingSpaceColor = getSpaceColor() ?? ""  // Load current color
        
        // Focus the name field after a short delay to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    /// Saves the edited Space name, emoji, and color
    /// FEATURE 5.5.9: Added color saving
    private func saveSpaceNameAndEmoji() {
        // Validate and save name with character limit
        let trimmedName = editingSpaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            // Empty name: remove custom name, will show default
            settings.spaceNames.removeValue(forKey: space.index)
        } else {
            // Validate and truncate to character limit
            let validatedName = settings.validateSpaceName(trimmedName)
            settings.spaceNames[space.index] = validatedName
        }
        
        // Save emoji (limit to first 2 characters to handle multi-byte emojis)
        let trimmedEmoji = String(editingSpaceEmoji.prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmoji.isEmpty {
            // Empty emoji: remove custom emoji, will show default
            settings.spaceEmojis.removeValue(forKey: space.index)
        } else {
            settings.spaceEmojis[space.index] = trimmedEmoji
        }
        
        // Save color (FEATURE 5.5.9)
        let trimmedColor = editingSpaceColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            // Empty color: remove custom color, will use default blue
            settings.spaceColors.removeValue(forKey: space.index)
        } else {
            settings.spaceColors[space.index] = trimmedColor
        }
        
        isEditingSpaceName = false
    }
    
    /// Cancels Space name/emoji/color editing
    /// FEATURE 5.5.9: Added color clearing
    private func cancelSpaceNameEditing() {
        isEditingSpaceName = false
        editingSpaceNameText = ""
        editingSpaceEmoji = ""
        editingSpaceColor = ""  // Clear color editing state
    }
}
