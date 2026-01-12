# SuperDimmer Build Checklist
## Step-by-Step Implementation Guide with Verification Checkpoints
### Version 1.0 | January 7, 2026

---

## 📋 How to Use This Checklist

Each phase contains:
- **Tasks** with checkboxes `[ ]` → Mark `[x]` when complete
- **Build Checks** 🔨 → Verify xcodebuild succeeds
- **Test Checks** 🧪 → Manual or automated testing
- **Review Points** 👀 → Code review / quality checks

**Rule:** Do NOT proceed to next phase until all checks in current phase pass.

---

## 🏗️ PHASE 0: Project Setup & Environment
**Estimated Time: 1 day**

### 0.1 Development Environment
- [x] Xcode 15.0+ installed and updated
- [x] macOS 14.0+ (Sonoma) on development machine
- [ ] Apple Developer account active (for signing)
- [x] Git repository initialized with .gitignore
- [x] Mac app pushed to GitHub: https://github.com/ak/SuperDimmer ✅ (Jan 8, 2026)

### 0.2 Create Xcode Project
- [x] Create new macOS App project in Xcode
- [x] Set Product Name: `SuperDimmer`
- [x] Set Bundle Identifier: `com.superdimmer.app`
- [x] Set Interface: SwiftUI
- [x] Set Language: Swift
- [x] Set minimum deployment target: macOS 13.0
- [x] Save project to `/Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App/`

### 0.3 Project Configuration
- [x] Configure app as menu bar only (LSUIElement = true in Info.plist)
- [x] Set app category: `public.app-category.utilities`
- [ ] Configure code signing (Developer ID for distribution)
- [x] Set up build configurations (Debug, Release)
- [x] Create SuperDimmer.entitlements file

### 0.4 Initial Entitlements Setup
- [x] Add `com.apple.security.device.screen-capture` entitlement
- [x] Add `com.apple.security.network.client` entitlement
- [x] Add `com.apple.security.automation.apple-events` entitlement
- [x] Add `com.apple.security.personal-information.location` entitlement

#### 🔨 BUILD CHECK 0.1
```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App
xcodebuild -scheme SuperDimmer -configuration Debug build 2>&1 | head -n 50
```
- [x] Build succeeds with no errors
- [x] Build succeeds with no warnings (or only expected warnings)

#### 🧪 TEST CHECK 0.1
- [x] App launches from Xcode
- [x] App appears in menu bar (no dock icon)
- [x] App quits cleanly

#### 👀 REVIEW POINT 0.1
- [x] Info.plist has all required keys
- [x] Entitlements file is properly linked to target
- [x] Bundle identifier matches intended value

---

## 🏗️ PHASE 1: Foundation (MVP)
**Estimated Time: 4 weeks**

### Week 1: Menu Bar Infrastructure

#### 1.1 Menu Bar App Structure
- [x] Create `SuperDimmerApp.swift` with @main entry point
- [x] Create `MenuBarController.swift` for NSStatusItem management
- [x] Implement basic menu bar icon (sun symbol)
- [x] Create dropdown menu with placeholder items
- [x] Add "Quit" menu item with ⌘Q shortcut

#### 🔨 BUILD CHECK 1.1
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build 2>&1 | tail -n 20
```
- [x] Build succeeds
- [x] No linker errors

#### 🧪 TEST CHECK 1.1
- [x] Menu bar icon appears on launch
- [x] Clicking icon shows dropdown menu (popover)
- [x] Quit command terminates app
- [x] App shows no dock icon

---

#### 1.2 Settings Management
- [x] Create `SettingsManager.swift` for UserDefaults wrapper
- [x] Define settings keys enum for type safety
- [x] Implement `isDimmingEnabled: Bool` setting
- [x] Implement `globalDimLevel: Double` setting (0.0-1.0)
- [x] Implement `brightnessThreshold: Double` setting (0.0-1.0)
- [x] Add settings change notification system

#### 🔨 BUILD CHECK 1.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] No compiler warnings about optionals

#### 🧪 TEST CHECK 1.2
- [x] Settings persist after app restart
- [x] Default values load correctly on first launch
- [x] Settings changes notify observers

---

### Week 2: Basic Overlay System

#### 1.3 Overlay Window Foundation
- [x] Create `DimOverlayWindow.swift` (NSWindow subclass)
- [x] Configure borderless, transparent window
- [x] Set `ignoresMouseEvents = true` (click-through)
- [x] Set window level to `.screenSaver`
- [x] Configure `collectionBehavior` for all Spaces
- [x] Implement dim level property with animation

#### 🔨 BUILD CHECK 1.3
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] NSWindow subclass compiles correctly

#### 🧪 TEST CHECK 1.3
- [x] Overlay window appears on screen
- [x] Overlay is click-through (can click items beneath)
- [x] Overlay dims content visibly
- [x] Overlay opacity can be changed

---

#### 1.4 Overlay Manager
- [x] Create `OverlayManager.swift` singleton
- [x] Implement full-screen overlay creation for each display
- [x] Implement overlay enable/disable methods
- [x] Handle display configuration changes
- [x] Add support for multi-monitor (create overlay per display)

#### 🔨 BUILD CHECK 1.4
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 1.4
- [x] Full-screen overlay covers entire display
- [ ] Overlay works on external monitors (not tested yet)
- [x] Disabling removes overlay completely
- [x] Re-enabling recreates overlay (no crashes!)

---

### Week 3: Menu Bar UI Integration

#### 1.5 Basic Controls UI
- [x] Create `MenuBarView.swift` (SwiftUI view for popover)
- [x] Implement master on/off toggle
- [x] Implement dim level slider (0-100%)
- [x] Wire controls to SettingsManager
- [x] Wire controls to OverlayManager
- [x] Add visual feedback for current state

#### 🔨 BUILD CHECK 1.5
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [ ] SwiftUI previews render

#### 🧪 TEST CHECK 1.5
- [x] Toggle turns dimming on/off immediately
- [x] Slider adjusts dim level in real-time
- [x] UI reflects persisted state on launch

---

#### 1.6 Menu Bar Icon States
- [x] Create icon assets for different states
- [x] Implement icon state: Disabled (outline)
- [x] Implement icon state: Active (filled)
- [x] Update icon based on dimming enabled state
- [x] Support both light and dark menu bar

#### 🔨 BUILD CHECK 1.6
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] Asset catalog has no warnings

#### 🧪 TEST CHECK 1.6
- [ ] Icon changes when toggling dimming
- [ ] Icon visible on light menu bar
- [ ] Icon visible on dark menu bar

---

### Week 4: Permission Handling & Polish

#### 1.7 Screen Recording Permission
- [x] Create `PermissionManager.swift`
- [x] Implement screen recording permission check
- [x] Implement permission request flow
- [x] Create user-facing permission explanation UI
- [x] Add deep link to System Settings → Privacy
- [x] Handle permission denied gracefully

#### 🔨 BUILD CHECK 1.7
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] Privacy string present in Info.plist

#### 🧪 TEST CHECK 1.7
- [ ] Permission prompt appears when needed
- [ ] App functions correctly after permission granted
- [ ] App shows helpful message if permission denied
- [ ] Settings link opens correct System Settings pane

---

#### 1.8 Launch at Login
- [x] Add ServiceManagement framework
- [x] Create `LaunchAtLoginManager.swift`
- [x] Implement launch at login toggle
- [x] Add UI toggle in preferences
- [ ] Test login item registration

#### 🔨 BUILD CHECK 1.8
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] ServiceManagement framework linked

#### 🧪 TEST CHECK 1.8
- [ ] Toggle adds app to login items
- [ ] Toggle removes app from login items
- [ ] Setting persists across app restarts

---

#### 1.9 Phase 1 Integration Testing

#### 🔨 BUILD CHECK - PHASE 1 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [ ] Release build succeeds
- [ ] No compiler warnings
- [ ] App size is reasonable (< 10 MB)

#### 🧪 TEST CHECK - PHASE 1 FINAL
- [ ] Fresh install works (delete app data, reinstall)
- [ ] All menu bar controls work
- [ ] Dimming persists across app restart
- [ ] Multi-monitor setup works
- [ ] Performance: CPU < 1% when idle
- [ ] Performance: Memory < 30 MB

#### 👀 REVIEW POINT - PHASE 1 COMPLETE
- [ ] Code follows Swift naming conventions
- [ ] All files have descriptive headers
- [ ] Comments explain "why" not just "what"
- [ ] No force unwraps without justification
- [ ] Error handling is comprehensive

---

## 🏗️ PHASE 2: Intelligent Detection
**Estimated Time: 3 weeks**

### Week 5: Screen Capture Service

#### 2.1 Screen Capture Implementation
- [x] Create `ScreenCaptureService.swift`
- [x] Implement `captureMainDisplay() -> CGImage?`
- [x] Implement `captureRegion(_ rect: CGRect) -> CGImage?`
- [x] Add capture throttling (max frequency)
- [x] Handle capture permission errors gracefully

#### 🔨 BUILD CHECK 2.1
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] CoreGraphics properly linked

#### 🧪 TEST CHECK 2.1
- [ ] Screen capture returns valid CGImage
- [ ] Capture works with permission granted
- [ ] Capture fails gracefully without permission
- [ ] Capture throttling works correctly

---

#### 2.2 Brightness Analysis Engine
- [x] Create `BrightnessAnalysisEngine.swift`
- [x] Implement luminance calculation (Rec. 709)
- [x] Implement `averageLuminance(in: CGImage, rect: CGRect) -> Float`
- [x] Use Accelerate/vDSP for performance
- [x] Add downsampling for efficiency

#### 🔨 BUILD CHECK 2.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds
- [x] Accelerate framework linked

#### 🧪 TEST CHECK 2.2
- [ ] White image returns luminance ~1.0
- [ ] Black image returns luminance ~0.0
- [ ] Mixed content returns expected range
- [ ] Performance: Analysis < 50ms for full screen

---

### 2.2.1 UI/UX Overhaul & Feature Reorganization
**Priority: HIGH | Added: January 9, 2026**

> **MAJOR CHANGE** - Reorganizing the app's feature hierarchy for better UX
>
> Current issues:
> - First-time users don't see immediate value (dimming is OFF by default)
> - Feature naming is confusing (what is "Intelligent Mode"?)
> - Too many toggles without clear explanations
> - No distinction between Light/Dark mode preferences
> - Debug features visible to end users
>
> Goal: Make the app immediately useful while offering advanced features for power users

---

#### 2.2.1.1 Appearance Mode System (Light/Dark/System)
> Settings should adapt to user's preferred appearance. Dark mode users want dimming features ON.
> Light mode users typically don't need aggressive dimming.

- [ ] Add `appearanceMode` setting: `.system`, `.dark`, `.light`
- [ ] Add `AppearanceManager.swift` to observe system appearance
- [ ] Store separate settings profiles for light vs dark mode:
  - [ ] `darkModeSettings: DimmingProfile`
  - [ ] `lightModeSettings: DimmingProfile`
- [ ] Create `DimmingProfile` struct with all dimming-related settings
- [ ] Auto-switch profiles when system appearance changes (if mode = .system)
- [ ] Add appearance picker at TOP of Preferences window
- [ ] Default dark mode: Super Dimming ON, features enabled
- [ ] Default light mode: Super Dimming OFF or minimal

#### 🧪 TEST CHECK 2.2.1.1
- [ ] Switching to Dark mode loads dark profile
- [ ] Switching to Light mode loads light profile
- [ ] System mode follows macOS appearance
- [ ] Profile changes persist correctly

---

#### 2.2.1.2 "Super Dimming" - Simplified Full-Screen Mode (DEFAULT)
> The main feature that works immediately out of the box.
> Uses full-screen brightness analysis to adjust dim level automatically.

- [ ] Rename current full-screen dimming to "Super Dimming"
- [ ] Enable by default on first install
- [ ] Add "Auto" mode (default) that adjusts based on screen brightness:
  - [ ] Capture full-screen screenshot periodically
  - [ ] Calculate average brightness
  - [ ] Adjust dim level ±15% (configurable) around base setting
  - [ ] Bright screen → increase dimming, Dark screen → decrease dimming
- [ ] Add manual override option (fixed dim level)
- [ ] Settings for Auto mode:
  - [ ] `autoAdjustRange: Double` (default 0.15 = ±15%)
  - [ ] `autoAdjustSensitivity: Double` (how quickly to respond)
  - [ ] Base dim level slider
- [ ] Clear explanatory text in UI:
  > "Super Dimming applies a gentle overlay to reduce screen brightness.
  > Auto mode adjusts based on what's on your screen."

#### 🔨 BUILD CHECK 2.2.1.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 2.2.1.2
- [ ] First launch shows Super Dimming ON
- [ ] Auto mode responds to bright/dark content
- [ ] Manual mode maintains fixed level
- [ ] Range slider affects adjustment amount
- [ ] Explanatory text is clear and helpful

---

#### 2.2.1.3 "Dim Windows Individually" - Beta Feature
> Advanced mode that dims specific windows. Marked as Beta because it's more complex.

- [ ] Add "Dim Windows Individually (Beta)" toggle
- [ ] OFF by default
- [ ] Show beta badge/label in UI
- [ ] Only visible when Super Dimming is ON
- [ ] When enabled, disables full-screen overlay and switches to per-window
- [ ] Clear explanation:
  > "Analyzes each window and applies individual dimming based on content brightness.
  > Beta: May have higher CPU usage."

#### 🧪 TEST CHECK 2.2.1.3
- [ ] Toggle shows "(Beta)" label
- [ ] Only appears when Super Dimming is ON
- [ ] Enabling switches from full-screen to per-window overlays
- [ ] Disabling returns to Super Dimming behavior

---

#### 2.2.1.4 "Dim Bright Areas" - Nested Feature
> Per-region dimming within windows. Only available when per-window is enabled.

- [ ] Add "Dim Bright Areas" toggle
- [ ] OFF by default
- [ ] Only appears when "Dim Windows Individually" is ON
- [ ] When enabled, detects bright regions within each window
- [ ] Clear explanation:
  > "Finds bright areas within windows (like white backgrounds in emails)
  > and dims only those regions. Uses more resources."

#### 🧪 TEST CHECK 2.2.1.4
- [ ] Toggle only visible when "Dim Windows Individually" is ON
- [ ] Enabling shows per-region overlays
- [ ] Disabling returns to per-window overlays

---

#### 2.2.1.5 "SuperFocus" - Productivity Features
> Groups all the inactivity-based features under a single umbrella concept.

- [ ] Create "SuperFocus" section in Preferences
- [ ] Add master "SuperFocus" toggle
- [ ] When enabled, shows sub-features:
  - [ ] **Window Fade**: Inactive windows gradually dim (current decay dimming)
  - [ ] **Auto-Hide Apps**: Apps not used for X minutes get hidden
  - [ ] **Auto-Minimize Windows**: Excess windows get minimized
- [ ] Clear explanation for each:
  > "SuperFocus helps you concentrate by de-emphasizing unused windows and apps."
  >
  > **Window Fade**: "Gradually dims windows you haven't clicked on recently"
  > **Auto-Hide Apps**: "Hides entire apps after they've been in the background"
  > **Auto-Minimize Windows**: "Minimizes excess windows when you have too many open"
- [ ] Settings for each sub-feature accessible via disclosure/expand

#### 🧪 TEST CHECK 2.2.1.5
- [ ] SuperFocus master toggle enables/disables all sub-features
- [ ] Each sub-feature can be individually configured
- [ ] Explanatory text is present and helpful
- [ ] Settings persist correctly

---

#### 2.2.1.6 Debug/Developer Tools
> Remove debug features from regular users, add Dev Tools section for developers.

- [ ] Remove "Debug Borders" from main UI
- [ ] Add `isDevMode` computed property (check for debug build or dev flag)
- [ ] Create "Developer Tools" section in Preferences (only visible in dev mode)
  - [ ] Debug Borders toggle
  - [ ] Analysis timing logs
  - [ ] Overlay count display
  - [ ] Force refresh button
- [ ] Alternative: Add hidden gesture/shortcut to enable Dev Tools
  - [ ] e.g., Option+Click on version number 5 times

#### 🧪 TEST CHECK 2.2.1.6
- [ ] Debug Borders NOT visible in release build
- [ ] Dev Tools visible in debug build
- [ ] Hidden activation works (if implemented)

---

#### 2.2.1.7 Reset to Defaults
> Users should be able to easily return to factory settings.

- [ ] Add "Reset to Defaults" button in Preferences
- [ ] Confirmation dialog before reset
- [ ] Reset behavior:
  - [ ] Clears all UserDefaults for app
  - [ ] Reloads default DimmingProfile for current appearance mode
  - [ ] Restores first-launch state
- [ ] Clear explanation:
  > "Resets all settings to their original values. This cannot be undone."

#### 🧪 TEST CHECK 2.2.1.7
- [ ] Reset button shows confirmation
- [ ] After reset, settings match first-launch defaults
- [ ] App continues working normally after reset

---

#### 2.2.1.8 Preferences UI Improvements
> Better explanations and organization throughout.

- [ ] Add section headers with brief descriptions
- [ ] Add tooltip/help icons for complex settings
- [ ] Use consistent terminology throughout:
  - "Super Dimming" (not "Global Dimming" or "Full Screen")
  - "Dim Amount" (not "Opacity" or "Level")
  - "Brightness Threshold" with explanation
- [ ] Add "Learn More" links to documentation/website
- [ ] Ensure all sliders have clear labels and value displays
- [ ] Group related settings visually
- [ ] Add keyboard shortcuts where appropriate

#### 🧪 TEST CHECK 2.2.1.8
- [ ] All sections have explanatory text
- [ ] Tooltips appear on hover
- [ ] Terminology is consistent
- [ ] UI is intuitive for first-time users

---

#### 2.2.1.9 First Launch Experience
> Make the app immediately useful and guide users.

- [ ] On first launch:
  - [ ] Enable Super Dimming automatically
  - [ ] Set appearance mode to `.system`
  - [ ] Apply appropriate profile based on current system appearance
  - [ ] Show brief welcome/onboarding (optional)
- [ ] Menu bar popover shows:
  - [ ] "Super Dimming: ON" prominently
  - [ ] Quick dim level slider
  - [ ] Link to Preferences for more options

#### 🧪 TEST CHECK 2.2.1.9
- [ ] Fresh install shows dimming immediately
- [ ] Menu bar shows clear status
- [ ] User can quickly adjust or disable

---

#### 🔨 BUILD CHECK 2.2.1 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] No SwiftUI preview errors

#### 🧪 TEST CHECK 2.2.1 FINAL
- [ ] Fresh install: Super Dimming ON, visible effect immediately
- [ ] Appearance mode switching works
- [ ] Feature hierarchy is clear (Super Dimming → Dim Windows → Dim Areas)
- [ ] SuperFocus features accessible and explained
- [ ] Debug features hidden in release
- [ ] Reset to defaults works
- [ ] All explanatory text is present and helpful
- [ ] Performance acceptable with new features

#### 👀 REVIEW POINT 2.2.1
- [ ] UI follows macOS Human Interface Guidelines
- [ ] Terminology is user-friendly (no developer jargon)
- [ ] Feature discoverability is good
- [ ] Complexity is progressive (simple by default, advanced available)

---

### Week 6: Window Tracking

#### 2.3 Window Tracker Service
- [x] Create `WindowTrackerService.swift`
- [x] Create `TrackedWindow` struct with metadata
- [x] Implement `getVisibleWindows() -> [TrackedWindow]`
- [x] Parse CGWindowListCopyWindowInfo results
- [x] Filter out system UI, dock, menu bar

#### 🔨 BUILD CHECK 2.3
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.3
- [ ] Returns list of visible windows
- [ ] Window bounds are accurate
- [ ] Owner PID and name are correct
- [ ] System UI is filtered out

---

#### 2.4 Active Window Detection
- [x] Implement frontmost app tracking via NSWorkspace
- [x] Mark windows as active/inactive based on owner PID
- [x] Add notification observer for app activation changes
- [x] Cache frontmost app to reduce lookups

#### 🔨 BUILD CHECK 2.4
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.4
- [ ] Correct app identified as frontmost
- [ ] Windows marked correctly as active/inactive
- [ ] State updates when switching apps
- [ ] Performance: Tracking adds minimal overhead

---

### Week 7: Per-Window Dimming

#### 2.5 Per-Window Analysis Loop
- [x] Create `DimmingCoordinator.swift` (main controller)
- [x] Implement analysis loop with configurable interval
- [x] Analyze brightness per visible window
- [x] Compare against threshold setting
- [x] Generate dimming decisions per window

#### 🔨 BUILD CHECK 2.5
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.5
- [ ] Analysis loop runs at configured interval
- [ ] Bright windows detected correctly
- [ ] Dark windows not flagged for dimming
- [ ] Threshold setting affects detection

---

#### 2.6 Per-Window Overlays
- [x] Modify OverlayManager for per-window overlays
- [x] Create/update/remove overlays based on analysis
- [x] Apply active window dim level to active windows
- [x] Apply inactive window dim level to inactive windows
- [x] Implement smooth transition animations

#### 🔨 BUILD CHECK 2.6
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.6
- [ ] Per-window overlays appear correctly positioned
- [ ] Overlays track window movement
- [ ] Overlays resize with windows
- [ ] Active/inactive dim levels applied correctly
- [ ] Transitions are smooth, not jarring

---

### 2.7 Per-Region Detection Mode (NEW!)

> **KILLER FEATURE** - This is what differentiates SuperDimmer from other dimming apps!
> Instead of dimming entire windows, we can detect and dim specific BRIGHT AREAS within windows.
> Example: Dark mode Mail app with a bright white email open - only the email content gets dimmed.

#### 2.7.1 Detection Mode Settings
- [x] Add `DetectionMode` enum (perWindow, perRegion)
- [x] Add `detectionMode` property to SettingsManager
- [x] Add `regionGridSize` setting (4-16, default 8)
- [x] Persist detection mode to UserDefaults

#### 2.7.2 BrightRegionDetector Service
- [x] Create `BrightRegionDetector.swift`
- [x] Create brightness grid from image (NxN cells)
- [x] Implement threshold comparison per cell
- [x] Find connected components (adjacent bright cells)
- [x] Calculate bounding boxes for regions
- [x] Merge overlapping/adjacent regions

#### 2.7.3 Per-Region Coordinator Updates
- [x] Add `performPerRegionAnalysis()` to DimmingCoordinator
- [x] Switch between modes based on `detectionMode` setting
- [x] Generate `RegionDimmingDecision` structs
- [x] Calculate dim level per region based on brightness

#### 2.7.4 Per-Region Overlay Management
- [x] Add `RegionDimmingDecision` struct to OverlayManager
- [x] Add `regionOverlays` dictionary
- [x] Implement `applyRegionDimmingDecisions()`
- [x] Create overlays for each bright region
- [x] Include region overlays in hide/show/remove methods

#### 2.7.5 UI for Detection Mode
- [x] Add mode picker (Per Window / Per Region) to MenuBarView
- [x] Add grid precision slider for per-region mode
- [x] Show description text for selected mode

#### 🔨 BUILD CHECK 2.7
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.7
- [x] Mode picker switches correctly
- [x] Per-region mode detects bright areas in dark windows
- [x] Mail app test: bright email content detected separately
- [x] Grid precision slider affects detection granularity
- [x] Region overlays appear only on bright areas

---

### 2.8 Multiple Windows & Enhancements (Jan 8, 2026)

> **USER FEEDBACK**: Only one Mail window was being dimmed when multiple windows were visible.
> Fixed by analyzing ALL visible windows, not just the active one.

#### 2.8.1 Multiple Windows Dimming
- [x] Modified `performPerRegionAnalysis()` to analyze ALL visible windows
- [x] Removed `isActive` filter that limited analysis to frontmost window only
- [x] Region overlays now created for bright regions across ALL windows
- [x] Debug logging shows "Analyzing ALL N visible windows"

#### 2.8.2 Feathered/Blurred Edges
- [x] Added `edgeBlurEnabled` setting to SettingsManager
- [x] Added `edgeBlurRadius` setting (5-50pt, default 15pt)
- [x] Implemented `setEdgeBlur(enabled:radius:)` in DimOverlayWindow
- [x] Created `createFeatheredMaskImage()` for soft edge gradient
- [x] Updated OverlayManager to apply edge blur to region overlays
- [x] Added "Soft Edges" toggle and slider to MenuBarView

#### 2.8.3 Excluded Apps Feature
- [x] Added `excludedAppBundleIDs` setting to SettingsManager
- [x] Modified WindowTrackerService to filter out excluded apps
- [x] Created `ExcludedAppsPreferencesTab` in PreferencesView
- [x] Implemented running apps picker for quick exclusion
- [x] Added manual bundle ID entry field
- [x] Shows excluded apps in MenuBarView with "Manage" link

#### 2.8.4 SwiftUI AttributeGraph Warnings Fix
- [x] Fixed "AttributeGraph: cycle detected" warnings in MenuBarView
- [x] Used `DispatchQueue.main.async` to defer state changes from view updates
- [x] Applied fix to intelligent mode toggle handler

#### 🔨 BUILD CHECK 2.8
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.8
- [x] Multiple windows are all analyzed in per-region mode
- [ ] Soft edges toggle enables/disables feathered edges
- [ ] Blur radius slider adjusts edge softness
- [ ] Excluded apps no longer get dimmed
- [ ] No AttributeGraph cycle warnings in console

---

#### 2.9 UI Updates for Intelligent Mode
- [ ] Add threshold slider to MenuBarView
- [ ] Add active window dim slider
- [ ] Add inactive window dim slider
- [ ] Add toggle for active/inactive differentiation
- [ ] Show real-time detection status indicator

#### 🔨 BUILD CHECK 2.9
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] SwiftUI previews render

#### 🧪 TEST CHECK 2.9
- [ ] All new controls are functional
- [ ] Threshold changes affect detection immediately
- [ ] Dim level changes apply immediately

---

### 2.10 Inactivity Decay Dimming (WINDOW-LEVEL) ✅ COMPLETED

> **UNIQUE FEATURE** - Progressive dimming for windows that are not in use
> Windows that haven't been switched to will gradually increase in dimness over time
> until they hit a user-configurable maximum limit. This creates a visual hierarchy
> that emphasizes the active window while naturally de-emphasizing stale windows.
> 
> **Why this matters:** When you have many windows open, the ones you haven't used
> recently naturally fade more, helping you focus on what's active while keeping
> background windows accessible but less distracting.

**COMPLETED: January 8, 2026**

#### 2.10.1 Decay Dimming Settings ✅
- [x] Add `inactivityDecayEnabled` setting to SettingsManager
- [x] Add `decayRate` setting (0.005-0.05 per second)
- [x] Add `decayStartDelay` setting (default 30 seconds)
- [x] Add `maxDecayDimLevel` setting (0-100%, default 80%)
- [x] Persist decay settings to UserDefaults

#### 2.10.2 Window Inactivity Tracker ✅
- [x] Create `WindowInactivityTracker.swift` service
- [x] Track `lastActiveTimestamp` per window ID
- [x] Track `lastFrontmostWindowID` for window-level (not app-level) tracking
- [x] Update timestamp when specific window becomes active
- [x] Calculate `timeSinceLastActive` for each tracked window

#### 2.10.3 Decay Dimming Logic in Coordinator ✅
- [x] Add `applyDecayDimmingToWindows()` method to DimmingCoordinator
- [x] Formula: `decayRate × max(0, timeSinceActive - decayStartDelay)`
- [x] Clamp result to `maxDecayDimLevel`
- [x] Creates FULL-WINDOW overlays (separate from region overlays)
- [x] Reset decay when window becomes active again

#### 2.10.4 Decay Dimming UI ✅
- [x] Add "Inactivity Decay" toggle to MenuBarView
- [x] Add "Fade Speed" slider (Slow/Medium/Fast)
- [x] Add "Max Fade" slider (0% - 100%)
- [x] Controls appear when Intelligent Mode is enabled

#### 🔨 BUILD CHECK 2.10 ✅
- [x] Build succeeds

#### 🧪 TEST CHECK 2.10
- [x] Window starts decaying after delay when inactive
- [x] Decay respects rate setting (gradual increase)
- [x] Decay stops at max level
- [x] Switching to window resets decay immediately
- [x] Decay is WINDOW-LEVEL (not app-level) - other windows of same app decay
- [ ] Performance verification needed

---

### 2.11 Auto-Hide Inactive Apps (APP-LEVEL)

> **PRODUCTIVITY FEATURE** - Automatically hide apps that haven't been used for a while
> Unlike decay dimming (which is per-window), this feature operates at the APP level.
> After an app hasn't been in the foreground for a configurable duration, it gets hidden.
> This reduces visual clutter and helps focus on actively used applications.
>
> **Why this matters:** Over the course of a workday, many apps accumulate on screen
> that you opened briefly but forgot about. Auto-hiding them keeps your workspace clean
> without requiring manual intervention.

#### 2.11.1 Auto-Hide Settings ✅
- [x] Add `autoHideEnabled` setting to SettingsManager
- [x] Add `autoHideDelay` setting (minutes before hiding, default 30 minutes)
- [x] Add `autoHideExcludedApps` setting (Set<String> of bundle IDs)
- [x] Add `autoHideExcludeSystemApps` setting (default true - Finder, etc.)
- [x] Persist auto-hide settings to UserDefaults

#### 2.11.2 App Inactivity Tracker ✅
- [x] Create `AppInactivityTracker.swift` service
- [x] Track `lastForegroundTimestamp` per bundle ID
- [x] Update timestamp when app becomes frontmost (NSWorkspace observer)
- [x] Calculate `timeSinceLastForeground` for each running app
- [x] Maintain list of apps that should be auto-hidden

#### 2.11.3 Auto-Hide Logic ✅
- [x] Create `AutoHideManager.swift` service
- [x] Implement `hideApp(bundleID:)` using NSRunningApplication.hide()
- [x] Check inactivity timer periodically (every 60 seconds)
- [x] Skip excluded apps (user-defined + system apps if setting enabled)
- [ ] Skip apps with unsaved changes (if detectable via Accessibility) - DEFERRED
- [x] Log auto-hide actions for user transparency

#### 2.11.4 Auto-Hide UI ✅
- [x] Add "Auto-Hide Inactive Apps" toggle to Preferences
- [x] Add auto-hide delay slider (5 min - 120 min)
- [x] Add excluded apps list editor (reuse ExcludedAppsPreferencesTab pattern)
- [x] Add "Exclude system apps" checkbox
- [ ] Show notification when app is auto-hidden (optional) - DEFERRED
- [ ] Add "Recently Auto-Hidden" list with "Unhide" buttons - DEFERRED

#### 2.11.5 App Delegate Integration ✅ (Jan 9, 2026)
- [x] Initialize AutoHideManager in AppDelegate
- [x] Start on launch if autoHideEnabled is true
- [x] Settings observer to start/stop when toggle changes
- [x] Stop on app termination

#### 🔨 BUILD CHECK 2.11 ✅
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.11
- [ ] Apps are hidden after inactivity delay - NEEDS TESTING
- [ ] Excluded apps are never auto-hidden - NEEDS TESTING
- [x] Using app resets its inactivity timer (fixed Jan 9)
- [ ] Auto-hide settings persist across restart - NEEDS TESTING
- [ ] Notification shown when app hidden (if enabled) - DEFERRED
- [ ] Hidden apps can be unhidden from list - DEFERRED

---

### 2.12 Auto-Minimize Inactive Windows (WINDOW-LEVEL)

> **SMART WINDOW MANAGEMENT** - Automatically minimize windows that haven't been used
> Unlike Auto-Hide (which hides entire apps), this operates at the WINDOW level.
> When an app has too many windows open (above a threshold), the oldest inactive
> windows are automatically minimized to the Dock.
>
> **Key Intelligence:**
> - Only counts ACTIVE usage time (pauses when you walk away)
> - Resets counters after extended idle (configurable)
> - Per-app window threshold (e.g., keep 2 Cursor windows, minimize extras)
> - Won't minimize below threshold (always keeps N windows per app)
>
> **Why this matters:** During a workday, you might open 15 browser tabs as windows
> or 8 Cursor windows. Instead of manual cleanup, SuperDimmer minimizes the oldest
> ones while keeping your most recent windows accessible.

#### 2.12.1 Auto-Minimize Settings ✅
- [x] Add `autoMinimizeEnabled` setting to SettingsManager
- [x] Add `autoMinimizeDelay` setting (minutes of ACTIVE use before minimize, default 15)
- [x] Add `autoMinimizeIdleResetTime` setting (minutes of idle to reset counters, default 5)
- [x] Add `autoMinimizeWindowThreshold` setting (min windows per app before minimizing, default 3)
- [x] Add `autoMinimizeExcludedApps` setting (Set<String> of bundle IDs)
- [x] Persist all settings to UserDefaults

#### 2.12.2 Active Usage Tracker ✅
- [x] Create `ActiveUsageTracker.swift` service
- [x] Detect user activity (mouse movement, key presses) via NSEvent.addGlobalMonitorForEvents
- [x] Track `isUserActive` state (true if activity within last 30 seconds)
- [x] Track `totalActiveTime` per window (only increments when user is active)
- [x] Reset all window timers when idle exceeds `autoMinimizeIdleResetTime`
- [x] Handle wake from sleep (reset timers)

#### 2.12.3 Window Inactivity Counter ✅
- [x] Uses existing `WindowInactivityTracker` for per-window timestamps
- [x] Track `activeUsageAccumulator` per window ID (seconds of active usage while inactive)
- [x] Only increment when `isUserActive == true` AND window is not frontmost
- [x] Reset accumulator when window becomes frontmost
- [x] Reset ALL accumulators when user returns from extended idle

#### 2.12.4 Auto-Minimize Logic ✅
- [x] Create `AutoMinimizeManager.swift` service
- [x] Group windows by owner app (bundle ID)
- [x] For each app: count visible windows on current Space
- [x] If count > `autoMinimizeWindowThreshold`:
  - [x] Sort windows by inactivity (longest inactive first)
  - [x] Minimize oldest until count == threshold
- [x] Use AppleScript to minimize windows (most reliable method)
- [x] Skip excluded apps
- [x] Log minimize actions for user transparency

#### 2.12.5 Auto-Minimize UI ✅
- [x] Add "Auto-Minimize Windows" section to Preferences
- [x] Add enable/disable toggle
- [x] Add "Minimize After" slider (5-60 minutes of active use)
- [x] Add "Reset After Idle" slider (2-30 minutes)
- [x] Add "Keep At Least" stepper (1-10 windows per app)
- [x] Add excluded apps list editor
- [ ] Add "Recently Minimized" section with restore option - DEFERRED
- [ ] Show status indicator: "Tracking: 5 windows across 3 apps" - DEFERRED

#### 2.12.6 App Delegate Integration ✅ (Jan 9, 2026)
- [x] Initialize AutoMinimizeManager in AppDelegate
- [x] Start on launch if autoMinimizeEnabled is true (default: OFF)
- [x] Settings observer to start/stop when toggle changes
- [x] Stop on app termination

#### 🔨 BUILD CHECK 2.12 ✅
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 2.12
- [ ] Windows minimize after configured active-use time - NEEDS TESTING
- [ ] Timer pauses when user is idle (no mouse/keyboard) - NEEDS TESTING
- [ ] Timers reset after extended idle period - NEEDS TESTING
- [ ] Threshold respected (keeps N windows per app) - NEEDS TESTING
- [ ] Excluded apps never auto-minimized - NEEDS TESTING
- [ ] Walking away overnight doesn't minimize everything - NEEDS TESTING
- [ ] Settings persist across restart - NEEDS TESTING

---

### 2.13 Temporary Disable / Pause Feature ✅ COMPLETED

> **USER FEATURE REQUEST** - Temporarily pause dimming for a set duration
> Users need to temporarily disable dimming for activities like:
> - Taking screenshots (10 seconds)
> - Quick color-sensitive tasks (5 minutes)
> - Meetings/presentations (30 minutes to 1 hour)
>
> **Why this matters:** Instead of manually toggling dimming on/off (and possibly
> forgetting to re-enable), users can select a preset duration and the app
> automatically resumes dimming when the timer expires.
>
> **Design decisions (based on user feedback):**
> - Click-based selection (not dial or typed value) for simplicity
> - 4 preset options covering common use cases
> - Countdown timer shows remaining time
> - "Resume" button allows early reactivation
> - Menu bar icon changes to "pause" symbol during disable

**COMPLETED: January 9, 2026**

#### 2.13.1 Temporary Disable Manager ✅
- [x] Create `TemporaryDisableManager.swift` singleton service
- [x] Define `DisableDuration` enum with presets: 10sec, 5min, 30min, 1hr
- [x] Implement `disableFor(_ duration:)` method
- [x] Implement `enableNow()` method for early reactivation
- [x] Track `isTemporarilyDisabled` state with @Published
- [x] Track `remainingSeconds` with countdown timer
- [x] Persist state to UserDefaults for app restart scenarios
- [x] Restore active disable on app relaunch if timer hasn't expired

#### 2.13.2 Timer and Countdown Logic ✅
- [x] Use Combine Timer publisher for main thread updates
- [x] Decrement `remainingSeconds` every second
- [x] Auto-reactivate dimming when timer reaches 0
- [x] Store dimming state BEFORE disable (to restore correctly)
- [x] Cancel timer on early reactivation

#### 2.13.3 Menu Bar View Integration ✅
- [x] Add `temporaryDisableSection` to MenuBarView
- [x] Show "Pause Dimming" button when dimming is enabled
- [x] Expand to show 4 duration buttons on click
- [x] When disabled: Show "Dimming Paused" with countdown and "Resume" button
- [x] Use monospaced digits for countdown display

#### 2.13.4 Menu Bar Icon State ✅
- [x] Update `MenuBarController.updateIconForCurrentState()` for pause state
- [x] Show "pause.circle" SF Symbol when temporarily disabled
- [x] Update tooltip to show remaining time
- [x] Priority: temporary disable > dimming enabled > color temp > disabled

#### 🔨 BUILD CHECK 2.13 ✅
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [x] Build succeeds
- [x] No new warnings introduced

#### 🧪 TEST CHECK 2.13
- [ ] Click "Pause Dimming" shows 4 duration options
- [ ] Selecting duration starts countdown
- [ ] Countdown updates every second
- [ ] Dimming resumes automatically when timer expires
- [ ] "Resume" button ends pause early
- [ ] Menu bar icon shows pause symbol during disable
- [ ] Tooltip shows remaining time
- [ ] State persists across app restart (if timer still active)

---

### 2.14 Phase 2 Integration Testing

#### 🔨 BUILD CHECK - PHASE 2 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [ ] Release build succeeds
- [ ] No new warnings introduced

#### 🧪 TEST CHECK - PHASE 2 FINAL
- [ ] Open white webpage in dark browser → dims correctly
- [ ] Switch active app → dim levels swap
- [ ] Resize window → overlay tracks
- [ ] Close window → overlay removed
- [ ] Open new window → overlay created if bright
- [ ] Pause dimming feature works (all 4 durations)
- [ ] Performance: CPU < 5% during active analysis
- [ ] Performance: Memory < 50 MB with many overlays

#### 👀 REVIEW POINT - PHASE 2 COMPLETE
- [ ] Dimming coordinator logic is clean
- [ ] No memory leaks with overlay creation/destruction
- [ ] Error handling for edge cases (hidden windows, etc.)
- [ ] Temporary disable state management is clean

---

## 🏗️ PHASE 3: Color Temperature
**Estimated Time: 2 weeks**
**NOTE: Basic implementation completed early (Jan 7, 2026) - advanced features pending**

### Week 8: Gamma Control

#### 3.1 Color Temperature Engine
- [x] Create `ColorTemperatureManager.swift` (named Manager not Engine)
- [x] Implement Kelvin to RGB conversion (Tanner Helland algorithm)
- [x] Implement `applyTemperature(_ kelvin: Double)`
- [x] Use CGSetDisplayTransferByFormula API
- [ ] Handle multi-display independently (applies to all currently)

#### 🔨 BUILD CHECK 3.1
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 3.1
- [x] 6500K shows no color shift (daylight)
- [x] 2700K shows warm orange tint
- [x] 1900K shows strong warm tint
- [ ] Changes apply to correct display (currently applies to all)

---

#### 3.2 Temperature Presets
- [x] Define preset temperatures (Daylight, Sunset, Night, Candlelight)
- [x] Create TemperaturePreset enum with Kelvin values
- [x] Implement preset selection UI (buttons in MenuBarView)
- [x] Add custom temperature slider (1900K-6500K)

#### 🔨 BUILD CHECK 3.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [x] Build succeeds

#### 🧪 TEST CHECK 3.2
- [x] Presets apply correct temperatures
- [x] Custom slider works across full range
- [x] UI shows current temperature/preset

---

### Week 9: Scheduling

#### 3.3 Time-Based Scheduling
- [ ] Create `ScheduleManager.swift`
- [ ] Implement manual time schedule (start time, end time)
- [ ] Add day/night temperature settings
- [ ] Implement gradual transition over duration
- [ ] Use Timer for schedule checking

#### 🔨 BUILD CHECK 3.3
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 3.3
- [ ] Schedule triggers at configured time
- [ ] Transition is gradual, not instant
- [ ] Schedule persists across restart

---

#### 3.4 Sunrise/Sunset Automation
- [ ] Add CoreLocation framework
- [ ] Create `LocationService.swift`
- [ ] Request location permission
- [ ] Calculate sunrise/sunset times
- [ ] Auto-adjust schedule based on location

#### 🔨 BUILD CHECK 3.4
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] CoreLocation linked
- [ ] Privacy string in Info.plist

#### 🧪 TEST CHECK 3.4
- [ ] Location permission request shows
- [ ] Sunrise/sunset times calculated correctly
- [ ] Schedule follows sun times
- [ ] Works without location (falls back to manual)

---

#### 3.5 Color Temperature UI
- [x] Add temperature section to MenuBarView
- [x] Add enable/disable toggle for color temp
- [x] Add preset buttons (Day, Sunset, Night, Candle)
- [x] Add temperature slider (1900K-6500K)
- [ ] Add schedule configuration in Preferences

#### 🔨 BUILD CHECK 3.5
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 3.5
- [ ] All temperature controls functional
- [ ] Toggle enables/disables color shift
- [ ] Schedule UI is intuitive

---

#### 🔨 BUILD CHECK - PHASE 3 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [ ] Release build succeeds

#### 🧪 TEST CHECK - PHASE 3 FINAL
- [ ] Color temperature + dimming work together
- [ ] Schedule triggers reliably
- [ ] Location-based schedule works
- [ ] Performance unchanged from Phase 2

#### 👀 REVIEW POINT - PHASE 3 COMPLETE
- [ ] Gamma restoration on quit (reset to default)
- [ ] No color artifacts or flickering
- [ ] Schedule edge cases handled (midnight crossing, DST)

---

## 🏗️ PHASE 4: Wallpaper Features
**Estimated Time: 2 weeks**

### Week 10: Wallpaper Management

#### 4.1 Wallpaper Service
- [ ] Create `WallpaperManager.swift`
- [ ] Implement get current wallpaper URL
- [ ] Implement set wallpaper for space
- [ ] Handle per-display wallpapers
- [ ] Use NSWorkspace wallpaper APIs

#### 🔨 BUILD CHECK 4.1
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 4.1
- [ ] Can read current wallpaper
- [ ] Can set new wallpaper
- [ ] Works on multiple displays

---

#### 4.2 Light/Dark Wallpaper Pairs
- [ ] Create data model for wallpaper pairs
- [ ] Implement pair storage/retrieval
- [ ] Create UI for selecting light wallpaper
- [ ] Create UI for selecting dark wallpaper
- [ ] Save pairs in UserDefaults/files

#### 🔨 BUILD CHECK 4.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 4.2
- [ ] Can select light and dark wallpapers
- [ ] Pairs persist across restart
- [ ] Can have multiple pairs (per space)

---

### Week 11: Auto-Switching

#### 4.3 Appearance Observer
- [ ] Create `AppearanceObserver.swift`
- [ ] Observe system appearance changes
- [ ] Detect Light Mode ↔ Dark Mode switch
- [ ] Trigger wallpaper switch on change

#### 🔨 BUILD CHECK 4.3
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 4.3
- [ ] Appearance change detected reliably
- [ ] Wallpaper switches when mode changes
- [ ] Works with "Auto" appearance setting

---

#### 4.4 Wallpaper Dimming
- [ ] Implement desktop-only overlay
- [ ] Create overlay that sits above wallpaper but below windows
- [ ] Add wallpaper dim amount setting
- [ ] Wire to schedule system (optional)

#### 🔨 BUILD CHECK 4.4
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 4.4
- [ ] Wallpaper dimmed, windows not affected
- [ ] Dim level adjustable
- [ ] Toggle enables/disables

---

#### 4.5 Wallpaper UI
- [ ] Add wallpaper section to Preferences
- [ ] Add auto-switch toggle
- [ ] Add wallpaper pair selector
- [ ] Add wallpaper dim slider
- [ ] Add preview thumbnails

#### 🔨 BUILD CHECK 4.5
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 4.5
- [ ] UI is intuitive and polished
- [ ] Thumbnails show correctly
- [ ] All controls functional

---

#### 🔨 BUILD CHECK - PHASE 4 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [ ] Release build succeeds

#### 🧪 TEST CHECK - PHASE 4 FINAL
- [ ] All wallpaper features work together
- [ ] Switch appearance → wallpaper changes
- [ ] Wallpaper dimming works correctly
- [ ] No visual glitches during switch

#### 👀 REVIEW POINT - PHASE 4 COMPLETE
- [ ] Wallpaper permissions handled (AppleEvents)
- [ ] Edge cases: missing wallpaper files, permission denied

---

## 🏗️ PHASE 5: Pro Features & Licensing
**Estimated Time: 3 weeks**

### Week 12: Paddle Integration

#### 5.1 Paddle SDK Setup
- [ ] Create Paddle developer account
- [ ] Get Paddle SDK framework
- [ ] Add Paddle.framework to project
- [ ] Configure product in Paddle dashboard
- [ ] Create `LicenseManager.swift`

#### 🔨 BUILD CHECK 5.1
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] Paddle framework linked

#### 🧪 TEST CHECK 5.1
- [ ] Paddle SDK initializes without error
- [ ] Can communicate with Paddle API (sandbox)

---

#### 5.2 License Validation
- [ ] Implement license key validation
- [ ] Implement trial period management
- [ ] Store license state securely
- [ ] Create license state enum (Free, Trial, Pro, Expired)
- [ ] Add license check on app launch

#### 🔨 BUILD CHECK 5.2
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 5.2
- [ ] Valid license activates Pro features
- [ ] Invalid license shows error
- [ ] Trial countdown works
- [ ] License persists across restart

---

#### 5.3 Feature Gating
- [ ] Create `FeatureGate.swift`
- [ ] Define Pro-only features list
- [ ] Gate intelligent detection (Pro)
- [ ] Gate per-app rules (Pro)
- [ ] Gate multi-display (Pro)
- [ ] Gate color temperature (Pro)
- [ ] Gate wallpaper features (Pro)
- [ ] Show upgrade prompts for gated features

#### 🔨 BUILD CHECK 5.3
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 5.3
- [ ] Free tier: Only full-screen dim works
- [ ] Pro tier: All features unlocked
- [ ] Upgrade prompts show correctly

---

### Week 13: Per-App Rules

#### 5.4 App Rules Engine
- [ ] Create `AppRulesManager.swift`
- [ ] Create `AppRule` data model
- [ ] Implement rule types: Always dim, Never dim, Custom
- [ ] Store rules with app bundle ID
- [ ] Apply rules during dimming analysis

#### 🔨 BUILD CHECK 5.4
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 5.4
- [ ] "Never dim" rule prevents dimming for app
- [ ] "Always dim" forces dimming regardless of brightness
- [ ] Custom threshold works per-app

---

#### 5.5 App Rules UI
- [ ] Create app list view showing running apps
- [ ] Create rule editor sheet
- [ ] Allow browsing /Applications for apps
- [ ] Show rule status in list
- [ ] Add to Preferences window

#### 🔨 BUILD CHECK 5.5
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 5.5
- [ ] Can add/edit/delete rules
- [ ] Rules list shows correctly
- [ ] App icons display

---

### Week 14: Keyboard Shortcuts & Polish

#### 5.6 Keyboard Shortcuts
- [ ] Add KeyboardShortcuts library (SPM)
- [ ] Create `KeyboardShortcutsManager.swift`
- [ ] Implement toggle dimming shortcut
- [ ] Implement increase/decrease dim shortcuts
- [ ] Add shortcut configuration UI
- [ ] Use standard shortcut recording control

#### 🔨 BUILD CHECK 5.6
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] SPM dependency resolves

#### 🧪 TEST CHECK 5.6
- [ ] Shortcuts trigger actions globally
- [ ] Shortcuts can be customized
- [ ] Shortcuts don't conflict with system

---

#### 5.7 Simple Update Checking (No Sparkle)

> **Approach:** Simple version check via JSON file hosted on HTTPS website.
> No third-party frameworks needed. Website is already secure (HTTPS + Cloudflare).
> App is already notarized by Apple, so downloads are trusted.

**How It Works:**
```
1. App launches → checks https://superdimmer.app/version.json
2. Compares with current version
3. If newer → shows alert "Update Available"
4. User clicks "Download" → opens download URL in browser
5. User installs new DMG manually (standard macOS flow)
```

**5.7.1 Create version.json on Website**
File: `SuperDimmer-Website/version.json`
```json
{
  "version": "1.0.0",
  "build": 1,
  "downloadURL": "https://superdimmer.app/releases/SuperDimmer-v1.0.0.dmg",
  "releaseNotesURL": "https://superdimmer.app/release-notes/v1.0.0.html",
  "minSystemVersion": "13.0"
}
```
- [x] version.json created on website ✅

**5.7.2 Create UpdateChecker.swift**
Simple Swift class that:
- Fetches version.json on app launch
- Compares versions
- Shows alert if update available
- Opens download URL when user clicks "Download"

- [ ] Created `UpdateChecker.swift`
- [ ] Added to Xcode project
- [ ] Called on app launch (AppDelegate or SuperDimmerApp)
- [ ] Added "Check for Updates..." menu item

**5.7.3 Release Workflow (Each Release)**
```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh X.Y.Z

# Then:
cd ..
git add . && git commit -m "Release vX.Y.Z" && git push
```
The script handles: build → sign → DMG → notarize → update version.json

#### 🔨 BUILD CHECK 5.7
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds
- [ ] Sparkle framework linked (no import errors)
- [ ] SUPublicEDKey in Info.plist

#### 🧪 TEST CHECK 5.7
- [ ] "Check for Updates" menu item works
- [ ] Sparkle shows "up to date" or update dialog
- [ ] Test full update: install old version → check → update installs

---

#### 5.8 Preferences Window Polish
- [ ] Create full Preferences window (SwiftUI)
- [ ] Implement tab navigation
- [ ] Polish General tab
- [ ] Polish Brightness tab
- [ ] Polish Color tab
- [ ] Polish Wallpaper tab
- [ ] Polish Apps tab
- [ ] Polish Displays tab
- [ ] Polish License tab
- [ ] Add About section

#### 🔨 BUILD CHECK 5.8
```bash
xcodebuild -scheme SuperDimmer -configuration Debug build
```
- [ ] Build succeeds

#### 🧪 TEST CHECK 5.8
- [ ] All tabs navigate correctly
- [ ] All settings save correctly
- [ ] UI is beautiful and polished

---

#### 🔨 BUILD CHECK - PHASE 5 FINAL
```bash
xcodebuild -scheme SuperDimmer -configuration Release build
```
- [ ] Release build succeeds
- [ ] App size reasonable (< 20 MB with frameworks)

#### 🧪 TEST CHECK - PHASE 5 FINAL
- [ ] Full free → Pro upgrade flow works
- [ ] License activation/deactivation works
- [ ] All Pro features gated correctly
- [ ] Shortcuts work system-wide
- [ ] Update mechanism works

#### 👀 REVIEW POINT - PHASE 5 COMPLETE
- [ ] No license bypass possible
- [ ] Graceful handling of network errors (license check)
- [ ] All UI strings are polished

---

## 🏗️ PHASE 6: Launch Preparation
**Estimated Time: 2 weeks**

### Week 15: Distribution Setup

#### 6.1 Code Signing & Notarization

> **What is Notarization?**
> Apple's security check for apps distributed outside Mac App Store.
> Without it, users see "cannot be opened" Gatekeeper warning.
> With it, app opens normally with no warnings.

**6.1.1 Developer ID Certificate (One-Time)**
- [x] Have Apple Developer account ($99/year)
- [x] Developer ID Application certificate in Keychain ✅
  ```bash
  # Verify with:
  security find-identity -v -p codesigning | grep "Developer ID"
  # Should show: Developer ID Application: Your Name (TEAM_ID)
  ```

**6.1.2 App-Specific Password (One-Time)**
- [ ] Go to https://appleid.apple.com
- [ ] Sign in → Security → App-Specific Passwords
- [ ] Generate password named "SuperDimmer Notarization"
- [ ] Copy the password (format: `xxxx-xxxx-xxxx-xxxx`)

**6.1.3 Environment Variables (One-Time)**
Add to `~/.zshrc`:
```bash
export APPLE_ID="your-apple-developer-email@example.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="HHHHZ6UV26"  # From your Developer ID cert
```
Then run: `source ~/.zshrc`

- [ ] APPLE_ID set in ~/.zshrc
- [ ] APPLE_APP_PASSWORD set in ~/.zshrc  
- [ ] APPLE_TEAM_ID set in ~/.zshrc
- [ ] Ran `source ~/.zshrc` to load variables

**6.1.4 Verify Setup**
```bash
echo "ID: $APPLE_ID"
echo "Team: $APPLE_TEAM_ID"
echo "Password: ${APPLE_APP_PASSWORD:+SET}"
```
- [ ] All three variables show correctly

**6.1.5 Test Notarization**
```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh 1.0.0
# Should show "Notarization complete" in step 5
```
- [ ] Notarization succeeds
- [ ] Stapling succeeds

#### 🔨 BUILD CHECK 6.1
```bash
# The release.sh script handles everything:
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging
./release.sh X.Y.Z
```
- [ ] Build succeeds
- [ ] Code signing succeeds
- [ ] Notarization succeeds (step 5)
- [ ] DMG created and stapled

#### 🧪 TEST CHECK 6.1
- [ ] Download DMG on a different Mac (or VM)
- [ ] Double-click to mount - no Gatekeeper warning
- [ ] Drag app to Applications
- [ ] Launch app - no "unidentified developer" warning
- [ ] App runs correctly

---

#### 6.2 Update System Setup (Simple JSON-based)
- [x] Create version.json on website ✅
- [x] Set up hosting on Cloudflare Pages ✅
- [x] Create release notes HTML format ✅
- [ ] Test update flow end-to-end

**Version Info:** `SuperDimmer-Website/version.json`
**Release Notes:** `SuperDimmer-Website/release-notes/vX.Y.Z.html`
**DMG Files:** `SuperDimmer-Website/releases/`

#### 🧪 TEST CHECK 6.2
- [ ] Visit https://superdimmer.app/version.json - JSON loads with correct version
- [ ] Visit https://superdimmer.app/releases/ - DMG downloadable
- [ ] Install old version → "Check for Updates" → Alert shows new version
- [ ] Click "Download" → Browser opens download URL

---

#### 6.3 Website & Purchase Flow
- [x] Create landing page for superdimmer.com ✅ (Jan 8, 2026)
- [x] Deploy website to Cloudflare Pages ✅ (connected to GitHub)
- [ ] Integrate Paddle checkout
- [ ] Set up license key delivery
- [x] Create download page with DMG links ✅ (releases/ folder)
- [ ] Test full purchase → download → activate flow

**Website Status (Jan 8, 2026):**
- Repository: https://github.com/buildngrowsv/SuperDimmer-Website
- Hosting: Cloudflare Pages (auto-deploys on push)
- Features: Hero, features grid, pricing, download links
- Design: Dark theme with warm amber accents

**Release Infrastructure Added:**
```
SuperDimmer-Website/
├── packaging/
│   └── release.sh      ← One command releases
├── sparkle/
│   └── appcast.xml     ← Auto-updated by release.sh
├── releases/
│   └── *.dmg           ← Download files
└── release-notes/
    └── vX.Y.Z.html     ← Shown in Sparkle dialog
```

#### 🧪 TEST CHECK 6.3
- [ ] Website loads at https://superdimmer.com
- [ ] Download button works
- [ ] Paddle checkout works (sandbox first, then production)
- [ ] License delivered after purchase

---

### Week 16: Final Testing & Launch

#### 6.4 Beta Testing
- [ ] Create beta distribution (separate signing)
- [ ] Recruit beta testers (5-10)
- [ ] Gather feedback
- [ ] Fix critical issues
- [ ] Iterate on UX concerns

#### 🧪 TEST CHECK 6.4
- [ ] All beta-reported bugs fixed
- [ ] No crash reports
- [ ] Performance acceptable

---

#### 6.5 Documentation
- [ ] Write getting started guide
- [ ] Write FAQ
- [ ] Document all features
- [ ] Create troubleshooting guide
- [ ] Add permission help docs

---

#### 6.6 Marketing Materials
- [ ] Create app icon (final polish)
- [ ] Create screenshots for website
- [ ] Create demo video
- [ ] Write press kit
- [ ] Prepare launch announcement

---

#### 6.7 Pre-Launch Verification

#### 6.7.1 DMG Packaging (Added Jan 8, 2026)
- [x] Created `packaging/` folder with DMG creation scripts
- [x] Created `create-dmg.sh` - main DMG creation script
- [x] Created `build-release.sh` - one-command build + DMG
- [x] Created `create-background.sh` - custom DMG background generator
- [x] Added hdiutil fallback for systems without create-dmg tool
- [x] Tested DMG creation successfully (SuperDimmer-v1.0.0.dmg)

**To create a DMG:**
```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App/packaging
./build-release.sh              # Build and create DMG
./build-release.sh --sign       # Build, sign, and create DMG
./build-release.sh --notarize   # Build, sign, notarize, and create DMG
```

#### 🔨 BUILD CHECK - FINAL RELEASE
```bash
xcodebuild -scheme SuperDimmer -configuration Release archive -archivePath SuperDimmer.xcarchive
```
- [ ] Final archive builds
- [ ] Archive exports for distribution
- [x] DMG creation scripts ready (packaging/ folder)

#### 🧪 FINAL TEST CHECKLIST
- [ ] Fresh install on clean Mac
- [ ] All permissions work correctly
- [ ] Free tier functions correctly
- [ ] Purchase and activate Pro license
- [ ] All Pro features work
- [ ] Update from older version works
- [ ] Quit and restart maintains state
- [ ] Works on multiple macOS versions (13, 14)
- [ ] Works on Intel and Apple Silicon
- [ ] CPU usage acceptable (< 5% active, < 0.5% idle)
- [ ] Memory usage acceptable (< 50 MB)
- [ ] No crashes in 24-hour soak test

#### 👀 FINAL REVIEW
- [ ] All code reviewed
- [ ] All strings localized (or English-only noted)
- [ ] Privacy policy created
- [ ] Terms of service created
- [ ] Support email configured

---

## ✅ LAUNCH CHECKLIST

- [ ] Final release build created
- [ ] Notarization complete
- [ ] Appcast published
- [ ] Website live
- [ ] Paddle checkout live (not sandbox)
- [ ] Download link active
- [ ] Support email ready
- [ ] Social media announcement prepared
- [ ] **🚀 LAUNCH!**

---

## 📊 Post-Launch Monitoring

### First 24 Hours
- [ ] Monitor crash reports (Sentry)
- [ ] Monitor support emails
- [ ] Monitor social media mentions
- [ ] Check download counts
- [ ] Check conversion rates

### First Week
- [ ] Release patch if critical issues
- [ ] Respond to all support requests
- [ ] Gather feature requests
- [ ] Plan v1.1 based on feedback

---

*Checklist Version: 1.0*
*Created: January 7, 2026*
