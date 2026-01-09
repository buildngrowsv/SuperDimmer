/**
 ====================================================================
 SuperDimmerTests.swift
 Unit tests for SuperDimmer
 ====================================================================
 
 PURPOSE:
 Main test file for SuperDimmer unit tests. Tests core functionality
 without requiring UI interaction.
 
 TEST CATEGORIES:
 - Settings persistence
 - Luminance calculation accuracy
 - Overlay configuration
 - Permission state handling
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import XCTest
@testable import SuperDimmer

// ====================================================================
// MARK: - Settings Manager Tests
// ====================================================================

final class SettingsManagerTests: XCTestCase {
    
    /// Test that default values are correctly set
    func testDefaultValues() {
        let settings = SettingsManager.shared
        
        // Reset to ensure defaults
        settings.resetToDefaults()
        
        // Verify defaults match PRD specification
        XCTAssertEqual(settings.globalDimLevel, 0.25, accuracy: 0.01, "Default global dim should be 25%")
        XCTAssertEqual(settings.brightnessThreshold, 0.85, accuracy: 0.01, "Default threshold should be 85%")
        XCTAssertEqual(settings.activeDimLevel, 0.15, accuracy: 0.01, "Default active dim should be 15%")
        XCTAssertEqual(settings.inactiveDimLevel, 0.35, accuracy: 0.01, "Default inactive dim should be 35%")
        XCTAssertEqual(settings.scanInterval, 1.0, accuracy: 0.1, "Default scan interval should be 1 second")
        XCTAssertFalse(settings.isDimmingEnabled, "Dimming should be off by default")
        XCTAssertEqual(settings.colorTemperature, 6500.0, accuracy: 10, "Default color temp should be 6500K")
    }
    
    /// Test that settings persist after change
    func testSettingsPersistence() {
        let settings = SettingsManager.shared
        
        // Change a setting
        let testValue = 0.42
        settings.globalDimLevel = testValue
        
        // Force save
        settings.save()
        
        // Read from UserDefaults directly to verify persistence
        let savedValue = UserDefaults.standard.double(forKey: "superdimmer.globalDimLevel")
        XCTAssertEqual(savedValue, testValue, accuracy: 0.001, "Setting should persist to UserDefaults")
        
        // Reset for other tests
        settings.resetToDefaults()
    }
}

// ====================================================================
// MARK: - Dimming Configuration Tests
// ====================================================================

final class DimmingConfigurationTests: XCTestCase {
    
    /// Test that configuration is created from settings correctly
    func testConfigurationFromSettings() {
        let settings = SettingsManager.shared
        settings.isDimmingEnabled = true
        settings.brightnessThreshold = 0.75
        settings.globalDimLevel = 0.30
        
        let config = DimmingConfiguration.fromSettings()
        
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.brightnessThreshold, 0.75, accuracy: 0.01)
        XCTAssertEqual(config.globalDimLevel, 0.30, accuracy: 0.01)
        
        // Reset
        settings.resetToDefaults()
    }
}

// ====================================================================
// MARK: - Temperature Preset Tests
// ====================================================================

final class TemperaturePresetTests: XCTestCase {
    
    /// Test preset Kelvin values
    func testPresetKelvinValues() {
        XCTAssertEqual(TemperaturePreset.daylight.kelvin, 6500)
        XCTAssertEqual(TemperaturePreset.sunset.kelvin, 4100)
        XCTAssertEqual(TemperaturePreset.night.kelvin, 2700)
        XCTAssertEqual(TemperaturePreset.candle.kelvin, 1900)
    }
    
    /// Test all presets are enumerable
    func testAllPresetsAvailable() {
        let allPresets = TemperaturePreset.allCases
        XCTAssertEqual(allPresets.count, 4, "Should have 4 temperature presets")
    }
}

// ====================================================================
// MARK: - Tracked Window Tests
// ====================================================================

final class TrackedWindowTests: XCTestCase {
    
    /// Test TrackedWindow initialization
    func testTrackedWindowInit() {
        let window = TrackedWindow(
            id: 12345,
            ownerPID: 100,
            ownerName: "TestApp",
            bundleID: "com.test.app",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            layer: 0,
            title: "Test Window",
            isActive: true
        )
        
        XCTAssertEqual(window.id, 12345)
        XCTAssertEqual(window.ownerName, "TestApp")
        XCTAssertTrue(window.isActive)
        XCTAssertEqual(window.bounds.width, 800)
    }
}

// ====================================================================
// MARK: - Dimming Decision Tests
// ====================================================================

final class DimmingDecisionTests: XCTestCase {
    
    /// Test creating a dimming decision
    func testDimmingDecisionCreation() {
        let window = TrackedWindow(
            id: 1,
            ownerPID: 100,
            ownerName: "Safari",
            bundleID: "com.apple.Safari",
            bounds: .zero,
            layer: 0,
            title: "Apple",
            isActive: true
        )
        
        let decision = DimmingDecision(
            window: window,
            shouldDim: true,
            dimLevel: 0.25,
            reason: .aboveThreshold
        )
        
        XCTAssertTrue(decision.shouldDim)
        XCTAssertEqual(decision.dimLevel, 0.25, accuracy: 0.01)
        XCTAssertEqual(decision.reason, .aboveThreshold)
    }
}
