/**
 ====================================================================
 FeatureGateService.swift
 Controls access to Pro features based on license state
 ====================================================================

 PURPOSE:
 This service sits between the UI layer and LicenseManager, providing
 a clear API for checking whether specific Pro features should be
 enabled. It encapsulates the business logic of which features are
 free vs Pro, separate from the license validation mechanics.

 HISTORY:
 - Created 2026-03-23 as part of the payment integration initiative.
 - Previously, Pro features were documented with comments like
   "This is a Pro feature - gated by license" in SettingsManager.swift
   but had no actual gating logic. This service replaces those comments
   with real enforcement.
 - Design was pre-specified in FILE_STRUCTURE_AND_COMPONENTS.md:1020

 ARCHITECTURE:
 FeatureGateService is an ObservableObject singleton that observes
 LicenseManager. When license state changes, all feature gate checks
 automatically update. SwiftUI views can bind to this directly.

 SEPARATION FROM LICENSEMANAGER:
 LicenseManager handles the "how" of licensing (Paddle SDK, keys, trials).
 FeatureGateService handles the "what" — which features require Pro.
 This separation means we can change the feature tiers (move features
 between free and Pro) without touching the licensing code.

 USAGE PATTERN:
 ```swift
 // In a SwiftUI view:
 @ObservedObject var featureGate = FeatureGateService.shared

 Toggle("Per-window dimming", isOn: $settings.intelligentDimmingEnabled)
     .disabled(!featureGate.isIntelligentDimmingAvailable)

 if !featureGate.hasProAccess {
     UpgradePromptView()
 }
 ```

 DEPENDENCIES:
 - LicenseManager (reads license state from)
 - SettingsManager (features being gated are defined there)
 - PreferencesView (disables Pro controls when free)
 - MenuBarView (shows upgrade prompt)

 ====================================================================
 Created: March 23, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import Combine

// ====================================================================
// MARK: - Feature Gate Service
// ====================================================================

/**
 Singleton service that gates Pro features based on current license state.

 WHY SINGLETON:
 Feature availability must be globally consistent. Multiple views query
 different features — they must all agree on the license tier.

 WHY OBSERVABLEOBJECT:
 When a user activates a Pro license or starts a trial, all gated UI
 controls must update instantly. Combine observation handles this
 automatically through the @Published chain:
 LicenseManager.licenseState changes → FeatureGateService re-evaluates
 → SwiftUI views with @ObservedObject update.
 */
final class FeatureGateService: ObservableObject {

    // ================================================================
    // MARK: - Singleton
    // ================================================================

    static let shared = FeatureGateService()

    // ================================================================
    // MARK: - Dependencies
    // ================================================================

    /**
     Reference to the license manager.

     We observe its licenseState property to keep our feature gates
     in sync with the current license tier.
     */
    private let licenseManager = LicenseManager.shared

    /// Combine subscriptions for observing license state changes.
    private var cancellables = Set<AnyCancellable>()

    // ================================================================
    // MARK: - Published Properties
    // ================================================================

    /**
     Whether the user currently has Pro access (via license or active trial).

     This is the top-level check. UI elements that need to know "is this user
     on Pro?" check this single property.

     UPDATES AUTOMATICALLY when LicenseManager.licenseState changes.
     */
    @Published private(set) var hasProAccess: Bool = false

    /**
     The current license state, forwarded from LicenseManager.

     Exposed for UI elements that need to show state-specific messaging
     (e.g., "Trial: 5 days remaining" vs "Pro License Active").
     */
    @Published private(set) var licenseState: SuperDimmerLicenseState = .free

    // ================================================================
    // MARK: - Feature-Specific Gates
    // ================================================================

    // These computed properties define WHICH features require Pro.
    // If we later decide to move a feature to free tier, we change it HERE,
    // not in every view that checks the feature.

    /**
     Whether intelligent per-window dimming is available.

     This is SuperDimmer's core differentiator — analyzing each window's
     brightness individually rather than dimming the whole screen.

     WHY PRO-ONLY:
     This is the feature that makes SuperDimmer unique. Users who experience
     it during trial will feel the loss when it reverts to global-only dimming.
     It's the primary conversion driver.

     REFERENCED IN: SettingsManager.swift line ~842
     (was comment: "This is a Pro feature - requires license for per-window targeting.")
     */
    var isIntelligentDimmingAvailable: Bool {
        return hasProAccess
    }

    /**
     Whether active/inactive window differentiation is available.

     When enabled, active windows dim less than inactive ones, creating
     a natural focus effect. Without this, all windows dim equally.

     WHY PRO-ONLY:
     Subtle but addictive once experienced. Users notice the "intelligent"
     behavior and attribute it to the app's quality. Strong retention driver.

     REFERENCED IN: SettingsManager.swift line ~823
     (was comment: "This is a Pro feature - gated by license.")
     */
    var isDifferentiateActiveInactiveAvailable: Bool {
        return hasProAccess
    }

    /**
     Whether Super Spaces (per-desktop configurations) is available.

     Lets users set different dimming configs for different macOS Spaces
     (virtual desktops). E.g., coding space dims more, browsing space dims less.

     WHY PRO-ONLY:
     Power-user feature that adds significant value for multi-space workflows.
     Free tier users with simple needs won't miss it; power users will pay for it.
     */
    var isSuperSpacesAvailable: Bool {
        return hasProAccess
    }

    /**
     Whether app exclusion list is available.

     Lets users exclude specific apps from dimming (e.g., video players,
     photo editors where color accuracy matters).

     WHY PRO-ONLY:
     Another power-user feature. The free tier dims everything, which is
     useful but not configurable. Pro users can fine-tune their experience.
     */
    var isAppExclusionsAvailable: Bool {
        return hasProAccess
    }

    /**
     Whether color temperature (blue light filter) adjustment is available.

     Shifts display gamma to warmer tones at night, similar to Night Shift
     but layered on top of SuperDimmer's region-specific dimming.

     WHY PRO-ONLY:
     Adds significant value for night-time users. f.lux is free but doesn't
     combine with region-specific dimming. This combo is unique to Pro.
     */
    var isColorTemperatureAvailable: Bool {
        return hasProAccess
    }

    /**
     Whether auto-hide of inactive apps is available.

     Automatically hides apps that haven't been used for a configurable
     duration, reducing visual clutter.

     WHY PRO-ONLY:
     Convenience feature that increases perceived value. Users who enable
     it find it surprisingly useful for focus.
     */
    var isAutoHideAvailable: Bool {
        return hasProAccess
    }

    // ================================================================
    // MARK: - Free Tier Features (always available)
    // ================================================================

    // These are documented here for clarity about the tier boundary.
    // They don't need gate checks — they're always enabled.

    // FREE FEATURES:
    // - Global dim level slider (single slider for all windows)
    // - Menu bar icon with basic on/off toggle
    // - Launch at login
    // - Manual dim level adjustment
    // - Basic schedule (sunrise/sunset dimming)

    // ================================================================
    // MARK: - Initialization
    // ================================================================

    /**
     Private init enforces singleton. Sets up observation of LicenseManager.

     When LicenseManager.licenseState changes, we update our hasProAccess
     and licenseState properties, which triggers SwiftUI view updates
     throughout the app.
     */
    private init() {
        // Observe license state changes from LicenseManager
        licenseManager.$licenseState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.licenseState = newState
                self?.hasProAccess = newState.hasProAccess
            }
            .store(in: &cancellables)

        // Set initial state
        licenseState = licenseManager.licenseState
        hasProAccess = licenseManager.licenseState.hasProAccess
    }

    // ================================================================
    // MARK: - Convenience Methods
    // ================================================================

    /**
     Check if a specific feature is available, with optional upgrade prompt.

     This is a convenience method for use in action handlers (not just UI state).
     When a user tries to toggle a Pro feature while on the free tier,
     this method can trigger the upgrade prompt automatically.

     - Parameters:
       - feature: A string identifying the feature (for logging/analytics)
       - showUpgradeIfNeeded: If true, opens purchase page when feature is gated
     - Returns: True if the feature is available, false if gated

     USAGE:
     ```swift
     if featureGate.checkAccess(feature: "intelligentDimming", showUpgradeIfNeeded: true) {
         settingsManager.intelligentDimmingEnabled = true
     }
     ```
     */
    func checkAccess(feature: String, showUpgradeIfNeeded: Bool = false) -> Bool {
        if hasProAccess {
            return true
        }

        AppLogger.licensing.info("Feature '\(feature)' blocked — license state: \(self.licenseState.displayDescription)")

        if showUpgradeIfNeeded {
            licenseManager.openPurchasePage()
        }

        return false
    }

    /**
     Convenience method to start a trial via LicenseManager.

     CALLED BY: UI elements that show "Start Free Trial" button.
     Delegates to LicenseManager which handles the actual trial logic.
     */
    func startTrial() {
        licenseManager.startTrial()
    }

    /**
     Convenience method to open the purchase page via LicenseManager.

     CALLED BY: UI elements that show "Buy Pro" / "Upgrade" buttons.
     */
    func openPurchasePage() {
        licenseManager.openPurchasePage()
    }
}
