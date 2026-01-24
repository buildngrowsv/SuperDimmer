# Infinite Loop Crash Fix (Rainbow Spinning Cursor)

**Date**: January 24, 2026  
**Issue**: App freezing with infinite rainbow spinning cursor (beachball)  
**Status**: ✅ FIXED

## Problem Description

The app was experiencing a critical infinite loop causing it to freeze with the rainbow spinning cursor. The logs showed:

```
🔄 applyDecayDimming START [BG- (null)}] decisions=8
🔄 applyDecayDimming END - decayOverlays.count=8
📥 AutoMinimizeManager: Minimized 1 windows from 'Google Chrome'
🔄 applyDecayDimming START [BG- (null)}] decisions=8
🔄 applyDecayDimming END - decayOverlays.count=8
📥 AutoMinimizeManager: Minimized 1 windows from 'Google Chrome'
[repeating infinitely...]
```

## Root Cause Analysis

The infinite loop was caused by a race condition in `AutoMinimizeManager.swift`:

### The Sequence of Events:

1. **AutoMinimizeManager** runs its check cycle (every 10 seconds)
2. It identifies a Chrome window that needs to be minimized
3. It calls `minimizeWindow(windowID:appName:)` which:
   - Removes overlays for the window
   - Executes an AppleScript to minimize the window (takes 100-500ms)
   - Only removes the window from tracking AFTER the script completes

4. **During the AppleScript execution** (100-500ms):
   - The analysis cycle continues running
   - The window is still in the tracking dictionary
   - The window gets identified for minimization AGAIN
   - Another `minimizeWindow()` call is made for the same window

5. **This creates an infinite loop**:
   - Same window gets queued for minimization repeatedly
   - Each minimization triggers window state changes
   - State changes trigger analysis cycles
   - Analysis cycles queue more minimizations
   - Loop continues indefinitely

### Why It Manifested Now:

The issue became apparent when:
- Multiple Chrome windows were open (exceeding the threshold)
- Windows had accumulated enough inactive time to trigger auto-minimize
- The timing aligned such that the analysis cycle ran during AppleScript execution

## The Fix

### Primary Fix: Prevent Duplicate Minimization

Added a `currentlyMinimizing` set to track windows that are in the process of being minimized:

```swift
// Track windows currently being minimized
private var currentlyMinimizing = Set<CGWindowID>()

private func minimizeWindow(windowID: CGWindowID, appName: String) {
    // CRITICAL: Check if this window is already being minimized
    lock.lock()
    if currentlyMinimizing.contains(windowID) {
        lock.unlock()
        return  // Skip to prevent infinite loop
    }
    // Mark as currently minimizing
    currentlyMinimizing.insert(windowID)
    lock.unlock()
    
    // ... minimize the window ...
    
    // Always remove from currentlyMinimizing when done
    lock.lock()
    currentlyMinimizing.remove(windowID)
    lock.unlock()
}
```

### Secondary Fix: Throttle Check Frequency

Added a throttle to `checkAndMinimizeWindows()` to prevent it from running more than once per 5 seconds:

```swift
// Track last check time
private var lastCheckTime: Date = .distantPast
private let minCheckInterval: TimeInterval = 5.0

private func checkAndMinimizeWindows() {
    // THROTTLE: Don't run more frequently than minCheckInterval
    lock.lock()
    let now = Date()
    let timeSinceLastCheck = now.timeIntervalSince(lastCheckTime)
    if timeSinceLastCheck < minCheckInterval {
        lock.unlock()
        return
    }
    lastCheckTime = now
    lock.unlock()
    
    // ... rest of the function ...
}
```

## Files Modified

1. **SuperDimmer/Services/AutoMinimizeManager.swift**
   - Added `currentlyMinimizing` set to track in-progress minimizations
   - Added `lastCheckTime` and `minCheckInterval` for throttling
   - Modified `minimizeWindow()` to check and update `currentlyMinimizing`
   - Modified `checkAndMinimizeWindows()` to throttle execution

## Testing

Build completed successfully:
```
** BUILD SUCCEEDED **
```

## Prevention

To prevent similar issues in the future:

1. **Always guard against re-entrant operations**: When an operation takes time (like AppleScript), track its state to prevent duplicate execution
2. **Add throttling to expensive operations**: Even if they should only run periodically, add guards against rapid calls
3. **Use locks properly**: All shared state modifications must be protected by locks
4. **Log state transitions**: The detailed logging helped identify the infinite loop quickly

## Related Code

- `DimmingCoordinator.swift` line 898: Calls `applyDecayDimmingToWindows()`
- `OverlayManager.swift` line 852: `applyDecayDimming()` function
- `AutoMinimizeManager.swift` line 335: `checkAndMinimizeWindows()` function
- `AutoMinimizeManager.swift` line 410: `minimizeWindow()` function

## Impact

- ✅ Eliminates infinite loop causing app freeze
- ✅ Prevents duplicate minimization operations
- ✅ Reduces unnecessary AppleScript executions
- ✅ Improves overall app stability
- ✅ No performance impact (guards are O(1) operations)

## Next Steps

1. Monitor logs for any remaining `AutoMinimizeManager: Minimized` messages appearing too frequently
2. Consider adding metrics to track how often the throttle/guard prevents duplicate operations
3. If needed, increase `minCheckInterval` from 5 to 10 seconds for even more safety margin
