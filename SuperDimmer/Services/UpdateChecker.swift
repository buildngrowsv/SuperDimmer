//
//  UpdateChecker.swift
//  SuperDimmer
//
//  PURPOSE:
//  Simple update checker that fetches version.json from our Cloudflare-hosted website
//  and alerts the user if a newer version is available. This provides a lightweight
//  alternative to Sparkle framework for initial releases.
//  
//  WHY THIS APPROACH:
//  - No third-party frameworks needed (no Sparkle)
//  - Simple to implement and maintain (100 lines vs 500+ for Sparkle)
//  - User manually downloads DMG (acceptable for early releases, common pattern)
//  - Can migrate to Sparkle later for auto-install if needed
//  - Follows same pattern as many indie Mac apps during beta/early access
//
//  HOW IT WORKS:
//  1. On app launch (and periodically), fetch version.json from website via HTTPS
//  2. Compare remote version with current CFBundleShortVersionString
//  3. If newer version available, show NSAlert with "Download" button
//  4. User clicks Download → Opens default browser → Manually downloads and installs DMG
//
//  SECURITY MODEL:
//  - Relies on HTTPS from Cloudflare (prevents man-in-the-middle attacks)
//  - Website content is from trusted GitHub repo deployed via Cloudflare Pages
//  - DMG is signed with Developer ID and notarized by Apple (Gatekeeper validates)
//  - No additional signature verification beyond what macOS provides
//  - This is sufficient for most indie Mac apps not distributed via Mac App Store
//
//  REFERENCE IMPLEMENTATIONS:
//  Many successful Mac apps use this simple approach initially:
//  - Rectangle (early versions) - simple update check before Sparkle
//  - Homebrew GUI clients - JSON-based update checks
//  - Various indie utilities during beta periods
//
//  FUTURE MIGRATION TO SPARKLE:
//  If you later want automatic updates with one-click install:
//  1. Add Sparkle framework via Swift Package Manager
//  2. Generate EdDSA keys for signing updates
//  3. Replace UpdateChecker with UpdateManager (Sparkle wrapper)
//  4. Update Info.plist with SUFeedURL and SUPublicEDKey
//  5. Sign all future DMGs with sign_update tool
//  See: /docs/deployment/UPDATE_DEPLOYMENT_STRATEGY.md
//

import Foundation
import AppKit

/// Manages checking for app updates via simple JSON feed hosted on Cloudflare Pages
/// No Sparkle framework needed - just URLSession and JSON parsing
/// This is a singleton because we only want one update checker per app lifecycle
final class UpdateChecker {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide update checking
    /// Usage: UpdateChecker.shared.checkForUpdatesAutomatically()
    static let shared = UpdateChecker()
    
    // MARK: - Configuration
    
    /// Base URL for update feeds
    private let baseURL = "https://superdimmer.app"
    
    /// Stable release version feed (default for most users)
    private var stableVersionURL: URL { URL(string: "\(baseURL)/version.json")! }
    
    /// Beta release version feed (for users who opt into beta)
    private var betaVersionURL: URL { URL(string: "\(baseURL)/version-beta.json")! }
    
    /// Changelog/update log URL that opens in browser
    private let changelogURL = URL(string: "https://superdimmer.app/changelog.html")!
    
    /// How often to automatically check for updates (24 hours)
    /// This prevents excessive requests to our server and respects user bandwidth
    /// Manual checks (from menu) always run regardless of this interval
    private let checkInterval: TimeInterval = 86400  // 24 hours = 86400 seconds
    
    /// UserDefaults key for storing last check date
    /// We track this to implement the check interval
    private let lastCheckKey = "lastUpdateCheckDate"
    
    /// UserDefaults key for beta channel opt-in
    /// When true, checks version-beta.json instead of version.json
    private let betaChannelKey = "updateChannelBeta"
    
    // MARK: - Beta Channel
    
    /// Whether user has opted into beta updates
    /// When true, UpdateChecker fetches version-beta.json which may have newer/unstable releases
    /// When false (default), UpdateChecker fetches version.json with stable releases only
    var isBetaChannelEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: betaChannelKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: betaChannelKey)
            print("   🔄 Update channel changed to: \(newValue ? "BETA" : "STABLE")")
        }
    }
    
    /// The current version feed URL based on beta channel setting
    private var currentVersionURL: URL {
        isBetaChannelEnabled ? betaVersionURL : stableVersionURL
    }
    
    // MARK: - Types
    
    /// Structure matching version.json format on our website
    /// This must exactly match the JSON structure we deploy to Cloudflare
    /// Example JSON from https://superdimmer.app/version.json:
    /// ```json
    /// {
    ///   "version": "1.0.1",
    ///   "build": 7,
    ///   "downloadURL": "https://superdimmer.app/releases/SuperDimmer-v1.0.1.dmg",
    ///   "releaseNotesURL": "https://superdimmer.app/release-notes/v1.0.1.html",
    ///   "minSystemVersion": "13.0",
    ///   "releaseDate": "2026-01-19"
    /// }
    /// ```
    struct VersionInfo: Codable {
        /// User-facing version string (e.g., "1.0.1")
        /// Must match CFBundleShortVersionString in Info.plist
        let version: String
        
        /// Internal build number (e.g., 7)
        /// Must match CFBundleVersion in Info.plist
        /// We primarily use version string for comparison, but build is useful for debugging
        let build: Int
        
        /// Direct HTTPS link to the DMG file
        /// This is what opens in the browser when user clicks "Download"
        let downloadURL: String
        
        /// Link to HTML page with release notes
        /// Optional - user can read before downloading
        let releaseNotesURL: String
        
        /// Minimum macOS version required (e.g., "13.0" for Ventura)
        /// Optional - could be used to prevent updates on unsupported systems
        let minSystemVersion: String?
        
        /// Release date in ISO format (e.g., "2026-01-19")
        /// Optional - for display purposes only
        let releaseDate: String?
    }
    
    // MARK: - Initialization
    
    /// Private initializer to enforce singleton pattern
    /// We only want one update checker per app to avoid duplicate alerts
    private init() {
        // No initialization needed - all properties are lazy or constants
    }
    
    // MARK: - Public Methods
    
    /// Check for updates automatically on app launch
    /// This respects the checkInterval and won't check if checked recently
    /// Called from SuperDimmerApp.init() or AppDelegate.applicationDidFinishLaunching
    /// Shows alert only if update is available (silent if up to date)
    func checkForUpdatesAutomatically() {
        guard shouldCheckNow() else {
            print("⏱️ UpdateChecker: Skipping automatic check - checked recently (within 24 hours)")
            return
        }
        
        print("🔍 UpdateChecker: Running automatic update check...")
        checkForUpdates(showUpToDateAlert: false)
    }
    
    /// Manually check for updates (triggered by menu item)
    /// Always checks immediately, regardless of when last checked
    /// Shows result even if up to date (so user gets feedback)
    /// Called from "Check for Updates..." menu item
    func checkForUpdatesManually() {
        let channel = isBetaChannelEnabled ? "BETA" : "STABLE"
        print("🔍 UpdateChecker: Running manual update check (user-initiated, channel: \(channel))...")
        checkForUpdates(showUpToDateAlert: true)
    }
    
    /// Opens the changelog page in the default browser
    /// Shows full update history for both stable and beta releases
    /// Called from "View Update Log" menu item or button
    func openChangelog() {
        print("📜 UpdateChecker: Opening changelog in browser...")
        NSWorkspace.shared.open(changelogURL)
    }
    
    // MARK: - Private Methods
    
    /// Determine if we should check now based on last check time
    /// Returns true if we've never checked OR if checkInterval has elapsed
    /// This implements the 24-hour throttling for automatic checks
    private func shouldCheckNow() -> Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date else {
            print("   First time checking for updates")
            return true  // Never checked before
        }
        
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
        let hoursElapsed = timeSinceLastCheck / 3600
        
        if timeSinceLastCheck >= checkInterval {
            print("   Last checked \(String(format: "%.1f", hoursElapsed)) hours ago - time to check again")
            return true
        } else {
            let hoursRemaining = (checkInterval - timeSinceLastCheck) / 3600
            print("   Last checked \(String(format: "%.1f", hoursElapsed)) hours ago - will check again in \(String(format: "%.1f", hoursRemaining)) hours")
            return false
        }
    }
    
    /// Perform the actual update check by fetching version.json from server
    /// This runs asynchronously via URLSession
    /// - Parameter showUpToDateAlert: If true, show alert even when app is up to date
    ///                                 (used for manual checks so user gets feedback)
    private func checkForUpdates(showUpToDateAlert: Bool) {
        let feedURL = currentVersionURL
        let channel = isBetaChannelEnabled ? "beta" : "stable"
        print("   Fetching \(feedURL.lastPathComponent) from \(feedURL.absoluteString) [channel: \(channel)]")
        
        // Create URL request with cache-busting to always get fresh data
        // Without this, URLSession might return cached version.json
        var request = URLRequest(url: feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10  // Fail fast if server unreachable
        
        // Fetch version.json asynchronously
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            
            // Handle network errors
            if let error = error {
                print("   ❌ Network error: \(error.localizedDescription)")
                if showUpToDateAlert {
                    // For manual checks, show error to user
                    DispatchQueue.main.async {
                        self?.showErrorAlert(error: error)
                    }
                }
                return
            }
            
            // Validate HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                print("   HTTP \(httpResponse.statusCode)")
                guard httpResponse.statusCode == 200 else {
                    print("   ❌ Server returned error status")
                    return
                }
            }
            
            // Parse JSON
            guard let data = data else {
                print("   ❌ No data received")
                return
            }
            
            guard let remoteVersion = try? JSONDecoder().decode(VersionInfo.self, from: data) else {
                print("   ❌ Failed to parse version.json - may be malformed")
                return
            }
            
            // Update last check date in UserDefaults
            // This enables the 24-hour throttling for automatic checks
            UserDefaults.standard.set(Date(), forKey: self?.lastCheckKey ?? "")
            
            // Get current version from Info.plist
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            
            print("   📱 Current version: \(currentVersion) (build \(currentBuild))")
            print("   🌐 Remote version:  \(remoteVersion.version) (build \(remoteVersion.build))")
            
            // Compare versions using numeric comparison
            // This properly handles version strings like "1.10.0" > "1.9.0"
            if self?.isNewer(remoteVersion.version, than: currentVersion) == true {
                print("   ✨ Update available: \(remoteVersion.version)")
                DispatchQueue.main.async {
                    self?.showUpdateAlert(version: remoteVersion, currentVersion: currentVersion)
                }
            } else {
                print("   ✅ App is up to date")
                if showUpToDateAlert {
                    DispatchQueue.main.async {
                        self?.showUpToDateAlert(currentVersion: currentVersion)
                    }
                }
            }
        }.resume()
    }
    
    /// Compare two version strings (e.g., "1.0.1" vs "1.0.0")
    /// Uses numeric comparison which properly handles multi-part versions
    /// Returns true if remote version is newer than current version
    ///
    /// Examples:
    /// - isNewer("1.0.1", than: "1.0.0") → true
    /// - isNewer("1.10.0", than: "1.9.0") → true  (numeric comparison handles this correctly)
    /// - isNewer("2.0.0", than: "1.9.9") → true
    /// - isNewer("1.0.0", than: "1.0.0") → false
    private func isNewer(_ remote: String, than current: String) -> Bool {
        return remote.compare(current, options: .numeric) == .orderedDescending
    }
    
    /// Show alert when update is available
    /// Gives user three options: Download, Release Notes, Later
    /// This runs on main thread (must be called via DispatchQueue.main)
    private func showUpdateAlert(version: VersionInfo, currentVersion: String) {
        let alert = NSAlert()
        let channel = isBetaChannelEnabled ? " (Beta Channel)" : ""
        alert.messageText = "Update Available\(channel)"
        alert.informativeText = """
        SuperDimmer \(version.version) is now available\(channel.isEmpty ? "" : " in the beta channel").
        You're currently using version \(currentVersion).
        
        Would you like to download the update?
        """
        alert.alertStyle = .informational
        
        // Primary action: Download
        alert.addButton(withTitle: "Download")
        
        // Secondary action: View release notes
        alert.addButton(withTitle: "Release Notes")
        
        // Tertiary action: Dismiss
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // User clicked "Download"
            // Opens DMG in default browser, user installs manually
            print("   User chose to download update")
            if let url = URL(string: version.downloadURL) {
                NSWorkspace.shared.open(url)
            } else {
                print("   ❌ Invalid download URL: \(version.downloadURL)")
            }
            
        } else if response == .alertSecondButtonReturn {
            // User clicked "Release Notes"
            // Opens release notes page in browser
            print("   User chose to view release notes")
            if let url = URL(string: version.releaseNotesURL) {
                NSWorkspace.shared.open(url)
            } else {
                print("   ❌ Invalid release notes URL: \(version.releaseNotesURL)")
            }
            
        } else {
            // User clicked "Later" or closed dialog
            print("   User dismissed update alert")
        }
    }
    
    /// Show alert when app is up to date
    /// This is only shown for manual checks (from menu)
    /// Automatic checks are silent when up to date
    private func showUpToDateAlert(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "SuperDimmer \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Show alert when update check fails
    /// Only shown for manual checks (automatic checks fail silently)
    private func showErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates. Please try again later.\n\nError: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
