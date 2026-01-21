//
//  SuperSpacesNoteEditor.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Note editor for Space-specific notes.
//  Allows users to add context, reminders, and task lists per Space.
//
//  FEATURE: 5.5.6 - Note Mode
//
//  WHY NOTES PER SPACE:
//  - Helps users remember what each Space is for
//  - Useful for context switching ("what was I working on?")
//  - Can include quick reminders or task lists
//  - Reduces cognitive load when switching between projects
//
//  NOTE MODE BEHAVIOR:
//  - Toggle between "Space Mode" (click to switch) and "Note Mode" (click to edit)
//  - In Note Mode:
//    - Single-click: Opens note editor
//    - Double-click: Switches to that Space (always works)
//  - Notes auto-save on text change (debounced)
//  - Visual indicator (note icon) on Spaces that have notes
//
//  UI DESIGN:
//  - Simple text editor with Space context
//  - Character count (optional limit)
//  - "Switch to Space" button for quick navigation
//  - Auto-focus on text field for immediate typing
//

import SwiftUI

/// Note editor for Space-specific notes
/// Provides a text editor for adding context and reminders to Spaces
struct SuperSpacesNoteEditor: View {
    
    // MARK: - Properties
    
    /// Space number being edited
    let spaceNumber: Int
    
    /// Space name (if customized)
    let spaceName: String?
    
    /// Space emoji (if set)
    let spaceEmoji: String?
    
    /// Note text binding
    @Binding var noteText: String
    
    /// Callback when user wants to switch to this Space
    var onSwitchToSpace: (() -> Void)?
    
    /// Callback when note is saved (debounced)
    var onNoteSaved: ((String) -> Void)?
    
    /// Focus state for text editor
    @FocusState private var isTextFieldFocused: Bool
    
    /// Character limit for notes (optional)
    private let characterLimit: Int = 500
    
    /// Timer for debounced save
    @State private var saveTimer: Timer?
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Space info
            HStack(spacing: 8) {
                // Emoji if set
                if let emoji = spaceEmoji {
                    Text(emoji)
                        .font(.system(size: 20))
                }
                
                // Space number and name
                VStack(alignment: .leading, spacing: 2) {
                    Text("Space \(spaceNumber)")
                        .font(.system(size: 13, weight: .semibold))
                    
                    if let name = spaceName {
                        Text(name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Character count
                Text("\(noteText.count)/\(characterLimit)")
                    .font(.system(size: 10))
                    .foregroundColor(noteText.count > characterLimit ? .red : .secondary)
            }
            
            Divider()
            
            // Note text editor
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
                .focused($isTextFieldFocused)
                .onChange(of: noteText) { newValue in
                    // Debounce auto-save
                    debouncedSave(newValue)
                }
            
            // Placeholder text when empty
            if noteText.isEmpty {
                Text("Add notes, reminders, or tasks for this Space...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, -112)
                    .allowsHitTesting(false)
            }
            
            Divider()
            
            // Actions
            HStack {
                // Switch to Space button
                Button(action: {
                    onSwitchToSpace?()
                }) {
                    HStack {
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
                
                // Clear note button (if note exists)
                if !noteText.isEmpty {
                    Button(action: clearNote) {
                        HStack {
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
        .padding(16)
        .frame(width: 320)
        .onAppear {
            // Auto-focus text field when editor opens
            isTextFieldFocused = true
        }
    }
    
    // MARK: - Actions
    
    /// Debounced save to avoid saving on every keystroke
    /// Waits 0.5 seconds after last keystroke before saving
    private func debouncedSave(_ text: String) {
        // Cancel previous timer
        saveTimer?.invalidate()
        
        // Schedule new save after delay
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            onNoteSaved?(text)
        }
    }
    
    /// Clears the note
    private func clearNote() {
        noteText = ""
        onNoteSaved?("")
    }
}

// MARK: - Preview

#if DEBUG
struct SuperSpacesNoteEditor_Previews: PreviewProvider {
    static var previews: some View {
        SuperSpacesNoteEditor(
            spaceNumber: 3,
            spaceName: "Development",
            spaceEmoji: "💻",
            noteText: .constant("Working on SuperDimmer Super Spaces feature.\n\nTODO:\n- Implement note mode\n- Add emoji picker\n- Test keyboard navigation")
        )
    }
}
#endif
