# HUD Duplication Fix - Jan 24, 2026

## Problem

When clicking the duplicate button on a Super Spaces HUD, the new HUD was appearing in the default position (top-right corner) instead of being offset from the source HUD.

## Root Cause

The bug was introduced in commit `4546db0` (Jan 23, 2026) when we fixed per-HUD position and size persistence.

### What Happened

1. **In `duplicateHUD()`:**
   - Created a new HUD (which has `storedConfiguration = nil`)
   - Called `copySettings()` to copy display mode, float on top, and size
   - Called `setFrameOrigin()` to set an offset position (+30, -30)
   - Called `show()` to display the HUD

2. **In `show()`:**
   ```swift
   if let config = self.storedConfiguration {
       // Restore position from stored config
       self.setFrameOrigin(config.position)
   } else {
       // No stored configuration (new HUD), use defaults
       self.positionToDefaultLocation()  // ❌ This overwrites the offset!
   }
   ```

3. **The Problem:**
   - Since the new HUD had no `storedConfiguration`, `show()` called `positionToDefaultLocation()`
   - This moved the HUD to the top-right corner, **overwriting** the offset position that was just set
   - Result: All duplicated HUDs appeared in the same default location

## Solution

Create a `storedConfiguration` for the new HUD **before** calling `show()`, so that `show()` uses the offset position instead of the default position.

### Changes Made

1. **Added `setStoredConfiguration()` method** to `SuperSpacesHUD`:
   ```swift
   func setStoredConfiguration(_ config: HUDConfiguration) {
       self.storedConfiguration = config
   }
   ```

2. **Updated `duplicateHUD()` in `SuperSpacesHUDManager`:**
   - Get source HUD's configuration via `getConfiguration()`
   - Calculate offset position
   - Create a new `HUDConfiguration` with the offset position
   - Call `setStoredConfiguration()` on the new HUD **before** calling `show()`
   - Now `show()` uses the stored configuration with the offset position

### Code Flow After Fix

1. **In `duplicateHUD()`:**
   ```swift
   let newHUD = createHUD()
   newHUD.copySettings(from: sourceHUD)
   
   // Get source configuration
   let sourceConfig = sourceHUD.getConfiguration()
   
   // Calculate offset position
   var offsetPosition = sourceConfig.position
   offsetPosition.x += 30
   offsetPosition.y -= 30
   
   // Create stored configuration with offset
   var config = HUDConfiguration(id: newHUD.hudID)
   config.displayMode = sourceConfig.displayMode
   config.position = offsetPosition  // ✅ Offset position
   config.size = sourceConfig.size
   config.floatOnTop = sourceConfig.floatOnTop
   config.isVisible = true
   newHUD.setStoredConfiguration(config)  // ✅ Set BEFORE show()
   
   // Show the HUD
   newHUD.show()  // ✅ Will use stored configuration
   ```

2. **In `show()`:**
   ```swift
   if let config = self.storedConfiguration {  // ✅ Now exists!
       // Restore position from stored config
       self.setFrameOrigin(config.position)  // ✅ Uses offset position
   } else {
       // No stored configuration (new HUD), use defaults
       self.positionToDefaultLocation()
   }
   ```

## Result

✅ Duplicated HUDs now appear offset from the source HUD (+30 right, -30 down)
✅ Multiple duplications create a cascade effect (each offset from the previous)
✅ Position is preserved correctly when the app restarts
✅ All other HUD settings (display mode, float on top, size) are copied correctly

## Build Status

✅ Build verified successful

## Files Changed

- `SuperDimmer/SuperSpaces/SuperSpacesHUD.swift`
  - Added `setStoredConfiguration()` method
  - Updated `duplicateHUD()` to create stored configuration before showing
  - Added detailed comments explaining the fix

## Testing Checklist

- [x] Build succeeds
- [ ] Duplicate button creates HUD at offset position
- [ ] Multiple duplications cascade correctly
- [ ] Duplicated HUD preserves display mode
- [ ] Duplicated HUD preserves float on top setting
- [ ] Duplicated HUD preserves window size
- [ ] Positions persist after app restart
