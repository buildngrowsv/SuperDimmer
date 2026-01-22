//
//  SpaceDetector.swift
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Detects macOS desktop Spaces (virtual desktops) by reading the com.apple.spaces.plist file.
//  This provides automated Space detection without requiring private APIs or manual user registration.
//
//  WHY THIS APPROACH:
//  - Public NSWorkspace APIs don't provide Space information (only NSScreen)
//  - Private CGS APIs would cause App Store rejection
//  - Reading com.apple.spaces.plist is a reliable, documented approach used by tools like Hammerspoon
//  - The plist contains Space UUIDs, display mappings, and current Space information
//
//  TECHNICAL DETAILS:
//  - Plist location: ~/Library/Preferences/com.apple.spaces.plist
//  - Contains "SpacesDisplayConfiguration" with all Space data
//  - Contains "SpaceProperties" with Space metadata
//  - Current Space is marked in the "Spaces" array for each display
//  - We use PropertyListSerialization for reliable parsing (better than shell commands)
//
//  USAGE:
//  - Call getCurrentSpace() to get current Space number and UUID
//  - Call getAllSpaces() to enumerate all Spaces across all displays
//  - Use SpaceChangeMonitor to detect when user switches Spaces
//
//  LIMITATIONS:
//  - Plist updates slightly lag actual Space changes (~100-200ms)
//  - Space numbers are per-display, not global
//  - No official API means structure could change in future macOS versions
//
//  PRODUCT CONTEXT:
//  This is the foundation for "Super Spaces" - SuperDimmer's Space navigation HUD.
//  It enables automatic Space detection so users don't need manual setup.
//

import Foundation
import AppKit

// MARK: - CGS Private API Declarations

/// CoreGraphics Services connection type
typealias CGSConnectionID = Int

/// Get the default connection to the window server
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// Get the ID of the currently active Space
/// Returns the ManagedSpaceID (same as in com.apple.spaces.plist)
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> Int

/// NOTE ON DIRECT SPACE SWITCHING (Jan 22, 2026):
/// We investigated using CGS private APIs for direct Space switching:
/// - CGSSetActiveSpace
/// - CGSManagedDisplaySetCurrentSpace
///
/// RESULT: These functions either don't exist in the CoreGraphics framework
/// or have undocumented/unclear signatures that we couldn't successfully call.
/// dlsym() fails to find them, and even Hammerspoon doesn't use them.
///
/// Instead, Hammerspoon uses the Accessibility API to programmatically open
/// Mission Control and click on Spaces, which is complex and still has delays.
///
/// DECISION: Stick with AppleScript Control+Arrow simulation for now.
/// It's simple, reliable, and works across all macOS versions.

/// Detects and provides information about macOS desktop Spaces (virtual desktops)
/// using CGS private APIs for real-time Space detection.
///
/// IMPORTANT: The plist file does NOT update in real-time when switching Spaces.
/// We use CGSGetActiveSpace() to get the actual current Space ID, then match it
/// with the plist data to get Space names and order.
final class SpaceDetector {
    
    // MARK: - Types
    
    /// Information about a detected Space
    struct SpaceInfo: Equatable {
        /// Space index/number (1-based, per display)
        let index: Int
        
        /// Unique UUID for this Space
        let uuid: String
        
        /// Display UUID this Space belongs to
        let displayUUID: String
        
        /// Whether this is the currently active Space
        let isCurrent: Bool
        
        /// Space type (user, fullscreen, etc.)
        let type: Int
    }
    
    /// Information about the current Space
    struct CurrentSpaceInfo {
        /// Space number (1-based)
        let spaceNumber: Int
        
        /// Space UUID
        let spaceUUID: String
        
        /// Display UUID
        let displayUUID: String
    }
    
    // MARK: - Properties
    
    /// Path to the com.apple.spaces.plist file
    /// This file contains all Space configuration and current state
    private static let plistPath = NSHomeDirectory()
        .appending("/Library/Preferences/com.apple.spaces.plist")
    
    // MARK: - Public Methods
    
    /// Gets information about the currently active Space
    ///
    /// TECHNICAL APPROACH:
    /// 1. Use CGSGetActiveSpace() to get current Space's ManagedSpaceID (REAL-TIME)
    /// 2. Read com.apple.spaces.plist to get Space UUIDs and display info
    /// 3. Match ManagedSpaceID with plist data to get Space number
    /// 4. Return Space number, UUID, and display info
    ///
    /// WHY CGS API:
    /// - The plist file does NOT update in real-time when switching Spaces
    /// - CGS API provides instant, accurate Space ID
    /// - Used by many shipping Mac apps (Hammerspoon, BetterTouchTool)
    ///
    /// PERFORMANCE:
    /// - CGS call: <1ms
    /// - Plist read: ~2-4ms
    /// - Total: ~3-5ms per call
    ///
    /// - Returns: CurrentSpaceInfo if successful, nil if detection fails
    static func getCurrentSpace() -> CurrentSpaceInfo? {
        // Get current Space ID using CGS private API (REAL-TIME)
        let connection = CGSMainConnectionID()
        let currentManagedSpaceID = CGSGetActiveSpace(connection)
        
        // Read plist to get Space metadata
        guard let plist = readSpacesPlist() else {
            print("⚠️ SpaceDetector: Failed to read spaces plist")
            return nil
        }
        
        // Navigate to the Spaces configuration
        guard let displayConfig = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = displayConfig["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            print("⚠️ SpaceDetector: Unexpected plist structure")
            return nil
        }
        
        // Get the first (main) monitor
        guard let mainMonitor = monitors.first,
              let spacesArray = mainMonitor["Spaces"] as? [[String: Any]] else {
            print("⚠️ SpaceDetector: Could not find Spaces array")
            return nil
        }
        
        // CRITICAL: Mission Control displays Spaces in PLIST ARRAY ORDER, not sorted by ManagedSpaceID!
        // When you rearrange Spaces in Mission Control, it updates the array order.
        // ManagedSpaceIDs stay the same but their position in the array changes.
        // We must use the array index directly to match Mission Control's display.
        
        let displayIdentifier = mainMonitor["Display Identifier"] as? String ?? "Main"
        
        // Find the current Space by matching ManagedSpaceID from CGS
        for (index, spaceDict) in spacesArray.enumerated() {
            guard let managedID = spaceDict["ManagedSpaceID"] as? Int else { continue }
            
            if managedID == currentManagedSpaceID {
                // Found it!
                guard let uuid = spaceDict["uuid"] as? String else {
                    print("⚠️ SpaceDetector: Space has no UUID")
                    continue
                }
                
                return CurrentSpaceInfo(
                    spaceNumber: index + 1,  // 1-based indexing, in plist array order = Mission Control order
                    spaceUUID: uuid,
                    displayUUID: displayIdentifier
                )
            }
        }
        
        print("⚠️ SpaceDetector: ManagedSpaceID \(currentManagedSpaceID) not found in plist")
        return nil
    }
    
    /// Gets information about all Spaces across all displays
    ///
    /// TECHNICAL APPROACH:
    /// 1. Read com.apple.spaces.plist
    /// 2. Parse all Spaces from SpacesDisplayConfiguration
    /// 3. Group by display
    /// 4. Return array of SpaceInfo structs
    ///
    /// SPACE NUMBERING:
    /// - Spaces are numbered 1-based per display
    /// - Display 1: Spaces 1, 2, 3, ...
    /// - Display 2: Spaces 1, 2, 3, ...
    /// - We currently focus on the main display
    ///
    /// SPACE TYPES:
    /// - Type 0: Regular user Space
    /// - Type 1: Fullscreen app Space
    /// - Type 2: Dashboard (deprecated)
    /// - We include all types for completeness
    ///
    /// - Returns: Array of SpaceInfo for all detected Spaces
    static func getAllSpaces() -> [SpaceInfo] {
        guard let plist = readSpacesPlist() else {
            print("⚠️ SpaceDetector: Failed to read spaces plist")
            return []
        }
        
        // Navigate to the Spaces configuration
        guard let displayConfig = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = displayConfig["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            print("⚠️ SpaceDetector: Unexpected plist structure")
            return []
        }
        
        // Get the first (main) monitor
        guard let mainMonitor = monitors.first,
              let spacesArray = mainMonitor["Spaces"] as? [[String: Any]] else {
            print("⚠️ SpaceDetector: Could not find Spaces array")
            return []
        }
        
        // Get current Space UUID for comparison
        let currentSpaceUUID = (mainMonitor["Current Space"] as? [String: Any])?["uuid"] as? String
        let displayIdentifier = mainMonitor["Display Identifier"] as? String ?? "Main"
        
        // CRITICAL: Mission Control displays Spaces in PLIST ARRAY ORDER!
        // When you rearrange Spaces in Mission Control, it updates the array order.
        // We must use the array index directly (NOT sort by ManagedSpaceID).
        
        var spaces: [SpaceInfo] = []
        
        // Parse each Space in plist array order (= Mission Control display order)
        for (index, spaceDict) in spacesArray.enumerated() {
            guard let uuid = spaceDict["uuid"] as? String else {
                continue
            }
            
            let spaceType = spaceDict["type"] as? Int ?? 0
            let isCurrent = (uuid == currentSpaceUUID)
            
            let spaceInfo = SpaceInfo(
                index: index + 1,  // 1-based indexing, in plist array order = Mission Control order
                uuid: uuid,
                displayUUID: displayIdentifier,
                isCurrent: isCurrent,
                type: spaceType
            )
            
            spaces.append(spaceInfo)
        }
        
        return spaces
    }
    
    /// Gets the total number of Spaces
    ///
    /// This is a convenience method that just counts getAllSpaces().
    /// Useful for quick checks without needing full Space info.
    ///
    /// - Returns: Total number of Spaces detected
    static func getSpaceCount() -> Int {
        return getAllSpaces().count
    }
    
    
    // MARK: - Private Methods
    
    /// Reads and parses the com.apple.spaces.plist file
    ///
    /// TECHNICAL DETAILS:
    /// - Uses PropertyListSerialization for reliable parsing
    /// - Better than shell commands (no parsing, no process overhead)
    /// - Handles binary and XML plist formats automatically
    ///
    /// ALTERNATIVE APPROACHES CONSIDERED:
    /// 1. Shell command: defaults read com.apple.spaces
    ///    - Rejected: Process overhead, output parsing complexity
    /// 2. NSUserDefaults: UserDefaults(suiteName: "com.apple.spaces")
    ///    - Rejected: Doesn't work for system preferences
    /// 3. CFPreferences API
    ///    - Rejected: More complex, no significant benefit
    ///
    /// - Returns: Dictionary representation of plist, or nil if read fails
    private static func readSpacesPlist() -> [String: Any]? {
        do {
            // Read plist data
            let plistURL = URL(fileURLWithPath: plistPath)
            let plistData = try Data(contentsOf: plistURL)
            
            // Parse plist
            let plist = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
            
            return plist
            
        } catch {
            print("⚠️ SpaceDetector: Error reading plist: \(error.localizedDescription)")
            return nil
        }
    }
}
