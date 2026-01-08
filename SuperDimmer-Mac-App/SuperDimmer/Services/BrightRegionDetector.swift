/**
 ====================================================================
 BrightRegionDetector.swift
 Detects bright rectangular regions within images
 ====================================================================
 
 PURPOSE:
 This is the core of SuperDimmer's unique "per-region" detection mode.
 While other dimming apps can only dim entire screens or windows,
 this service finds SPECIFIC BRIGHT AREAS within windows.
 
 USE CASE EXAMPLE:
 - Mac Mail in dark mode with a bright white email open
 - The window itself isn't entirely bright, but part of it is
 - We detect just the email content area and dim only that region
 
 HOW IT WORKS:
 1. Divide the image into a grid (e.g., 8x8 = 64 cells)
 2. Analyze brightness of each cell using BrightnessAnalysisEngine
 3. Find cells that exceed the threshold
 4. Merge adjacent bright cells into rectangular regions
 5. Return the regions as CGRects (relative to window bounds)
 
 REGION MERGING:
 To avoid creating 64 tiny overlays, we merge adjacent bright cells
 into larger rectangles. This gives better visual results and
 better performance.
 
 PERFORMANCE:
 - Uses downsampled images for speed
 - Grid-based approach is O(n) where n = grid cells
 - Region merging uses connected component analysis
 
 ====================================================================
 Created: January 8, 2026
 Version: 1.0.0
 ====================================================================
 */

import Foundation
import CoreGraphics
import AppKit

// ====================================================================
// MARK: - Bright Region Detector
// ====================================================================

/**
 Detects bright rectangular regions within images.
 
 USAGE:
 ```
 let detector = BrightRegionDetector.shared
 let regions = detector.detectBrightRegions(
     in: windowImage,
     threshold: 0.85,
     gridSize: 8
 )
 for region in regions {
     // region.rect is relative to image bounds (0.0-1.0)
     // Convert to window coordinates for overlay placement
 }
 ```
 */
final class BrightRegionDetector {
    
    // ================================================================
    // MARK: - Singleton
    // ================================================================
    
    static let shared = BrightRegionDetector()
    
    // ================================================================
    // MARK: - Dependencies
    // ================================================================
    
    private let brightnessEngine = BrightnessAnalysisEngine.shared
    
    // ================================================================
    // MARK: - Initialization
    // ================================================================
    
    private init() {
        print("✓ BrightRegionDetector initialized")
    }
    
    // ================================================================
    // MARK: - Detection Result
    // ================================================================
    
    /**
     A detected bright region within an image.
     */
    struct BrightRegion: Identifiable {
        /// Unique ID for this region
        let id = UUID()
        
        /// Rectangle in normalized coordinates (0.0-1.0)
        /// Multiply by window dimensions to get actual position
        let normalizedRect: CGRect
        
        /// Average brightness of this region (0.0-1.0)
        let brightness: Float
        
        /// Number of grid cells that make up this region
        let cellCount: Int
        
        /// Converts normalized rect to actual screen coordinates
        /// 
        /// COORDINATE SYSTEMS:
        /// - Image/Grid: y=0 at TOP, increases downward (how pixels are stored)
        /// - Cocoa/NSWindow: y=0 at BOTTOM, increases upward
        /// 
        /// So we need to flip the y coordinate:
        /// - normalizedRect.y=0 (top of image) → top of window → bounds.y + bounds.height - regionHeight
        /// - normalizedRect.y=0.8 (bottom of image) → bottom of window → bounds.y
        func rect(in bounds: CGRect) -> CGRect {
            // Flip Y: convert from top-down to bottom-up coordinates
            // Formula: cocoaY = bounds.y + (1 - normalizedY - normalizedHeight) * bounds.height
            let flippedY = bounds.origin.y + (1.0 - normalizedRect.origin.y - normalizedRect.height) * bounds.height
            
            return CGRect(
                x: bounds.origin.x + normalizedRect.origin.x * bounds.width,
                y: flippedY,
                width: normalizedRect.width * bounds.width,
                height: normalizedRect.height * bounds.height
            )
        }
    }
    
    // ================================================================
    // MARK: - Detection
    // ================================================================
    
    /**
     Detects bright regions within an image.
     
     - Parameters:
       - image: The CGImage to analyze
       - threshold: Brightness threshold (0.0-1.0)
       - gridSize: Number of cells in each dimension (e.g., 8 = 8x8 grid)
       - minRegionSize: Minimum cells required to form a region (filters noise)
     - Returns: Array of detected bright regions
     */
    func detectBrightRegions(
        in image: CGImage,
        threshold: Float,
        gridSize: Int = 8,
        minRegionSize: Int = 2
    ) -> [BrightRegion] {
        
        // 1. Create brightness grid
        let brightnessGrid = createBrightnessGrid(image: image, gridSize: gridSize)
        
        // 2. Create binary grid (above/below threshold)
        var binaryGrid = [[Bool]](repeating: [Bool](repeating: false, count: gridSize), count: gridSize)
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                binaryGrid[row][col] = brightnessGrid[row][col] > threshold
            }
        }
        
        // 3. Find connected components (groups of adjacent bright cells)
        let components = findConnectedComponents(grid: binaryGrid)
        
        // 4. Convert components to regions
        var regions: [BrightRegion] = []
        
        for component in components {
            // Skip small components (noise)
            guard component.count >= minRegionSize else { continue }
            
            // Find bounding box of this component
            let boundingBox = calculateBoundingBox(cells: component, gridSize: gridSize)
            
            // Calculate average brightness of this region
            var totalBrightness: Float = 0
            for (row, col) in component {
                totalBrightness += brightnessGrid[row][col]
            }
            let avgBrightness = totalBrightness / Float(component.count)
            
            let region = BrightRegion(
                normalizedRect: boundingBox,
                brightness: avgBrightness,
                cellCount: component.count
            )
            regions.append(region)
        }
        
        // 5. Optionally merge overlapping regions
        let mergedRegions = mergeOverlappingRegions(regions)
        
        return mergedRegions
    }
    
    /**
     Quick check if any region in the image exceeds the threshold.
     
     - Parameters:
       - image: The CGImage to check
       - threshold: Brightness threshold
       - gridSize: Grid resolution
     - Returns: true if any region is bright
     */
    func hasBrightRegions(in image: CGImage, threshold: Float, gridSize: Int = 4) -> Bool {
        let brightnessGrid = createBrightnessGrid(image: image, gridSize: gridSize)
        
        for row in brightnessGrid {
            for brightness in row {
                if brightness > threshold {
                    return true
                }
            }
        }
        return false
    }
    
    // ================================================================
    // MARK: - Grid Creation
    // ================================================================
    
    /**
     Creates a brightness grid for the image.
     
     Divides the image into gridSize x gridSize cells and calculates
     the average brightness of each cell.
     */
    private func createBrightnessGrid(image: CGImage, gridSize: Int) -> [[Float]] {
        // Use the engine's grid analysis if available
        if let grid = brightnessEngine.brightnessGrid(of: image, gridSize: gridSize) {
            return grid
        }
        
        // Fallback: manual grid creation
        var grid = [[Float]](repeating: [Float](repeating: 0, count: gridSize), count: gridSize)
        
        let cellWidth = CGFloat(image.width) / CGFloat(gridSize)
        let cellHeight = CGFloat(image.height) / CGFloat(gridSize)
        
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let rect = CGRect(
                    x: CGFloat(col) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                
                let brightness = brightnessEngine.averageLuminance(of: image, inRect: rect) ?? 0
                grid[row][col] = brightness
            }
        }
        
        return grid
    }
    
    // ================================================================
    // MARK: - Connected Components
    // ================================================================
    
    /**
     Finds connected components in a binary grid.
     
     Uses flood fill to group adjacent cells that are true.
     Returns array of components, each component is array of (row, col) tuples.
     */
    private func findConnectedComponents(grid: [[Bool]]) -> [[(Int, Int)]] {
        let rows = grid.count
        let cols = grid[0].count
        var visited = [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        var components: [[(Int, Int)]] = []
        
        for row in 0..<rows {
            for col in 0..<cols {
                if grid[row][col] && !visited[row][col] {
                    // Start flood fill from this cell
                    var component: [(Int, Int)] = []
                    floodFill(grid: grid, visited: &visited, row: row, col: col, component: &component)
                    components.append(component)
                }
            }
        }
        
        return components
    }
    
    /**
     Flood fill helper for connected component detection.
     */
    private func floodFill(
        grid: [[Bool]],
        visited: inout [[Bool]],
        row: Int,
        col: Int,
        component: inout [(Int, Int)]
    ) {
        let rows = grid.count
        let cols = grid[0].count
        
        // Bounds check
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        
        // Already visited or not bright
        guard !visited[row][col], grid[row][col] else { return }
        
        // Mark visited and add to component
        visited[row][col] = true
        component.append((row, col))
        
        // Check 4-connected neighbors (up, down, left, right)
        floodFill(grid: grid, visited: &visited, row: row - 1, col: col, component: &component)
        floodFill(grid: grid, visited: &visited, row: row + 1, col: col, component: &component)
        floodFill(grid: grid, visited: &visited, row: row, col: col - 1, component: &component)
        floodFill(grid: grid, visited: &visited, row: row, col: col + 1, component: &component)
    }
    
    // ================================================================
    // MARK: - Bounding Box
    // ================================================================
    
    /**
     Calculates the bounding box of a set of cells.
     
     Returns normalized coordinates (0.0-1.0).
     */
    private func calculateBoundingBox(cells: [(Int, Int)], gridSize: Int) -> CGRect {
        guard !cells.isEmpty else { return .zero }
        
        var minRow = Int.max, maxRow = Int.min
        var minCol = Int.max, maxCol = Int.min
        
        for (row, col) in cells {
            minRow = min(minRow, row)
            maxRow = max(maxRow, row)
            minCol = min(minCol, col)
            maxCol = max(maxCol, col)
        }
        
        // Convert to normalized coordinates
        let cellSize = 1.0 / CGFloat(gridSize)
        
        return CGRect(
            x: CGFloat(minCol) * cellSize,
            y: CGFloat(minRow) * cellSize,
            width: CGFloat(maxCol - minCol + 1) * cellSize,
            height: CGFloat(maxRow - minRow + 1) * cellSize
        )
    }
    
    // ================================================================
    // MARK: - Region Merging
    // ================================================================
    
    /**
     Merges overlapping or adjacent regions into larger ones.
     
     This reduces the number of overlays needed.
     */
    private func mergeOverlappingRegions(_ regions: [BrightRegion]) -> [BrightRegion] {
        guard regions.count > 1 else { return regions }
        
        var merged: [BrightRegion] = []
        var used = Set<UUID>()
        
        for region in regions {
            guard !used.contains(region.id) else { continue }
            
            var combinedRect = region.normalizedRect
            var combinedBrightness = region.brightness * Float(region.cellCount)
            var combinedCells = region.cellCount
            
            // Check for overlapping/adjacent regions
            for other in regions {
                guard other.id != region.id, !used.contains(other.id) else { continue }
                
                // Check if regions overlap or are very close
                let expanded = combinedRect.insetBy(dx: -0.05, dy: -0.05)
                if expanded.intersects(other.normalizedRect) {
                    used.insert(other.id)
                    combinedRect = combinedRect.union(other.normalizedRect)
                    combinedBrightness += other.brightness * Float(other.cellCount)
                    combinedCells += other.cellCount
                }
            }
            
            used.insert(region.id)
            
            let mergedRegion = BrightRegion(
                normalizedRect: combinedRect,
                brightness: combinedBrightness / Float(combinedCells),
                cellCount: combinedCells
            )
            merged.append(mergedRegion)
        }
        
        return merged
    }
}
