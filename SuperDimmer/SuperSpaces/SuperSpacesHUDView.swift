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
    
    /// Currently hovered Space UUID (for hover effects)
    /// MIGRATION (Feb 11, 2026): Changed from Int to String (UUID) for reorder resilience
    @State private var hoveredSpace: String?
    
    /// Settings manager for accessing Space customizations
    @EnvironmentObject var settings: SettingsManager
    
    /// Display modes for the HUD
    enum DisplayMode {
        case compact    // Compact: Numbered buttons with emoji/name in a row
        case note       // Note mode: Persistent note editor with Space selector and inline editing
        case overview   // Overview: Grid showing all Spaces with notes, all editable (PHASE 4)
    }
    
    /// Space UUID whose note is currently being viewed/edited in note mode
    /// MIGRATION (Feb 11, 2026): Changed from Int to String (UUID) for reorder resilience
    /// When the user selects a space in note mode, we store its UUID so the note stays
    /// associated with the correct space even if the user reorders spaces later.
    @State private var selectedNoteSpace: String?
    
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
    /// MIGRATION (Feb 11, 2026): Changed from Int to String (UUID) for reorder resilience
    @State private var emojiPickerForSpace: String?
    
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
                
                // Color overlay tint — INCREASED from 5% to 15% (Feb 18, 2026)
                // User requested more intense hue so the desktop color is immediately obvious
                // at a glance. 15% gives a clear tint without overwhelming the blur material.
                getCurrentSpaceAccentColor()
                    .opacity(0.15)
            }
            .cornerRadius(12)
            
            // Content
            // COMPACT MODE REDESIGN (Feb 13, 2026):
            // In compact mode, we collapse everything into a single row.
            // No header, no divider, no "Space X" text at top left.
            // Just the space buttons + control buttons in one horizontal strip.
            // The ACTIVE space is expanded to show its full name (not truncated).
            // Inactive spaces stay compact (number + emoji only, or just number).
            // This was requested by the user to reduce visual clutter and make
            // the HUD feel like a minimal, polished space switcher bar.
            if displayMode == .compact {
                compactSingleRowView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    // Header: Current Space info and controls (only for note/overview modes)
                    headerView
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Space grid/list (varies by display mode)
                    spacesView
                }
                .padding(16)
            }
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
            // Load display mode from view model (per-HUD setting)
            // ARCHITECTURE CHANGE (Jan 23, 2026):
            // Previously loaded from global settings.superSpacesDisplayMode
            // Now each HUD maintains its own mode via viewModel.currentDisplayModeString
            displayMode = displayModeFromString(viewModel.currentDisplayModeString)
            
            // Calculate initial button width (PHASE 2.1)
            updateButtonWidth()
        }
        .onChange(of: viewModel.currentDisplayModeString) { newValue in
            // Sync when view model changes (from HUD instance)
            displayMode = displayModeFromString(newValue)
        }
        .onChange(of: displayMode) { newValue in
            // Notify HUD instance when mode changes in UI
            // This triggers per-HUD save instead of global settings save
            let modeString = displayModeToString(newValue)
            viewModel.currentDisplayModeString = modeString
            viewModel.onDisplayModeChange?(modeString)
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
        // BUG FIX (Feb 17, 2026): Sync note mode noteText from external changes
        //
        // PROBLEM: When user edits notes in the grid/overview mode HUD, the note mode
        // HUD has a stale local @State noteText that never gets updated. On the next
        // space change, the note mode's .onChange handler (below) would save the stale
        // noteText to settings, OVERWRITING the fresh grid edits. This caused total
        // note loss: 5+ minutes of typing wiped out on a single desktop switch.
        //
        // SOLUTION: Watch settings.spaceNotes and sync noteText whenever the selected
        // space's note changes externally. This keeps the note mode in sync with edits
        // made in any other HUD mode (grid/overview), so when space change triggers
        // a save, it saves the CORRECT text instead of stale text.
        //
        // WHY THIS IS NEEDED:
        // - Multiple HUD instances can exist (note mode + overview mode simultaneously)
        // - Each HUD has its own @State noteText that's only updated by local typing
        // - Without this sync, note mode's noteText diverges from settings when grid edits
        // - The space change handler then blindly saves the diverged (stale) text
        .onChange(of: settings.spaceNotes) { newNotes in
            if displayMode == .note, let spaceUUID = selectedNoteSpace {
                let settingsNote = newNotes[spaceUUID] ?? ""
                if noteText != settingsNote {
                    noteText = settingsNote
                }
            }
        }
        // NOTE FOLLOWS CURRENT SPACE (Feb 11, 2026)
        // When the user switches macOS Spaces and the "follow" toggle is on,
        // automatically update the note mode to show the new Space's note.
        // This only triggers when:
        //   1. We're in note mode (.note display mode)
        //   2. The user has the "follows current space" setting enabled
        // Without this, the note stays pinned to whichever Space was manually selected.
        //
        // BUG FIX (Feb 17, 2026): Changed save logic to prevent cross-HUD data loss.
        // Previously: Always saved noteText on space change, even if it was stale.
        // Now: Flushes the debounce timer and only saves if noteText actually differs
        // from what's already in settings (meaning we have unsaved LOCAL edits).
        // Combined with the .onChange(of: settings.spaceNotes) sync above, this ensures
        // we never overwrite fresh grid edits with stale note mode text.
        .onChange(of: viewModel.currentSpaceNumber) { newSpaceNumber in
            if displayMode == .note && settings.noteFollowsCurrentSpace {
                // Flush any pending debounced save timer to prevent losing the last 0.5s of typing
                noteSaveTimer?.invalidate()
                
                // Only save if we have UNSAVED local edits (noteText differs from settings)
                // This prevents overwriting external edits (e.g., from grid/overview mode)
                // with stale text that was loaded earlier but never edited locally.
                // Thanks to the .onChange(of: settings.spaceNotes) sync above, noteText
                // stays in sync with grid edits, so this check correctly skips saving
                // when the user was editing in grid mode instead of note mode.
                if let currentSpace = selectedNoteSpace {
                    let settingsNote = settings.spaceNotes[currentSpace] ?? ""
                    if noteText != settingsNote {
                        saveNoteForSpace(currentSpace, text: noteText)
                    }
                }
                // MIGRATION (Feb 11, 2026): Look up UUID for the new space number
                // selectedNoteSpace is now UUID-based for reorder resilience
                if let spaceUUID = viewModel.allSpaces.first(where: { $0.index == newSpaceNumber })?.uuid {
                    selectedNoteSpace = spaceUUID
                    loadNoteForSpace(spaceUUID)
                }
            }
        }
        // Emoji picker popover (context menu)
        // MIGRATION (Feb 11, 2026): emojiPickerForSpace is now UUID
        .popover(
            isPresented: $showEmojiPicker,
            arrowEdge: .bottom
        ) {
            if let spaceUUID = emojiPickerForSpace {
                let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index ?? 1
                SuperSpacesEmojiPicker(
                    spaceNumber: spaceIndex,
                    selectedEmoji: Binding(
                        get: { getSpaceEmoji(spaceUUID, spaceIndex: spaceIndex) },
                        set: { newEmoji in
                            if let emoji = newEmoji {
                                settings.spaceEmojis[spaceUUID] = emoji
                            } else {
                                settings.spaceEmojis.removeValue(forKey: spaceUUID)
                            }
                        }
                    ),
                    onEmojiSelected: { emoji in
                        if let emoji = emoji {
                            settings.spaceEmojis[spaceUUID] = emoji
                        } else {
                            settings.spaceEmojis.removeValue(forKey: spaceUUID)
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
            if let spaceUUID = selectedNoteSpace {
                let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index ?? 1
                SuperSpacesEmojiPicker(
                    spaceNumber: spaceIndex,
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
        // MIGRATION (Feb 11, 2026): selectedNoteSpace is now UUID
        .popover(
            isPresented: $showColorPicker,
            arrowEdge: .bottom
        ) {
            if let spaceUUID = selectedNoteSpace {
                let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index ?? 1
                SuperSpacesColorPicker(
                    spaceNumber: spaceIndex,
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
            // MIGRATION (Feb 11, 2026): selectedNoteSpace is now UUID, need to resolve to index for display
            HStack(spacing: 8) {
                // Resolve the display space number and UUID
                let displaySpaceUUID: String? = displayMode == .note ? selectedNoteSpace : viewModel.allSpaces.first(where: { $0.index == viewModel.currentSpaceNumber })?.uuid
                let displaySpaceIndex: Int = {
                    if displayMode == .note, let uuid = selectedNoteSpace {
                        return viewModel.allSpaces.first(where: { $0.uuid == uuid })?.index ?? viewModel.currentSpaceNumber
                    }
                    return viewModel.currentSpaceNumber
                }()
                
                // Emoji if set (looked up by UUID)
                if let uuid = displaySpaceUUID, let emoji = getSpaceEmoji(uuid, spaceIndex: displaySpaceIndex) {
                    Text(emoji)
                        .font(.system(size: scaledFontSize(16)))
                } else {
                    Image(systemName: displayMode == .note ? "note.text" : "square.grid.3x3")
                        .font(.system(size: scaledFontSize(16)))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Space \(displaySpaceIndex)")
                        .font(.system(size: scaledFontSize(14), weight: .semibold))
                    
                    if let uuid = displaySpaceUUID, let spaceName = getSpaceName(uuid, spaceIndex: displaySpaceIndex) {
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
                .focusEffectDisabled()  // Disable focus ring/outline on click
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
                .focusEffectDisabled()  // Disable focus ring/outline on click
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
                .focusEffectDisabled()  // Disable focus ring/outline on click
                .help("Overview Mode")
            }
            .padding(3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            
            // Copy button - Duplicates the HUD (Jan 23, 2026)
            // Creates a new HUD instance with the same settings but offset position
            // This allows users to have multiple HUDs open simultaneously for monitoring different Spaces
            Button(action: {
                viewModel.duplicateHUD()
            }) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: scaledFontSize(14)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()  // Disable focus ring/outline on click
            .help("Duplicate HUD")
            
            // Settings button (moved from footer)
            Button(action: {
                showQuickSettings.toggle()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: scaledFontSize(14)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()  // Disable focus ring/outline on click
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
            .focusEffectDisabled()  // Disable focus ring/outline on click
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
    
    // MARK: - Compact Single Row View (Feb 13, 2026)
    // REDESIGN: Entire compact HUD is now ONE horizontal row.
    // No header, no "Space X" label, no divider. Just:
    //   [space1] [space2] [ACTIVE SPACE expanded] [space4] ... [controls]
    // The active space expands to show its full name (never truncated).
    // Inactive spaces show number + emoji (or just number if no emoji).
    // Control buttons (mode switcher, duplicate, settings, close) sit at the end.
    // This makes the HUD feel like a sleek macOS-native space switcher bar.
    
    private var compactSingleRowView: some View {
        HStack(spacing: 6) {
            // GeometryReader to measure available width for adaptive button sizing.
            // This is the same pattern used by noteDisplayView - we measure the space
            // available for buttons and decide how much info to show per button.
            // When the HUD is wide: all buttons show number + emoji + name.
            // When narrow: inactive buttons contract to number + emoji, or just number.
            // The ACTIVE space always shows its full name regardless of width.
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.allSpaces, id: \.uuid) { space in
                            compactSingleRowSpaceButton(
                                for: space,
                                availableWidth: geometry.size.width
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            
            // Thin vertical separator between spaces and controls
            Divider()
                .frame(height: 24)
                .padding(.horizontal, 2)
            
            // Inline control buttons (mode switcher + utility buttons)
            compactInlineControls
        }
    }
    
    /// Determines the display mode for INACTIVE buttons in the compact single-row layout.
    /// Uses the same adaptive logic as the NoteButtonMode system:
    /// - Measures available width, subtracts the space taken by the active button + controls,
    ///   then divides remaining width among inactive buttons to decide their expansion level.
    /// - .compact: Number only (very narrow)
    /// - .medium: Number + emoji
    /// - .expanded: Number + emoji + name (wide window)
    ///
    /// The ACTIVE space is always fully expanded (not counted in this calculation)
    /// because it always shows its full name to identify the current space.
    private func getCompactInactiveButtonMode(availableWidth: CGFloat) -> NoteButtonMode {
        let spaceCount = CGFloat(viewModel.allSpaces.count)
        guard spaceCount > 1 else { return .expanded }
        
        let inactiveCount = spaceCount - 1  // Active space is handled separately
        let spacing: CGFloat = 6
        let padding: CGFloat = 4
        // Estimate active button width (~140pt for number + emoji + full name)
        let activeButtonEstimate: CGFloat = 140
        let totalSpacing = (spaceCount - 1) * spacing + padding * 2
        let availableForInactive = availableWidth - totalSpacing - activeButtonEstimate
        let spacePerButton = availableForInactive / inactiveCount
        
        // Thresholds: same philosophy as getNoteButtonMode, prefer showing more info.
        // When the window is wide enough, show everything. User can always resize.
        if spacePerButton >= 70 {
            return .expanded  // Number + emoji + name
        } else if spacePerButton >= 45 {
            return .medium    // Number + emoji
        } else {
            return .compact   // Number only
        }
    }
    
    /// A single space button for the compact single-row layout.
    ///
    /// ADAPTIVE BEHAVIOR (restored Feb 13, 2026):
    /// - ACTIVE space: ALWAYS shows number + emoji + full name (never truncated).
    ///   This is the key visual indicator of which space you're on.
    /// - INACTIVE spaces: Adapt based on available width.
    ///   Wide window → number + emoji + name (all buttons look like the original).
    ///   Medium window → number + emoji only.
    ///   Narrow window → number only.
    ///   This matches the original adaptive sizing behavior the user liked,
    ///   while ensuring the active space is always expanded for clarity.
    private func compactSingleRowSpaceButton(for space: SpaceDetector.SpaceInfo, availableWidth: CGFloat) -> some View {
        let isActive = space.index == viewModel.currentSpaceNumber
        let inactiveMode = getCompactInactiveButtonMode(availableWidth: availableWidth)
        
        return Button(action: {
            handleSpaceClick(space.index)
        }) {
            HStack(spacing: 5) {
                // Space number (always shown)
                Text("\(space.index)")
                    .font(.system(size: scaledFontSize(12), weight: isActive ? .bold : .semibold))
                    .frame(minWidth: 14)
                
                // Emoji: shown for active always, for inactive when mode >= .medium
                if isActive || inactiveMode != .compact {
                    if let emoji = getSpaceEmoji(space.uuid, spaceIndex: space.index) {
                        Text(emoji)
                            .font(.system(size: scaledFontSize(13)))
                    }
                }
                
                // Name: Active space ALWAYS shows full name (fixedSize, no truncation).
                // Inactive spaces show name only when mode is .expanded (wide window).
                // This gives the "expand when wide, contract when narrow" behavior
                // the user wanted, while the active space is always prominent.
                if isActive {
                    if let name = getSpaceName(space.uuid, spaceIndex: space.index), !name.isEmpty {
                        Text(name)
                            .font(.system(size: scaledFontSize(12), weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                } else if inactiveMode == .expanded {
                    if let name = getSpaceName(space.uuid, spaceIndex: space.index), !name.isEmpty {
                        Text(name)
                            .font(.system(size: scaledFontSize(12)))
                            .lineLimit(1)
                    }
                }
                
                // Note indicator dot
                if hasNote(space.uuid) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, isActive ? 12 : 8)
            .padding(.vertical, 7)
            .background(
                // FEATURE 5.5.9: Color-coded backgrounds per space.
                // Active: full color. Inactive: faded (20% opacity).
                getSpaceBackgroundColor(space.uuid, spaceIndex: space.index, isActive: isActive)
            )
            .foregroundColor(
                isActive ? .white : .primary
            )
            .cornerRadius(8)
            // FEATURE 5.5.8: Visit recency dimming overlay
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(getSpaceDimmingOverlayOpacity(space.uuid)))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(getSpaceTooltip(space.index))
    }
    
    /// Inline control buttons for the compact single-row layout.
    /// These sit at the right end of the row: [mode switcher] [duplicate] [settings] [close]
    /// Kept small and unobtrusive so the space buttons are the visual focus.
    private var compactInlineControls: some View {
        HStack(spacing: 3) {
            // Display mode buttons (compact / note / overview)
            HStack(spacing: 2) {
                Button(action: { switchToMode(.compact) }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: scaledFontSize(10)))
                        .foregroundColor(displayMode == .compact ? .white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(displayMode == .compact ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Compact Mode")
                
                Button(action: { switchToMode(.note) }) {
                    Image(systemName: "note.text")
                        .font(.system(size: scaledFontSize(10)))
                        .foregroundColor(displayMode == .note ? .white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(displayMode == .note ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Note Mode")
                
                Button(action: { switchToMode(.overview) }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: scaledFontSize(10)))
                        .foregroundColor(displayMode == .overview ? .white : .secondary)
                        .frame(width: 20, height: 18)
                        .background(displayMode == .overview ? getCurrentSpaceAccentColor() : Color.clear)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Overview Mode")
            }
            .padding(2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(5)
            
            // Duplicate HUD button
            Button(action: { viewModel.duplicateHUD() }) {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: scaledFontSize(12)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Duplicate HUD")
            
            // Settings button
            Button(action: { showQuickSettings.toggle() }) {
                Image(systemName: "gear")
                    .font(.system(size: scaledFontSize(12)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Settings")
            .popover(isPresented: $showQuickSettings, arrowEdge: .bottom) {
                SuperSpacesQuickSettings(viewModel: viewModel)
                    .environmentObject(settings)
            }
            
            // Close button
            Button(action: { viewModel.closeHUD() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: scaledFontSize(12)))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Close (Esc)")
        }
    }
    
    /// Compact display mode: Numbered buttons with emoji and name in a scrollable row
    /// NOTE: This is the OLD compact view, kept for reference but replaced by compactSingleRowView.
    /// The spacesView switch still references this for backward compat but compact mode
    /// now uses compactSingleRowView directly from the body.
    private var compactSpacesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.allSpaces, id: \.uuid) { space in
                    compactSpaceButton(for: space)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    /// Creates a compact Space button with number, emoji, and name
    /// NOTE: This is the OLD compact button, kept for backward compat.
    /// The new single-row layout uses compactSingleRowSpaceButton instead.
    private func compactSpaceButton(for space: SpaceDetector.SpaceInfo) -> some View {
        Button(action: {
            handleSpaceClick(space.index)
        }) {
            HStack(spacing: 6) {
                Text("\(space.index)")
                    .font(.system(size: scaledFontSize(12), weight: .semibold))
                    .frame(width: 20)
                
                if let emoji = getSpaceEmoji(space.uuid, spaceIndex: space.index) {
                    Text(emoji)
                        .font(.system(size: scaledFontSize(14)))
                }
                
                if let name = getSpaceName(space.uuid, spaceIndex: space.index), !name.isEmpty {
                    Text(name)
                        .font(.system(size: scaledFontSize(12)))
                        .lineLimit(1)
                }
                
                if hasNote(space.uuid) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: maxButtonWidth)
            .padding(.vertical, 8)
            .background(
                getSpaceBackgroundColor(space.uuid, spaceIndex: space.index, isActive: space.index == viewModel.currentSpaceNumber)
            )
            .foregroundColor(
                space.index == viewModel.currentSpaceNumber ? .white : .primary
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(getSpaceDimmingOverlayOpacity(space.uuid)))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(getSpaceTooltip(space.index))
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
                            // MIGRATION (Feb 11, 2026): Use UUID for identity (stable across reorders)
                            ForEach(viewModel.allSpaces, id: \.uuid) { space in
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
                // MIGRATION (Feb 11, 2026): selectedNoteSpace is now UUID
                if let spaceUUID = selectedNoteSpace {
                    let spaceNumber = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index ?? 1
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
                            // MIGRATION (Feb 11, 2026): Use UUID for data lookups
                            HStack(spacing: 8) {
                                // Emoji display (UUID lookup)
                                if let emoji = getSpaceEmoji(spaceUUID, spaceIndex: spaceNumber), !emoji.isEmpty {
                                    Text(emoji)
                                        .font(.system(size: scaledFontSize(20)))
                                } else {
                                    Text("➕")
                                        .font(.system(size: scaledFontSize(16)))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Name display (UUID lookup)
                                Text(getSpaceName(spaceUUID, spaceIndex: spaceNumber) ?? "Unnamed Space")
                                    .font(.system(size: scaledFontSize(14), weight: .medium))
                                    .foregroundColor(getSpaceName(spaceUUID, spaceIndex: spaceNumber) == nil ? .secondary : .primary)
                                
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
                    // Note header with follow-space toggle
                    HStack(spacing: 6) {
                        Text("Note")
                            .font(.system(size: scaledFontSize(11), weight: .medium))
                            .foregroundColor(.secondary)
                        
                        // FOLLOW CURRENT SPACE TOGGLE (Feb 11, 2026)
                        // Placed in the note header so it's always visible regardless of window height.
                        // The bottom action buttons can get pushed offscreen when the window is short,
                        // so this toggle lives up here where users can always see and reach it.
                        //
                        // BEHAVIOR:
                        // When enabled, the note automatically switches to show the current Space's note
                        // whenever the user changes macOS Spaces (via Mission Control, trackpad, keyboard).
                        // When disabled, the note stays pinned to whichever Space was manually selected
                        // via the Space selector buttons above - useful for referencing one Space's notes
                        // while working in a different Space.
                        //
                        // ICON RATIONALE:
                        // - "pin.fill" when following is OFF (note is "pinned" to a specific Space)
                        // - "arrow.triangle.2.circlepath" when following is ON (note follows/cycles with Spaces)
                        // The filled pin is a strong visual cue that the note won't move.
                        //
                        // CLICK TARGET:
                        // Using contentShape(Rectangle()) to ensure the entire pill area is clickable,
                        // not just the small icon. Critical for usability since SF Symbols have tiny hit areas.
                        Button(action: {
                            settings.noteFollowsCurrentSpace.toggle()
                            
                            // When turning follow ON, immediately snap to the current Space's note
                            // so the user sees the effect right away instead of waiting for the next
                            // Space switch to trigger
                            if settings.noteFollowsCurrentSpace {
                                if let currentSpace = selectedNoteSpace {
                                    saveNoteForSpace(currentSpace, text: noteText)
                                }
                                // MIGRATION (Feb 11, 2026): Look up UUID for current space
                                if let spaceUUID = viewModel.allSpaces.first(where: { $0.index == viewModel.currentSpaceNumber })?.uuid {
                                    selectedNoteSpace = spaceUUID
                                    loadNoteForSpace(spaceUUID)
                                }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: settings.noteFollowsCurrentSpace
                                      ? "arrow.triangle.2.circlepath"
                                      : "pin.fill")
                                    .font(.system(size: scaledFontSize(9)))
                                Text(settings.noteFollowsCurrentSpace ? "Follows Space" : "Pinned")
                                    .font(.system(size: scaledFontSize(9)))
                            }
                            .foregroundColor(settings.noteFollowsCurrentSpace ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            settings.noteFollowsCurrentSpace
                                ? Color.accentColor.opacity(0.1)
                                : Color.secondary.opacity(0.08)
                        )
                        .cornerRadius(4)
                        .help(settings.noteFollowsCurrentSpace
                              ? "Note follows current Space. Click to pin to this Space."
                              : "Note is pinned. Click to follow current Space.")
                        
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
                            // MIGRATION (Feb 11, 2026): selectedNoteSpace is UUID, need index for switching
                            if let spaceUUID = selectedNoteSpace,
                               let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index {
                                viewModel.switchToSpace(spaceIndex)
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
            // MIGRATION (Feb 11, 2026): Use UUID for selectedNoteSpace
            if selectedNoteSpace == nil {
                if let spaceUUID = viewModel.allSpaces.first(where: { $0.index == viewModel.currentSpaceNumber })?.uuid {
                    selectedNoteSpace = spaceUUID
                    loadNoteForSpace(spaceUUID)
                }
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
    /// MIGRATION (Feb 11, 2026): Uses space.uuid for all data lookups, space.index for display
    ///
    /// ACTIVE DESKTOP EXPANSION (Feb 17, 2026):
    /// The ACTIVE desktop (currentSpaceNumber) now ALWAYS shows its full name, matching
    /// the compact single-row view behavior. This gives the user a clear visual indicator
    /// of which space they're currently on, even when the window is narrow.
    /// Inactive spaces still adapt based on available width (compact/medium/expanded).
    /// The user liked this treatment in compact mode and requested it for note mode too.
    private func noteSpaceButton(for space: SpaceDetector.SpaceInfo, availableWidth: CGFloat) -> some View {
        // Determine what to show based on available width (calculate once outside button)
        let buttonMode = getNoteButtonMode(availableWidth: availableWidth)
        
        // ACTIVE DESKTOP EXPANSION (Feb 17, 2026):
        // Check if this is the ACTIVE desktop (the one the user is currently on).
        // The active desktop always gets full expansion regardless of width constraints,
        // matching the compact view's behavior where the active space always shows
        // number + emoji + full name. This was requested by the user because they liked
        // how compact mode clearly shows which space you're on.
        let isActiveDesktop = space.index == viewModel.currentSpaceNumber
        let isSelectedNote = selectedNoteSpace == space.uuid
        
        return Button(action: {
            // Single click: Load note for this Space (by UUID for reorder resilience)
            selectNoteSpace(space.uuid)
        }) {
            HStack(spacing: 5) {
                // NUMBER: Always shown (display position - may change on reorder)
                // FIX (Feb 17, 2026): Changed from fixed width: 16 to minWidth: 18
                // to prevent clipping on two-digit space numbers like "10".
                // The old width: 16 was too narrow for double-digit numbers.
                Text("\(space.index)")
                    .font(.system(size: scaledFontSize(12), weight: isActiveDesktop ? .bold : .semibold))
                    .frame(minWidth: 14)
                
                // EMOJI: Active desktop ALWAYS shows emoji. Inactive shows when mode >= .medium
                // This mirrors compact view behavior where active space always shows emoji.
                if isActiveDesktop || buttonMode != .compact {
                    if let emoji = getSpaceEmoji(space.uuid, spaceIndex: space.index) {
                        Text(emoji)
                            .font(.system(size: scaledFontSize(13)))
                    }
                }
                
                // NAME: Active desktop ALWAYS shows full name (fixedSize, no truncation).
                // Inactive spaces show name only when mode is .expanded (wide window).
                // This gives the "expand when wide, contract when narrow" behavior
                // matching compact view. The active space is always prominent.
                if isActiveDesktop {
                    if let name = getSpaceName(space.uuid, spaceIndex: space.index), !name.isEmpty {
                        Text(name)
                            .font(.system(size: scaledFontSize(12), weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                } else if buttonMode == .expanded {
                    if let name = getSpaceName(space.uuid, spaceIndex: space.index), !name.isEmpty {
                        Text(name)
                            .font(.system(size: scaledFontSize(11)))
                            .lineLimit(1)
                    }
                }
                
                // Note indicator (UUID lookup)
                if hasNote(space.uuid) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, isActiveDesktop ? 12 : (buttonMode == .expanded ? 8 : 6))
            .padding(.vertical, 7)
            .frame(height: 32)
            .background(
                // FEATURE 5.5.9: Show each Space's color (UUID lookup)
                // Active desktop or selected note: Full color intensity
                // Unselected spaces: Faded color (20% opacity) to show their identity
                getSpaceBackgroundColor(space.uuid, spaceIndex: space.index, isActive: isActiveDesktop || isSelectedNote)
            )
            .foregroundColor(
                (isActiveDesktop || isSelectedNote) ? .white : .primary
            )
            .cornerRadius(8)
            // FEATURE: 5.5.8 - Dim to Indicate Order (UUID lookup)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(getSpaceDimmingOverlayOpacity(space.uuid)))
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(getSpaceName(space.uuid, spaceIndex: space.index) ?? "Space \(space.index)")
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                // Double-click: Switch to this Space (index for keyboard shortcuts)
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
    ///
    /// NOTE (Feb 17, 2026): This is now only used for INACTIVE buttons in note mode.
    /// The active/selected space always gets full expansion (see noteSpaceButton).
    /// This mirrors the compact view behavior where the active desktop is always
    /// expanded to show its full name while inactive spaces adapt to width.
    private func getNoteButtonMode(availableWidth: CGFloat) -> NoteButtonMode {
        let spaceCount = CGFloat(viewModel.allSpaces.count)
        guard spaceCount > 0 else { return .compact }
        
        // REDESIGN (Feb 17, 2026): Account for the active space button being expanded.
        // The active/selected space always shows full name, so we subtract its estimated
        // width from available space and calculate mode for the remaining inactive buttons.
        // This matches the compact view's getCompactInactiveButtonMode approach.
        let inactiveCount = max(spaceCount - 1, 1)
        let spacing: CGFloat = 8
        let padding: CGFloat = 8
        // Estimate active button width (~140pt for number + emoji + full name)
        let activeButtonEstimate: CGFloat = 140
        let totalSpacing = (spaceCount - 1) * spacing + padding * 2
        let availableForInactive = availableWidth - totalSpacing - activeButtonEstimate
        let spacePerButton = availableForInactive / inactiveCount
        
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
                    // MIGRATION (Feb 11, 2026): Use UUID for identity (stable across reorders)
                    ForEach(viewModel.allSpaces, id: \.uuid) { space in
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
    /// FONT SIZE ADAPTATION (Updated Jan 22, 2026):
    /// Thresholds scale with fontSizeMultiplier so that larger text triggers fewer columns
    /// at the same window width. This ensures cards remain readable and don't become cramped
    /// when text size increases. For example, at 3.0x text size (maximum), the 2-column
    /// threshold increases from 450pt to 1350pt (450 * 3.0), ensuring comfortable spacing
    /// even with very large text. This adaptive scaling is critical for accessibility.
    private func getOverviewColumns(for width: CGFloat) -> [GridItem] {
        let columnCount: Int
        
        // Scale thresholds by font size multiplier
        // Larger text = higher thresholds = fewer columns at same width
        // This ensures proper spacing and readability at all text sizes (0.8x to 3.0x)
        let multiplier = viewModel.fontSizeMultiplier
        let threshold1 = 450 * multiplier  // 1 column threshold (at 3.0x: 1350pt)
        let threshold2 = 700 * multiplier  // 2 column threshold (at 3.0x: 2100pt)
        let threshold3 = 1000 * multiplier // 3 column threshold (at 3.0x: 3000pt)
        let threshold4 = 1300 * multiplier // 4 column threshold (at 3.0x: 3900pt)
        
        if width < threshold1 {
            columnCount = 1  // Single column for narrow windows or large text
        } else if width < threshold2 {
            columnCount = 2
        } else if width < threshold3 {
            columnCount = 3
        } else if width < threshold4 {
            columnCount = 4
        } else {
            columnCount = 5
        }
        
        // Scale grid spacing with font size multiplier for better layout at larger text sizes
        // At 1.0x: 12pt spacing (default)
        // At 3.0x: 36pt spacing (3x larger for proportional spacing with large text)
        let scaledSpacing = 12 * multiplier
        
        return Array(repeating: GridItem(.flexible(), spacing: scaledSpacing), count: columnCount)
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
            getSpaceDimmingOverlayOpacity: getSpaceDimmingOverlayOpacity,  // FEATURE: 5.5.8 - Pass dimming overlay calculator
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
    /// COMPACT REDESIGN (Feb 13, 2026): Compact mode is now a single horizontal row,
    /// so it needs to be wider to fit all space buttons + inline controls.
    private func calculateMinWidth() -> CGFloat {
        switch displayMode {
        case .compact:
            // Single row needs enough width for space buttons + controls.
            return 500
        default:
            return 400
        }
    }
    
    /// Calculates ideal width based on display mode and number of Spaces
    /// COMPACT REDESIGN (Feb 13, 2026): Compact mode dynamically sizes based on
    /// number of spaces so the row fits comfortably without excessive scrolling.
    private func calculateWidth() -> CGFloat {
        switch displayMode {
        case .compact:
            // Dynamic width: each inactive button ~55pt, active ~140pt, controls ~150pt
            let spaceCount = CGFloat(viewModel.allSpaces.count)
            let estimatedWidth = (spaceCount - 1) * 55 + 140 + 160 + 40
            return max(estimatedWidth, 600)
        case .note:
            // Wider for note editing and inline name/emoji editing
            return 480
        case .overview:
            // PHASE 4: Wide enough for 2-column grid
            return 600
        }
    }
    
    /// Calculates minimum height based on display mode
    /// COMPACT REDESIGN (Feb 13, 2026): Compact is now a single row,
    /// so it only needs ~50pt height for one row of buttons.
    private func calculateMinHeight() -> CGFloat {
        switch displayMode {
        case .compact:
            // Single row: just buttons + padding
            return 50
        case .note:
            // Minimum height for note mode to prevent clipping
            return 360
        case .overview:
            // PHASE 4: Minimum for grid view
            return 400
        }
    }
    
    /// Calculates ideal height based on display mode
    /// COMPACT REDESIGN (Feb 13, 2026): Compact is a single row, ideal height
    /// is just enough for one line of buttons with comfortable padding.
    private func calculateHeight() -> CGFloat {
        switch displayMode {
        case .compact:
            // Single row: buttons (~32pt) + vertical padding (10+10) + breathing room
            return 52
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
    
    /// Gets custom name for a Space by UUID
    /// MIGRATION (Feb 11, 2026): Changed from Int spaceNumber to String spaceUUID
    /// Now looks up name by UUID (stable identifier) instead of array position.
    /// The spaceIndex is only used for generating the default "Desktop X" name.
    ///
    /// PHASE 2.2: Returns default "Desktop X" if no custom name set
    private func getSpaceName(_ spaceUUID: String, spaceIndex: Int) -> String? {
        // Check for custom name first (keyed by UUID for reorder resilience)
        if let customName = settings.spaceNames[spaceUUID] {
            return customName
        }
        // Return default name based on current display position
        return settings.generateDefaultSpaceName(for: spaceIndex)
    }
    
    /// Gets Space emoji by UUID (custom or default)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID lookup
    /// PHASE 2.3: Returns preset emoji if no custom emoji set
    private func getSpaceEmoji(_ spaceUUID: String, spaceIndex: Int) -> String? {
        // Check for custom emoji first (keyed by UUID)
        if let customEmoji = settings.spaceEmojis[spaceUUID] {
            return customEmoji
        }
        // Return default emoji based on current display position (for Spaces 1-16)
        return settings.getDefaultEmoji(for: spaceIndex)
    }
    
    /// Gets Space color by UUID (custom or nil for default)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID lookup
    /// FEATURE 5.5.9: Returns custom color hex if set
    private func getSpaceColor(_ spaceUUID: String) -> String? {
        return settings.spaceColors[spaceUUID]
    }
    
    /// Gets the background color for a Space button by UUID
    /// MIGRATION (Feb 11, 2026): Changed from Int spaceNumber to UUID + index
    /// FEATURE 5.5.9: Returns appropriate color based on active state
    ///
    /// BEHAVIOR:
    /// - Active space: Full color intensity (100% opacity)
    /// - Inactive space: Faded color (20% opacity) to show identity without overwhelming
    ///
    /// COLOR SOURCE:
    /// - Uses custom color if user has set one (looked up by UUID)
    /// - Falls back to default color based on space index (cycling through palette)
    /// - This ensures every space has a distinct color, even before customization
    ///
    /// WHY SHOW COLORS FOR INACTIVE SPACES:
    /// - Provides visual identity and distinction between spaces
    /// - Helps users quickly recognize and navigate to specific spaces
    /// - Creates a more colorful, engaging interface
    /// - Reduces cognitive load by using color as a memory aid
    ///
    /// - Parameters:
    ///   - spaceUUID: The Space UUID (for custom color lookup)
    ///   - spaceIndex: The Space's current display index (for default color cycling)
    ///   - isActive: Whether this is the currently active/selected Space
    /// - Returns: SwiftUI Color with appropriate opacity
    private func getSpaceBackgroundColor(_ spaceUUID: String, spaceIndex: Int, isActive: Bool) -> Color {
        // Get the color hex (custom or default)
        let colorHex = settings.getSpaceColorOrDefault(forUUID: spaceUUID, spaceIndex: spaceIndex)
        let color = settings.hexToColor(colorHex)
        
        // Apply full opacity for active, boosted for inactive (Feb 18, 2026)
        // INCREASED inactive from 20% to 35% so each space's identity color is more
        // recognizable even when not active — user wanted colors to pop more.
        return isActive ? color : color.opacity(0.35)
    }
    
    /// Gets the accent color for the current Space
    /// MIGRATION (Feb 11, 2026): Now looks up by UUID first, falls back to index
    /// FEATURE 5.5.9: Returns custom color or default color
    ///
    /// Used for HUD background tint and other accent elements
    private func getCurrentSpaceAccentColor() -> Color {
        // In note mode, use the selected note space; otherwise use the current space
        if displayMode == .note, let selectedUUID = selectedNoteSpace {
            // Look up the space index for the selected UUID
            let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == selectedUUID })?.index ?? viewModel.currentSpaceNumber
            let colorHex = settings.getSpaceColorOrDefault(forUUID: selectedUUID, spaceIndex: spaceIndex)
            return settings.hexToColor(colorHex)
        } else {
            // Use current space's color
            let currentSpaceNumber = viewModel.currentSpaceNumber
            let colorHex = settings.getSpaceColorOrDefault(for: currentSpaceNumber)
            return settings.hexToColor(colorHex)
        }
    }
    
    /// Checks if a Space has a note (by UUID)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID lookup
    private func hasNote(_ spaceUUID: String) -> Bool {
        guard let note = settings.spaceNotes[spaceUUID] else { return false }
        return !note.isEmpty
    }
    
    /// Gets tooltip text for a Space button
    private func getSpaceTooltip(_ spaceIndex: Int) -> String {
        return "Switch to Space \(spaceIndex)"
    }
    
    /// Gets dimming overlay opacity for a Space button based on visit recency
    ///
    /// FEATURE: 5.5.8 - Dim to Indicate Order (Visit Recency Visualization)
    ///
    /// DESIGN CHANGE (Jan 22, 2026):
    /// Changed from transparency-based dimming to overlay-based dimming.
    /// Instead of making the entire button/card transparent (which reduces visibility),
    /// we now apply a dark overlay on top. This keeps elements fully visible but darker.
    ///
    /// WHY THIS IS BETTER:
    /// - More consistent with SuperDimmer's core dimming functionality
    /// - Better visibility - dimmed elements remain clear and readable
    /// - More natural visual hierarchy - darkness indicates less recent visits
    /// - Matches the app's brand identity (dimming specialist)
    ///
    /// When spaceOrderDimmingEnabled is true, buttons are dimmed based on
    /// how recently each Space was visited. This creates a visual "heat map"
    /// of your workflow.
    ///
    /// CALCULATION:
    /// - Current Space: 0% overlay (fully bright, no dimming)
    /// - Last visited: Slight overlay (e.g., 5% dark overlay)
    /// - Older Spaces: Progressively darker overlay (up to maximum dim level)
    /// - Maximum dimming controlled by spaceOrderMaxDimLevel setting
    ///
    /// WHEN DISABLED:
    /// - All buttons have 0% overlay (no dimming)
    ///
    /// - Parameter spaceUUID: The Space UUID to get overlay opacity for
    ///   MIGRATION (Feb 11, 2026): Changed from Int spaceNumber to String UUID
    /// - Returns: Overlay opacity value (0.0-1.0) where 0.0 is no dimming, 1.0 is maximum dimming
    private func getSpaceDimmingOverlayOpacity(_ spaceUUID: String) -> Double {
        // If dimming is disabled, return no overlay
        guard settings.spaceOrderDimmingEnabled else {
            return 0.0
        }
        
        // Get opacity from visit tracker (this represents visibility)
        // MIGRATION (Feb 11, 2026): Now uses UUID for visit tracking
        // We need to invert it to get dimming level
        let totalSpaces = viewModel.allSpaces.count
        let visibilityOpacity = SpaceVisitTracker.shared.getOpacity(
            for: spaceUUID,
            maxDimLevel: settings.spaceOrderMaxDimLevel,
            totalSpaces: totalSpaces
        )
        
        // Convert visibility opacity to dimming overlay opacity
        // visibility 1.0 (fully visible) = overlay 0.0 (no dimming)
        // visibility 0.5 (50% transparent) = overlay 0.5 (50% dark overlay)
        // This creates equivalent visual effect but with better visibility
        return 1.0 - visibilityOpacity
    }
    
    /// Handles Space button click (always switches Space in mini/compact/expanded modes)
    /// NOTE: switchToSpace still takes index because it needs the position for keyboard shortcuts
    private func handleSpaceClick(_ spaceNumber: Int) {
        viewModel.switchToSpace(spaceNumber)
    }
    
    /// Shows emoji picker for a Space (by UUID)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID
    private func showEmojiPickerForSpace(_ spaceUUID: String) {
        emojiPickerForSpace = spaceUUID
        showEmojiPicker = true
    }
    
    // MARK: - Note Mode Helpers
    
    /// Selects a Space to view/edit its note (by UUID)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID
    private func selectNoteSpace(_ spaceUUID: String) {
        // Save current note before switching
        if let currentSpace = selectedNoteSpace {
            saveNoteForSpace(currentSpace, text: noteText)
        }
        
        // Load new Space's note
        selectedNoteSpace = spaceUUID
        loadNoteForSpace(spaceUUID)
    }
    
    /// Loads note for a specific Space (by UUID)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID lookup
    private func loadNoteForSpace(_ spaceUUID: String) {
        noteText = settings.spaceNotes[spaceUUID] ?? ""
    }
    
    /// Saves note for a specific Space (by UUID)
    /// MIGRATION (Feb 11, 2026): Changed from Int to UUID key
    private func saveNoteForSpace(_ spaceUUID: String, text: String) {
        if text.isEmpty {
            settings.spaceNotes.removeValue(forKey: spaceUUID)
        } else {
            settings.spaceNotes[spaceUUID] = text
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
    /// MIGRATION (Feb 11, 2026): Now uses UUID for data lookup
    /// FEATURE 5.5.9: Added color editing support
    private func startEditingSpaceName() {
        guard let spaceUUID = selectedNoteSpace else { return }
        
        // Look up the space index for default name/emoji fallback
        let spaceIndex = viewModel.allSpaces.first(where: { $0.uuid == spaceUUID })?.index ?? 1
        
        isEditingSpaceName = true
        editingSpaceNameText = getSpaceName(spaceUUID, spaceIndex: spaceIndex) ?? ""
        editingSpaceEmoji = getSpaceEmoji(spaceUUID, spaceIndex: spaceIndex) ?? ""
        editingSpaceColor = getSpaceColor(spaceUUID) ?? ""  // Load current color
        
        // Focus the name field after a short delay to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    /// Saves the edited Space name, emoji, and color
    /// MIGRATION (Feb 11, 2026): Now saves with UUID key
    /// PHASE 2.2: Validates and enforces character limit
    /// FEATURE 5.5.9: Added color saving
    private func saveSpaceNameAndEmoji() {
        guard let spaceUUID = selectedNoteSpace else { return }
        
        // Validate and save name with character limit (keyed by UUID)
        let trimmedName = editingSpaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            // Empty name: remove custom name, will show default
            settings.spaceNames.removeValue(forKey: spaceUUID)
        } else {
            // Validate and truncate to character limit
            let validatedName = settings.validateSpaceName(trimmedName)
            settings.spaceNames[spaceUUID] = validatedName
        }
        
        // Save emoji (limit to first 2 characters to handle multi-byte emojis)
        let trimmedEmoji = String(editingSpaceEmoji.prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmoji.isEmpty {
            // Empty emoji: remove custom emoji, will show default
            settings.spaceEmojis.removeValue(forKey: spaceUUID)
        } else {
            settings.spaceEmojis[spaceUUID] = trimmedEmoji
        }
        
        // Save color (FEATURE 5.5.9)
        let trimmedColor = editingSpaceColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            // Empty color: remove custom color, will use default blue
            settings.spaceColors.removeValue(forKey: spaceUUID)
        } else {
            settings.spaceColors[spaceUUID] = trimmedColor
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
    /// MIGRATION (Feb 11, 2026): Uses UUID for data lookups
    private func calculateMaxButtonWidth() -> CGFloat {
        var maxWidth: CGFloat = 100  // Minimum width
        
        // Iterate through all Spaces and measure their content
        for space in viewModel.allSpaces {
            // Get name (custom or default) - UUID lookup
            guard let name = getSpaceName(space.uuid, spaceIndex: space.index) else { continue }
            
            let numberWidth: CGFloat = 20
            let emojiWidth: CGFloat = getSpaceEmoji(space.uuid, spaceIndex: space.index) != nil ? 20 : 0
            let noteWidth: CGFloat = hasNote(space.uuid) ? 10 : 0
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
    /// MIGRATION (Feb 11, 2026): Changed from (Int) -> String? to (String, Int) -> String?
    /// First param is UUID (for data lookup), second is index (for default fallback)
    let getSpaceEmoji: (String, Int) -> String?
    let getSpaceName: (String, Int) -> String?
    let getSpaceDimmingOverlayOpacity: (String) -> Double  // FEATURE: 5.5.8 - UUID-based
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
    
    /// Gets the Space color by UUID (FEATURE 5.5.9)
    /// MIGRATION (Feb 11, 2026): Changed to UUID lookup
    private func getSpaceColor() -> String? {
        return settings.spaceColors[space.uuid]
    }
    
    /// Gets the accent color for this Space (FEATURE 5.5.9)
    /// MIGRATION (Feb 11, 2026): Uses UUID for custom color lookup
    ///
    /// FIX (Feb 5, 2026): Previously fell back to Color.accentColor when no custom
    /// color was set. Now uses getSpaceColorOrDefault() for consistency.
    private func getSpaceAccentColor() -> Color {
        let colorHex = settings.getSpaceColorOrDefault(forUUID: space.uuid, spaceIndex: space.index)
        return settings.hexToColor(colorHex)
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
                    // BACKGROUND WATERMARK: Large desktop number (display position)
                    Text("\(space.index)")
                        .font(.system(size: scaledFontSize(80), weight: .black))
                        .foregroundColor(.secondary.opacity(0.08))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.top, 10)
                    
                    // TextEditor with local state
                    // CRITICAL: Using id() to force SwiftUI to create a unique TextEditor instance
                    // MIGRATION (Feb 11, 2026): Use UUID for unique ID (stable across reorders)
                    TextEditor(text: $noteText)
                        .font(.system(size: scaledFontSize(11)))
                        .frame(height: calculatedHeight)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .id("note-editor-\(space.uuid)")  // UUID for stable identity
                        .onChange(of: noteText) { newValue in
                            // Debounced save to settings (keyed by UUID)
                            saveTimer?.invalidate()
                            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                if newValue.isEmpty {
                                    settings.spaceNotes.removeValue(forKey: space.uuid)
                                } else {
                                    settings.spaceNotes[space.uuid] = newValue
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
                    // INCREASED from 0.1/0.05 to 0.2/0.08 (Feb 18, 2026) for stronger color identity
                    space.index == viewModel.currentSpaceNumber ?
                        getSpaceAccentColor().opacity(0.2) : Color.secondary.opacity(0.08)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    // FEATURE 5.5.9: Use Space's custom color for border
                    // INCREASED from 0.3 to 0.5 (Feb 18, 2026) for a more visible colored border
                    space.index == viewModel.currentSpaceNumber ?
                        getSpaceAccentColor().opacity(0.5) : Color.clear,
                    lineWidth: 2
                )
        )
        // FEATURE: 5.5.8 - Dim to Indicate Order (Visit Recency Visualization)
        // DESIGN CHANGE (Jan 22, 2026): Using dark overlay instead of transparency
        // This keeps cards fully visible but darker, matching SuperDimmer's core functionality
        // CRITICAL: allowsHitTesting(false) ensures overlay doesn't block clicks on text fields and buttons
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(getSpaceDimmingOverlayOpacity(space.uuid)))
                .allowsHitTesting(false)
        )
        .onAppear {
            // Load note from settings when card appears (only once)
            // MIGRATION (Feb 11, 2026): Use UUID for data lookup
            if !hasInitialized {
                noteText = settings.spaceNotes[space.uuid] ?? ""
                hasInitialized = true
            }
        }
        .onChange(of: settings.spaceNotes[space.uuid]) { newValue in
            // Sync from settings if changed externally (but not during our own saves)
            if hasInitialized && noteText != (newValue ?? "") {
                noteText = newValue ?? ""
            }
        }
        // BUG FIX (Feb 17, 2026): Flush debounced save immediately on space change
        //
        // PROBLEM: The debounced save has a 0.5s delay. If the user switches desktops
        // within 0.5s of their last keystroke, the save hasn't fired yet. If the
        // LazyVGrid then resets @State during the allSpaces refresh, the unsaved text
        // in the debounce window is lost permanently.
        //
        // SOLUTION: When a space change occurs, immediately cancel the debounce timer
        // and save the current noteText to settings. This ensures no text is lost in
        // the debounce window, even if @State gets reset afterwards.
        //
        // WHY THIS IS SAFE: We only save if noteText is non-empty (preventing accidental
        // deletion from @State reset, since @State resets to "" which is the initial value).
        // If noteText IS empty and the user genuinely cleared the note, the regular
        // .onChange(of: noteText) debounced save handles that case.
        .onChange(of: viewModel.currentSpaceNumber) { _ in
            // Flush any pending debounced save immediately
            saveTimer?.invalidate()
            saveTimer = nil
            
            // Save current text to settings immediately (skip debounce)
            // Only save non-empty text to prevent @State reset from deleting notes
            let settingsNote = settings.spaceNotes[space.uuid] ?? ""
            if noteText != settingsNote && !noteText.isEmpty {
                settings.spaceNotes[space.uuid] = noteText
            }
        }
        // Emoji picker popover
        .popover(
            isPresented: $showEmojiPicker,
            arrowEdge: .bottom
        ) {
            SuperSpacesEmojiPicker(
                spaceNumber: space.index,  // Display index for the picker title
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
                spaceNumber: space.index,  // Display index for the picker title
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
    /// MIGRATION (Feb 11, 2026): Uses UUID for data lookups, index for display/switching
    private var displayHeaderView: some View {
        HStack(spacing: 8) {
            // Emoji and Name - CLICKABLE BAR to switch to this Space
            Button(action: {
                viewModel.switchToSpace(space.index)  // Index for keyboard shortcuts
            }) {
                HStack(spacing: 6) {
                    // Emoji (UUID lookup)
                    if let emoji = getSpaceEmoji(space.uuid, space.index), !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: scaledFontSize(18)))
                    } else {
                        Text("➕")
                            .font(.system(size: scaledFontSize(16)))
                            .foregroundColor(.secondary)
                    }
                    
                    // Name (UUID lookup)
                    Text(getSpaceName(space.uuid, space.index) ?? "Unnamed")
                        .font(.system(size: scaledFontSize(13), weight: .medium))
                        .foregroundColor(getSpaceName(space.uuid, space.index) == nil ? .secondary : .primary)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    // MIGRATION (Feb 11, 2026): Use UUID-based color lookup
                    // INCREASED from 0.15/0.05 to 0.25/0.08 (Feb 18, 2026) for bolder color identity
                    space.index == viewModel.currentSpaceNumber ?
                        settings.hexToColor(settings.getSpaceColorOrDefault(forUUID: space.uuid, spaceIndex: space.index)).opacity(0.25) : Color.secondary.opacity(0.08)
                )
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
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
            .focusEffectDisabled()  // Disable focus ring/outline on click
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
    /// MIGRATION (Feb 11, 2026): Uses UUID for data lookups
    /// FEATURE 5.5.9: Added color editing support
    private func startEditingSpaceName() {
        isEditingSpaceName = true
        editingSpaceNameText = getSpaceName(space.uuid, space.index) ?? ""
        editingSpaceEmoji = getSpaceEmoji(space.uuid, space.index) ?? ""
        editingSpaceColor = getSpaceColor() ?? ""  // Load current color (already UUID-based)
        
        // Focus the name field after a short delay to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFieldFocused = true
        }
    }
    
    /// Saves the edited Space name, emoji, and color
    /// MIGRATION (Feb 11, 2026): Saves with UUID key for reorder resilience
    /// FEATURE 5.5.9: Added color saving
    private func saveSpaceNameAndEmoji() {
        // Validate and save name with character limit (keyed by UUID)
        let trimmedName = editingSpaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            settings.spaceNames.removeValue(forKey: space.uuid)
        } else {
            let validatedName = settings.validateSpaceName(trimmedName)
            settings.spaceNames[space.uuid] = validatedName
        }
        
        // Save emoji (keyed by UUID)
        let trimmedEmoji = String(editingSpaceEmoji.prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmoji.isEmpty {
            settings.spaceEmojis.removeValue(forKey: space.uuid)
        } else {
            settings.spaceEmojis[space.uuid] = trimmedEmoji
        }
        
        // Save color (keyed by UUID)
        let trimmedColor = editingSpaceColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            settings.spaceColors.removeValue(forKey: space.uuid)
        } else {
            settings.spaceColors[space.uuid] = trimmedColor
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
