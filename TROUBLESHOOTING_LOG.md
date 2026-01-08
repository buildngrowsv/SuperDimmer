# SuperDimmer Troubleshooting Log

## Issue: Toggle Dimming Crashes/Freezes App

**Date:** January 7, 2026

### Problem Description
When user toggles the "Brightness Dimming" switch ON/OFF in the menu bar popover, the app either:
1. Crashes after 1-2 toggle cycles
2. Freezes completely (spinning wheel)

---

## Attempt 1: Initial Implementation
**What we did:**
- `handleDimmingToggled()` in AppDelegate responds to Combine publisher for `isDimmingEnabled`
- Creates `DimmingCoordinator` if nil, calls `start()`
- `start()` creates overlays via `DispatchQueue.main.async`
- `stop()` removes overlays via `DispatchQueue.main.async`

**What happened:**
- Overlay created successfully
- Immediately removed by `performAnalysisCycle()` which checked `configuration.isEnabled`
- Race condition: async overlay creation, then sync check of settings

**Learning:**
- Don't re-check `isEnabled` in the timer callback - that's what `start()`/`stop()` are for
- Async operations can interleave in unexpected ways

---

## Attempt 2: Remove isEnabled check from performAnalysisCycle
**What we did:**
- Removed the guard that checked `configuration.isEnabled` in `performAnalysisCycle()`
- Timer callback now just updates dim level, doesn't decide whether to run

**What happened:**
- Worked for ONE toggle cycle
- Crashed when toggling quickly (ON → OFF → ON)

**Learning:**
- The issue isn't just the analysis cycle
- Rapid toggling creates race between async overlay create/remove operations

---

## Attempt 3: Add debouncing + coordinatorQueue
**What we did:**
- Added 100ms debounce to `handleDimmingToggled()` using `DispatchWorkItem`
- Added `coordinatorQueue` (serial queue) to synchronize start/stop
- Used `DispatchQueue.main.sync` inside coordinatorQueue to ensure overlay operations complete before returning

**What happened:**
- **APP DEADLOCKED** - spinning wheel, complete freeze
- Could not interact with app at all

**Root cause:**
```
Main thread → Combine sink → handleDimmingToggled → debounce fires on main → 
coordinatorQueue.sync → DispatchQueue.main.sync → DEADLOCK
```
When you call `DispatchQueue.main.sync` from the main thread, it waits forever for itself.

**Learning:**
- NEVER use `DispatchQueue.main.sync` from code that might already be on main thread
- Combine's `@Published` sinks fire on main thread
- SwiftUI bindings update on main thread

---

## Attempt 4: Remove sync dispatches, use objc_sync mutex
**What we did:**
- Removed `coordinatorQueue.sync` wrapper
- Removed `DispatchQueue.main.sync` calls
- Added `objc_sync_enter/exit` for simple locking
- Added `dispatchPrecondition(condition: .onQueue(.main))` to verify thread

**Status:** UNTESTED - user reported still seeing issues

---

## Current Code Flow

```
User toggles switch
    ↓
SwiftUI binding updates settings.isDimmingEnabled (main thread)
    ↓
@Published didSet fires, saves to UserDefaults
    ↓
Combine $isDimmingEnabled sink fires (main thread)
    ↓
handleDimmingToggled(enabled) called
    ↓
DispatchWorkItem scheduled with 100ms delay (debounce)
    ↓
After 100ms, workItem executes on main thread
    ↓
If enabled: create coordinator if nil, call start()
If disabled: call stop()
    ↓
start(): creates overlays, starts timer
stop(): invalidates timer, removes overlays
```

---

## Key Technical Constraints

1. **Overlay windows (NSWindow) must be created/destroyed on main thread**
2. **SwiftUI/Combine updates happen on main thread**
3. **Timer callbacks happen on main thread (when scheduled on main RunLoop)**
4. **Cannot use DispatchQueue.main.sync from main thread = deadlock**

---

## Potential Solutions to Try

### Option A: Single-threaded, no async
Since everything must happen on main thread anyway, just do it all synchronously:
- Remove all `DispatchQueue.main.async` wrappers
- Add simple boolean flag to prevent re-entry
- Trust that main thread serializes everything naturally

### Option B: State machine approach
- Create explicit states: `.idle`, `.starting`, `.running`, `.stopping`
- Only allow valid transitions
- Ignore toggle requests during transitions

### Option C: Don't recreate overlays
- Create overlays once on app launch
- `start()` just shows them (orderFront)
- `stop()` just hides them (orderOut)
- No destruction/recreation = no race conditions

### Option D: Disable toggle during transition
- Set toggle to disabled when starting/stopping
- Re-enable after operation complete
- User can't rapid-fire toggle

---

## Questions to Investigate

1. Is `OverlayManager.removeAllOverlays()` synchronous or does it have async cleanup?
2. Is `DimOverlayWindow.close()` or `orderOut()` synchronous?
3. Are there any notifications/observers firing during overlay destruction that cause issues?
4. Is the crash in Swift code or in AppKit/system code?

---

## Console Output Pattern Before Crash

```
📺 Full-screen dimming enabled on 1 display(s)
🔄 Dimming toggled: OFF
⏹️ Stopping DimmingCoordinator...
⏹️ DimmingCoordinator stopped
🗑️ All overlays removed
📦 DimOverlayWindow destroyed: display-5
[CRASH or FREEZE happens here when toggling ON again]
```

The crash happens AFTER successful stop, when trying to start again.

---

## Attempt 5: Hide/Show instead of Create/Destroy (SOLUTION)

**Date:** January 7, 2026

**Root Cause Discovered:**
The OverlayManager already had `hideAllOverlays()` and `showAllOverlays()` methods that 
use `orderOut()` and `orderFront()` - keeping windows alive. But we were using 
`removeAllOverlays()` which calls `close()` and destroys the windows.

NSWindow destruction triggers various AppKit cleanup, notifications, and potentially 
async operations. Rapidly creating and destroying windows caused race conditions in 
AppKit that led to crashes.

**What we did:**
1. Changed `DimmingCoordinator.stop()` to call `hideAllOverlays()` instead of `removeAllOverlays()`
2. Changed `DimmingCoordinator.start()` to check if overlays exist:
   - If yes: call `showAllOverlays()` (just unhide them)
   - If no: call `enableFullScreenDimming()` (create them once)
3. Added `DimmingCoordinator.cleanup()` for actual destruction on app quit
4. Removed the `dispatchPrecondition` and `objc_sync` (no longer needed)
5. Removed the debouncing in AppDelegate (no longer needed - toggle is now safe)

**Why this works:**
- Windows are created ONCE and reused
- Toggle just changes visibility (orderOut/orderFront)
- No destruction = no race conditions
- Much better performance too (no recreation overhead)

**Status:** ✅ FIXED - User confirmed working with no crashes!

---

## Resolution Summary

The toggle crash was caused by rapidly creating/destroying NSWindow instances. The fix was:
1. Use `hideAllOverlays()` instead of `removeAllOverlays()` on stop
2. Use `showAllOverlays()` instead of `enableFullScreenDimming()` on restart
3. Windows stay alive and are just shown/hidden

Color Temperature feature added:
- `ColorTemperatureManager.swift` using `CGSetDisplayTransferByFormula`
- Kelvin to RGB conversion using Tanner Helland algorithm
- Observes settings changes automatically
- Restores gamma on disable or app quit

---

## Feature: Multiple Windows Not Dimmed (Jan 8, 2026)

**User Report:**
"One of the mail windows is getting dimmed but the other is not."

**Root Cause:**
The `performPerRegionAnalysis()` function was only analyzing the **active/frontmost** window:
```swift
let windowsToAnalyze = windows.filter { $0.isActive }  // WRONG
```

This was originally done to avoid z-order issues, but it prevented dimming other bright windows.

**Fix:**
Changed to analyze ALL visible windows:
```swift
let windowsToAnalyze = windows  // CORRECT - analyze all
```

The z-ordering is now handled by:
1. Overlay window level set to `.floating` (above normal windows, below system UI)
2. WindowTrackerService filtering already excludes system UI and our own overlays

---

## Feature: Soft/Feathered Edges (Jan 8, 2026)

**User Request:**
"Can we make the dimming blurred at the edges without too much load on rendering."

**Implementation:**
Added feathered edge effect that creates a soft gradient around overlay edges:

1. New settings in `SettingsManager`:
   - `edgeBlurEnabled: Bool` (default: false)
   - `edgeBlurRadius: Double` (5-50pt, default: 15pt)

2. New method in `DimOverlayWindow`:
   - `setEdgeBlur(enabled:radius:)` - applies or removes edge mask
   - `createFeatheredMaskImage()` - creates grayscale gradient mask image
   - Uses CALayer mask for GPU-accelerated rendering (no expensive blur filters)

3. UI in `MenuBarView`:
   - "Soft Edges" toggle
   - Blur radius slider (when enabled)

**Performance:**
- Uses CoreGraphics bitmap mask, not blur filter
- Mask is created once per overlay creation/resize
- GPU handles alpha blending efficiently

---

## Feature: Excluded Apps (Jan 8, 2026)

**User Request:**
"Add a way to exclude apps from dimming."

**Implementation:**
1. New setting: `excludedAppBundleIDs: [String]` in SettingsManager

2. Modified `WindowTrackerService.shouldTrackWindow()`:
   - Combined system exclusions with user exclusions
   - Computed property rechecks settings on each call

3. New UI:
   - `ExcludedAppsPreferencesTab` in Preferences window
   - Shows list of excluded apps with icons/names
   - Add from running apps dropdown
   - Manual bundle ID entry field
   - Remove button per app

---

## Issue: AttributeGraph Cycle Warnings

**Problem:**
SwiftUI console spam with warnings like:
```
=== AttributeGraph: cycle detected through attribute 113324 ===
```

**Cause:**
State changes triggered during view body evaluation, common when:
- `@Published` property modified inside a Toggle's `isOn` binding
- Combine sink fires while view is updating

**Fix:**
Wrapped state changes in `DispatchQueue.main.async` to defer to next run loop:
```swift
Toggle("", isOn: Binding(
    get: { settings.intelligentDimmingEnabled },
    set: { newValue in
        DispatchQueue.main.async {  // <-- Defer state change
            if newValue {
                requestScreenRecordingAndEnable()
            } else {
                settings.intelligentDimmingEnabled = false
            }
        }
    }
))
```

This breaks the cycle by allowing the current view update to complete before modifying state.

---

## [Jan 8, 2026] Website & GitHub Setup

### Progress Made

**Mac App Repository:**
- Committed all Mac app code to GitHub
- Fixed embedded git repository issue (SuperDimmer-Mac-App had nested `.git`)
- Repository: https://github.com/ak/SuperDimmer

**Marketing Website Created:**
- Created new repository: https://github.com/ak/SuperDimmer-Website
- Built modern, polished landing page with:
  - Hero section with app mockup
  - 6 feature cards
  - How-it-works 4-step flow
  - Pricing (Free $0 / Pro $12)
  - CTA and footer
- Design: Dark theme, warm amber accents, Cormorant Garamond + Sora fonts
- Tech: Pure HTML/CSS, responsive, CSS animations

### Next Steps
- [ ] Deploy to Cloudflare Pages
- [ ] Purchase and configure superdimmer.app domain
- [ ] Integrate Paddle checkout
- [ ] Add download links once app is signed/notarized
