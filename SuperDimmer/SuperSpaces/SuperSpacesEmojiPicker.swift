//
//  SuperSpacesEmojiPicker.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Emoji picker for Space customization.
//  Allows users to assign emojis/icons to Spaces for visual identification.
//
//  FEATURE: 5.5.5 - Space Name & Emoji Customization
//
//  WHY EMOJIS:
//  - Visual identification is faster than reading text
//  - Emojis add personality and help users remember Space purposes
//  - Common pattern in modern productivity apps (Notion, Slack, etc.)
//  - Helps distinguish Spaces at a glance
//
//  UI DESIGN:
//  - Grid of commonly used emojis
//  - Organized by category (work, communication, media, etc.)
//  - "Remove Emoji" button to clear selection
//  - Simple, focused interface
//
//  EMOJI SELECTION:
//  We provide a curated list of emojis that make sense for Spaces:
//  - Work/productivity: 💻 📧 📝 📊 📁 📋
//  - Communication: 💬 📞 📹 👥 🗣️ 📱
//  - Media/creative: 🎨 🎵 🎬 📷 🎮 🎭
//  - General: 🏠 🏢 🎓 ✈️ 🚗 ⭐
//

import SwiftUI

/// Emoji picker for Space customization
/// Provides a grid of commonly used emojis for visual Space identification
struct SuperSpacesEmojiPicker: View {
    
    // MARK: - Properties
    
    /// Space number being customized
    let spaceNumber: Int
    
    /// Current emoji (if any)
    @Binding var selectedEmoji: String?
    
    /// Callback when emoji is selected
    var onEmojiSelected: ((String?) -> Void)?
    
    /// Curated emoji list organized by category
    private let emojiCategories: [(String, [String])] = [
        ("Work", ["💻", "📧", "📝", "📊", "📁", "📋", "🖥️", "⌨️"]),
        ("Communication", ["💬", "📞", "📹", "👥", "🗣️", "📱", "✉️", "📮"]),
        ("Media", ["🎨", "🎵", "🎬", "📷", "🎮", "🎭", "🎪", "🎯"]),
        ("Places", ["🏠", "🏢", "🎓", "🏥", "✈️", "🚗", "🌍", "🏖️"]),
        ("Symbols", ["⭐", "❤️", "🔥", "💡", "🎯", "🚀", "⚡", "🌟"])
    ]
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("Choose Emoji for Space \(spaceNumber)")
                .font(.system(size: 13, weight: .semibold))
            
            Divider()
            
            // Emoji grid by category
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(emojiCategories, id: \.0) { category, emojis in
                        VStack(alignment: .leading, spacing: 8) {
                            // Category label
                            Text(category)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            // Emoji grid for this category
                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: 40), spacing: 4)
                                ],
                                spacing: 4
                            ) {
                                ForEach(emojis, id: \.self) { emoji in
                                    emojiButton(emoji)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Remove emoji button
            Button(action: removeEmoji) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Remove Emoji")
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
    
    /// Creates an emoji button
    private func emojiButton(_ emoji: String) -> some View {
        Button(action: {
            selectEmoji(emoji)
        }) {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    selectedEmoji == emoji ?
                        Color.accentColor.opacity(0.2) : Color.clear
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            selectedEmoji == emoji ?
                                Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Use \(emoji)")
    }
    
    // MARK: - Actions
    
    /// Selects an emoji
    private func selectEmoji(_ emoji: String) {
        selectedEmoji = emoji
        onEmojiSelected?(emoji)
    }
    
    /// Removes the current emoji
    private func removeEmoji() {
        selectedEmoji = nil
        onEmojiSelected?(nil)
    }
}

// MARK: - Preview

#if DEBUG
struct SuperSpacesEmojiPicker_Previews: PreviewProvider {
    static var previews: some View {
        SuperSpacesEmojiPicker(
            spaceNumber: 3,
            selectedEmoji: .constant("💻")
        )
    }
}
#endif
