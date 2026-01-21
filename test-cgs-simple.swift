import Foundation

typealias CGSConnectionID = Int

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> Int

print("Getting connection...")
let conn = CGSMainConnectionID()
print("Connection ID: \(conn)")

print("Getting active Space...")
let spaceID = CGSGetActiveSpace(conn)
print("Active Space ID: \(spaceID)")
