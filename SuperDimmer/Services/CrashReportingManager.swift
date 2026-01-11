/**
 ====================================================================
 CrashReportingManager.swift
 Automatic crash reporting integration for SuperDimmer
 ====================================================================
 
 PURPOSE:
 This service manages crash reporting using Sentry SDK. It automatically
 captures crashes, errors, and performance metrics from user devices and
 sends them to our Sentry dashboard for analysis.
 
 WHY SENTRY:
 - SuperDimmer is distributed outside the App Store (via DMG + Sparkle)
 - TestFlight crash reports only work for TestFlight/App Store builds
 - Sentry provides:
   1. Automatic crash symbolication (no manual dSYM upload needed)
   2. Real-time crash alerts
   3. User feedback collection
   4. Performance monitoring
   5. Release tracking
 
 IMPORTANT CONTEXT:
 SuperDimmer CANNOT be distributed via the Mac App Store because:
 - The app uses `com.apple.security.device.screen-capture` entitlement
 - This entitlement is NOT allowed in sandboxed App Store apps
 - Screen capture requires running OUTSIDE the sandbox
 - This is the same reason f.lux, BetterDisplay, etc. are not on the App Store
 
 Therefore we need our own crash reporting solution (Sentry) rather than
 relying on Apple's TestFlight crash reports.
 
 SETUP REQUIRED:
 1. Add Sentry SDK via SPM: https://github.com/getsentry/sentry-cocoa
 2. Create Sentry project at https://sentry.io
 3. Get DSN from Sentry project settings
 4. Set the DSN below or via environment variable
 
 PRIVACY CONSIDERATIONS:
 - Crash reports contain stack traces, device info, and app state
 - NO screen content or personal data is captured
 - User can opt-out via preferences (respectsUserPrivacy setting)
 - Privacy policy on website must mention crash reporting
 
 ====================================================================
 Created: January 11, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation

// NOTE: Uncomment the import below after adding Sentry via SPM
// import Sentry

// ====================================================================
// MARK: - Crash Reporting Manager
// ====================================================================

/**
 Singleton service that manages crash reporting via Sentry SDK.
 
 RESPONSIBILITIES:
 1. Initialize Sentry SDK on app launch
 2. Configure crash collection settings
 3. Tag reports with app version and user context
 4. Provide manual error/message capture methods
 5. Respect user privacy preferences
 
 USAGE:
 - Initialize early in AppDelegate.applicationDidFinishLaunching()
 - Use `captureError()` for caught errors you want to track
 - Use `captureMessage()` for non-error events of interest
 
 ARCHITECTURE NOTE:
 We're using a stub implementation that compiles without Sentry.
 Once Sentry SDK is added via SPM, uncomment the real implementation
 sections marked with "// SENTRY IMPLEMENTATION" comments.
 */
final class CrashReportingManager {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /**
     Shared instance for app-wide crash reporting access.
     
     WHY SINGLETON:
     - Sentry SDK should only be initialized once
     - Crash reporting is a global concern, not per-object
     - Matches Sentry's own SPUStandardUpdaterController pattern
     */
    static let shared = CrashReportingManager()
    
    // ================================================================
    // MARK: - Configuration
    // ================================================================
    
    /**
     Sentry DSN (Data Source Name) - the URL that identifies your Sentry project.
     
     HOW TO GET YOUR DSN:
     1. Go to https://sentry.io
     2. Create account / sign in
     3. Create new project → Select "Apple (Cocoa)"
     4. Copy the DSN from the onboarding page
     5. Paste it here or set SENTRY_DSN environment variable
     
     FORMAT: https://PUBLIC_KEY@oORG_ID.ingest.sentry.io/PROJECT_ID
     
     SECURITY NOTE:
     The DSN is NOT a secret - it only allows sending events TO Sentry,
     not reading events FROM Sentry. Safe to commit to repo.
     But we use a placeholder here to remind you to set up your own project.
     */
    private let sentryDSN: String = {
        // Check for environment variable first (useful for different environments)
        if let envDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"], !envDSN.isEmpty {
            return envDSN
        }
        // TODO: Replace with your actual Sentry DSN
        return "YOUR_SENTRY_DSN_HERE"
    }()
    
    /**
     Whether crash reporting has been successfully initialized.
     
     Used to guard against calling Sentry methods before SDK is ready.
     Also useful for showing status in debug UI.
     */
    private(set) var isInitialized = false
    
    /**
     Whether crash reporting is enabled (respects user privacy preference).
     
     PRIVACY FLOW:
     1. On first launch, crashReportingEnabled defaults to true
     2. User can disable in Preferences → Privacy tab
     3. When disabled, we still initialize Sentry but set enabled=false
     4. This allows user to re-enable without app restart
     */
    var isEnabled: Bool {
        get {
            // Check user's privacy preference
            return SettingsManager.shared.crashReportingEnabled
        }
        set {
            SettingsManager.shared.crashReportingEnabled = newValue
            // Update Sentry's enabled state at runtime
            updateSentryEnabled(newValue)
        }
    }
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Private initializer enforces singleton pattern.
     
     Does NOT initialize Sentry - call initialize() explicitly.
     This allows us to control exactly when Sentry starts (after settings load).
     */
    private init() {}
    
    /**
     Initialize the Sentry SDK. Call this early in app lifecycle.
     
     WHEN TO CALL:
     - In AppDelegate.applicationDidFinishLaunching(), AFTER settings are loaded
     - This ensures we know the user's privacy preference before starting
     
     WHAT IT DOES:
     1. Validates DSN is configured
     2. Configures Sentry SDK options
     3. Starts crash monitoring
     4. Tags current app version for release tracking
     
     - Parameter enableDebugLogging: If true, prints Sentry debug info to console.
                                     Useful during development, disable for release.
     */
    func initialize(enableDebugLogging: Bool = false) {
        // ============================================================
        // Validate DSN
        // ============================================================
        guard sentryDSN != "YOUR_SENTRY_DSN_HERE" else {
            print("⚠️ CrashReporting: Sentry DSN not configured - crash reporting disabled")
            print("   To enable, set SENTRY_DSN environment variable or update CrashReportingManager.swift")
            return
        }
        
        guard !sentryDSN.isEmpty else {
            print("⚠️ CrashReporting: Sentry DSN is empty - crash reporting disabled")
            return
        }
        
        // ============================================================
        // Get app info for tagging releases
        // ============================================================
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let releaseVersion = "superdimmer@\(appVersion)+\(buildNumber)"
        
        // ============================================================
        // Initialize Sentry SDK
        // ============================================================
        // NOTE: Uncomment the block below after adding Sentry via SPM:
        //
        // File → Add Package Dependencies → https://github.com/getsentry/sentry-cocoa
        //
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        
        SentrySDK.start { options in
            // ========================================================
            // Core Configuration
            // ========================================================
            options.dsn = self.sentryDSN
            
            // Debug logging - helpful during development
            options.debug = enableDebugLogging
            
            // Release tracking - groups crashes by app version
            // Format: project@version+build
            options.releaseName = releaseVersion
            
            // Environment - helps separate dev vs prod crashes
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            
            // ========================================================
            // Crash Handling
            // ========================================================
            // Enable crash collection (this is the main purpose!)
            options.enableCrashHandler = true
            
            // Attach stack traces to all events (even non-fatal)
            options.attachStacktrace = true
            
            // ========================================================
            // Performance Monitoring (Optional)
            // ========================================================
            // Sample rate for performance monitoring (0.0 to 1.0)
            // Set to 0.0 to disable, or low value like 0.1 to sample 10%
            // This tracks things like app start time, slow operations
            options.tracesSampleRate = 0.1  // Sample 10% of transactions
            
            // ========================================================
            // Privacy Settings
            // ========================================================
            // Respect user's privacy preference
            options.enabled = self.isEnabled
            
            // Don't send PII (personally identifiable information)
            // This prevents IP addresses from being logged
            options.sendDefaultPii = false
            
            // ========================================================
            // macOS Specific Settings
            // ========================================================
            // Enable watchdog termination tracking
            // Detects when macOS kills the app for being unresponsive
            options.enableWatchdogTerminationTracking = true
            
            // Enable out of memory tracking
            // Detects when app is killed due to memory pressure
            options.enableOutOfMemoryTracking = true
        }
        
        */ // END SENTRY IMPLEMENTATION
        
        isInitialized = true
        print("✓ CrashReporting: Initialized (enabled: \(isEnabled))")
        print("   Release: \(releaseVersion)")
    }
    
    // ================================================================
    // MARK: - Runtime Control
    // ================================================================
    
    /**
     Update Sentry's enabled state at runtime.
     
     Called when user toggles crash reporting in preferences.
     Allows enabling/disabling without restarting the app.
     
     - Parameter enabled: Whether to enable crash reporting
     */
    private func updateSentryEnabled(_ enabled: Bool) {
        guard isInitialized else { return }
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        SentrySDK.setOptions { options in
            options.enabled = enabled
        }
        */
        
        print("✓ CrashReporting: \(enabled ? "Enabled" : "Disabled") by user preference")
    }
    
    // ================================================================
    // MARK: - Manual Capture Methods
    // ================================================================
    
    /**
     Capture a caught error for tracking.
     
     Use this for errors you catch in try/catch blocks that you want
     to track even though they didn't crash the app.
     
     Example:
     ```swift
     do {
         try somethingRisky()
     } catch {
         CrashReportingManager.shared.captureError(error)
         // Handle error gracefully
     }
     ```
     
     - Parameter error: The Swift Error to capture
     - Parameter context: Optional dictionary of additional context
     */
    func captureError(_ error: Error, context: [String: Any]? = nil) {
        guard isInitialized && isEnabled else { return }
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        SentrySDK.capture(error: error) { scope in
            if let context = context {
                scope.setContext(value: context, key: "additional_context")
            }
        }
        */
        
        print("📊 CrashReporting: Captured error - \(error.localizedDescription)")
    }
    
    /**
     Capture a message for tracking.
     
     Use this for non-error events you want to track, like:
     - Feature usage analytics
     - Unusual but non-fatal conditions
     - Debug breadcrumbs for crash investigation
     
     - Parameter message: Description of the event
     - Parameter level: Severity level (debug, info, warning, error, fatal)
     */
    func captureMessage(_ message: String, level: CrashSeverityLevel = .info) {
        guard isInitialized && isEnabled else { return }
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level.sentryLevel)
        }
        */
        
        print("📊 CrashReporting: Captured message - [\(level.rawValue)] \(message)")
    }
    
    /**
     Add a breadcrumb for crash investigation.
     
     Breadcrumbs are a trail of events leading up to a crash.
     They help understand what the user was doing before the crash.
     
     Example:
     ```swift
     CrashReportingManager.shared.addBreadcrumb(
         category: "ui.toggle",
         message: "User enabled dimming"
     )
     ```
     
     - Parameter category: Category of the breadcrumb (e.g., "ui", "network", "state")
     - Parameter message: Description of what happened
     - Parameter data: Optional additional data dictionary
     */
    func addBreadcrumb(category: String, message: String, data: [String: Any]? = nil) {
        guard isInitialized && isEnabled else { return }
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        let breadcrumb = Breadcrumb()
        breadcrumb.category = category
        breadcrumb.message = message
        breadcrumb.level = .info
        if let data = data {
            breadcrumb.data = data
        }
        SentrySDK.addBreadcrumb(breadcrumb)
        */
    }
    
    /**
     Set user context for crash reports.
     
     Associates crashes with a user identifier (NOT personal info).
     Use a hash or anonymous ID, not email/name.
     
     This helps identify if the same user is experiencing repeated crashes.
     
     - Parameter userId: Anonymous user identifier (e.g., UUID stored locally)
     */
    func setUserContext(userId: String) {
        guard isInitialized && isEnabled else { return }
        
        /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
        let user = User()
        user.userId = userId
        SentrySDK.setUser(user)
        */
    }
}

// ====================================================================
// MARK: - Severity Level Enum
// ====================================================================

/**
 Severity levels for captured messages.
 
 Maps to Sentry's built-in severity levels.
 Used when calling `captureMessage()` to indicate importance.
 */
enum CrashSeverityLevel: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case fatal = "fatal"
    
    /* // SENTRY IMPLEMENTATION - Uncomment after adding Sentry package
    var sentryLevel: SentryLevel {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .fatal: return .fatal
        }
    }
    */
}

// ====================================================================
// MARK: - Extension to SettingsManager for Privacy Preference
// ====================================================================

/**
 Add crash reporting privacy setting to SettingsManager.
 
 This allows users to opt-out of crash reporting in preferences.
 Default is TRUE (opted-in) because crash reports help us fix bugs.
 
 PRIVACY POLICY NOTE:
 Make sure the privacy policy on superdimmer.com mentions:
 - Crash reports are collected
 - What data is included (stack traces, device info, app state)
 - What data is NOT included (screen content, personal files)
 - How to opt-out (Preferences → Privacy)
 */
extension SettingsManager {
    
    /**
     Key for storing crash reporting preference in UserDefaults.
     */
    private static let crashReportingKey = "crashReportingEnabled"
    
    /**
     Whether crash reporting is enabled. Default: true (opted-in).
     
     RATIONALE FOR DEFAULT ON:
     - Crash reports are anonymous and contain no personal data
     - They help us identify and fix bugs quickly
     - Users who care about privacy can easily opt-out
     - Most successful apps default to ON (Sentry, Crashlytics best practices)
     */
    var crashReportingEnabled: Bool {
        get {
            // Default to true if not set (opted-in by default)
            if UserDefaults.standard.object(forKey: Self.crashReportingKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.crashReportingKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.crashReportingKey)
        }
    }
}
