import Foundation

typealias CGSConnectionID = Int

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> Int

print("=== CGS Space Polling Test ===", terminator: "\n")
fflush(stdout)

let conn = CGSMainConnectionID()
var lastSpaceID: Int? = nil

for i in 0..<20 {  // Run for 10 seconds (20 * 0.5s)
    let spaceID = CGSGetActiveSpace(conn)
    
    if spaceID != lastSpaceID {
        print("✓ Space changed: \(lastSpaceID ?? 0) -> \(spaceID)", terminator: "\n")
        fflush(stdout)
        lastSpaceID = spaceID
    } else if i % 4 == 0 {
        print("  Current: \(spaceID)", terminator: "\n")
        fflush(stdout)
    }
    
    usleep(500_000)
}

print("Done", terminator: "\n")
fflush(stdout)
