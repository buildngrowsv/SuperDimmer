/**
 ====================================================================
 ColorTemperatureManager.swift
 Manages display color temperature (blue light filter)
 ====================================================================
 
 PURPOSE:
 This class provides f.lux-like color temperature adjustment by
 modifying the display's gamma curves. Lower color temperatures
 (warmer) reduce blue light which can help reduce eye strain at night.
 
 HOW IT WORKS:
 We use CGSetDisplayTransferByFormula to adjust the gamma curves.
 The formula takes RGB coefficients that we calculate based on the
 target color temperature in Kelvin.
 
 COLOR TEMPERATURE BASICS:
 - 6500K = "Daylight" - neutral white, normal display
 - 5000K = Slightly warm
 - 4000K = "Sunset" - noticeably warmer
 - 2700K = "Incandescent" - very warm, orange tint
 - 1900K = "Candle" - extremely warm, deep orange
 
 ALGORITHM:
 We convert Kelvin temperature to RGB multipliers using the algorithm
 by Tanner Helland (based on CIE color matching functions).
 See: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import CoreGraphics
import Combine

// ====================================================================
// MARK: - Color Temperature Manager
// ====================================================================

/**
 Singleton that manages display color temperature adjustments.
 
 USAGE:
 1. Enable via SettingsManager.colorTemperatureEnabled = true
 2. Adjust via SettingsManager.colorTemperature = 3000 (kelvin)
 3. Manager automatically applies changes to all displays
 
 LIFECYCLE:
 - Initialize via ColorTemperatureManager.shared
 - Automatically observes settings changes
 - Call restore() to reset to default on app quit
 */
final class ColorTemperatureManager {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = ColorTemperatureManager()
    
    // ================================================================
    // MARK: - Properties
    // ================================================================
    
    /// Whether color temperature adjustment is currently active
    private(set) var isActive: Bool = false
    
    /// Current applied temperature (0 if inactive)
    private(set) var currentTemperature: Double = 6500
    
    /// Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Saved original gamma tables for restoration
    /// Key: displayID, Value: (redTable, greenTable, blueTable)
    private var savedGamma: [CGDirectDisplayID: ([CGGammaValue], [CGGammaValue], [CGGammaValue])] = [:]
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        setupObservers()
        print("✓ ColorTemperatureManager initialized")
        
        // Apply initial state if enabled
        if SettingsManager.shared.colorTemperatureEnabled {
            applyTemperature(SettingsManager.shared.colorTemperature)
        }
    }
    
    deinit {
        restore()
    }
    
    // ================================================================
    // MARK: - Setup
    // ================================================================
    
    /**
     Sets up observers for settings changes.
     */
    private func setupObservers() {
        // Observe colorTemperatureEnabled changes
        SettingsManager.shared.$colorTemperatureEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                print("🌡️ Color temperature toggle: \(enabled ? "ON" : "OFF")")
                if enabled {
                    self?.applyTemperature(SettingsManager.shared.colorTemperature)
                } else {
                    self?.restore()
                }
            }
            .store(in: &cancellables)
        
        // Observe colorTemperature value changes
        SettingsManager.shared.$colorTemperature
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main) // Debounce slider drag
            .sink { [weak self] temperature in
                guard SettingsManager.shared.colorTemperatureEnabled else { return }
                print("🌡️ Color temperature changed to: \(Int(temperature))K")
                self?.applyTemperature(temperature)
            }
            .store(in: &cancellables)
    }
    
    // ================================================================
    // MARK: - Public Methods
    // ================================================================
    
    /**
     Applies a specific color temperature to all displays.
     
     - Parameter kelvin: The color temperature in Kelvin (1900-6500)
     
     HOW THIS WORKS:
     We create gamma lookup tables (LUTs) for each RGB channel and multiply
     each value by the color temperature's RGB multiplier. This directly
     affects the color output of the display.
     
     The gamma table is an array of 256 values (0.0 to 1.0) that map input
     pixel values to output values. By scaling the table with our RGB multipliers,
     we effectively tint the entire display.
     
     For example, at 3000K (warm/orange):
     - Red multiplier ≈ 1.0 (full red)
     - Green multiplier ≈ 0.7 (reduced green)
     - Blue multiplier ≈ 0.4 (heavily reduced blue)
     
     This reduces blue light and creates the warm orange tint.
     */
    func applyTemperature(_ kelvin: Double) {
        let clampedKelvin = max(1900, min(6500, kelvin))
        
        // Calculate RGB multipliers from Kelvin
        let rgb = kelvinToRGB(kelvin: clampedKelvin)
        
        print("🌡️ Applying temperature \(Int(clampedKelvin))K")
        print("   RGB multipliers: R=\(String(format: "%.3f", rgb.red)), G=\(String(format: "%.3f", rgb.green)), B=\(String(format: "%.3f", rgb.blue))")
        
        // Apply to all displays
        var displayCount: UInt32 = 0
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == .success else {
            print("⚠️ Failed to get display list")
            return
        }
        
        // Create gamma tables (256 entries, standard for macOS)
        // Each table maps input values (0-255) to output values (0.0-1.0)
        let tableSize = 256
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)
        
        // Build the gamma tables with color temperature applied
        // We use a standard gamma curve (2.2) and multiply by RGB multipliers
        // The formula is: output = (input / 255) ^ gamma * rgbMultiplier
        let gamma = 2.2
        for i in 0..<tableSize {
            let normalized = Double(i) / Double(tableSize - 1)
            let gammaAdjusted = pow(normalized, 1.0 / gamma)
            
            // Apply color temperature multipliers
            redTable[i] = Float(gammaAdjusted * rgb.red)
            greenTable[i] = Float(gammaAdjusted * rgb.green)
            blueTable[i] = Float(gammaAdjusted * rgb.blue)
        }
        
        // Apply the gamma tables to all displays
        for i in 0..<Int(displayCount) {
            let displayID = onlineDisplays[i]
            
            // Save original gamma if not already saved
            saveOriginalGamma(for: displayID)
            
            // Apply the gamma tables
            // CGSetDisplayTransferByTable directly sets the lookup table
            // This is the same method used by f.lux and similar apps
            let result = CGSetDisplayTransferByTable(
                displayID,
                UInt32(tableSize),
                &redTable,
                &greenTable,
                &blueTable
            )
            
            if result == .success {
                print("🌡️ ✓ Applied to display \(displayID)")
            } else {
                print("⚠️ Failed to apply to display \(displayID): \(result)")
            }
        }
        
        isActive = true
        currentTemperature = clampedKelvin
    }
    
    /**
     Restores all displays to their default gamma.
     */
    func restore() {
        print("🌡️ Restoring default gamma...")
        
        var displayCount: UInt32 = 0
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        guard CGGetOnlineDisplayList(16, &onlineDisplays, &displayCount) == .success else {
            print("⚠️ Failed to get display list for restore")
            return
        }
        
        // Restore all displays to default gamma
        // Note: CGDisplayRestoreColorSyncSettings restores all displays globally
        CGDisplayRestoreColorSyncSettings()
        
        savedGamma.removeAll()
        isActive = false
        currentTemperature = 6500
        
        print("🌡️ ✓ Gamma restored to defaults")
    }
    
    // ================================================================
    // MARK: - Private Methods
    // ================================================================
    
    /**
     Saves the original gamma table for a display (for later restoration).
     */
    private func saveOriginalGamma(for displayID: CGDirectDisplayID) {
        guard savedGamma[displayID] == nil else { return }
        
        var redTable = [CGGammaValue](repeating: 0, count: 256)
        var greenTable = [CGGammaValue](repeating: 0, count: 256)
        var blueTable = [CGGammaValue](repeating: 0, count: 256)
        var sampleCount: UInt32 = 0
        
        let result = CGGetDisplayTransferByTable(
            displayID,
            256,
            &redTable,
            &greenTable,
            &blueTable,
            &sampleCount
        )
        
        if result == .success {
            savedGamma[displayID] = (redTable, greenTable, blueTable)
            print("🌡️ Saved original gamma for display \(displayID)")
        }
    }
    
    /**
     Converts color temperature in Kelvin to RGB multipliers.
     
     Algorithm by Tanner Helland, based on CIE color matching functions.
     Source: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
     
     - Parameter kelvin: Temperature in Kelvin (1000-40000)
     - Returns: RGB multipliers (0.0-1.0 for each channel)
     */
    private func kelvinToRGB(kelvin: Double) -> (red: Double, green: Double, blue: Double) {
        // Temperature should be in range 1000-40000, but we clamp to 1900-6500 for practical use
        let temp = kelvin / 100.0
        
        var red: Double
        var green: Double
        var blue: Double
        
        // Calculate Red
        if temp <= 66 {
            red = 255
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            red = max(0, min(255, red))
        }
        
        // Calculate Green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
        } else {
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492)
        }
        green = max(0, min(255, green))
        
        // Calculate Blue
        if temp >= 66 {
            blue = 255
        } else if temp <= 19 {
            blue = 0
        } else {
            blue = temp - 10
            blue = 138.5177312231 * log(blue) - 305.0447927307
            blue = max(0, min(255, blue))
        }
        
        // Normalize to 0-1 range
        return (red / 255.0, green / 255.0, blue / 255.0)
    }
}
