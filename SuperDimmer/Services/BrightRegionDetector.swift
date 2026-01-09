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
    // ================================================================
    // MARK: - Configuration
    // ================================================================
    
    /**
     Minimum pixel dimensions for a region overlay.
     Regions smaller than this are filtered out (noise, small UI elements).
     */
    private let minimumRegionPixelSize: CGFloat = 100.0
    
    /**
     Maximum pixel dimensions for a single region.
     Regions larger than this suggest the whole window is bright - 
     in that case, use per-window mode instead of per-region.
     */
    private let maximumRegionPixelSize: CGFloat = 2000.0
    
    /**
     Resolution for pixel-level analysis.
     Image is downsampled to this size for fast connected-component analysis.
     Higher = more precise but slower. 64-128 is a good balance.
     */
    private let analysisResolution: Int = 80
    
    // ================================================================
    // MARK: - Main Detection (Pixel-Level Precision)
    // ================================================================
    
    /**
     Detects bright regions with **exact pixel-level boundaries**.
     
     NEW APPROACH (Jan 8, 2026):
     Instead of a coarse grid, this uses pixel-level thresholding:
     1. Downsample image to analysisResolution (e.g., 80x80)
     2. Convert to grayscale and threshold each pixel
     3. Find connected components (flood fill at pixel level)
     4. Get exact bounding rectangles of each component
     5. Filter by min/max size
     
     This gives MUCH more accurate region boundaries compared to the
     old grid-based approach.
     
     - Parameters:
       - image: The CGImage to analyze
       - threshold: Brightness threshold (0.0-1.0)
       - gridSize: DEPRECATED - kept for API compatibility but ignored
       - minRegionSize: DEPRECATED - use minimumRegionPixelSize instead
     - Returns: Array of detected bright regions with precise boundaries
     */
    func detectBrightRegions(
        in image: CGImage,
        threshold: Float,
        gridSize: Int = 6,  // Ignored - using analysisResolution instead
        minRegionSize: Int = 4  // Ignored - using pixel-based filtering
    ) -> [BrightRegion] {
        
        // 1. Downsample and get pixel brightness data
        guard let brightnessData = getPixelBrightnessData(
            from: image,
            targetSize: analysisResolution
        ) else {
            return []
        }
        
        let width = brightnessData.width
        let height = brightnessData.height
        let pixels = brightnessData.pixels
        
        // 2. Create binary mask (above threshold = true)
        var binaryMask = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                binaryMask[y][x] = pixels[y * width + x] > threshold
            }
        }
        
        // 3. Find connected components using flood fill
        let components = findPixelConnectedComponents(mask: binaryMask, width: width, height: height)
        
        // 4. Convert to regions with normalized coordinates
        var regions: [BrightRegion] = []
        
        for component in components {
            // Get bounding box of this component
            var minX = width, maxX = 0, minY = height, maxY = 0
            var totalBrightness: Float = 0
            
            for (y, x) in component {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                totalBrightness += pixels[y * width + x]
            }
            
            // Convert to normalized coordinates (0.0-1.0)
            let normalizedRect = CGRect(
                x: CGFloat(minX) / CGFloat(width),
                y: CGFloat(minY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height)
            )
            
            let region = BrightRegion(
                normalizedRect: normalizedRect,
                brightness: totalBrightness / Float(component.count),
                cellCount: component.count
            )
            regions.append(region)
        }
        
        // 5. Merge nearby regions
        return mergeOverlappingRegions(regions)
    }
    
    /**
     Filters regions by minimum and maximum pixel size.
     
     - Minimum: Filters out tiny bright spots (buttons, icons)
     - Maximum: Filters out regions that cover most of the window
               (those should use per-window dimming instead)
     */
    func filterByMinimumSize(_ regions: [BrightRegion], windowBounds: CGRect) -> [BrightRegion] {
        return regions.filter { region in
            let screenRect = region.rect(in: windowBounds)
            let meetsMin = screenRect.width >= minimumRegionPixelSize && 
                          screenRect.height >= minimumRegionPixelSize
            let meetsMax = screenRect.width <= maximumRegionPixelSize ||
                          screenRect.height <= maximumRegionPixelSize
            return meetsMin && meetsMax
        }
    }
    
    // ================================================================
    // MARK: - Pixel-Level Analysis Helpers
    // ================================================================
    
    /**
     Brightness data from a downsampled image.
     */
    private struct PixelBrightnessData {
        let pixels: [Float]  // Row-major brightness values (0.0-1.0)
        let width: Int
        let height: Int
    }
    
    /**
     Downsamples image and extracts per-pixel brightness values.
     
     - Parameters:
       - image: Source CGImage
       - targetSize: Target dimension (image will be scaled to targetSize x targetSize)
     - Returns: Array of brightness values in row-major order, or nil on failure
     */
    private func getPixelBrightnessData(from image: CGImage, targetSize: Int) -> PixelBrightnessData? {
        // Create a small bitmap context
        let width = targetSize
        let height = targetSize
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Draw the image scaled down
        context.interpolationQuality = .low  // Fast scaling
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Get pixel data
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        
        // Calculate brightness for each pixel using luminance formula
        var pixels = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = Float(buffer[offset]) / 255.0
                let g = Float(buffer[offset + 1]) / 255.0
                let b = Float(buffer[offset + 2]) / 255.0
                
                // Standard luminance formula (perceived brightness)
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                pixels[y * width + x] = luminance
            }
        }
        
        return PixelBrightnessData(pixels: pixels, width: width, height: height)
    }
    
    /**
     Finds connected components in a binary pixel mask using flood fill.
     
     - Parameters:
       - mask: 2D boolean array (true = bright pixel)
       - width: Mask width
       - height: Mask height
     - Returns: Array of components, each component is array of (y, x) coordinates
     */
    private func findPixelConnectedComponents(
        mask: [[Bool]],
        width: Int,
        height: Int
    ) -> [[(Int, Int)]] {
        var visited = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        var components: [[(Int, Int)]] = []
        
        // Minimum component size in pixels (at analysis resolution)
        // This filters out noise at the pixel level
        let minComponentPixels = 10  // ~1.5% of 80x80 image
        
        for y in 0..<height {
            for x in 0..<width {
                if mask[y][x] && !visited[y][x] {
                    // Start flood fill
                    var component: [(Int, Int)] = []
                    var stack: [(Int, Int)] = [(y, x)]
                    
                    while !stack.isEmpty {
                        let (cy, cx) = stack.removeLast()
                        
                        // Bounds and visited check
                        guard cy >= 0, cy < height, cx >= 0, cx < width else { continue }
                        guard !visited[cy][cx], mask[cy][cx] else { continue }
                        
                        visited[cy][cx] = true
                        component.append((cy, cx))
                        
                        // Add 4-connected neighbors
                        stack.append((cy - 1, cx))
                        stack.append((cy + 1, cx))
                        stack.append((cy, cx - 1))
                        stack.append((cy, cx + 1))
                    }
                    
                    // Only keep components above minimum size
                    if component.count >= minComponentPixels {
                        components.append(component)
                    }
                }
            }
        }
        
        return components
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
            // FIX (Jan 8, 2026): Increased expansion from 0.05 to 0.15 (15% of window)
            // This merges regions that are close to each other, reducing patchwork effect
            for other in regions {
                guard other.id != region.id, !used.contains(other.id) else { continue }
                
                // Check if regions overlap or are close (within 15% of window size)
                let expanded = combinedRect.insetBy(dx: -0.15, dy: -0.15)
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
        
        // If we merged any regions, do ONE more pass to catch regions that became adjacent
        // But only if we actually reduced the count (to prevent infinite recursion)
        if merged.count > 1 && merged.count < regions.count {
            return mergeOverlappingRegions(merged)
        }
        
        return merged
    }
}
