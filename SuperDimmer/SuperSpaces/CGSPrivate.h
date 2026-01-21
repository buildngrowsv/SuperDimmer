//
//  CGSPrivate.h
//  SuperDimmer
//
//  Created by SuperDimmer on 1/21/26.
//
//  PURPOSE: Private CoreGraphics Services (CGS) API declarations for Space detection.
//  These are undocumented Apple APIs that provide access to Space information.
//
//  WHY PRIVATE APIs:
//  - Public APIs (NSWorkspace, plist) don't provide real-time Space information
//  - NSWorkspace.activeSpaceDidChangeNotification doesn't fire reliably
//  - com.apple.spaces.plist doesn't update in real-time
//  - CGS APIs are the ONLY way to get current Space ID reliably
//
//  APP STORE COMPATIBILITY:
//  - These APIs are used by many shipping Mac apps (e.g., Hammerspoon, BetterTouchTool)
//  - Apple generally allows them for non-malicious purposes
//  - If rejected, we can fall back to plist-based detection (less reliable)
//
//  TECHNICAL NOTES:
//  - CGSGetActiveSpace returns the current Space ID
//  - Space IDs are integers that match the ManagedSpaceID in the plist
//  - These APIs have been stable since macOS 10.5
//  - They may break in future macOS versions, but unlikely
//

#ifndef CGSPrivate_h
#define CGSPrivate_h

#import <Foundation/Foundation.h>

// CoreGraphics Services connection type
typedef int CGSConnectionID;

// Get the default connection to the window server
extern CGSConnectionID CGSMainConnectionID(void);

// Get the ID of the currently active Space
// Returns the ManagedSpaceID (same as in com.apple.spaces.plist)
extern int CGSGetActiveSpace(CGSConnectionID cid);

// Get all Space IDs for a display
// Returns an array of Space IDs
extern CFArrayRef CGSCopySpaces(CGSConnectionID cid, int displayID);

// Display ID constants
#define kCGSAllDisplays 0xFFFFFFFF
#define kCGSMainDisplay 0

#endif /* CGSPrivate_h */
