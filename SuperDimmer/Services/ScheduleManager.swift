/**
 ====================================================================
 ScheduleManager.swift
 Time-based scheduling for color temperature adjustments
 ====================================================================
 
 PURPOSE:
 This manager handles automatic color temperature scheduling based on:
 - Manual time schedule (user-defined start/end times)
 - Sunrise/sunset times (via LocationService)
 
 The scheduler allows users to automatically warm their display at night
 and return to neutral colors during the day, similar to f.lux.
 
 ARCHITECTURE:
 - Uses Timer for schedule checking
 - Supports gradual transitions between day/night temperatures
 - Integrates with ColorTemperatureManager to apply changes
 - Observes SettingsManager for configuration updates
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import Combine

// ====================================================================
// MARK: - Schedule Manager
// ====================================================================

/**
 Manages time-based scheduling for color temperature.
 
 USAGE:
 - Configure schedule via SettingsManager
 - Call start() to begin schedule monitoring
 - Scheduler will automatically adjust temperature based on time
 */
final class ScheduleManager: ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = ScheduleManager()
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /// Current schedule mode
    @Published private(set) var currentMode: ScheduleMode = .day
    
    /// Whether the scheduler is actively running
    @Published private(set) var isRunning: Bool = false
    
    /// Next transition time
    @Published private(set) var nextTransitionTime: Date?
    
    /// Current transition progress (0.0-1.0) for gradual changes
    @Published private(set) var transitionProgress: CGFloat = 0.0
    
    // ================================================================
    // MARK: - Private Properties
    // ================================================================
    
    /// Timer for checking schedule
    private var scheduleTimer: Timer?
    
    /// Timer for gradual transitions
    private var transitionTimer: Timer?
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Reference to settings
    private let settings = SettingsManager.shared
    
    /// Reference to color temperature manager
    private var colorTempManager: ColorTemperatureManager?
    
    /// Location service for sunrise/sunset times (lazy loaded)
    private lazy var locationService: LocationService? = {
        // LocationService will be created in Phase 3.4
        return nil
    }()
    
    // ================================================================
    // MARK: - Schedule Configuration
    // ================================================================
    
    /// Day temperature (neutral)
    private var dayTemperature: Double { settings.dayTemperature }
    
    /// Night temperature (warm)
    private var nightTemperature: Double { settings.nightTemperature }
    
    /// Manual schedule start time (sunset equivalent)
    private var scheduleStartTime: Date { settings.scheduleStartTime }
    
    /// Manual schedule end time (sunrise equivalent)
    private var scheduleEndTime: Date { settings.scheduleEndTime }
    
    /// Duration for gradual transition (minutes)
    private var transitionDuration: TimeInterval { settings.transitionDuration }
    
    /// Whether to use location-based sunrise/sunset
    private var useLocationBasedSchedule: Bool { settings.useLocationBasedSchedule }
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        print("✓ ScheduleManager initialized")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Starts the schedule monitoring.
     
     - Parameter colorTempManager: The color temperature manager to control
     */
    func start(with colorTempManager: ColorTemperatureManager) {
        guard !isRunning else { return }
        
        self.colorTempManager = colorTempManager
        isRunning = true
        
        // Initial check
        checkSchedule()
        
        // Start timer - check every minute
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
        RunLoop.current.add(scheduleTimer!, forMode: .common)
        
        print("⏰ ScheduleManager started")
    }
    
    /**
     Stops the schedule monitoring.
     */
    func stop() {
        isRunning = false
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        transitionTimer?.invalidate()
        transitionTimer = nil
        
        print("⏰ ScheduleManager stopped")
    }
    
    /**
     Forces an immediate schedule check.
     */
    func checkNow() {
        checkSchedule()
    }
    
    // ================================================================
    // MARK: - Private Methods
    // ================================================================
    
    /**
     Sets up observers for settings changes.
     */
    private func setupObservers() {
        // Re-check schedule when relevant settings change
        settings.$colorTemperatureScheduleEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.checkSchedule()
                }
            }
            .store(in: &cancellables)
    }
    
    /**
     Checks current time against schedule and updates temperature.
     */
    private func checkSchedule() {
        guard settings.colorTemperatureScheduleEnabled else { return }
        
        let now = Date()
        let (startTime, endTime) = getScheduleTimes()
        
        // Determine current mode based on time
        let newMode = determineMode(at: now, start: startTime, end: endTime)
        
        // Calculate next transition time
        nextTransitionTime = calculateNextTransition(from: now, start: startTime, end: endTime)
        
        // Apply temperature if mode changed or during transition
        if newMode != currentMode {
            currentMode = newMode
            applyModeTransition(to: newMode)
        }
    }
    
    /**
     Gets the start and end times for the schedule.
     Uses location-based times if enabled, otherwise manual times.
     */
    private func getScheduleTimes() -> (start: Date, end: Date) {
        if useLocationBasedSchedule, let locationService = locationService {
            // Use sunrise/sunset from location service
            // This will be implemented in Phase 3.4
            let sunrise = locationService.sunriseTime ?? settings.scheduleEndTime
            let sunset = locationService.sunsetTime ?? settings.scheduleStartTime
            return (sunset, sunrise)
        } else {
            // Use manual schedule times
            return (scheduleStartTime, scheduleEndTime)
        }
    }
    
    /**
     Determines whether we should be in day or night mode.
     */
    private func determineMode(at time: Date, start: Date, end: Date) -> ScheduleMode {
        let calendar = Calendar.current
        let now = calendar.dateComponents([.hour, .minute], from: time)
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 20) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 7) * 60 + (endComponents.minute ?? 0)
        
        // Handle schedule that crosses midnight
        if startMinutes > endMinutes {
            // Night spans midnight (e.g., 8pm to 7am)
            if nowMinutes >= startMinutes || nowMinutes < endMinutes {
                return .night
            } else {
                return .day
            }
        } else {
            // Day schedule (rare, but handle it)
            if nowMinutes >= startMinutes && nowMinutes < endMinutes {
                return .night
            } else {
                return .day
            }
        }
    }
    
    /**
     Calculates when the next transition will occur.
     */
    private func calculateNextTransition(from now: Date, start: Date, end: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Create today's schedule times
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        
        var todayStart = calendar.date(bySettingHour: startComponents.hour ?? 20,
                                        minute: startComponents.minute ?? 0,
                                        second: 0, of: today)!
        var todayEnd = calendar.date(bySettingHour: endComponents.hour ?? 7,
                                      minute: endComponents.minute ?? 0,
                                      second: 0, of: today)!
        
        // If end time is before start time, end is tomorrow
        if todayEnd <= todayStart {
            todayEnd = calendar.date(byAdding: .day, value: 1, to: todayEnd)!
        }
        
        // Find next transition
        if now < todayStart {
            return todayStart
        } else if now < todayEnd {
            return todayEnd
        } else {
            // Both have passed, next is tomorrow's start
            return calendar.date(byAdding: .day, value: 1, to: todayStart)!
        }
    }
    
    /**
     Applies the temperature for a given mode.
     Uses gradual transition if configured.
     */
    private func applyModeTransition(to mode: ScheduleMode) {
        guard let colorTempManager = colorTempManager else { return }
        
        let targetTemp = mode == .night ? nightTemperature : dayTemperature
        
        if transitionDuration > 0 {
            // Gradual transition
            startGradualTransition(to: targetTemp, duration: transitionDuration)
        } else {
            // Instant change
            settings.colorTemperature = targetTemp
            colorTempManager.applyTemperature(targetTemp)
        }
        
        print("⏰ Schedule: Transitioning to \(mode) mode (\(Int(targetTemp))K)")
    }
    
    /**
     Starts a gradual transition to the target temperature.
     */
    private func startGradualTransition(to targetTemp: Double, duration: TimeInterval) {
        transitionTimer?.invalidate()
        
        let startTemp = settings.colorTemperature
        let tempDelta = targetTemp - startTemp
        let steps = 60 // Update every second for 1 minute, or proportionally
        let stepDuration = duration / Double(steps)
        var currentStep = 0
        
        transitionProgress = 0.0
        
        transitionTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentStep += 1
            let progress = Double(currentStep) / Double(steps)
            self.transitionProgress = CGFloat(progress)
            
            let newTemp = startTemp + (tempDelta * progress)
            self.settings.colorTemperature = newTemp
            self.colorTempManager?.applyTemperature(newTemp)
            
            if currentStep >= steps {
                timer.invalidate()
                self.transitionProgress = 1.0
            }
        }
        RunLoop.current.add(transitionTimer!, forMode: .common)
    }
}

// ====================================================================
// MARK: - Schedule Mode
// ====================================================================

/**
 Represents the current schedule mode.
 */
enum ScheduleMode: String {
    case day = "day"
    case night = "night"
    
    var displayName: String {
        switch self {
        case .day: return "Day"
        case .night: return "Night"
        }
    }
    
    var icon: String {
        switch self {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        }
    }
}

// ====================================================================
// MARK: - Location Service Placeholder
// ====================================================================

/**
 Placeholder for LocationService (to be implemented in Phase 3.4).
 
 This stub allows ScheduleManager to compile without the full
 location service implementation.
 */
class LocationService {
    var sunriseTime: Date?
    var sunsetTime: Date?
}
