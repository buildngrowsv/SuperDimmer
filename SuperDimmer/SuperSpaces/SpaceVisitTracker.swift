//
//  SpaceVisitTracker.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Tracks the order in which macOS Spaces are visited to enable
//  progressive button dimming based on recency in the Super Spaces HUD.
//
//  FEATURE: 5.5.8 - Dim to Indicate Order (Visit Recency Visualization)
//
//  WHY THIS FEATURE:
//  - Provides instant visual feedback on which Spaces you've been using recently
//  - Creates a natural "heat map" of your workflow without manual configuration
//  - Helps identify "stale" Spaces you haven't visited in a while
//  - Complements the existing window-level inactivity decay feature
//
//  HOW IT WORKS (Updated Jan 22, 2026 - More dramatic progressive dimming):
//  - Maintains an ordered array of Space numbers: [current, last, secondToLast, ...]
//  - When user switches to a Space, it moves to position 0 (most recent)
//  - Button opacity is calculated based on position in the array
//  - Unvisited Spaces (not in array): 50% opacity (neutral/default state)
//  - Current Space (position 0): 100% opacity (fully bright)
//  - Last visited (position 1): ~97.5% opacity (just switched away - still very bright)
//  - Older visited Spaces: Progressively more dimmed (down to minimum opacity)
//
//  ALGORITHM:
//  For N total Spaces with max dim level M (default 25% = 75% min opacity):
//  - Unvisited: opacity = 0.5 (50%)
//  - Position 0 (current): opacity = 1.0 (100%)
//  - Position 1+ (visited): opacity dims progressively from 100% down
//  - Opacity step = (1.0 - minOpacity) / N
//  - Space at position P: opacity = 1.0 - (P * step)
//  - Example: 10 Spaces, 25% max dim → 2.5% step per position from 100% down to 75%
//  - This creates clear visual hierarchy: each rank away from current is noticeably dimmer
//
//  PERFORMANCE:
//  - Visit tracking: O(n) where n = number of Spaces (typically < 10)
//  - Opacity calculation: O(1) per Space
//  - Persistence: Debounced to avoid excessive UserDefaults writes
//  - Total impact: Negligible (< 0.1% CPU)
//
//  PERSISTENCE:
//  - Visit order saved to UserDefaults as JSON array
//  - Restored on app launch to maintain history across sessions
//  - User can reset visit order via settings
//
//  PRODUCT CONTEXT:
//  This creates a visual hierarchy in the Super Spaces HUD that naturally
//  emphasizes the Spaces you're actively using while de-emphasizing ones
//  you haven't touched recently. It's like a "recently used" indicator
//  but expressed through progressive dimming instead of a list.
//

import Foundation
import Combine

/// Tracks the order in which macOS Spaces are visited
/// to enable progressive button dimming based on recency.
final class SpaceVisitTracker: ObservableObject {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide access
    /// Singleton pattern ensures consistent visit history across all HUD instances
    static let shared = SpaceVisitTracker()
    
    // MARK: - Properties
    
    /// Ordered array of Space numbers, most recent first
    /// Index 0 = current Space, Index 1 = last visited, etc.
    /// Example: [3, 2, 6, 1, 4] means currently on Space 3, was on 2 before that, etc.
    @Published private(set) var visitOrder: [Int] = []
    
    /// UserDefaults key for persisting visit order
    private let visitOrderKey = "superdimmer.spaceVisitOrder"
    
    /// Debounce timer for saving to UserDefaults
    /// Prevents excessive writes during rapid Space switching
    private var saveTimer: Timer?
    
    /// Debounce interval for saving (seconds)
    /// Waits 2 seconds after last change before saving
    private let saveDebounceInterval: TimeInterval = 2.0
    
    // MARK: - Initialization
    
    private init() {
        // Load persisted visit order from UserDefaults
        // This restores the visit history from the last session
        loadVisitOrder()
        
        print("✓ SpaceVisitTracker: Initialized with \(visitOrder.count) tracked Spaces")
    }
    
    // MARK: - Public Methods
    
    /// Records a visit to a Space
    ///
    /// ALGORITHM:
    /// 1. If Space is already in array, remove it from current position
    /// 2. Insert Space at position 0 (most recent)
    /// 3. Trim array if it exceeds reasonable size (20 Spaces max)
    /// 4. Schedule debounced save to UserDefaults
    ///
    /// THREAD SAFETY:
    /// This method should be called on the main thread since it updates @Published property.
    /// SpaceChangeMonitor already calls callbacks on main thread, so this is safe.
    ///
    /// EXAMPLE:
    /// Before: [3, 2, 6, 1]  (currently on Space 3)
    /// Visit Space 6: [6, 3, 2, 1]  (Space 6 moves to front, was at position 2)
    ///
    /// - Parameter spaceNumber: The Space number that was just visited (1-based)
    func recordVisit(to spaceNumber: Int) {
        // Remove Space from current position if it exists
        // This ensures each Space appears only once in the array
        if let existingIndex = visitOrder.firstIndex(of: spaceNumber) {
            visitOrder.remove(at: existingIndex)
        }
        
        // Insert at position 0 (most recent)
        visitOrder.insert(spaceNumber, at: 0)
        
        // Trim to reasonable size (20 Spaces max)
        // Most users have < 10 Spaces, but we support up to 20
        // Beyond that, we drop the least recently visited
        if visitOrder.count > 20 {
            visitOrder = Array(visitOrder.prefix(20))
        }
        
        print("✓ SpaceVisitTracker: Recorded visit to Space \(spaceNumber). Order: \(visitOrder.prefix(5).map(String.init).joined(separator: ", "))")
        
        // Schedule debounced save
        scheduleSave()
    }
    
    /// Gets the opacity level for a Space based on visit recency
    ///
    /// BEHAVIOR (Updated Jan 22, 2026 - More dramatic progressive dimming):
    /// - All Spaces start at 50% opacity (default/neutral state)
    /// - Position 0 (current Space): 100% opacity (fully bright)
    /// - After being visited (positions 1+): Progressive dimming from 100% down to minOpacity
    ///
    /// CALCULATION:
    /// 1. Find Space's position in visitOrder array
    /// 2. If position 0 (current): return 100% opacity
    /// 3. If position > 0 (visited before): calculate progressive dim from 100% down
    /// 4. If not in visit order (never visited): return 50% opacity (default)
    ///
    /// FORMULA FOR VISITED SPACES (position > 0):
    /// - Start at 100% opacity for position 0 (current)
    /// - Each position away from current progressively dims
    /// - dimRange = 1.0 - minOpacity (e.g., 1.0 - 0.75 = 0.25 range)
    /// - dimStep = dimRange / totalSpaces
    /// - opacity = 1.0 - (position * dimStep)
    ///
    /// EXAMPLE (10 Spaces, 25% max dim = 75% min opacity):
    /// Position 0 (current): opacity = 1.0 (100%)
    /// Position 1 (last): opacity = ~0.975 (97.5%, just switched away - still very bright)
    /// Position 2: opacity = ~0.95 (95%)
    /// Position 3: opacity = ~0.925 (92.5%)
    /// Position 4: opacity = ~0.90 (90%)
    /// Position 5: opacity = ~0.875 (87.5%)
    /// ...
    /// Position 10+: opacity = 0.75 (75%, minimum)
    ///
    /// WHY THIS WORKS BETTER:
    /// - Creates clear visual hierarchy: current is brightest, progressively dims with each rank
    /// - Each position has a noticeable ~2.5% opacity difference (for 10 Spaces)
    /// - More dramatic than the old 50%→25% range which was too subtle
    /// - The full 100%→75% range provides better visual distinction
    ///
    /// UNVISITED SPACES:
    /// - Not in visitOrder array: opacity = 0.5 (50%, default state)
    /// - This makes them clearly distinct from visited Spaces (which are 75%+)
    ///
    /// - Parameters:
    ///   - spaceNumber: The Space number to get opacity for
    ///   - maxDimLevel: Maximum dim level (0.0-1.0, default 0.25 = 25%)
    ///   - totalSpaces: Total number of Spaces (used to calculate step size)
    /// - Returns: Opacity value (0.0-1.0) where 1.0 is fully visible
    func getOpacity(for spaceNumber: Int, maxDimLevel: Double = 0.25, totalSpaces: Int) -> Double {
        // Find position in visit order
        guard let position = visitOrder.firstIndex(of: spaceNumber) else {
            // Space not in visit order yet (unvisited)
            // Default to 50% opacity (neutral state)
            // This makes unvisited Spaces clearly distinct from visited ones
            return 0.5
        }
        
        // Position 0 = current Space, always 100% opacity
        if position == 0 {
            return 1.0
        }
        
        // For visited Spaces (position > 0):
        // Progressive dimming from 100% (current) down to minOpacity (oldest visited)
        // This creates a clear visual hierarchy based on recency
        let minOpacity = 1.0 - maxDimLevel  // e.g., 0.75 for 25% max dim
        let dimRange = 1.0 - minOpacity     // Range from 100% down to min (e.g., 0.25)
        
        // Calculate dim step per position
        // Each position away from current gets progressively dimmer
        // For 10 Spaces with 25% max dim: step = 0.25 / 10 = 0.025 (2.5% per position)
        let dimStep = totalSpaces > 0 ? dimRange / Double(totalSpaces) : 0.0
        
        // Calculate opacity for this position
        // Position 1 = 100% - 1 step, Position 2 = 100% - 2 steps, etc.
        let opacity = 1.0 - (Double(position) * dimStep)
        
        // Clamp to valid range [minOpacity, 1.0]
        // This ensures we never go below the minimum opacity setting
        return max(minOpacity, min(1.0, opacity))
    }
    
    /// Resets the visit order
    ///
    /// WHEN TO USE:
    /// - User clicks "Reset Visit History" in settings
    /// - User wants to clear the dimming visualization
    /// - Debugging/testing
    ///
    /// BEHAVIOR:
    /// - Clears the visitOrder array
    /// - Removes persisted data from UserDefaults
    /// - All Spaces will have equal opacity until visited again
    func resetVisitOrder() {
        visitOrder.removeAll()
        UserDefaults.standard.removeObject(forKey: visitOrderKey)
        print("✓ SpaceVisitTracker: Visit order reset")
    }
    
    /// Initializes visit order with all available Spaces
    ///
    /// NOTE (Jan 21, 2026): This function is DEPRECATED for normal initialization.
    /// We now prefer to only add Spaces to visitOrder when they are actually visited.
    /// This creates clearer visual feedback: 50% = unvisited, 100% = current, progressive dim = visited.
    ///
    /// WHEN TO USE (Legacy/Special Cases):
    /// - Manual testing or debugging
    /// - User explicitly requests to "mark all Spaces as visited"
    /// - Migration from old behavior (if needed)
    ///
    /// BEHAVIOR:
    /// - Adds all Spaces to visitOrder in numerical order
    /// - Current Space (if known) is placed at position 0
    /// - Other Spaces are added in order: [current, 1, 2, 3, ...]
    /// - This will cause all Spaces to show progressive dimming from 1-N
    ///
    /// - Parameters:
    ///   - spaceNumbers: Array of all available Space numbers
    ///   - currentSpace: The currently active Space (optional)
    func initializeWithSpaces(_ spaceNumbers: [Int], currentSpace: Int?) {
        // Start with current Space if known
        var newOrder: [Int] = []
        if let current = currentSpace {
            newOrder.append(current)
        }
        
        // Add all other Spaces in numerical order
        for spaceNumber in spaceNumbers.sorted() {
            if spaceNumber != currentSpace {
                newOrder.append(spaceNumber)
            }
        }
        
        visitOrder = newOrder
        scheduleSave()
        
        print("✓ SpaceVisitTracker: Initialized with \(spaceNumbers.count) Spaces. Current: \(currentSpace ?? 0)")
    }
    
    // MARK: - Private Methods
    
    /// Loads visit order from UserDefaults
    ///
    /// PERSISTENCE FORMAT:
    /// Stored as JSON array of integers: [3, 2, 6, 1, 4]
    /// If no data exists (first launch), array is empty
    ///
    /// ERROR HANDLING:
    /// - If JSON decoding fails, logs error and starts with empty array
    /// - Invalid data is ignored (doesn't crash the app)
    private func loadVisitOrder() {
        guard let data = UserDefaults.standard.data(forKey: visitOrderKey) else {
            print("ℹ️ SpaceVisitTracker: No persisted visit order found (first launch)")
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode([Int].self, from: data)
            visitOrder = decoded
            print("✓ SpaceVisitTracker: Loaded visit order: \(decoded.prefix(5).map(String.init).joined(separator: ", "))")
        } catch {
            print("⚠️ SpaceVisitTracker: Failed to decode visit order: \(error)")
        }
    }
    
    /// Saves visit order to UserDefaults (debounced)
    ///
    /// DEBOUNCING:
    /// - Waits 2 seconds after last change before saving
    /// - Prevents excessive UserDefaults writes during rapid Space switching
    /// - If user switches Spaces 5 times in 2 seconds, only saves once
    ///
    /// THREAD SAFETY:
    /// - Timer is scheduled on main thread
    /// - UserDefaults writes are thread-safe
    private func scheduleSave() {
        // Cancel existing timer
        saveTimer?.invalidate()
        
        // Schedule new timer
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
            self?.saveVisitOrder()
        }
    }
    
    /// Immediately saves visit order to UserDefaults
    ///
    /// PERSISTENCE:
    /// - Encodes visitOrder as JSON array
    /// - Saves to UserDefaults under visitOrderKey
    /// - Synchronous write (UserDefaults handles async internally)
    private func saveVisitOrder() {
        do {
            let encoded = try JSONEncoder().encode(visitOrder)
            UserDefaults.standard.set(encoded, forKey: visitOrderKey)
            print("✓ SpaceVisitTracker: Saved visit order to UserDefaults")
        } catch {
            print("⚠️ SpaceVisitTracker: Failed to encode visit order: \(error)")
        }
    }
}
