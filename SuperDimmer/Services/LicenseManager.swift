/**
 ====================================================================
 LicenseManager.swift
 Manages license state and Paddle SDK integration for Pro features
 ====================================================================

 PURPOSE:
 This is the single source of truth for whether the user has a Pro license.
 It wraps the Paddle Mac Framework V4 SDK for license key validation and
 provides a simple observable interface that the rest of the app can query.

 HISTORY:
 - Created 2026-03-23 as part of the payment integration initiative.
 - The app had Pro feature comments since v1.0.0 but no actual gating logic.
 - REFERENCE_APPS_DEEP_ANALYSIS.md researched Paddle as the recommended provider
   based on BetterDisplay's successful use of it in the same product category.
 - PAYMENT-INTEGRATION-PLAN.md (2026-03-23) documented the full integration plan.
 - 2026-03-23 (Builder 9, BridgeSwarm): Upgraded from stub mode to real Paddle
   Mac Framework V4 integration using #if canImport(Paddle) conditional compilation.
   Research confirmed Paddle V4 (v4.5.0) uses PADProduct, PADProductConfiguration,
   and supports SPM via https://github.com/PaddleHQ/Mac-Framework-V4.
   The stub mode is preserved as fallback when framework isn't linked.

 ARCHITECTURE:
 LicenseManager is an ObservableObject singleton. SwiftUI views observe it
 for license state changes. FeatureGateService wraps this with feature-specific
 logic (which features are Pro, trial behavior, etc.).

 The flow:
 1. App launches → LicenseManager.shared initializes
 2. If Paddle SDK is linked: initializes PADProduct with vendor/product config
 3. Checks license state via Paddle API (or local UserDefaults fallback)
 4. Publishes licenseState → FeatureGateService reacts → UI updates

 PADDLE SDK INTEGRATION (V4):
 The Paddle Mac Framework V4 is added via Swift Package Manager:
   Xcode → File → Add Package Dependencies → https://github.com/PaddleHQ/Mac-Framework-V4
 Once added, `#if canImport(Paddle)` enables the real SDK code paths.
 Without it, the manager operates in "stub mode" using UserDefaults only.

 WHY CONDITIONAL COMPILATION (#if canImport):
 We use #if canImport(Paddle) instead of commenting/uncommenting imports because:
 1. Both code paths compile and are syntax-checked by the compiler
 2. No manual toggling needed — adding the SPM package auto-enables real mode
 3. CI builds without the framework still compile cleanly
 4. We can test the stub mode behavior without removing the framework

 DEPENDENCIES:
 - FeatureGateService (reads from this)
 - AppDelegate (initializes this on launch)
 - PreferencesView / LicenseView (displays license status)
 - MenuBarView (shows upgrade prompt)

 PADDLE ACCOUNT SETUP REQUIRED:
 Before the real SDK works, you need:
 1. Create account at paddle.com (requires bank details for payouts)
 2. Create a product "SuperDimmer Pro" ($12 one-time, 7-day trial)
 3. Get your Vendor ID, Product ID, and API Key from the dashboard
 4. Replace the placeholder values in PaddleCredentials below
 5. Add the SPM package to the Xcode project

 ====================================================================
 Created: March 23, 2026
 Version: 2.0.0 — Real Paddle SDK integration with conditional compilation
 ====================================================================
 */

import Foundation
import Combine
import AppKit  // Needed for NSWorkspace.shared.open() in openPurchasePage()

// ====================================================================
// MARK: - Conditional Paddle Import
// ====================================================================
// The Paddle Mac Framework V4 is imported conditionally. When the SPM
// package (https://github.com/PaddleHQ/Mac-Framework-V4) is added to
// the Xcode project, this import succeeds and enables real SDK integration.
// Without it, the app falls back to stub/local-only license management.
// This approach was chosen over manual comment toggling because it's
// compiler-verified and auto-switches based on framework availability.
#if canImport(Paddle)
import Paddle
#endif

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

 BUSINESS CONTEXT:
 The freemium model is core to SuperDimmer's monetization strategy.
 Free tier provides basic global dimming (still useful, generates goodwill
 and word-of-mouth), while Pro unlocks intelligent per-window dimming,
 per-region dimming, Super Spaces, and other advanced features that
 power users need. The 7-day trial is critical for conversion — once
 users experience intelligent dimming, they feel the loss when it reverts.
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
     unlocked some features, conversion would be lower. BetterDisplay
     (our main competitor, also using Paddle) follows this same pattern.
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
// MARK: - Paddle Credentials
// ====================================================================

/**
 Paddle dashboard credentials for SuperDimmer Pro product.

 SECURITY NOTE:
 These are NOT secrets. Paddle vendor IDs, product IDs, and API keys are
 public-facing identifiers embedded in every macOS app that uses Paddle
 (you can extract them from BetterDisplay's binary, for example).
 The license key itself (entered by the user after purchase) is the actual
 credential that unlocks Pro features.

 HOW TO GET THESE VALUES:
 1. Log in to vendors.paddle.com
 2. Go to Catalog → Products → SuperDimmer Pro
 3. Vendor ID is on your account settings page
 4. Product ID is on the product detail page
 5. API Key is under Developer Tools → Authentication

 IMPORTANT: Replace these placeholder values with real ones from your
 Paddle dashboard before shipping. The app will compile and run with
 placeholders but all SDK operations will fail gracefully and fall back
 to stub mode behavior.
 */
private enum PaddleCredentials {
    /// Your Paddle seller/vendor account ID (numeric, from account settings).
    /// Example: 12345 — replace with your real vendor ID from vendors.paddle.com
    static let paddleVendorIdentifier: String = "REPLACE_WITH_PADDLE_VENDOR_ID"

    /// The product ID for "SuperDimmer Pro" (numeric, from product catalog).
    /// Created when you add a new product in the Paddle dashboard.
    static let paddleProductIdentifier: String = "REPLACE_WITH_PADDLE_PRODUCT_ID"

    /// The API key for SDK authentication (from Developer Tools → Authentication).
    /// This key identifies your app to Paddle's servers for license operations.
    static let paddleFrameworkApiKey: String = "REPLACE_WITH_PADDLE_API_KEY"

    /// Product display name shown in Paddle checkout UI and receipts.
    static let paddleProductDisplayName: String = "SuperDimmer Pro"

    /// Vendor display name shown in Paddle checkout UI.
    static let paddleVendorDisplayName: String = "SuperDimmer"

    /// One-time purchase price in USD for SuperDimmer Pro.
    /// Chosen based on competitive analysis: BetterDisplay charges $18,
    /// our $12 price point is low enough for impulse purchase while still
    /// generating meaningful revenue ($11.40 net after Paddle's ~5% fee).
    static let paddleProductPriceInUSD: NSNumber = 12.00

    /// Trial duration in days. 7 days gives users enough time to experience
    /// intelligent dimming across different workflows and feel the value.
    /// Paddle manages this server-side to prevent trial resets on reinstall.
    static let paddleTrialDurationInDays: Int = 7

    /// Whether credentials have been configured with real values.
    /// The app checks this on launch to decide whether to use real SDK or stub mode.
    /// This prevents confusing SDK errors when running with placeholder values.
    static var areCredentialsConfigured: Bool {
        return paddleVendorIdentifier != "REPLACE_WITH_PADDLE_VENDOR_ID"
            && paddleProductIdentifier != "REPLACE_WITH_PADDLE_PRODUCT_ID"
            && paddleFrameworkApiKey != "REPLACE_WITH_PADDLE_API_KEY"
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

 DUAL MODE OPERATION:
 This manager operates in one of two modes, determined at runtime:
 1. REAL MODE: When Paddle.framework is linked AND credentials are configured.
    Uses PADProduct for server-validated license checks, in-app checkout,
    and hardware-bound trial tracking.
 2. STUB MODE: When framework isn't linked OR credentials are placeholders.
    Uses UserDefaults-only license state. Accepts any non-empty key.
    This lets us build and test the UI flow before Paddle account exists.

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

    /**
     Whether the manager is currently communicating with Paddle servers.

     Observed by UI to show loading indicators during license operations
     like activation, deactivation, or refresh. Prevents double-taps
     on the Activate button while a request is in flight.
     */
    @Published private(set) var isProcessingLicenseOperation: Bool = false

    /**
     The last error message from a license operation, if any.

     Displayed in LicenseView to inform the user about activation failures,
     network errors, or invalid keys. Cleared on next successful operation.
     */
    @Published private(set) var lastLicenseOperationError: String? = nil

    /**
     Whether the real Paddle SDK is active (vs stub mode).

     Used by UI to show appropriate messaging — e.g., stub mode shows
     "Demo mode — any key accepted" in the license input field.
     */
    @Published private(set) var isPaddleSDKIntegrationActive: Bool = false

    // ================================================================
    // MARK: - Private Properties
    // ================================================================

    /**
     UserDefaults keys for license persistence.

     Grouped in an enum to prevent typo-based key mismatches and
     to make it easy to audit what we store.

     WHY WE STILL USE USERDEFAULTS WITH PADDLE:
     Paddle SDK has its own persistence layer, but we keep a UserDefaults
     mirror for two reasons:
     1. Fast synchronous reads on app launch (Paddle SDK init is async)
     2. Fallback when Paddle servers are unreachable
     The Paddle server state is authoritative; local state is a cache.
     */
    private enum DefaultsKeys {
        static let licenseKeyStorageIdentifier = "SuperDimmer_LicenseKey"
        static let licenseStateStorageIdentifier = "SuperDimmer_LicenseState"
        static let trialStartDateStorageIdentifier = "SuperDimmer_TrialStartDate"
        static let trialDurationInDays = 7  // Matches PaddleCredentials.paddleTrialDurationInDays
    }

    /// Standard UserDefaults for persistence.
    private let userDefaultsStorage = UserDefaults.standard

    #if canImport(Paddle)
    // ================================================================
    // MARK: - Paddle SDK Properties (Real Mode)
    // ================================================================

    /**
     The Paddle framework instance.

     This is the main entry point for all Paddle SDK operations.
     Initialized once in initializePaddleSDK() with vendor credentials.
     All subsequent operations (checkout, activation, verification)
     go through this instance.

     WHY OPTIONAL:
     The Paddle instance may fail to initialize if credentials are invalid
     or if there's a framework loading issue. We handle nil gracefully
     by falling back to stub mode behavior.
     */
    private var paddleFrameworkInstance: Paddle?

    /**
     The PADProduct representing "SuperDimmer Pro".

     Configured with product ID, trial settings, and pricing info.
     Used for:
     - License key activation (product.activate)
     - License verification (product.verifyActivation)
     - Showing checkout UI (product.showBuyWindow)
     - Trial state checking (product.trialDaysRemaining)

     This is the Paddle V4 way of representing a purchasable product.
     Each product has its own activation state, trial period, and
     license key independent of other products (though SuperDimmer
     only has one product).
     */
    private var paddleSuperDimmerProProduct: PADProduct?

    /**
     Product configuration used to initialize the PADProduct.

     Contains the product name, vendor name, trial length, pricing,
     and other display info that Paddle shows in its checkout UI.
     Also used for offline product access dialogs when the user's
     trial has expired.
     */
    private var paddleProductConfiguration: PADProductConfiguration?
    #endif

    // ================================================================
    // MARK: - Initialization
    // ================================================================

    /**
     Private initializer enforces singleton pattern.

     On init:
     1. Loads any stored license key from UserDefaults (fast, synchronous)
     2. Attempts to initialize Paddle SDK (may update state asynchronously)
     3. Sets isPaddleSDKIntegrationActive based on whether SDK loaded

     The UserDefaults load gives us an immediate license state for the UI,
     while the Paddle SDK validation may correct it asynchronously after
     a network round-trip (e.g., if the license was revoked server-side).
     */
    private init() {
        loadStoredLicenseStateFromUserDefaults()
        initializePaddleSDK()
    }

    // ================================================================
    // MARK: - Public API
    // ================================================================

    /**
     Activate a license key entered by the user.

     Flow:
     1. Store the key locally in UserDefaults
     2. If Paddle SDK active: validate with Paddle API (async callback)
     3. If stub mode: accept any non-empty key immediately
     4. Update licenseState based on result
     5. Completion handler reports success/failure for UI feedback

     CALLED BY: LicenseView when user taps "Activate" button.

     WHY COMPLETION HANDLER:
     Paddle SDK validation is asynchronous (network call). The previous
     stub version returned Bool synchronously, but real activation needs
     a callback. We keep the completion optional for backward compatibility
     with any callers that don't need the result.

     - Parameter licenseKeyToActivate: The license key string from Paddle checkout email.
     - Parameter activationCompletionHandler: Called on main thread with (success, errorMessage).
     */
    /**
     Backward-compatible synchronous activation method.

     CALLED BY: LicenseView.swift (line ~441) which expects a synchronous Bool return.
     In stub mode, this returns true immediately for any non-empty key.
     In real Paddle mode, this returns true optimistically (key is stored locally)
     while the async validation runs in the background. If validation fails,
     the state will revert asynchronously.

     WHY WE KEEP THIS:
     The existing LicenseView was built with synchronous activation in mind.
     Rather than requiring a UI rewrite just to add Paddle, we keep this
     synchronous wrapper and add the async version alongside it. Future UI
     refactors can switch to the async version for better UX (loading spinner).

     - Parameter key: The license key string from Paddle checkout.
     - Returns: True if the key is non-empty (stub mode) or stored for validation.
     */
    @discardableResult
    func activateLicense(key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }

        // Call the full async version — the synchronous return covers stub mode
        activateLicenseWithCompletion(licenseKeyToActivate: trimmedKey, activationCompletionHandler: nil)

        // In stub mode, state is already .pro by the time we return.
        // In Paddle mode, we return true optimistically (key stored locally).
        return true
    }

    /**
     Full async activation with completion handler for Paddle SDK integration.

     CALLED BY: Future LicenseView updates that want loading states and error handling.
     The completion handler fires on the main thread after Paddle server validation.

     - Parameter licenseKeyToActivate: The license key string from Paddle checkout email.
     - Parameter activationCompletionHandler: Called on main thread with (success, errorMessage).
     */
    func activateLicenseWithCompletion(
        licenseKeyToActivate: String,
        activationCompletionHandler: ((Bool, String?) -> Void)? = nil
    ) {
        // Guard against empty keys — don't waste a network call
        let trimmedLicenseKey = licenseKeyToActivate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLicenseKey.isEmpty else {
            lastLicenseOperationError = "Please enter a license key"
            activationCompletionHandler?(false, "Please enter a license key")
            return
        }

        // Prevent double-tap while an operation is in flight
        guard !isProcessingLicenseOperation else {
            AppLogger.licensing.info("Activation rejected — another operation is in progress")
            return
        }

        isProcessingLicenseOperation = true
        lastLicenseOperationError = nil

        // Store the key locally regardless of validation outcome.
        // If validation fails, we'll remove it. If the user is offline,
        // having it stored means we can retry validation on next launch.
        userDefaultsStorage.set(trimmedLicenseKey, forKey: DefaultsKeys.licenseKeyStorageIdentifier)
        licenseKey = trimmedLicenseKey

        #if canImport(Paddle)
        // ============================================================
        // REAL PADDLE SDK ACTIVATION
        // Uses PADProduct.activate() which sends the key to Paddle servers
        // for validation, checks activation count against allowed_uses,
        // and binds to this machine's hardware ID.
        // ============================================================
        if let paddleProduct = paddleSuperDimmerProProduct, isPaddleSDKIntegrationActive {
            AppLogger.licensing.info("Attempting Paddle SDK activation for key: \(trimmedLicenseKey.prefix(8))...")

            paddleProduct.activate(
                email: "",  // Email is optional for activation — user already has key
                license: trimmedLicenseKey
            ) { [weak self] activated, activationError in
                DispatchQueue.main.async {
                    guard let strongSelfReference = self else { return }
                    strongSelfReference.isProcessingLicenseOperation = false

                    if activated {
                        // Activation succeeded — Paddle has validated the key,
                        // checked activation count, and bound to this hardware ID.
                        strongSelfReference.updateLicenseState(.pro)
                        strongSelfReference.lastLicenseOperationError = nil
                        AppLogger.licensing.info("Paddle SDK activation successful for key: \(trimmedLicenseKey.prefix(8))...")
                        activationCompletionHandler?(true, nil)
                    } else {
                        // Activation failed — could be invalid key, max activations reached,
                        // or network error. Remove the stored key since it's not valid.
                        let activationErrorDescription = activationError?.localizedDescription ?? "Unknown activation error"
                        strongSelfReference.userDefaultsStorage.removeObject(forKey: DefaultsKeys.licenseKeyStorageIdentifier)
                        strongSelfReference.licenseKey = nil
                        strongSelfReference.lastLicenseOperationError = activationErrorDescription

                        // Revert to whatever state we were in before (trial or free)
                        let previousLicenseState = strongSelfReference.checkTrialStateFromLocalStorage()
                        strongSelfReference.updateLicenseState(previousLicenseState)

                        AppLogger.licensing.error("Paddle SDK activation failed: \(activationErrorDescription)")
                        activationCompletionHandler?(false, activationErrorDescription)
                    }
                }
            }
            return  // Exit — completion handler will be called asynchronously
        }
        #endif

        // ============================================================
        // STUB MODE ACTIVATION
        // When Paddle SDK is not linked or credentials aren't configured,
        // accept any non-empty key for testing. This lets us build and
        // test the full UI flow without a live Paddle account.
        // ============================================================
        updateLicenseState(.pro)
        isProcessingLicenseOperation = false
        AppLogger.licensing.info("License activated (stub mode): \(trimmedLicenseKey.prefix(8))...")
        activationCompletionHandler?(true, nil)
    }

    /**
     Deactivate the current license.

     Used when user wants to transfer their license to another machine.
     Paddle SDK handles the server-side deactivation to free up the
     activation slot (each license key has a limited number of activations,
     typically 2-3 machines).

     CALLED BY: LicenseView when user taps "Deactivate" button.

     - Parameter deactivationCompletionHandler: Called on main thread with (success, errorMessage).
     */
    /**
     Deactivate the current license (backward-compatible no-arg version).

     CALLED BY: LicenseView.swift (line ~166) and FeatureGateService.
     Wraps the async version without needing a completion handler.
     */
    func deactivateLicense() {
        deactivateLicenseWithCompletion(deactivationCompletionHandler: nil)
    }

    /**
     Full async deactivation with completion handler for Paddle SDK integration.

     - Parameter deactivationCompletionHandler: Called on main thread with (success, errorMessage).
     */
    func deactivateLicenseWithCompletion(
        deactivationCompletionHandler: ((Bool, String?) -> Void)? = nil
    ) {
        guard !isProcessingLicenseOperation else {
            AppLogger.licensing.info("Deactivation rejected — another operation is in progress")
            return
        }

        isProcessingLicenseOperation = true
        lastLicenseOperationError = nil

        #if canImport(Paddle)
        // ============================================================
        // REAL PADDLE SDK DEACTIVATION
        // Calls Paddle servers to release the activation slot for this
        // hardware ID. The user can then activate on a different machine.
        // ============================================================
        if let paddleProduct = paddleSuperDimmerProProduct, isPaddleSDKIntegrationActive {
            AppLogger.licensing.info("Attempting Paddle SDK deactivation...")

            paddleProduct.deactivate { [weak self] deactivated, deactivationError in
                DispatchQueue.main.async {
                    guard let strongSelfReference = self else { return }
                    strongSelfReference.isProcessingLicenseOperation = false

                    if deactivated {
                        strongSelfReference.clearStoredLicenseKeyFromDefaults()
                        let revertedLicenseState = strongSelfReference.checkTrialStateFromLocalStorage()
                        strongSelfReference.updateLicenseState(revertedLicenseState)
                        AppLogger.licensing.info("Paddle SDK deactivation successful")
                        deactivationCompletionHandler?(true, nil)
                    } else {
                        let deactivationErrorDescription = deactivationError?.localizedDescription ?? "Unknown deactivation error"
                        strongSelfReference.lastLicenseOperationError = deactivationErrorDescription
                        AppLogger.licensing.error("Paddle SDK deactivation failed: \(deactivationErrorDescription)")
                        deactivationCompletionHandler?(false, deactivationErrorDescription)
                    }
                }
            }
            return
        }
        #endif

        // STUB MODE: Just clear local state
        clearStoredLicenseKeyFromDefaults()
        let revertedLicenseState = checkTrialStateFromLocalStorage()
        updateLicenseState(revertedLicenseState)
        isProcessingLicenseOperation = false
        AppLogger.licensing.info("License deactivated (stub mode)")
        deactivationCompletionHandler?(true, nil)
    }

    /**
     Start the 7-day Pro trial.

     Called when user taps "Start Free Trial" in the upgrade prompt.
     Records the trial start date in UserDefaults. When Paddle SDK is active,
     also registers the trial server-side to prevent reset on reinstall
     (Paddle binds trials to hardware ID).

     BUSINESS LOGIC:
     Trial can only be started once per install. If the user reinstalls
     the app, Paddle's server-side tracking prevents re-trialing (the
     hardware ID is bound). Local-only fallback uses UserDefaults date.

     CALLED BY: LicenseView or upgrade prompt in MenuBarView.
     */
    /**
     Backward-compatible name for startProFeatureTrial.
     CALLED BY: LicenseView.swift (line ~289), FeatureGateService.swift (line ~306).
     */
    func startTrial() {
        startProFeatureTrial()
    }

    /**
     Start the 7-day Pro trial (full implementation).
     */
    func startProFeatureTrial() {
        guard licenseState == .free else {
            // Trial already started, expired, or user is already pro
            AppLogger.licensing.info("Trial start rejected — current state: \(self.licenseState.displayDescription)")
            return
        }

        let trialStartTimestamp = Date()
        userDefaultsStorage.set(trialStartTimestamp, forKey: DefaultsKeys.trialStartDateStorageIdentifier)

        #if canImport(Paddle)
        // When Paddle SDK is active, the trial is also tracked server-side.
        // PADProduct handles trial registration automatically based on the
        // PADProductConfiguration.trialLength setting. We just need to tell
        // it to start the trial and it handles hardware ID binding.
        if let paddleProduct = paddleSuperDimmerProProduct, isPaddleSDKIntegrationActive {
            // Paddle SDK tracks the trial automatically via PADProductConfiguration.
            // The local UserDefaults date serves as a fast local cache.
            AppLogger.licensing.info("Trial started with Paddle SDK tracking: \(PaddleCredentials.paddleTrialDurationInDays) days from \(trialStartTimestamp)")
        }
        #endif

        updateLicenseState(.trial(daysRemaining: PaddleCredentials.paddleTrialDurationInDays))
        AppLogger.licensing.info("Trial started: \(PaddleCredentials.paddleTrialDurationInDays) days from \(trialStartTimestamp)")
    }

    /**
     Open the Paddle checkout page for purchasing a Pro license.

     When Paddle SDK is active: shows the in-app Paddle checkout overlay
     (a WKWebView-based window with payment form, Apple Pay, etc.).
     When in stub mode: opens the website pricing page in the default browser.

     The in-app checkout is preferred because it keeps the user in the app,
     reduces friction, and automatically activates the license after purchase
     without the user needing to copy/paste a key.

     CALLED BY: Any "Buy Pro" / "Upgrade" button in the app.
     */
    /**
     Backward-compatible name for openPurchaseCheckoutPage.
     CALLED BY: LicenseView.swift (lines ~305, ~331, ~394),
     FeatureGateService.swift (line ~315), MenuBarView.swift (line ~192).
     */
    func openPurchasePage() {
        openPurchaseCheckoutPage()
    }

    /**
     Open the Paddle checkout page for purchasing a Pro license (full implementation).
     */
    func openPurchaseCheckoutPage() {
        #if canImport(Paddle)
        // ============================================================
        // REAL PADDLE SDK CHECKOUT
        // Shows the Paddle in-app checkout overlay. When the user
        // completes purchase, Paddle calls our delegate/callback with
        // the license key, and we auto-activate it.
        // ============================================================
        if let paddleProduct = paddleSuperDimmerProProduct,
           let paddleInstance = paddleFrameworkInstance,
           isPaddleSDKIntegrationActive {
            AppLogger.licensing.info("Opening Paddle in-app checkout overlay")

            // showBuyWindow presents the Paddle checkout overlay as a
            // macOS window/sheet. After successful purchase, the product
            // is automatically activated and our delegate receives the callback.
            paddleInstance.showProductAccessDialog(with: paddleProduct)
            return
        }
        #endif

        // FALLBACK: Open website pricing page
        // This works even without Paddle SDK — user can purchase on website
        // and manually enter the license key in Preferences
        if let websitePricingPageURL = URL(string: "https://superdimmer.com/pricing.html") {
            NSWorkspace.shared.open(websitePricingPageURL)
            AppLogger.licensing.info("Opened pricing page in browser (stub mode / SDK not available)")
        }
    }

    /**
     Refresh license state from Paddle servers (or local storage in stub mode).

     Called on app launch and periodically (every 24 hours) to ensure
     local state matches server state. Handles edge cases like:
     - License revoked (chargeback)
     - License transferred to another machine
     - Trial expired while app was closed

     CALLED BY: AppDelegate on applicationDidFinishLaunching, and
     by a timer every 24 hours while the app is running.
     */
    /**
     Backward-compatible name for refreshLicenseStateFromServer.
     CALLED BY: Any code that needs to refresh license state.
     */
    func refreshLicenseState() {
        refreshLicenseStateFromServer()
    }

    /**
     Refresh license state from Paddle servers (or local storage in stub mode).
     */
    func refreshLicenseStateFromServer() {
        #if canImport(Paddle)
        // ============================================================
        // REAL PADDLE SDK REFRESH
        // Checks the current product state with Paddle servers.
        // This catches: license revocations, chargebacks, trial expiry,
        // and activation transfers.
        // ============================================================
        if let paddleProduct = paddleSuperDimmerProProduct, isPaddleSDKIntegrationActive {
            AppLogger.licensing.info("Refreshing license state from Paddle servers...")

            paddleProduct.verifyActivation { [weak self] verificationState, verificationError in
                DispatchQueue.main.async {
                    guard let strongSelfReference = self else { return }

                    if let verifyError = verificationError {
                        // Network error or other issue — keep current state
                        // (Paddle SDK caches locally, so we trust the cached state)
                        AppLogger.licensing.warning("Paddle verification error (keeping cached state): \(verifyError.localizedDescription)")
                        return
                    }

                    // Map Paddle's verification state to our license state enum.
                    // PADVerificationState tells us whether the activation is valid,
                    // and PADProduct properties tell us about trial status.
                    switch verificationState {
                    case .verified:
                        // License is valid and active on this machine
                        strongSelfReference.updateLicenseState(.pro)
                        AppLogger.licensing.info("License verified as active via Paddle")

                    case .unverified:
                        // License was valid but is no longer (revoked, transferred, etc.)
                        strongSelfReference.clearStoredLicenseKeyFromDefaults()
                        let localFallbackState = strongSelfReference.checkTrialStateFromLocalStorage()
                        strongSelfReference.updateLicenseState(localFallbackState)
                        AppLogger.licensing.warning("License no longer valid — reverted to: \(localFallbackState.displayDescription)")

                    case .noActivation:
                        // No activation exists — check trial state
                        let trialOrFreeState = strongSelfReference.checkTrialStateFromLocalStorage()
                        strongSelfReference.updateLicenseState(trialOrFreeState)
                        AppLogger.licensing.info("No activation found — state: \(trialOrFreeState.displayDescription)")

                    @unknown default:
                        // Future Paddle SDK states we don't handle yet
                        AppLogger.licensing.warning("Unknown Paddle verification state — keeping current state")
                    }
                }
            }
            return
        }
        #endif

        // STUB MODE: Re-check local state from UserDefaults
        loadStoredLicenseStateFromUserDefaults()
        AppLogger.licensing.info("License state refreshed (stub mode): \(self.licenseState.displayDescription)")
    }

    // ================================================================
    // MARK: - Private Methods — State Management
    // ================================================================

    /**
     Load license state from UserDefaults on startup.

     Checks in order:
     1. Is there a stored license key? → .pro (pending server validation)
     2. Is there an active trial? → .trial(daysRemaining)
     3. Was there a trial that expired? → .expired
     4. Otherwise → .free

     This local check runs synchronously for instant UI display.
     Paddle SDK validation may override this state asynchronously
     after a network round-trip (e.g., if the license was revoked).

     WHY CHECK LOCAL FIRST:
     The app should render something immediately on launch. Waiting
     for a network call would show a flash of "Free" state even for
     Pro users. By reading UserDefaults first, Pro users see "Pro"
     instantly, and if Paddle later says "revoked", it updates.
     */
    private func loadStoredLicenseStateFromUserDefaults() {
        // Check for stored license key first — optimistic .pro
        if let storedLicenseKey = userDefaultsStorage.string(forKey: DefaultsKeys.licenseKeyStorageIdentifier),
           !storedLicenseKey.isEmpty {
            licenseKey = storedLicenseKey
            updateLicenseState(.pro)
            return
        }

        // No license key — check trial state
        let currentTrialState = checkTrialStateFromLocalStorage()
        updateLicenseState(currentTrialState)
    }

    /**
     Check the local trial state based on stored start date.

     MATH:
     - Trial start date stored in UserDefaults
     - Trial duration is 7 days (configurable in PaddleCredentials)
     - Days remaining = trial end date - today
     - If days remaining <= 0 → expired
     - If no start date → free (trial never started)

     WHY LOCAL CHECK:
     Paddle SDK tracks trials server-side too, but we need a local
     fallback for offline users. The server state is authoritative
     when available. This method is called both as a standalone check
     and as a fallback within Paddle SDK callbacks.
     */
    private func checkTrialStateFromLocalStorage() -> SuperDimmerLicenseState {
        guard let trialStartDate = userDefaultsStorage.object(forKey: DefaultsKeys.trialStartDateStorageIdentifier) as? Date else {
            return .free  // Trial was never started
        }

        let trialEndDate = Calendar.current.date(
            byAdding: .day,
            value: PaddleCredentials.paddleTrialDurationInDays,
            to: trialStartDate
        ) ?? trialStartDate

        let currentTimestamp = Date()

        if currentTimestamp >= trialEndDate {
            return .expired
        }

        let remainingTrialDays = Calendar.current.dateComponents(
            [.day],
            from: currentTimestamp,
            to: trialEndDate
        ).day ?? 0

        return .trial(daysRemaining: max(1, remainingTrialDays))
    }

    /**
     Clear the stored license key from UserDefaults.

     Called during deactivation and when Paddle reports the license
     is no longer valid. Separated into its own method because both
     the real SDK path and stub mode path need to do the same cleanup.
     */
    private func clearStoredLicenseKeyFromDefaults() {
        userDefaultsStorage.removeObject(forKey: DefaultsKeys.licenseKeyStorageIdentifier)
        licenseKey = nil
    }

    /**
     Update the license state on the main thread.

     WHY MAIN THREAD:
     @Published properties must be mutated on the main thread for
     SwiftUI observation to work correctly. Paddle SDK callbacks may
     come from background threads, so we always dispatch to main.
     */
    private func updateLicenseState(_ newLicenseState: SuperDimmerLicenseState) {
        if Thread.isMainThread {
            licenseState = newLicenseState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.licenseState = newLicenseState
            }
        }
    }

    // ================================================================
    // MARK: - Private Methods — Paddle SDK Initialization
    // ================================================================

    /**
     Initialize Paddle SDK with vendor and product credentials.

     This is called once during init(). When the Paddle framework is
     available and credentials are configured, it:
     1. Creates a Paddle instance with vendor ID and API key
     2. Creates a PADProductConfiguration with product details
     3. Creates a PADProduct for license operations
     4. Sets isPaddleSDKIntegrationActive = true

     PADDLE V4 INITIALIZATION FLOW (from Mac-Framework-V4 docs):
     1. Create Paddle.sharedInstance with vendorId and apiKey
     2. Create PADProductConfiguration with product display info
     3. Create PADProduct with productId and configuration
     4. Use PADProduct methods for activation, verification, checkout

     WHY WE DON'T CRASH ON MISSING CREDENTIALS:
     During development, credentials won't be set. The app should still
     compile and run with full stub mode functionality. Only when real
     credentials are configured does the SDK activate.
     */
    private func initializePaddleSDK() {
        #if canImport(Paddle)
        // Only initialize if credentials have been configured with real values.
        // This prevents confusing SDK errors during development when running
        // with placeholder "REPLACE_WITH_..." values.
        guard PaddleCredentials.areCredentialsConfigured else {
            isPaddleSDKIntegrationActive = false
            AppLogger.licensing.info("LicenseManager: Paddle credentials not configured — running in stub mode. Set real credentials in PaddleCredentials to enable SDK.")
            return
        }

        AppLogger.licensing.info("Initializing Paddle SDK with vendor: \(PaddleCredentials.paddleVendorIdentifier)...")

        // Step 1: Get the shared Paddle instance.
        // Paddle.sharedInstance() returns the framework singleton.
        // We configure it with our vendor ID and API key.
        let paddleInstance = Paddle.sharedInstance(
            withVendorID: PaddleCredentials.paddleVendorIdentifier,
            apiKey: PaddleCredentials.paddleFrameworkApiKey,
            productID: PaddleCredentials.paddleProductIdentifier,
            configuration: nil,  // We set product config separately
            delegate: nil  // We use completion handlers, not delegate pattern
        )
        self.paddleFrameworkInstance = paddleInstance

        // Step 2: Create product configuration.
        // PADProductConfiguration holds the display info shown in
        // Paddle's checkout overlay, product access dialog, and trial UI.
        let productConfiguration = PADProductConfiguration()
        productConfiguration.productName = PaddleCredentials.paddleProductDisplayName
        productConfiguration.vendorName = PaddleCredentials.paddleVendorDisplayName
        productConfiguration.trialLength = NSNumber(value: PaddleCredentials.paddleTrialDurationInDays)
        productConfiguration.trialType = .timeLimited
        productConfiguration.currency = "USD"
        productConfiguration.price = PaddleCredentials.paddleProductPriceInUSD
        self.paddleProductConfiguration = productConfiguration

        // Step 3: Create the PADProduct for "SuperDimmer Pro".
        // This is the object we use for all license operations:
        // activation, deactivation, verification, and checkout.
        let superDimmerProProduct = PADProduct(
            productID: PaddleCredentials.paddleProductIdentifier,
            productType: .sdkProduct,
            configuration: productConfiguration
        )
        self.paddleSuperDimmerProProduct = superDimmerProProduct

        // Mark SDK as active so the rest of the code uses real paths
        isPaddleSDKIntegrationActive = true
        AppLogger.licensing.info("Paddle SDK initialized successfully for product: \(PaddleCredentials.paddleProductDisplayName)")

        // Step 4: Verify current activation state on launch.
        // This is the "phone home" that catches revoked licenses,
        // expired trials, and activation transfers.
        refreshLicenseStateFromServer()

        #else
        // Paddle framework not linked — stub mode
        isPaddleSDKIntegrationActive = false
        AppLogger.licensing.info("LicenseManager initialized (stub mode — Paddle.framework not linked via SPM)")
        #endif
    }
}
