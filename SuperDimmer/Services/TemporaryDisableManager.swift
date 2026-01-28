/**
 ====================================================================
 TemporaryDisableManager.swift
 Manages temporary disable/pause functionality for SuperDimmer
 ====================================================================
 
 PURPOSE:
 This class handles the "Disable for X time" feature, allowing users to
 temporarily pause dimming for a specified duration. Common use cases:
 - Taking screenshots (10 seconds)
 - Quick tasks requiring accurate colors (5 minutes)
 - Meetings/presentations (30 minutes to 1 hour)
 
 WHY THIS FEATURE:
 Users need to temporarily disable dimming without:
 1. Forgetting to turn it back on
 2. Manually toggling (risk of forgetting)
 3. Adjusting settings each time
 
 DESIGN DECISIONS:
 - Pre-defined time intervals (not manual input) for simplicity
 - 4 options: 10s (screenshot), 5min, 30min, 1hr
 - Countdown timer with remaining time display
 - Auto-reactivate when timer expires
 - Option to reactivate early via "Enable Now" button
 - Menu bar icon changes to indicate paused state
 
 REFERENCE:
 - f.lux: "Disable for 1 hour", "Disable until sunrise"
 - Night Shift: "Turn Off Until Tomorrow"
 - Most apps use predefined intervals, not manual input
 
 ====================================================================
 Created: January 9, 2026
 Version: 1.2.0
 
 CHANGELOG:
 - v1.2.0 (Jan 27, 2026): Fixed cancelDisable() integration - now properly
   cancels pause timer when user manually toggles dimming ON. Fixed timer
   drift by calculating remaining time from disableEndTime instead of
   decrementing.
 ====================================================================
 */

import Foundation
import Combine

// ====================================================================
// MARK: - Disable Duration Presets
// ====================================================================

/**
 Predefined time intervals for temporary disable.
 
 WHY THESE SPECIFIC VALUES:
 - 10 seconds: Perfect for screenshots - long enough to capture, short enough to auto-restore
 - 5 minutes: Quick reference check, color-sensitive task
 - 30 minutes: Short meeting, presentation segment
 - 1 hour: Full presentation, extended work session
 
 Users requested click-based selection (not dial or typed value), so we provide
 clear, practical intervals that cover common use cases.
 */
enum DisableDuration: Int, CaseIterable, Identifiable {
    case tenSeconds = 10
    case fiveMinutes = 300
    case thirtyMinutes = 1800
    case oneHour = 3600
    
    var id: Int { rawValue }
    
    /// User-facing display name for the button
    var displayName: String {
        switch self {
        case .tenSeconds: return "10 sec"
        case .fiveMinutes: return "5 min"
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        }
    }
    
    /// Longer description for tooltips/accessibility
    var description: String {
        switch self {
        case .tenSeconds: return "Disable for 10 seconds (screenshot)"
        case .fiveMinutes: return "Disable for 5 minutes"
        case .thirtyMinutes: return "Disable for 30 minutes"
        case .oneHour: return "Disable for 1 hour"
        }
    }
    
    /// Icon to display alongside the option
    /// Using SF Symbols for consistency with macOS design
    var icon: String {
        switch self {
        case .tenSeconds: return "camera" // Screenshot use case
        case .fiveMinutes: return "clock"
        case .thirtyMinutes: return "clock.fill"
        case .oneHour: return "clock.badge"
        }
    }
    
    /// Duration in TimeInterval (seconds) for timer use
    var timeInterval: TimeInterval {
        return TimeInterval(rawValue)
    }
}

// ====================================================================
// MARK: - Temporary Disable Manager
// ====================================================================

/**
 Manages the temporary disable state and countdown timer.
 
 This is an ObservableObject so SwiftUI views can react to state changes.
 Uses Combine for timer updates to be compatible with Swift Concurrency.
 
 THREAD SAFETY:
 All operations must be on main thread since we're updating UI state.
 Timer fires on main RunLoop.
 
 LIFECYCLE:
 - Created as singleton, lives for app lifetime
 - State persisted via SettingsManager for app restarts
 - Timer automatically starts if app launches while disable was active
 */
final class TemporaryDisableManager: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    /**
     Shared singleton instance.
     
     WHY SINGLETON:
     - Disable state is app-global
     - Multiple UI components need to observe the same state
     - Ensures single timer instance
     */
    static let shared = TemporaryDisableManager()
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /**
     Whether temporary disable is currently active.
     
     When true:
     - Dimming is paused (overlays hidden)
     - Countdown timer is running
     - Menu bar icon shows "paused" state
     - UI shows remaining time
     */
    @Published private(set) var isTemporarilyDisabled: Bool = false
    
    /**
     Remaining time in seconds until auto-reactivation.
     
     Updated every second by the countdown timer.
     When reaches 0, disable ends automatically.
     */
    @Published private(set) var remainingSeconds: Int = 0
    
    /**
     The original duration that was selected (for UI display).
     
     Stored so we can show "Disabled for 5 min • 3:45 remaining" format.
     */
    @Published private(set) var selectedDuration: DisableDuration?
    
    // ================================================================
    // MARK: - Private Properties
    // ================================================================
    
    /**
     Timer for countdown updates.
     
     Uses Combine Timer publisher instead of old Timer class for:
     - Better integration with SwiftUI
     - Automatic cleanup on cancellation
     - Main thread delivery
     */
    private var timerCancellable: AnyCancellable?
    
    /**
     The timestamp when disable will end.
     
     Stored for persistence - if app restarts during disable period,
     we can calculate remaining time from this.
     */
    private var disableEndTime: Date?
    
    /**
     Reference to settings manager for persisting state.
     */
    private let settings = SettingsManager.shared
    
    /**
     Stores the dimming enabled state before disable was triggered.
     
     WHY NEEDED:
     When user clicks "Disable for X time", we need to remember if dimming
     was actually enabled. If dimming was already OFF, we shouldn't
     auto-enable it when the disable timer expires.
     */
    private var wasDimmingEnabledBeforeDisable: Bool = false
    
    /**
     Combine subscriptions for observing settings changes.
     
     FIX (Jan 27, 2026): Added to detect when user manually toggles dimming
     during a temporary disable, so we can cancel the timer and give them
     full control rather than fighting with the timer.
     */
    private var cancellables = Set<AnyCancellable>()
    
    /**
     Flag to prevent recursive handling when we ourselves toggle isDimmingEnabled.
     
     Without this flag, when disableFor() sets isDimmingEnabled = false, our
     observer would detect it as a "manual toggle" and incorrectly cancel the disable.
     */
    private var isInternallyTogglingDimming: Bool = false
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    /**
     Private init for singleton pattern.
     
     Checks if there was an active disable when app last quit
     and restores it if still valid.
     
     FIX (Jan 27, 2026): Now sets up observer for manual dimming toggles
     so we can cancel the pause timer if user takes manual control.
     */
    private init() {
        restoreStateIfNeeded()
        setupDimmingEnabledObserver()
        print("✓ TemporaryDisableManager initialized")
    }
    
    deinit {
        timerCancellable?.cancel()
        cancellables.removeAll()
        print("📍 TemporaryDisableManager deallocated")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Temporarily disables dimming for the specified duration.
     
     - Parameter duration: The predefined time interval to disable for
     
     WHAT HAPPENS:
     1. Stores current dimming state (so we can restore correctly)
     2. Disables dimming (hides overlays, stops analysis)
     3. Starts countdown timer
     4. Updates UI to show remaining time
     5. Posts notification for menu bar icon update
     
     If already disabled, this REPLACES the current disable with new duration.
     */
    func disableFor(_ duration: DisableDuration) {
        print("📍 Disabling dimming for \(duration.displayName)")
        
        // Store current dimming state before disabling
        // This way, if dimming was OFF when user clicked disable,
        // we won't auto-enable it when timer expires
        wasDimmingEnabledBeforeDisable = settings.isDimmingEnabled
        
        // Set disable state
        selectedDuration = duration
        remainingSeconds = duration.rawValue
        disableEndTime = Date().addingTimeInterval(duration.timeInterval)
        isTemporarilyDisabled = true
        
        // Actually disable dimming
        // Use flag to prevent our observer from detecting this as a "manual toggle"
        if settings.isDimmingEnabled {
            isInternallyTogglingDimming = true
            settings.isDimmingEnabled = false
            isInternallyTogglingDimming = false
        }
        
        // Also disable color temperature if it was on
        // (This is what f.lux does - full disable includes color temp)
        if settings.colorTemperatureEnabled {
            settings.colorTemperatureEnabled = false
        }
        
        // Persist state for app restart scenarios
        persistState()
        
        // Start countdown timer
        startTimer()
        
        // Notify observers (menu bar icon, etc.)
        NotificationCenter.default.post(
            name: .temporaryDisableStateChanged,
            object: nil,
            userInfo: ["isDisabled": true, "remainingSeconds": remainingSeconds]
        )
    }
    
    /**
     Immediately ends the temporary disable and re-enables dimming.
     
     Called when user clicks "Enable Now" button.
     
     WHAT HAPPENS:
     1. Stops countdown timer
     2. Re-enables dimming (if it was enabled before disable)
     3. Clears all disable state
     4. Posts notification for UI updates
     */
    func enableNow() {
        print("📍 User requested early enable - ending temporary disable")
        endDisable(restoreDimming: true)
    }
    
    /**
     Cancels the temporary disable WITHOUT re-enabling dimming.
     
     Called internally when user manually toggles dimming during disable.
     This allows user to take full control rather than fighting the timer.
     */
    func cancelDisable() {
        print("📍 Cancelling temporary disable (user took manual control)")
        endDisable(restoreDimming: false)
    }
    
    /**
     Returns a formatted string of remaining time for UI display.
     
     Examples:
     - "0:10" for 10 seconds
     - "4:32" for 4 minutes 32 seconds
     - "32:15" for 32 minutes 15 seconds
     - "1:00:00" for 1 hour exactly
     
     WHY NOT USE DateComponentsFormatter:
     We want a compact format that fits in the menu bar UI.
     Standard formatters produce longer strings like "5 minutes".
     */
    var remainingTimeFormatted: String {
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
    
    /**
     Returns a user-friendly status string for the UI.
     
     Example: "Disabled • 4:32 remaining"
     */
    var statusText: String {
        guard isTemporarilyDisabled else { return "" }
        return "Paused • \(remainingTimeFormatted) remaining"
    }
    
    // ================================================================
    // MARK: - Private Methods
    // ================================================================
    
    /**
     Starts the countdown timer that fires every second.
     
     Timer fires on main thread to update @Published properties safely.
     When remainingSeconds reaches 0, timer stops and dimming is restored.
     */
    private func startTimer() {
        // Cancel any existing timer
        timerCancellable?.cancel()
        
        // Create timer that fires every second
        // Using Combine's Timer publisher for cleaner integration
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.timerTick()
            }
    }
    
    /**
     Called every second by the timer.
     
     FIX (Jan 27, 2026): Changed from decrementing to calculating from disableEndTime.
     This prevents timer drift caused by CPU contention, system sleep, or timer jitter.
     The countdown display now always accurately reflects actual remaining time.
     
     BEFORE: remainingSeconds -= 1 (could drift if timer fires late)
     AFTER: remainingSeconds = disableEndTime - now (always accurate)
     */
    private func timerTick() {
        guard isTemporarilyDisabled, let endTime = disableEndTime else { return }
        
        // Calculate remaining time from the actual end timestamp
        // This prevents drift - if system was sleeping or CPU was busy,
        // the countdown will skip ahead to show correct remaining time
        let now = Date()
        let remaining = Int(ceil(endTime.timeIntervalSince(now)))
        remainingSeconds = max(0, remaining)
        
        // Post update notification (for any external observers)
        NotificationCenter.default.post(
            name: .temporaryDisableTimeUpdated,
            object: nil,
            userInfo: ["remainingSeconds": remainingSeconds]
        )
        
        // Check if time is up
        if remainingSeconds <= 0 {
            print("📍 Temporary disable timer expired - restoring dimming")
            endDisable(restoreDimming: true)
        }
    }
    
    /**
     Ends the temporary disable state.
     
     - Parameter restoreDimming: If true, re-enables dimming to pre-disable state
     
     Called when:
     1. Timer expires naturally (restoreDimming: true)
     2. User clicks "Enable Now" (restoreDimming: true)
     3. User manually toggles dimming (restoreDimming: false - user took control)
     */
    private func endDisable(restoreDimming: Bool) {
        // Stop timer
        timerCancellable?.cancel()
        timerCancellable = nil
        
        // Clear state
        isTemporarilyDisabled = false
        remainingSeconds = 0
        selectedDuration = nil
        disableEndTime = nil
        
        // Clear persisted state
        clearPersistedState()
        
        // Restore dimming if requested AND if it was enabled before
        // Use flag to prevent our observer from detecting this as a "manual toggle"
        if restoreDimming && wasDimmingEnabledBeforeDisable {
            print("📍 Restoring dimming to enabled state")
            isInternallyTogglingDimming = true
            settings.isDimmingEnabled = true
            isInternallyTogglingDimming = false
        }
        
        // Note: We don't auto-restore color temperature here
        // because it has its own schedule and the user may not want it
        // They can toggle it manually if needed
        
        // Notify observers
        NotificationCenter.default.post(
            name: .temporaryDisableStateChanged,
            object: nil,
            userInfo: ["isDisabled": false]
        )
    }
    
    /**
     Persists disable state to UserDefaults for app restart scenarios.
     
     WHY PERSIST:
     If user selects "Disable for 1 hour" and then the app crashes or
     they restart their Mac, we should continue the disable when app
     relaunches (if time hasn't expired).
     */
    private func persistState() {
        UserDefaults.standard.set(disableEndTime, forKey: "superdimmer.temporaryDisable.endTime")
        UserDefaults.standard.set(wasDimmingEnabledBeforeDisable, forKey: "superdimmer.temporaryDisable.wasDimmingEnabled")
        if let duration = selectedDuration {
            UserDefaults.standard.set(duration.rawValue, forKey: "superdimmer.temporaryDisable.selectedDuration")
        }
    }
    
    /**
     Clears persisted disable state.
     */
    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: "superdimmer.temporaryDisable.endTime")
        UserDefaults.standard.removeObject(forKey: "superdimmer.temporaryDisable.wasDimmingEnabled")
        UserDefaults.standard.removeObject(forKey: "superdimmer.temporaryDisable.selectedDuration")
    }
    
    /**
     Restores disable state if app was relaunched during active disable.
     
     Called during init. Checks if there's a persisted disable that hasn't
     expired yet, and restores the timer if so.
     */
    private func restoreStateIfNeeded() {
        guard let endTime = UserDefaults.standard.object(forKey: "superdimmer.temporaryDisable.endTime") as? Date else {
            return // No persisted disable
        }
        
        let now = Date()
        
        // Check if disable has already expired
        if now >= endTime {
            print("📍 Persisted temporary disable has expired - clearing")
            clearPersistedState()
            
            // Restore dimming if it was enabled before
            // Use flag to prevent our observer from detecting this as a "manual toggle"
            let wasDimmingEnabled = UserDefaults.standard.bool(forKey: "superdimmer.temporaryDisable.wasDimmingEnabled")
            if wasDimmingEnabled && !settings.isDimmingEnabled {
                isInternallyTogglingDimming = true
                settings.isDimmingEnabled = true
                isInternallyTogglingDimming = false
            }
            return
        }
        
        // Restore the active disable
        let remaining = Int(endTime.timeIntervalSince(now))
        print("📍 Restoring temporary disable with \(remaining) seconds remaining")
        
        wasDimmingEnabledBeforeDisable = UserDefaults.standard.bool(forKey: "superdimmer.temporaryDisable.wasDimmingEnabled")
        
        if let durationRaw = UserDefaults.standard.object(forKey: "superdimmer.temporaryDisable.selectedDuration") as? Int {
            selectedDuration = DisableDuration(rawValue: durationRaw)
        }
        
        disableEndTime = endTime
        remainingSeconds = remaining
        isTemporarilyDisabled = true
        
        // Start timer to continue countdown
        startTimer()
        
        // Ensure dimming stays off during the restored disable
        // Use flag to prevent our observer from detecting this as a "manual toggle"
        if settings.isDimmingEnabled {
            isInternallyTogglingDimming = true
            settings.isDimmingEnabled = false
            isInternallyTogglingDimming = false
        }
    }
    
    /**
     Sets up observer to detect when user manually toggles dimming during a pause.
     
     FIX (Jan 27, 2026): Previously, the cancelDisable() method existed but was never
     called. This caused confusing behavior where:
     1. User pauses dimming for 5 minutes
     2. User manually toggles dimming ON
     3. The timer CONTINUES running in the background
     4. UI still shows "Dimming Paused" with countdown
     5. When timer expires, it redundantly sets isDimmingEnabled = true
     
     NOW: When user manually toggles dimming ON during a pause, we detect it and
     cancel the timer immediately, giving them full control. The "Paused" UI
     disappears and the timer stops.
     
     IMPORTANT: We use isInternallyTogglingDimming flag to distinguish between:
     - Manual toggle by user (should cancel pause)
     - Our own toggle in disableFor() or endDisable() (should NOT cancel)
     */
    private func setupDimmingEnabledObserver() {
        settings.$isDimmingEnabled
            .dropFirst() // Skip initial value
            .sink { [weak self] newValue in
                guard let self = self else { return }
                
                // Ignore our own internal toggles
                guard !self.isInternallyTogglingDimming else { return }
                
                // If user manually ENABLED dimming while we're in temporary disable,
                // cancel the pause and let them take full control
                if newValue == true && self.isTemporarilyDisabled {
                    print("📍 User manually enabled dimming during pause - cancelling timer")
                    self.cancelDisable()
                }
                
                // Note: We don't need to handle the case where user disables during pause,
                // because dimming is already disabled during pause. If they toggle it OFF
                // again (which would be a no-op from their perspective), we don't need
                // to do anything special.
            }
            .store(in: &cancellables)
    }
}

// ====================================================================
// MARK: - Notification Names
// ====================================================================

/**
 Notification names for temporary disable events.
 
 Used by MenuBarController and other components that need to
 react to disable state changes.
 */
extension Notification.Name {
    /// Posted when temporary disable state changes (started or ended)
    static let temporaryDisableStateChanged = Notification.Name("superdimmer.temporaryDisableStateChanged")
    
    /// Posted every second during active disable (for countdown updates)
    static let temporaryDisableTimeUpdated = Notification.Name("superdimmer.temporaryDisableTimeUpdated")
}
