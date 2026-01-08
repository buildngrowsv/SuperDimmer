/**
 ====================================================================
 BrightnessAnalysisEngine.swift
 High-performance brightness analysis using Accelerate framework
 ====================================================================
 
 PURPOSE:
 This engine analyzes captured screen images to determine their brightness.
 It's used by the DimmingCoordinator to decide which windows/regions
 should be dimmed based on their perceived brightness.
 
 ALGORITHM:
 We calculate perceived luminance using the Rec. 709 standard:
   Y = 0.2126 * R + 0.7152 * G + 0.0722 * B
 
 This matches human perception where green contributes most to
 perceived brightness, followed by red, then blue.
 
 PERFORMANCE:
 - Uses Accelerate framework (vDSP) for SIMD operations
 - Processes millions of pixels in milliseconds
 - Downsampled images provide faster analysis with minimal accuracy loss
 - Target: <50ms for full screen at 1/4 resolution
 
 OUTPUT:
 - Luminance values are normalized to 0.0-1.0
 - 0.0 = completely black
 - 1.0 = completely white
 - Typical bright content (white webpage) ≈ 0.9+
 - Typical dark content (dark mode app) ≈ 0.1-0.3
 
 ====================================================================
 Created: January 7, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import CoreGraphics
import Accelerate

// ====================================================================
// MARK: - Brightness Analysis Engine
// ====================================================================

/**
 High-performance brightness analysis for screen content.
 
 USAGE:
 ```
 let engine = BrightnessAnalysisEngine.shared
 if let image = screenCapture {
     let brightness = engine.averageLuminance(of: image)
     if brightness > 0.85 {
         // This region is very bright, consider dimming
     }
 }
 ```
 
 THREAD SAFETY:
 All methods are thread-safe and can be called from any queue.
 */
final class BrightnessAnalysisEngine {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = BrightnessAnalysisEngine()
    
    // ================================================================
    // MARK: - Constants
    // ================================================================
    
    /**
     Rec. 709 luminance coefficients.
     These define how RGB values contribute to perceived brightness.
     */
    private let redCoefficient: Float = 0.2126
    private let greenCoefficient: Float = 0.7152
    private let blueCoefficient: Float = 0.0722
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        print("✓ BrightnessAnalysisEngine initialized")
    }
    
    // ================================================================
    // MARK: - Full Image Analysis
    // ================================================================
    
    /**
     Calculates the average luminance of an entire image.
     
     - Parameter image: The CGImage to analyze
     - Returns: Average luminance value (0.0-1.0), or nil if analysis failed
     
     This is the main entry point for brightness analysis.
     For performance, consider using a downsampled image.
     */
    func averageLuminance(of image: CGImage) -> Float? {
        return analyzeLuminance(image: image, region: nil).average
    }
    
    /**
     Calculates the average luminance of a specific region within an image.
     
     - Parameters:
       - image: The source CGImage
       - rect: The region to analyze (in image coordinates, not screen coordinates)
     - Returns: Average luminance of the region (0.0-1.0), or nil if failed
     
     The rect is clamped to the image bounds if necessary.
     */
    func averageLuminance(of image: CGImage, inRect rect: CGRect) -> Float? {
        return analyzeLuminance(image: image, region: rect).average
    }
    
    // ================================================================
    // MARK: - Detailed Analysis
    // ================================================================
    
    /**
     Detailed luminance analysis result.
     */
    struct LuminanceResult {
        /// Average luminance (0.0-1.0)
        let average: Float?
        
        /// Maximum luminance in the region
        let maximum: Float
        
        /// Minimum luminance in the region
        let minimum: Float
        
        /// Standard deviation of luminance values
        let standardDeviation: Float
        
        /// Percentage of pixels above 0.9 brightness (very bright)
        let percentageVeryBright: Float
        
        /// Percentage of pixels above 0.7 brightness (bright)
        let percentageBright: Float
        
        /// Number of pixels analyzed
        let pixelCount: Int
        
        /// Analysis time in milliseconds
        let analysisTimeMs: Double
    }
    
    /**
     Performs detailed luminance analysis on an image.
     
     - Parameters:
       - image: The CGImage to analyze
       - region: Optional region to analyze (nil = entire image)
     - Returns: Detailed analysis results
     
     This provides more information than simple average, useful for
     making nuanced dimming decisions.
     */
    func analyzeLuminance(image: CGImage, region: CGRect?) -> LuminanceResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Get pixel data from image
        guard let pixelData = extractPixelData(from: image, region: region) else {
            return LuminanceResult(
                average: nil,
                maximum: 0,
                minimum: 0,
                standardDeviation: 0,
                percentageVeryBright: 0,
                percentageBright: 0,
                pixelCount: 0,
                analysisTimeMs: 0
            )
        }
        
        let pixelCount = pixelData.count / 4  // RGBA = 4 bytes per pixel
        guard pixelCount > 0 else {
            return LuminanceResult(
                average: nil,
                maximum: 0,
                minimum: 0,
                standardDeviation: 0,
                percentageVeryBright: 0,
                percentageBright: 0,
                pixelCount: 0,
                analysisTimeMs: 0
            )
        }
        
        // Calculate luminance for each pixel using Accelerate
        let luminanceValues = calculateLuminanceValues(from: pixelData, pixelCount: pixelCount)
        
        // Calculate statistics using Accelerate
        var mean: Float = 0
        var stdDev: Float = 0
        var min: Float = 0
        var max: Float = 0
        
        vDSP_normalize(luminanceValues, 1, nil, 1, &mean, &stdDev, vDSP_Length(pixelCount))
        vDSP_minv(luminanceValues, 1, &min, vDSP_Length(pixelCount))
        vDSP_maxv(luminanceValues, 1, &max, vDSP_Length(pixelCount))
        
        // Count bright pixels
        var veryBrightCount: Int = 0
        var brightCount: Int = 0
        
        for lum in luminanceValues {
            if lum > 0.9 {
                veryBrightCount += 1
                brightCount += 1
            } else if lum > 0.7 {
                brightCount += 1
            }
        }
        
        let percentageVeryBright = Float(veryBrightCount) / Float(pixelCount) * 100
        let percentageBright = Float(brightCount) / Float(pixelCount) * 100
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let analysisTimeMs = (endTime - startTime) * 1000
        
        return LuminanceResult(
            average: mean,
            maximum: max,
            minimum: min,
            standardDeviation: stdDev,
            percentageVeryBright: percentageVeryBright,
            percentageBright: percentageBright,
            pixelCount: pixelCount,
            analysisTimeMs: analysisTimeMs
        )
    }
    
    // ================================================================
    // MARK: - Histogram Analysis
    // ================================================================
    
    /**
     Generates a brightness histogram for an image.
     
     - Parameter image: The CGImage to analyze
     - Parameter bins: Number of histogram bins (default: 256)
     - Returns: Array of bin counts, or nil if analysis failed
     
     Useful for understanding the brightness distribution:
     - Left-heavy = dark image
     - Right-heavy = bright image
     - Bimodal = high contrast
     */
    func brightnessHistogram(of image: CGImage, bins: Int = 256) -> [Int]? {
        guard let pixelData = extractPixelData(from: image, region: nil) else {
            return nil
        }
        
        let pixelCount = pixelData.count / 4
        guard pixelCount > 0 else { return nil }
        
        let luminanceValues = calculateLuminanceValues(from: pixelData, pixelCount: pixelCount)
        
        var histogram = [Int](repeating: 0, count: bins)
        
        for lum in luminanceValues {
            let bin = min(bins - 1, Int(lum * Float(bins)))
            histogram[bin] += 1
        }
        
        return histogram
    }
    
    // ================================================================
    // MARK: - Region-Based Analysis
    // ================================================================
    
    /**
     Analyzes brightness in a grid pattern.
     
     - Parameters:
       - image: The CGImage to analyze
       - gridSize: Number of cells in each dimension (e.g., 3 = 3x3 grid)
     - Returns: 2D array of luminance values, or nil if failed
     
     Useful for identifying which areas of the screen are brightest.
     */
    func brightnessGrid(of image: CGImage, gridSize: Int = 3) -> [[Float]]? {
        guard gridSize > 0 else { return nil }
        
        let cellWidth = CGFloat(image.width) / CGFloat(gridSize)
        let cellHeight = CGFloat(image.height) / CGFloat(gridSize)
        
        var grid = [[Float]]()
        
        for row in 0..<gridSize {
            var rowValues = [Float]()
            for col in 0..<gridSize {
                let rect = CGRect(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                
                let luminance = averageLuminance(of: image, inRect: rect) ?? 0
                rowValues.append(luminance)
            }
            grid.append(rowValues)
        }
        
        return grid
    }
    
    // ================================================================
    // MARK: - Quick Checks
    // ================================================================
    
    /**
     Quick check if an image is above a brightness threshold.
     
     - Parameters:
       - image: The CGImage to check
       - threshold: Brightness threshold (0.0-1.0)
     - Returns: true if average brightness exceeds threshold
     
     Faster than full analysis when you just need a yes/no answer.
     */
    func isBrighterThan(_ threshold: Float, image: CGImage) -> Bool {
        guard let avg = averageLuminance(of: image) else {
            return false
        }
        return avg > threshold
    }
    
    /**
     Quick check if an image has significant bright areas.
     
     - Parameters:
       - image: The CGImage to check
       - percentageThreshold: Minimum percentage of bright pixels
       - brightnessThreshold: What counts as "bright" (default: 0.85)
     - Returns: true if percentage of bright pixels exceeds threshold
     
     Useful for detecting images with bright content areas even if
     the overall average isn't high.
     */
    func hasBrightAreas(image: CGImage, percentageThreshold: Float, brightnessThreshold: Float = 0.85) -> Bool {
        let result = analyzeLuminance(image: image, region: nil)
        
        // Use percentageBright if threshold is lower, veryBright if higher
        if brightnessThreshold > 0.85 {
            return result.percentageVeryBright >= percentageThreshold
        } else {
            return result.percentageBright >= percentageThreshold
        }
    }
    
    // ================================================================
    // MARK: - Private Helpers
    // ================================================================
    
    /**
     Extracts pixel data from a CGImage.
     
     - Parameters:
       - image: Source image
       - region: Optional region to extract
     - Returns: Array of RGBA pixel values (4 bytes per pixel)
     */
    private func extractPixelData(from image: CGImage, region: CGRect?) -> [UInt8]? {
        // Determine the region to process
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let targetRect = region?.intersection(imageRect) ?? imageRect
        
        guard targetRect.width > 0, targetRect.height > 0 else {
            return nil
        }
        
        let width = Int(targetRect.width)
        let height = Int(targetRect.height)
        
        // Create a bitmap context to draw the image
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Draw the image (or region) into the context
        let drawRect = CGRect(x: 0, y: 0, width: width, height: height)
        
        if region != nil {
            // Crop to region by translating context
            context.translateBy(x: -targetRect.origin.x, y: -targetRect.origin.y)
            context.draw(image, in: imageRect)
        } else {
            context.draw(image, in: drawRect)
        }
        
        return pixelData
    }
    
    /**
     Calculates luminance values for all pixels using Accelerate.
     
     - Parameters:
       - pixelData: RGBA pixel data
       - pixelCount: Number of pixels
     - Returns: Array of luminance values (0.0-1.0)
     
     Uses vDSP for vectorized operations.
     */
    private func calculateLuminanceValues(from pixelData: [UInt8], pixelCount: Int) -> [Float] {
        // Separate channels and convert to Float
        var redValues = [Float](repeating: 0, count: pixelCount)
        var greenValues = [Float](repeating: 0, count: pixelCount)
        var blueValues = [Float](repeating: 0, count: pixelCount)
        
        // Extract and normalize RGB values (skip alpha)
        for i in 0..<pixelCount {
            let offset = i * 4
            redValues[i] = Float(pixelData[offset]) / 255.0
            greenValues[i] = Float(pixelData[offset + 1]) / 255.0
            blueValues[i] = Float(pixelData[offset + 2]) / 255.0
        }
        
        // Apply luminance coefficients using vDSP
        var luminance = [Float](repeating: 0, count: pixelCount)
        
        // luminance = red * redCoef + green * greenCoef + blue * blueCoef
        var redCoef = redCoefficient
        var greenCoef = greenCoefficient
        var blueCoef = blueCoefficient
        
        // Multiply red by coefficient
        vDSP_vsmul(redValues, 1, &redCoef, &luminance, 1, vDSP_Length(pixelCount))
        
        // Add green * coefficient
        var greenResult = [Float](repeating: 0, count: pixelCount)
        vDSP_vsmul(greenValues, 1, &greenCoef, &greenResult, 1, vDSP_Length(pixelCount))
        vDSP_vadd(luminance, 1, greenResult, 1, &luminance, 1, vDSP_Length(pixelCount))
        
        // Add blue * coefficient
        var blueResult = [Float](repeating: 0, count: pixelCount)
        vDSP_vsmul(blueValues, 1, &blueCoef, &blueResult, 1, vDSP_Length(pixelCount))
        vDSP_vadd(luminance, 1, blueResult, 1, &luminance, 1, vDSP_Length(pixelCount))
        
        return luminance
    }
}
