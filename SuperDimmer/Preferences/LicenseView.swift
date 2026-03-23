/**
 ====================================================================
 LicenseView.swift
 License management UI tab for SuperDimmer Preferences
 ====================================================================

 PURPOSE:
 This SwiftUI view provides the user-facing interface for managing their
 SuperDimmer Pro license. It displays the current license state and provides
 actions appropriate to each state:
 - Free: "Start Trial" and "Buy Pro" buttons
 - Trial: Countdown display + "Buy Pro" button
 - Pro: License key display + "Deactivate" button
 - Expired: Urgent "Buy Pro" prompt

 HISTORY:
 - Created 2026-03-23 as part of the Paddle payment integration initiative
   (BridgeMind task 39cc4a31).
 - Previously, SuperDimmer had no license UI at all — all features were
   unlocked for free. This view is the first step toward monetization.
 - Design follows the PAYMENT-INTEGRATION-PLAN.md Phase 4 specification.

 ARCHITECTURE:
 LicenseView observes both LicenseManager (for license state) and
 FeatureGateService (for feature availability). It's embedded as a tab
 in PreferencesView alongside General, SuperDimmer, etc.

 The view adapts its layout based on license state:
 - .free → hero section encouraging trial start, feature comparison
 - .trial → countdown timer, buy prompt, feature list showing what's active
 - .pro → confirmation, license key, deactivation option
 - .expired → urgent upgrade prompt, feature comparison showing what's lost

 DEPENDENCIES:
 - LicenseManager (reads/writes license state)
 - FeatureGateService (reads feature availability)
 - PreferencesView (parent — embeds this as a tab)

 ====================================================================
 Created: March 23, 2026
 Version: 1.0.0
 ====================================================================
 */

import SwiftUI

// ====================================================================
// MARK: - License View
// ====================================================================

/**
 SwiftUI view for license management in the Preferences window.

 WHY A SEPARATE VIEW:
 License management is complex enough to warrant its own file, following
 the project's one-function-per-class principle. It also keeps
 PreferencesView clean — each tab is its own view file.

 USAGE:
 Embedded in PreferencesView as a tab:
 ```swift
 case .license:
     LicensePreferencesTab()
 ```
 */
struct LicensePreferencesTab: View {

    // ================================================================
    // MARK: - Observed Objects
    // ================================================================

    /**
     Observe LicenseManager for license state changes.
     When the user activates/deactivates a license or starts a trial,
     this view updates automatically via Combine observation.
     */
    @ObservedObject private var licenseManager = LicenseManager.shared

    /**
     Observe FeatureGateService for feature availability.
     Used to show which features are currently unlocked vs locked.
     */
    @ObservedObject private var featureGate = FeatureGateService.shared

    // ================================================================
    // MARK: - Local State
    // ================================================================

    /**
     The license key text field binding.
     User types their Paddle license key here before clicking "Activate".
     Separate from LicenseManager.licenseKey because we don't want to
     persist partial input — only persist on successful activation.
     */
    @State private var licenseKeyInput: String = ""

    /**
     Whether to show the activation result alert.
     Shown after user clicks "Activate" to confirm success or failure.
     */
    @State private var showActivationResult = false

    /**
     Whether the last activation attempt succeeded.
     Controls the alert message shown to the user.
     */
    @State private var activationSucceeded = false

    /**
     Whether to show the deactivation confirmation dialog.
     Prevents accidental deactivation — user must confirm.
     */
    @State private var showDeactivateConfirmation = false

    // ================================================================
    // MARK: - Body
    // ================================================================

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ========================================================
                // License Status Hero Section
                // ========================================================
                // Large, prominent display of current license state.
                // This is the first thing the user sees in the License tab.
                licenseStatusHeroSection

                Divider()

                // ========================================================
                // Action Section (state-dependent)
                // ========================================================
                // Shows different actions based on current license state:
                // - Free: Start Trial + Buy Pro
                // - Trial: Buy Pro (with countdown)
                // - Pro: License key display + Deactivate
                // - Expired: Buy Pro (urgent)
                licenseActionSection

                Divider()

                // ========================================================
                // Pro Features Comparison
                // ========================================================
                // Shows what's included in free vs Pro, helping users
                // understand the value of upgrading.
                proFeaturesComparisonSection
            }
            .padding(20)
        }
        // Alert for activation result feedback
        .alert(
            activationSucceeded ? "License Activated" : "Activation Failed",
            isPresented: $showActivationResult
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(activationSucceeded
                 ? "Your SuperDimmer Pro license is now active. All Pro features are unlocked!"
                 : "The license key could not be validated. Please check the key and try again.")
        }
        // Confirmation dialog for deactivation
        .alert("Deactivate License?", isPresented: $showDeactivateConfirmation) {
            Button("Deactivate", role: .destructive) {
                licenseManager.deactivateLicense()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will deactivate your Pro license on this machine. You can re-activate it later or transfer it to another Mac.")
        }
    }

    // ================================================================
    // MARK: - License Status Hero Section
    // ================================================================

    /**
     Large status display at the top of the License tab.

     Shows an icon, the current state description, and contextual
     messaging based on the license tier. This is designed to be
     immediately scannable — users should know their status at a glance.
     */
    private var licenseStatusHeroSection: some View {
        VStack(spacing: 12) {
            // Status icon — changes based on license state
            // WHY SF SYMBOLS: Native macOS look, retina-quality, and they
            // automatically adapt to light/dark mode.
            Image(systemName: licenseStatusIcon)
                .font(.system(size: 48))
                .foregroundColor(licenseStatusColor)

            // Status title
            Text(licenseManager.licenseState.displayDescription)
                .font(.title2)
                .fontWeight(.semibold)

            // Contextual subtitle
            Text(licenseStatusSubtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// SF Symbol icon name based on current license state.
    private var licenseStatusIcon: String {
        switch licenseManager.licenseState {
        case .free:
            return "moon.fill"
        case .trial:
            return "clock.badge.checkmark"
        case .pro:
            return "checkmark.seal.fill"
        case .expired:
            return "exclamationmark.triangle.fill"
        }
    }

    /// Color for the status icon based on current license state.
    private var licenseStatusColor: Color {
        switch licenseManager.licenseState {
        case .free:
            return .secondary
        case .trial:
            return .orange
        case .pro:
            return .green
        case .expired:
            return .red
        }
    }

    /// Subtitle text providing context for the current license state.
    /// This helps users understand what their status means and what
    /// actions they can take.
    private var licenseStatusSubtitle: String {
        switch licenseManager.licenseState {
        case .free:
            return "You're using the free version of SuperDimmer. Upgrade to Pro to unlock intelligent per-window dimming, Super Spaces, and more."
        case .trial(let daysRemaining):
            return "You have \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in your Pro trial. All Pro features are currently unlocked."
        case .pro:
            return "Thank you for supporting SuperDimmer! All Pro features are permanently unlocked."
        case .expired:
            return "Your trial has ended. Pro features are now locked. Purchase a license to unlock them permanently."
        }
    }

    // ================================================================
    // MARK: - License Action Section
    // ================================================================

    /**
     State-dependent action buttons and controls.

     This section adapts completely based on the license state,
     showing only relevant actions for each tier.
     */
    private var licenseActionSection: some View {
        VStack(spacing: 16) {
            switch licenseManager.licenseState {
            case .free:
                freeStateActions
            case .trial:
                trialStateActions
            case .pro:
                proStateActions
            case .expired:
                expiredStateActions
            }
        }
    }

    /// Actions for free tier: Start Trial and Buy Pro buttons.
    /// Both are prominent — trial is the primary CTA because it drives
    /// conversion (users who try Pro features are more likely to buy).
    private var freeStateActions: some View {
        VStack(spacing: 12) {
            // Primary CTA: Start free trial
            // WHY TRIAL FIRST: The payment plan (PAYMENT-INTEGRATION-PLAN.md)
            // identifies trial as the primary conversion driver. Users who
            // experience Pro features during trial feel the loss when it expires.
            Button(action: {
                licenseManager.startTrial()
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start 7-Day Free Trial")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)

            // Secondary CTA: Buy Pro directly
            Button(action: {
                licenseManager.openPurchasePage()
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Buy Pro License — $12")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            // License key entry for existing customers
            // Some users may have purchased through the website and
            // need to enter their key manually.
            licenseKeyEntrySection
        }
    }

    /// Actions for trial state: Buy Pro button with countdown emphasis.
    /// The countdown creates urgency without being pushy.
    private var trialStateActions: some View {
        VStack(spacing: 12) {
            // Buy Pro CTA — more prominent during trial because
            // the user has already experienced the features
            Button(action: {
                licenseManager.openPurchasePage()
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Buy Pro License — $12")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)

            // License key entry for manual activation
            licenseKeyEntrySection
        }
    }

    /// Actions for Pro state: License info and deactivation option.
    /// Minimal UI — the user is happy, don't clutter the screen.
    private var proStateActions: some View {
        VStack(spacing: 12) {
            // Show the stored license key (masked for privacy)
            if let key = licenseManager.licenseKey {
                HStack {
                    Text("License Key:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(maskedLicenseKey(key))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            }

            // Deactivate button — small and unobtrusive.
            // Users rarely need this, but it's important for license
            // transfer between machines.
            Button(action: {
                showDeactivateConfirmation = true
            }) {
                HStack {
                    Image(systemName: "arrow.uturn.left")
                    Text("Deactivate License")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(.secondary)
        }
    }

    /// Actions for expired trial: Urgent buy prompt.
    /// More prominent than the free state because the user has
    /// already experienced Pro features and knows what they're missing.
    private var expiredStateActions: some View {
        VStack(spacing: 12) {
            // Urgent CTA
            Button(action: {
                licenseManager.openPurchasePage()
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Unlock Pro Features — $12")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)

            // License key entry
            licenseKeyEntrySection
        }
    }

    // ================================================================
    // MARK: - License Key Entry Section
    // ================================================================

    /**
     Text field + Activate button for manual license key entry.

     Some users purchase through the website or receive keys via email.
     This section lets them paste their key and activate it.

     REUSED across free, trial, and expired states.
     */
    private var licenseKeyEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already have a license key?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                // License key text field
                // WHY .monospaced: License keys are alphanumeric strings.
                // Monospaced font makes them easier to read and verify.
                TextField("Enter license key", text: $licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                // Activate button — only enabled when there's input
                Button("Activate") {
                    activationSucceeded = licenseManager.activateLicense(key: licenseKeyInput)
                    showActivationResult = true
                    if activationSucceeded {
                        licenseKeyInput = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    // ================================================================
    // MARK: - Pro Features Comparison Section
    // ================================================================

    /**
     Feature comparison table showing Free vs Pro features.

     This is the "value proposition" section — it helps users understand
     exactly what they get by upgrading. Each feature row shows:
     - Feature name and icon
     - Whether it's available in the current tier (checkmark or lock)

     WHY INLINE TABLE (not a separate view):
     This is only used here. No reuse needed. Keeping it in LicenseView
     follows the project's principle of not creating abstractions for
     one-time operations.
     */
    private var proFeaturesComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feature Comparison")
                .font(.headline)
                .fontWeight(.semibold)

            // Feature rows
            VStack(spacing: 0) {
                featureRow(name: "Global Screen Dimming", icon: "sun.max.fill", isFree: true)
                Divider()
                featureRow(name: "Menu Bar Controls", icon: "menubar.rectangle", isFree: true)
                Divider()
                featureRow(name: "Launch at Login", icon: "power", isFree: true)
                Divider()
                featureRow(name: "Intelligent Per-Window Dimming", icon: "wand.and.stars", isFree: false)
                Divider()
                featureRow(name: "Per-Region Zone Dimming", icon: "rectangle.split.3x3", isFree: false)
                Divider()
                featureRow(name: "Active/Inactive Window Differentiation", icon: "rectangle.2.swap", isFree: false)
                Divider()
                featureRow(name: "Super Spaces", icon: "square.grid.3x3", isFree: false)
                Divider()
                featureRow(name: "App Exclusions", icon: "xmark.app", isFree: false)
                Divider()
                featureRow(name: "Color Temperature", icon: "thermometer.sun", isFree: false)
                Divider()
                featureRow(name: "Auto-Hide Inactive Apps", icon: "eye.slash", isFree: false)
            }
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }

    /**
     Single row in the feature comparison table.

     - Parameters:
       - name: Feature display name
       - icon: SF Symbol name for the feature icon
       - isFree: Whether this feature is available on the free tier
     */
    private func featureRow(name: String, icon: String, isFree: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(isFree ? .blue : (featureGate.hasProAccess ? .green : .secondary))

            Text(name)
                .font(.subheadline)

            Spacer()

            // Status indicator: checkmark if available, lock if not
            if isFree || featureGate.hasProAccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // ================================================================
    // MARK: - Helpers
    // ================================================================

    /**
     Masks a license key for display privacy.
     Shows first 4 and last 4 characters with dots in between.
     Example: "ABCD-1234-EFGH-5678" → "ABCD...5678"

     WHY MASK: License keys displayed in settings could be visible in
     screenshots or screen shares. Masking prevents accidental exposure
     while still letting the user verify they have the right key.
     */
    private func maskedLicenseKey(_ key: String) -> String {
        if key.count <= 8 {
            return key
        }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// ====================================================================
// MARK: - Preview
// ====================================================================

#if DEBUG
struct LicensePreferencesTab_Previews: PreviewProvider {
    static var previews: some View {
        LicensePreferencesTab()
            .frame(width: 500, height: 600)
    }
}
#endif
