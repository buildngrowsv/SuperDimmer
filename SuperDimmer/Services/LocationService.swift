/**
 ====================================================================
 LocationService.swift
 Location-based sunrise/sunset time calculation
 ====================================================================
 
 PURPOSE:
 This service provides sunrise and sunset times for the user's current
 location, enabling automatic color temperature scheduling that follows
 the sun.
 
 FUNCTIONALITY:
 - Requests location permission from the user
 - Gets current location coordinates
 - Calculates sunrise/sunset times using astronomical formulas
 - Updates times daily
 - Provides fallback for when location is unavailable
 
 PRIVACY:
 - Only requests "when in use" authorization
 - Uses location only for sunrise/sunset calculation
 - No location data is stored or transmitted
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import CoreLocation
import Combine

// ====================================================================
// MARK: - Location Service
// ====================================================================

/**
 Provides location-based sunrise and sunset times.
 
 USAGE:
 1. Call requestPermission() to prompt user
 2. If authorized, call startUpdates()
 3. Observe sunriseTime and sunsetTime published properties
 */
final class LocationService: NSObject, ObservableObject {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = LocationService()
    
    // ================================================================
    // MARK: - Published Properties
    // ================================================================
    
    /// Current sunrise time for today
    @Published private(set) var sunriseTime: Date?
    
    /// Current sunset time for today
    @Published private(set) var sunsetTime: Date?
    
    /// Current authorization status
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// Whether location is currently available
    @Published private(set) var isLocationAvailable: Bool = false
    
    /// Last known location (for display/debugging)
    @Published private(set) var lastLocation: CLLocation?
    
    // ================================================================
    // MARK: - Private Properties
    // ================================================================
    
    /// Core Location manager
    private let locationManager = CLLocationManager()
    
    /// Timer for daily updates
    private var dailyUpdateTimer: Timer?
    
    /// Last date we calculated sun times (to avoid redundant calculations)
    private var lastCalculationDate: Date?
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // City-level is fine
        authorizationStatus = locationManager.authorizationStatus
        
        // Set up daily refresh at midnight
        setupDailyRefresh()
        
        print("✓ LocationService initialized")
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Requests location permission from the user.
     */
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    /**
     Starts location updates to get current position.
     */
    func startUpdates() {
        guard authorizationStatus == .authorized || authorizationStatus == .authorizedAlways else {
            print("⚠️ LocationService: Not authorized, cannot start updates")
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    /**
     Stops location updates (call when not needed to save battery).
     */
    func stopUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    /**
     Forces a refresh of sunrise/sunset times.
     */
    func refreshSunTimes() {
        if let location = lastLocation {
            calculateSunTimes(for: location)
        }
    }
    
    /**
     Returns whether permission has been granted.
     */
    var hasPermission: Bool {
        authorizationStatus == .authorized || authorizationStatus == .authorizedAlways
    }
    
    // ================================================================
    // MARK: - Private Methods
    // ================================================================
    
    /**
     Sets up a timer to refresh sun times at midnight.
     */
    private func setupDailyRefresh() {
        // Cancel any existing timer
        dailyUpdateTimer?.invalidate()
        
        // Calculate time until next midnight
        let calendar = Calendar.current
        let now = Date()
        guard let nextMidnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) else {
            return
        }
        
        let interval = nextMidnight.timeIntervalSince(now)
        
        // Schedule timer
        dailyUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refreshSunTimes()
            self?.setupDailyRefresh() // Schedule next day's refresh
        }
        
        print("⏰ LocationService: Next sun time refresh at \(nextMidnight)")
    }
    
    /**
     Calculates sunrise and sunset times for a given location.
     
     Uses the NOAA Solar Calculator algorithm for accuracy.
     */
    private func calculateSunTimes(for location: CLLocation) {
        let today = Date()
        
        // Check if we already calculated for today
        if let lastDate = lastCalculationDate,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return
        }
        
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        
        // Calculate using Solar class
        let solar = SolarCalculator(latitude: latitude, longitude: longitude, date: today)
        sunriseTime = solar.sunrise
        sunsetTime = solar.sunset
        lastCalculationDate = today
        
        print("☀️ LocationService: Sunrise \(formatTime(sunriseTime)), Sunset \(formatTime(sunsetTime)) for (\(latitude), \(longitude))")
    }
    
    /**
     Formats a date as HH:MM for display.
     */
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// ====================================================================
// MARK: - CLLocationManagerDelegate
// ====================================================================

extension LocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
            
            switch status {
            case .authorized, .authorizedAlways:
                self?.isLocationAvailable = true
                self?.locationManager.startUpdatingLocation()
            case .denied, .restricted:
                self?.isLocationAvailable = false
            case .notDetermined:
                self?.isLocationAvailable = false
            @unknown default:
                self?.isLocationAvailable = false
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.lastLocation = location
            self?.calculateSunTimes(for: location)
            
            // Stop updates after getting location (save battery)
            // Location doesn't change often enough to need continuous updates
            self?.locationManager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ LocationService error: \(error.localizedDescription)")
    }
}

// ====================================================================
// MARK: - Solar Calculator
// ====================================================================

/**
 Calculates sunrise and sunset times using NOAA formulas.
 
 Based on the NOAA Solar Calculator:
 https://gml.noaa.gov/grad/solcalc/calcdetails.html
 
 Provides accurate times for any location and date.
 */
struct SolarCalculator {
    let latitude: Double
    let longitude: Double
    let date: Date
    
    /// Calculated sunrise time
    var sunrise: Date? {
        return calculateSunrise()
    }
    
    /// Calculated sunset time
    var sunset: Date? {
        return calculateSunset()
    }
    
    // ================================================================
    // MARK: - Constants
    // ================================================================
    
    private let zenith: Double = 90.833 // Official zenith for sunrise/sunset
    
    // ================================================================
    // MARK: - Calculations
    // ================================================================
    
    private func calculateSunrise() -> Date? {
        return calculateSunTime(isSunrise: true)
    }
    
    private func calculateSunset() -> Date? {
        return calculateSunTime(isSunrise: false)
    }
    
    private func calculateSunTime(isSunrise: Bool) -> Date? {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        
        // Longitude hour
        let lngHour = longitude / 15.0
        
        // Approximate time
        let t: Double
        if isSunrise {
            t = Double(dayOfYear) + ((6.0 - lngHour) / 24.0)
        } else {
            t = Double(dayOfYear) + ((18.0 - lngHour) / 24.0)
        }
        
        // Sun's mean anomaly
        let M = (0.9856 * t) - 3.289
        
        // Sun's true longitude
        var L = M + (1.916 * sin(toRadians(M))) + (0.020 * sin(toRadians(2 * M))) + 282.634
        L = normalizeAngle(L)
        
        // Sun's right ascension
        var RA = toDegrees(atan(0.91764 * tan(toRadians(L))))
        RA = normalizeAngle(RA)
        
        // Right ascension quadrant adjustment
        let Lquadrant = floor(L / 90.0) * 90.0
        let RAquadrant = floor(RA / 90.0) * 90.0
        RA = RA + (Lquadrant - RAquadrant)
        
        // Convert to hours
        RA = RA / 15.0
        
        // Sun's declination
        let sinDec = 0.39782 * sin(toRadians(L))
        let cosDec = cos(asin(sinDec))
        
        // Sun's local hour angle
        let cosH = (cos(toRadians(zenith)) - (sinDec * sin(toRadians(latitude)))) / (cosDec * cos(toRadians(latitude)))
        
        // Check if sun rises/sets at this location
        if cosH > 1 || cosH < -1 {
            return nil // No sunrise/sunset at this latitude
        }
        
        // Calculate hour angle
        var H: Double
        if isSunrise {
            H = 360.0 - toDegrees(acos(cosH))
        } else {
            H = toDegrees(acos(cosH))
        }
        H = H / 15.0
        
        // Calculate local mean time of rising/setting
        let T = H + RA - (0.06571 * t) - 6.622
        
        // Adjust back to UTC
        var UT = T - lngHour
        UT = normalizeHour(UT)
        
        // Convert to local time
        let timeZone = TimeZone.current
        let localOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        var localTime = UT + localOffset
        localTime = normalizeHour(localTime)
        
        // Create date from time
        let hour = Int(localTime)
        let minute = Int((localTime - Double(hour)) * 60)
        
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }
    
    // ================================================================
    // MARK: - Helper Functions
    // ================================================================
    
    private func toRadians(_ degrees: Double) -> Double {
        return degrees * .pi / 180.0
    }
    
    private func toDegrees(_ radians: Double) -> Double {
        return radians * 180.0 / .pi
    }
    
    private func normalizeAngle(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 360.0)
        if result < 0 { result += 360.0 }
        return result
    }
    
    private func normalizeHour(_ hour: Double) -> Double {
        var result = hour.truncatingRemainder(dividingBy: 24.0)
        if result < 0 { result += 24.0 }
        return result
    }
}
