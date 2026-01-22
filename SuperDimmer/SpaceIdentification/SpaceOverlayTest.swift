/**
 ====================================================================
 SpaceOverlayTest.swift
 Minimal test implementation for Space-specific overlays
 ====================================================================
 
 PURPOSE:
 This is a PROOF-OF-CONCEPT to test whether removing canJoinAllSpaces
 actually pins overlays to individual Spaces as expected.
 
 USAGE:
 1. Add this file to Xcode project
 2. Call SpaceOverlayTest.shared.runTest() from menu bar or app launch
 3. Follow the on-screen instructions
 4. Verify overlays stay on their assigned Spaces
 
 TEST PROCEDURE:
 - Creates 4 test overlays with different colors
 - User manually switches to each Space and registers it
 - Each overlay should stay on its registered Space
 - Switching Spaces should show different colored overlays
 
 WHAT TO OBSERVE:
 - ✅ SUCCESS: Each Space shows its unique colored overlay
 - ❌ FAILURE: All overlays appear on all Spaces (canJoinAllSpaces not removed)
 
 ====================================================================
 Created: January 21, 2026
 Status: TEST/POC - Not production code
 ====================================================================
 */

import AppKit
import SwiftUI

// ====================================================================
// MARK: - Space Overlay Test Manager
// ====================================================================

/**
 Test manager for Space-specific overlay proof-of-concept.
 
 This creates simple colored overlays to test whether removing
 canJoinAllSpaces successfully pins windows to individual Spaces.
 */
final class SpaceOverlayTest {
    
    // Singleton for easy access
    static let shared = SpaceOverlayTest()
    
    // Track created test overlays
    private var testOverlays: [Int: TestSpaceOverlay] = [:]
    
    // Current registration step
    private var currentRegistrationStep: Int = 0
    
    // Test colors for each Space
    private let testColors: [NSColor] = [
        NSColor.systemBlue.withAlphaComponent(0.15),    // Space 1: Blue
        NSColor.systemGreen.withAlphaComponent(0.15),   // Space 2: Green
        NSColor.systemPurple.withAlphaComponent(0.15),  // Space 3: Purple
        NSColor.systemOrange.withAlphaComponent(0.15)   // Space 4: Orange
    ]
    
    private init() {}
    
    // ================================================================
    // MARK: - Test Execution
    // ================================================================
    
    /**
     Runs the Space overlay test.
     
     INSTRUCTIONS FOR USER:
     1. This will show an alert with instructions
     2. You'll register 4 Spaces one by one
     3. Switch to each Space and click "Register This Space"
     4. After all 4 are registered, switch between Spaces to verify
     
     EXPECTED RESULT:
     - Space 1 should have blue tint
     - Space 2 should have green tint
     - Space 3 should have purple tint
     - Space 4 should have orange tint
     - Each tint should ONLY appear on its registered Space
     */
    func runTest() {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 SPACE OVERLAY TEST - Starting")
        print(String(repeating: "=", count: 60))
        
        // Show initial instructions
        showInstructions()
    }
    
    /**
     Shows test instructions to the user.
     */
    private func showInstructions() {
        let alert = NSAlert()
        alert.messageText = "🧪 Space Overlay Test"
        alert.informativeText = """
        This test will verify if we can create Space-specific overlays.
        
        SETUP:
        1. Make sure you have at least 4 Spaces (virtual desktops)
        2. You'll register each Space one by one
        3. Each Space will get a different colored overlay
        
        PROCEDURE:
        1. Click "Start Test"
        2. You'll see a prompt to register Space 1
        3. Click "Register This Space"
        4. Switch to Space 2 (swipe or Ctrl+→)
        5. Click "Register This Space" again
        6. Repeat for Spaces 3 and 4
        
        VERIFICATION:
        After registering all 4 Spaces, switch between them.
        You should see:
        - Space 1: Blue tint
        - Space 2: Green tint
        - Space 3: Purple tint
        - Space 4: Orange tint
        
        If each Space shows ONLY its own color, the test PASSED! ✅
        If all colors appear on all Spaces, the test FAILED. ❌
        
        Ready to start?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Test")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            startRegistrationProcess()
        } else {
            print("🧪 Test cancelled by user")
        }
    }
    
    /**
     Starts the Space registration process.
     */
    private func startRegistrationProcess() {
        currentRegistrationStep = 0
        showRegistrationPrompt()
    }
    
    /**
     Shows prompt to register the current Space.
     */
    private func showRegistrationPrompt() {
        let spaceNumber = currentRegistrationStep + 1
        let color = testColors[currentRegistrationStep]
        let colorName = getColorName(for: currentRegistrationStep)
        
        let alert = NSAlert()
        alert.messageText = "Register Space \(spaceNumber)"
        alert.informativeText = """
        You are about to register Space \(spaceNumber) with a \(colorName) overlay.
        
        INSTRUCTIONS:
        1. Make sure you're on Space \(spaceNumber)
        2. Click "Register This Space"
        3. The overlay will be created on THIS Space
        4. Then switch to Space \(spaceNumber + 1) for the next step
        
        Current Space will get: \(colorName) tint
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Register This Space")
        alert.addButton(withTitle: "Cancel Test")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            registerCurrentSpace()
        } else {
            cleanupTest()
            print("🧪 Test cancelled")
        }
    }
    
    /**
     Registers the current Space with a test overlay.
     */
    private func registerCurrentSpace() {
        let spaceIndex = currentRegistrationStep
        let color = testColors[spaceIndex]
        let colorName = getColorName(for: spaceIndex)
        
        guard let screen = NSScreen.main else {
            print("❌ No main screen found")
            return
        }
        
        // Create the test overlay
        let overlay = TestSpaceOverlay(
            spaceIndex: spaceIndex,
            color: color,
            screen: screen
        )
        
        testOverlays[spaceIndex] = overlay
        overlay.orderFront(nil)
        
        print("✅ Registered Space \(spaceIndex + 1) with \(colorName) overlay")
        
        // Move to next step
        currentRegistrationStep += 1
        
        if currentRegistrationStep < testColors.count {
            // More Spaces to register
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showRegistrationPrompt()
            }
        } else {
            // All done!
            showCompletionMessage()
        }
    }
    
    /**
     Shows completion message after all Spaces are registered.
     */
    private func showCompletionMessage() {
        let alert = NSAlert()
        alert.messageText = "✅ Test Setup Complete!"
        alert.informativeText = """
        All 4 Spaces have been registered with colored overlays.
        
        NOW VERIFY:
        Switch between your Spaces and check:
        
        Space 1 should show: Blue tint
        Space 2 should show: Green tint
        Space 3 should show: Purple tint
        Space 4 should show: Orange tint
        
        TEST RESULTS:
        ✅ PASS: Each Space shows ONLY its own color
        ❌ FAIL: All colors appear on all Spaces
        
        The overlays will remain until you click "Cleanup Test"
        or restart the app.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cleanup Test Now")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            cleanupTest()
        }
        
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 TEST COMPLETE - Switch between Spaces to verify")
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    /**
     Cleans up all test overlays.
     */
    func cleanupTest() {
        print("🧹 Cleaning up test overlays...")
        
        for (index, overlay) in testOverlays {
            overlay.close()
            print("  Removed overlay for Space \(index + 1)")
        }
        
        testOverlays.removeAll()
        currentRegistrationStep = 0
        
        print("✅ Test cleanup complete")
    }
    
    // ================================================================
    // MARK: - Helpers
    // ================================================================
    
    private func getColorName(for index: Int) -> String {
        switch index {
        case 0: return "Blue"
        case 1: return "Green"
        case 2: return "Purple"
        case 3: return "Orange"
        default: return "Unknown"
        }
    }
}

// ====================================================================
// MARK: - Test Space Overlay Window
// ====================================================================

/**
 A simple colored overlay for testing Space-specific behavior.
 
 This is a minimal implementation to test the core concept:
 - Does removing canJoinAllSpaces pin the window to one Space?
 - Can we create different overlays on different Spaces?
 */
final class TestSpaceOverlay: NSWindow {
    
    let spaceIndex: Int
    let color: NSColor
    
    init(spaceIndex: Int, color: NSColor, screen: NSScreen) {
        self.spaceIndex = spaceIndex
        self.color = color
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        configure()
        setupView()
    }
    
    /**
     Configures the window for Space-specific overlay behavior.
     
     CRITICAL TEST: We remove .canJoinAllSpaces here.
     This should pin the window to the Space where it was created.
     */
    private func configure() {
        // Make transparent and click-through
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        
        // Set level below windows but above wallpaper
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        
        // CRITICAL: Remove canJoinAllSpaces to pin to this Space
        self.collectionBehavior = [
            // .canJoinAllSpaces ← NOT INCLUDED! This is the test!
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        
        // Don't hide on deactivate
        self.hidesOnDeactivate = false
        
        print("🔧 Configured overlay for Space \(spaceIndex + 1) - canJoinAllSpaces: REMOVED")
    }
    
    /**
     Creates the colored view with a label.
     */
    private func setupView() {
        let view = NSView(frame: self.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        
        // Set the background color
        view.layer?.backgroundColor = color.cgColor
        
        // Add a label showing which Space this is
        let label = NSTextField(labelWithString: "Space \(spaceIndex + 1) - Test Overlay")
        label.font = NSFont.systemFont(ofSize: 48, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(
            x: 0,
            y: (view.bounds.height - 60) / 2,
            width: view.bounds.width,
            height: 60
        )
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        
        // Add shadow to label for visibility
        label.shadow = NSShadow()
        label.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.8)
        label.shadow?.shadowOffset = NSSize(width: 0, height: -2)
        label.shadow?.shadowBlurRadius = 4
        
        view.addSubview(label)
        
        self.contentView = view
        
        print("🎨 Created \(getColorName()) overlay for Space \(spaceIndex + 1)")
    }
    
    private func getColorName() -> String {
        if color.isEqual(NSColor.systemBlue.withAlphaComponent(0.15)) {
            return "Blue"
        } else if color.isEqual(NSColor.systemGreen.withAlphaComponent(0.15)) {
            return "Green"
        } else if color.isEqual(NSColor.systemPurple.withAlphaComponent(0.15)) {
            return "Purple"
        } else if color.isEqual(NSColor.systemOrange.withAlphaComponent(0.15)) {
            return "Orange"
        }
        return "Unknown"
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// ====================================================================
// MARK: - SwiftUI Test View (Optional)
// ====================================================================

/**
 SwiftUI view for triggering the test from Preferences.
 
 Add this to your Preferences window to make testing easy.
 */
struct SpaceOverlayTestView: View {
    @State private var testRunning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🧪 Space Overlay Test")
                .font(.headline)
            
            Text("Test whether we can create Space-specific overlays by removing canJoinAllSpaces.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("What this test does:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("• Creates 4 colored overlays (blue, green, purple, orange)")
                    .font(.caption)
                Text("• You register each Space manually")
                    .font(.caption)
                Text("• Each overlay should stay on its registered Space")
                    .font(.caption)
                Text("• Switch between Spaces to verify")
                    .font(.caption)
            }
            .padding(.leading, 8)
            
            Divider()
            
            HStack {
                Button("Run Test") {
                    SpaceOverlayTest.shared.runTest()
                    testRunning = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Cleanup Test") {
                    SpaceOverlayTest.shared.cleanupTest()
                    testRunning = false
                }
                .buttonStyle(.bordered)
                .disabled(!testRunning)
            }
            
            Text("⚠️ This is a proof-of-concept test only")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding()
        .frame(maxWidth: 500)
    }
}

// ====================================================================
// MARK: - Preview
// ====================================================================

#Preview {
    SpaceOverlayTestView()
}
