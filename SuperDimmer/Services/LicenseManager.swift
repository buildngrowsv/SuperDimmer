/**
 ====================================================================
 LicenseManager.swift
 Manages license state and Paddle SDK integration for Pro features
 ====================================================================

 PURPOSE:
 This is the single source of truth for whether the user has a Pro license.
 It wraps the Paddle SDK for license key validation and provides a simple
 observable interface that the rest of the app can query.

 HISTORY:
 - Created 2026-03-23 as part of the payment integration initiative.
 - The app had Pro feature comments since v1.0.0 but no actual gating logic.
 - REFERENCE_APPS_DEEP_ANALYSIS.md researched Paddle as the recommended provider
   based on BetterDisplay's successful use of it in the same product category.
 - PAYMENT-INTEGRATION-PLAN.md (2026-03-23) documented the full integration plan.

 ARCHITECTURE:
 LicenseManager is an ObservableObject singleton. SwiftUI views observe it
 for license state changes. FeatureGateService wraps this with feature-specific
 logic (which features are Pro, trial behavior, etc.).

 The flow:
 1. App launches → LicenseManager.shared initializes
 2. Checks UserDefaults for stored license key
 3. If key exists → validates with Paddle API (or offline cache)
 4. Publishes licenseState → FeatureGateService reacts → UI updates

 PADDLE SDK INTEGRATION:
 When the Paddle.framework is added to the Xcode project:
 1. Uncomment the Paddle import and SDK initialization in initializePaddle()
 2. Replace placeholder vendor/product IDs with real ones from Paddle dashboard
 3. The license validation, trial tracking, and checkout flow all come from Paddle

 Until Paddle account is set up, this manager operates in "stub mode" where
 it reads license state from UserDefaults only. This lets us build and test
 the feature gating UI without a live Paddle account.

 DEPENDENCIES:
 - FeatureGateService (reads from this)
 - AppDelegate (initializes this on launch)
 - PreferencesView / LicenseView (displays license status)
 - MenuBarView (shows upgrade prompt)

 ====================================================================
 Created: March 23, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import Combine
import AppKit  // Needed for NSWorkspace.shared.open() in openPurchasePage()
// import Paddle  // TODO: Uncomment when Paddle.framework is added to project

// ====================================================================
// MARK: - License State Enum
// ====================================================================

/**
 Represents the current license state of the application.

 WHY AN ENUM:
 License state is a finite state machine with clear transitions:
 - .free → .trial (user starts trial)
 - .trial → .pro (user purchases during trial)
 - .trial → .expired (trial runs out without purchase)
 - .expired → .pro (user purchases after trial)
 - .free → .pro (user purchases without trial)

 Each state determines which features are available (via FeatureGateService)
 and what UI is shown (upgrade prompts, trial countdown, etc.).
 */
enum SuperDimmerLicenseState: Equatable {

    /// No license, no trial. Only free-tier features available.
    /// This is the initial state for new installs.
    case free

    /// Trial period active. All Pro features available temporarily.
    /// The associated value tracks remaining days so the UI can show a countdown.
    /// Paddle SDK manages the actual trial expiration — we read it each launch.
    case trial(daysRemaining: Int)

    /// Valid Pro license activated. All features permanently unlocked.
    /// This is the "happy path" end state.
    case pro

    /// Trial expired, no license purchased. Reverts to free-tier features.
    /// Shows more prominent upgrade prompts than .free state.
    case expired

    // ================================================================
    // MARK: - Computed Properties
    // ================================================================

    /**
     Whether Pro features should be accessible in this state.

     Used by FeatureGateService to determine if a specific Pro feature
     should be enabled. Both .trial and .pro allow access.

     WHY TRIAL GETS FULL ACCESS:
     The business model depends on users experiencing the Pro features
     during trial so they feel the loss when it expires. If trial only
     unlocked some features, conversion would be lower.
     */
    var hasProAccess: Bool {
        switch self {
        case .pro, .trial:
            return true
        case .free, .expired:
            return false
        }
    }

    /**
     Human-readable description for the UI.

     Shown in the Preferences → License tab and in the menu bar popover
     when there's license-relevant information to display.
     */
    var displayDescription: String {
        switch self {
        case .free:
            return "Free"
        case .trial(let daysRemaining):
            return "Trial — \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining"
        case .pro:
            return "Pro License Active"
        case .expired:
            return "Trial Expired"
        }
    }
}

// ====================================================================
// MARK: - License Manager
// ====================================================================

/**
 Singleton manager for license state and Paddle SDK operations.

 WHY SINGLETON:
 License state must be globally consistent — if two views query license
 status, they must get the same answer. A singleton with @Published
 properties ensures this via Combine's observation.

 OFFLINE BEHAVIOR:
 Paddle SDK caches the last known license state locally. If the user
 is offline, the cached state is used. This prevents the app from
 breaking when there's no internet. The cache is refreshed on next
 successful online validation.

 THREAD SAFETY:
 All mutations to licenseState happen on the main thread via
 DispatchQueue.main.async, matching SwiftUI's expectation for
 @Published property changes.
 */
final class LicenseManager: ObservableObject {

    // ================================================================
    // MARK: - Singleton
    // ================================================================

    /**
     Shared instance accessed throughout the app.

     Created lazily on first access. In practice, AppDelegate calls
     LicenseManager.shared during applicationDidFinishLaunching to
     trigger initialization early.
     */
    static let shared = LicenseManager()

    // ================================================================
    // MARK: - Published Properties
    // ================================================================

    /**
     The current license state, observable by SwiftUI views.

     FeatureGateService, PreferencesView, MenuBarView, and other components
     observe this property to react to license changes in real-time.

     Changes trigger UI updates across the app:
     - Menu bar shows/hides "Upgrade" badge
     - Preferences enables/disables Pro feature controls
     - Trial countdown updates
     */
    @Published private(set) var licenseState: SuperDimmerLicenseState = .free

    /**
     The stored license key, if any.

     Persisted in UserDefaults so users don't need to re-enter it.
     Set when user activates a license, cleared when deactivated.

     WHY NOT KEYCHAIN:
     A license key is not a secret — it's a commercial identifier.
     UserDefaults is simpler and sufficient. Keychain would add
     complexity without security benefit for a non-sensitive value.
     */
    @Published private(set) var licenseKey: String? = nil

    // ================================================================
    // MARK: - Private Properties
    // ================================================================

    /**
     UserDefaults keys for license persistence.

     Grouped in an enum to prevent typo-based key mismatches and
     to make it easy to audit what we store.
     */
    private enum DefaultsKeys {
        static let licenseKey = "SuperDimmer_LicenseKey"
        static let licenseState = "SuperDimmer_LicenseState"
        static let trialStartDate = "SuperDimmer_TrialStartDate"
        static let trialDurationDays = 7  // Paddle default, configurable in dashboard
    }

    /// Standard UserDefaults for persistence.
    private let defaults = UserDefaults.standard

    // ================================================================
    // MARK: - Initialization
    // ================================================================

    /**
     Private initializer enforces singleton pattern.

     On init:
     1. Loads any stored license key from UserDefaults
     2. Determines current license state (validates key or checks trial)
     3. Sets up Paddle SDK if framework is available

     This runs synchronously on first access. Paddle SDK validation
     may update the state asynchronously after network call completes.
     */
    private init() {
        loadStoredLicenseState()
        initializePaddleSDK()
    }

    // ================================================================
    // MARK: - Public API
    // ================================================================

    /**
     Activate a license key entered by the user.

     Flow:
     1. Store the key locally
     2. Validate with Paddle API (when SDK integrated)
     3. Update licenseState based on validation result
     4. Return success/failure for UI feedback

     CALLED BY: LicenseView when user taps "Activate" button.

     - Parameter key: The license key string from Paddle checkout.
     - Returns: True if activation succeeded, false if invalid/network error.
     */
    @discardableResult
    func activateLicense(key: String) -> Bool {
        // Store the key regardless of validation — we'll validate on next launch too
        defaults.set(key, forKey: DefaultsKeys.licenseKey)
        licenseKey = key

        // ============================================================
        // PADDLE SDK VALIDATION
        // TODO: When Paddle.framework is added, replace this stub with:
        //
        // let result = PaddleSDK.shared.activateProduct(
        //     productId: paddleProductId,
        //     licenseKey: key
        // )
        // if result.activated {
        //     updateState(.pro)
        //     return true
        // } else {
        //     return false
        // }
        // ============================================================

        // STUB MODE: Accept any non-empty key for testing
        // This lets us build and test the UI flow before Paddle account exists
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateState(.pro)
            AppLogger.licensing.info("License activated (stub mode): \(key.prefix(8))...")
            return true
        }

        return false
    }

    /**
     Deactivate the current license.

     Used when user wants to transfer their license to another machine.
     Paddle SDK handles the server-side deactivation to free up the
     activation slot.

     CALLED BY: LicenseView when user taps "Deactivate" button.
     */
    func deactivateLicense() {
        // ============================================================
        // PADDLE SDK DEACTIVATION
        // TODO: When Paddle.framework is added:
        //
        // PaddleSDK.shared.deactivateProduct(productId: paddleProductId)
        // ============================================================

        defaults.removeObject(forKey: DefaultsKeys.licenseKey)
        licenseKey = nil

        // Check if there's a trial still active, otherwise go to free
        let trialState = checkTrialState()
        updateState(trialState)

        AppLogger.licensing.info("License deactivated")
    }

    /**
     Start the 7-day Pro trial.

     Called when user taps "Start Free Trial" in the upgrade prompt.
     Records the trial start date in UserDefaults. Paddle SDK also
     tracks this server-side for consistency.

     BUSINESS LOGIC:
     Trial can only be started once per install. If the user reinstalls
     the app, Paddle's server-side tracking prevents re-trialing (the
     hardware ID is bound). Local-only fallback uses UserDefaults date.

     CALLED BY: LicenseView or upgrade prompt in MenuBarView.
     */
    func startTrial() {
        guard licenseState == .free else {
            // Trial already started, expired, or user is already pro
            AppLogger.licensing.info("Trial start rejected — current state: \(self.licenseState.displayDescription)")
            return
        }

        let now = Date()
        defaults.set(now, forKey: DefaultsKeys.trialStartDate)

        updateState(.trial(daysRemaining: DefaultsKeys.trialDurationDays))
        AppLogger.licensing.info("Trial started: \(DefaultsKeys.trialDurationDays) days from \(now)")
    }

    /**
     Open the Paddle checkout page for purchasing a Pro license.

     Uses Paddle's in-app checkout overlay when SDK is integrated,
     or falls back to opening the website pricing page in browser.

     CALLED BY: Any "Buy Pro" / "Upgrade" button in the app.
     */
    func openPurchasePage() {
        // ============================================================
        // PADDLE SDK CHECKOUT
        // TODO: When Paddle.framework is added:
        //
        // PaddleSDK.shared.showCheckout(
        //     productId: paddleProductId,
        //     completion: { [weak self] result in
        //         if result.purchased {
        //             self?.activateLicense(key: result.licenseKey)
        //         }
        //     }
        // )
        // ============================================================

        // FALLBACK: Open website pricing page
        // This works even without Paddle SDK — user can purchase on website
        // and manually enter the license key in Preferences
        if let pricingURL = URL(string: "https://superdimmer.com/pricing.html") {
            NSWorkspace.shared.open(pricingURL)
            AppLogger.licensing.info("Opened pricing page in browser")
        }
    }

    /**
     Refresh license state from Paddle servers.

     Called on app launch and periodically (every 24 hours) to ensure
     local state matches server state. Handles edge cases like:
     - License revoked (chargeback)
     - License transferred to another machine
     - Trial expired while app was closed

     CALLED BY: AppDelegate on applicationDidFinishLaunching, and
     by a timer every 24 hours while the app is running.
     */
    func refreshLicenseState() {
        // ============================================================
        // PADDLE SDK REFRESH
        // TODO: When Paddle.framework is added:
        //
        // PaddleSDK.shared.refreshProduct(productId: paddleProductId) { [weak self] result in
        //     DispatchQueue.main.async {
        //         if result.activated {
        //             self?.updateState(.pro)
        //         } else if result.trialing {
        //             self?.updateState(.trial(daysRemaining: result.trialDaysLeft))
        //         } else {
        //             self?.updateState(self?.checkTrialState() ?? .free)
        //         }
        //     }
        // }
        // ============================================================

        // STUB MODE: Re-check local state
        loadStoredLicenseState()
        AppLogger.licensing.info("License state refreshed: \(self.licenseState.displayDescription)")
    }

    // ================================================================
    // MARK: - Private Methods
    // ================================================================

    /**
     Load license state from UserDefaults on startup.

     Checks in order:
     1. Is there a stored license key? → .pro (pending validation)
     2. Is there an active trial? → .trial(daysRemaining)
     3. Was there a trial that expired? → .expired
     4. Otherwise → .free

     This local check runs synchronously. Paddle SDK validation may
     override this state asynchronously after a network round-trip.
     */
    private func loadStoredLicenseState() {
        // Check for stored license key first
        if let storedKey = defaults.string(forKey: DefaultsKeys.licenseKey),
           !storedKey.isEmpty {
            licenseKey = storedKey
            updateState(.pro)
            return
        }

        // No license key — check trial state
        let trialState = checkTrialState()
        updateState(trialState)
    }

    /**
     Check the local trial state based on stored start date.

     MATH:
     - Trial start date stored in UserDefaults
     - Trial duration is 7 days (configurable in DefaultsKeys)
     - Days remaining = trial end date - today
     - If days remaining <= 0 → expired
     - If no start date → free (trial never started)

     WHY LOCAL CHECK:
     Paddle SDK tracks trials server-side too, but we need a local
     fallback for offline users. The server state is authoritative
     when available.
     */
    private func checkTrialState() -> SuperDimmerLicenseState {
        guard let trialStartDate = defaults.object(forKey: DefaultsKeys.trialStartDate) as? Date else {
            return .free  // Trial was never started
        }

        let trialEndDate = Calendar.current.date(
            byAdding: .day,
            value: DefaultsKeys.trialDurationDays,
            to: trialStartDate
        ) ?? trialStartDate

        let now = Date()

        if now >= trialEndDate {
            return .expired
        }

        let daysRemaining = Calendar.current.dateComponents(
            [.day],
            from: now,
            to: trialEndDate
        ).day ?? 0

        return .trial(daysRemaining: max(1, daysRemaining))
    }

    /**
     Update the license state on the main thread.

     WHY MAIN THREAD:
     @Published properties must be mutated on the main thread for
     SwiftUI observation to work correctly. Paddle SDK callbacks may
     come from background threads, so we always dispatch to main.
     */
    private func updateState(_ newState: SuperDimmerLicenseState) {
        if Thread.isMainThread {
            licenseState = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.licenseState = newState
            }
        }
    }

    /**
     Initialize Paddle SDK with vendor and product credentials.

     This is called once during init(). The SDK handles:
     - License key caching
     - Trial period tracking
     - Offline grace periods
     - Hardware ID generation for activation binding

     PADDLE CREDENTIALS:
     The vendor ID and product ID come from the Paddle developer dashboard.
     They are NOT secrets — they're embedded in every macOS app that uses Paddle
     (including BetterDisplay). The license key itself is the user's credential.
     */
    private func initializePaddleSDK() {
        // ============================================================
        // PADDLE SDK INITIALIZATION
        // TODO: When Paddle.framework is added and account is created:
        //
        // let vendorId = "REPLACE_WITH_PADDLE_VENDOR_ID"
        // let productId = "REPLACE_WITH_PADDLE_PRODUCT_ID"
        // let apiKey = "REPLACE_WITH_PADDLE_API_KEY"
        //
        // let paddleConfig = PaddleConfiguration(
        //     vendorId: vendorId,
        //     productId: productId,
        //     apiKey: apiKey
        // )
        //
        // Paddle.shared.initialize(with: paddleConfig)
        //
        // // Set up product for licensing
        // let product = PaddleProduct(
        //     productId: productId,
        //     productType: .sdkProduct,
        //     configuration: PaddleProductConfiguration(
        //         productName: "SuperDimmer Pro",
        //         vendorName: "SuperDimmer",
        //         trialLength: DefaultsKeys.trialDurationDays,
        //         trialType: .timeLimited,
        //         currency: "USD",
        //         price: 12.00
        //     )
        // )
        // ============================================================

        AppLogger.licensing.info("LicenseManager initialized (stub mode — Paddle SDK not yet integrated)")
    }
}
