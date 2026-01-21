#!/usr/bin/env swift

import Foundation

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

// MARK: - Test

print("=== CGS Space Detection Test ===")
print("This will poll the current Space ID every 0.5 seconds.")
print("Switch between Spaces using Ctrl+Arrow keys to test.")
print("Press Ctrl+C to stop.")
print("")

let connection = CGSMainConnectionID()
var lastSpaceID: Int? = nil
var iteration = 0

while true {
    let currentSpaceID = CGSGetActiveSpace(connection)
    
    if currentSpaceID != lastSpaceID {
        print("✓ Space changed: \(lastSpaceID ?? 0) -> \(currentSpaceID)")
        lastSpaceID = currentSpaceID
    } else {
        // Only print every 4th iteration (every 2 seconds) to reduce spam
        if iteration % 4 == 0 {
            print("  Current Space ID: \(currentSpaceID)")
        }
    }
    
    iteration += 1
    usleep(500_000) // 0.5 seconds
}
