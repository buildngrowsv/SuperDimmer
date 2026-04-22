/**
 ====================================================================
 EquidistantSpreadService.swift
 Pro feature: "Spread Windows Evenly" — deterministic window organizer
 ====================================================================

 PURPOSE (the lead, not buried)
 ------------------------------
 Ships the Equidistant Drift algorithm as a one-click menu action in
 SuperDimmer. When the user clicks "Spread Windows Evenly", every
 visible window on the current display is redistributed to concentric
 rectangular "orbits" around the screen center:

   - 4% margin from screen edges (outer orbit = spread bounds)
   - Outer orbit has 12 perimeter positions (4 corners + 8 edge points)
   - Inner orbits scaled to 0.6× and 0.3× of bounds when more windows
   - ONE window always lands at exact screen center (when N ≥ 2)
   - Assignment by global greedy + 2-opt local search → each window goes
     to its TRULY NEAREST orbit position, minimizing total movement
   - Windows stay in their general area; clusters fan to adjacent
     perimeter positions only when conflicts force it

 WHY THIS IS A SEPARATE SERVICE (not part of dimming pipeline)
 -------------------------------------------------------------
 Dimming is a continuous background process (scan → analyze → apply
 overlays every ~33ms). Window spreading is a one-shot user-triggered
 action. Keeping them in separate services means:
   - Spread runs don't interfere with dimming's tight timing budget
   - The feature can be Pro-gated without touching dimming paths
   - Failures in spread can't cascade into dimming (critical path)
   - The algorithm mirrors the standalone test harness in
     tools/equidistant-drift/equidistant_spread.swift for easy debug

 WHY THE ALGORITHM IS WHAT IT IS
 -------------------------------
 The algorithm evolved through 8 iterations based on live user feedback:
   v0.1-v0.3: uniform grid cells → corners stayed empty
   v0.4 (size-proportional rows + edge anchor): corners filled, but
     smaller windows got disproportionate space
   v0.5 (concentric orbits, rank-based t-assignment): corners filled,
     but windows rotated across screen instead of staying relative
   v0.6 (orbits + center always): center preserved
   v0.7 (global greedy across all orbits, not per-orbit): no more
     across-screen rotations
   v0.8 (+ 2-opt local search): eliminates the greedy worst-case where
     one window could make a huge move because its first-choice spot
     was taken by an even-closer window

 AX PERMISSION (permissions UX note)
 -----------------------------------
 This service REQUIRES Accessibility permission (same as all window
 moves on macOS). The app already requires it for dimming overlay
 management, so most users have already granted it. We still re-check
 explicitly before each run because:
   - Permission can be revoked in System Settings at any time
   - If the user hasn't granted (e.g. new install, just opened menu),
     we bail with a friendly "Grant Accessibility" prompt instead of
     silently failing 30 AX calls.

 PRO GATE
 --------
 Routed through FeatureGateService.shared.checkAccess(feature:).
 Free tier: no access (shows upgrade prompt).
 Trial / Pro: access granted.

 ====================================================================
 Created: 2026-04-20 (v1.0.8)
 Algorithm reference: EQUIDISTANT-DRIFT-SPEC.md v0.8 in parent docs repo
 Test harness: tools/equidistant-drift/equidistant_spread.swift
 ====================================================================
 */

import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

// ====================================================================
// MARK: - Private AX API note
// ====================================================================

/*
 This service uses _AXUIElementGetWindow (declared in
 AutoMinimizeManager.swift via @_silgen_name) to resolve CGWindowID →
 AXUIElement unambiguously. _AXUIElementGetWindow is a private Apple
 API stable since macOS 10.6; every serious macOS window manager
 (Rectangle, Magnet, Hammerspoon, yabai, AeroSpace) uses it for the
 same reason: the public API doesn't expose this mapping, and
 frame-matching fallback fails when multiple same-app windows pile up
 at identical coordinates (common in the middle of spread operations).
 */

// ====================================================================
// MARK: - Configuration
// ====================================================================

/*
 Spread parameters. Values were tuned on a 6720×3780 (8K) display and
 verified to degrade gracefully down to typical laptop displays
 (1440×900). User-configurable via SettingsManager.
 */
struct EquidistantSpreadConfig {
    /// Anchor windows currently flush to screen edges/corners — they
    /// stay put and the spread works around them. User setting.
    var anchorEdges: Bool = false

    /// Percent of visibleFrame to inset spread bounds on each side.
    /// 4% means leftmost window's left edge sits exactly at 4% of
    /// screen width from the left wall. Tuned empirically.
    var marginPercent: CGFloat = 4.0

    /// Edge-detection threshold for --anchor-edges.
    var edgeAnchorThresholdPx: CGFloat = 16

    /// Bundle IDs always excluded (recording/call apps).
    /// Merged with user's excludedAppBundleIDs from SettingsManager.
    var extraExcludeBundleIds: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.SystemUIServer",
        "com.apple.WindowManager",
        "com.superdimmer.app",          // never move ourselves
        "us.zoom.xos",
        "com.google.meet",
        "com.microsoft.teams2",
    ]

    /// App names always excluded (for apps without reliable bundle IDs).
    var extraExcludeAppNames: Set<String> = [
        "OBS Studio", "Loom", "Screen Studio", "QuickTime Player",
        "FaceTime", "zoom.us", "CleanShot X",
        "Notification Center", "CursorUIViewService",
    ]

    /// Per-move AX settle delay. 80ms gives Electron apps + Terminal
    /// char-grid enough time to acknowledge the AX write before we
    /// verify. Tuned during the spec's v0.5 "drift bug" investigation.
    var settleMs: Int = 80

    /// Max retry count when a window drifts off its target after
    /// AX write (usually due to app-enforced min-size constraints).
    var retryOnDrift: Int = 1

    /// Drift tolerance for pixel-perfect verification (below this, OK).
    var driftThresholdPx: CGFloat = 6
}

// ====================================================================
// MARK: - Errors
// ====================================================================

enum EquidistantSpreadError: LocalizedError {
    case accessibilityPermissionMissing
    case proFeatureNotUnlocked
    case noScreen
    case noMovableWindows

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "SuperDimmer needs Accessibility permission to move windows. Open System Settings → Privacy & Security → Accessibility, add SuperDimmer, and try again."
        case .proFeatureNotUnlocked:
            return "Spread Windows Evenly is a Pro feature. Start your trial or upgrade to unlock it."
        case .noScreen:
            return "Couldn't read screen information. Try again or restart SuperDimmer."
        case .noMovableWindows:
            return "No movable windows found on the current screen (everything is excluded or floating)."
        }
    }
}

// ====================================================================
// MARK: - Service
// ====================================================================

/**
 Service that spreads every visible window on the current screen into
 equidistant orbit positions in one user-triggered action.

 Call sites:
   - MenuBarView "Spread Windows Evenly" button (primary)
   - AppleScript / shortcut integration (future)
   - Idle-drift daemon (Phase 2 — not yet implemented, see
     EQUIDISTANT-DRIFT-SPEC.md §10 roadmap)
 */
final class EquidistantSpreadService {

    static let shared = EquidistantSpreadService()
    private init() {}

    // ================================================================
    // MARK: - Public API
    // ================================================================

    /**
     Spread every movable window on the primary screen to equidistant
     orbit positions. Blocks the calling thread for ~1-5 seconds (depends
     on window count × settle time). Call from a background queue for UX.

     Feature-gated: throws .proFeatureNotUnlocked if the user is on the
     free tier. Permission-gated: throws .accessibilityPermissionMissing
     if AX permission wasn't granted.

     - Parameter config: spread parameters (default = marginPercent 4%, no anchor-edges)
     - Returns: (windowsMoved, windowsDrifted) counts for UI feedback
     - Throws: EquidistantSpreadError
     */
    @discardableResult
    func spread(config: EquidistantSpreadConfig = EquidistantSpreadConfig()) throws -> (moved: Int, drifted: Int) {

        // Pro gate first — cheap check, avoids any work if user isn't entitled.
        guard FeatureGateService.shared.checkAccess(feature: "equidistantSpread",
                                                     showUpgradeIfNeeded: false) else {
            throw EquidistantSpreadError.proFeatureNotUnlocked
        }

        // AX permission check. Same check PermissionManager exposes but we
        // don't want to prompt-during-spread (jarring); caller is expected
        // to have prompted already. If missing, bail with a clear error.
        guard AXIsProcessTrusted() else {
            throw EquidistantSpreadError.accessibilityPermissionMissing
        }

        // Screen / visibleFrame. Spread operates on the screen containing
        // the menu bar (primary) for now. Multi-display spread is §11
        // roadmap in the spec.
        guard let screen = NSScreen.screens.first else {
            throw EquidistantSpreadError.noScreen
        }
        let vf = cocoaToQuartz(screen.visibleFrame)

        // Enumerate candidate windows.
        let candidates = enumerateCandidates(vf: vf, edgeThreshold: config.edgeAnchorThresholdPx)
        let partition = filterCandidates(candidates, config: config)
        guard !partition.free.isEmpty else {
            throw EquidistantSpreadError.noMovableWindows
        }

        AppLogger.tracking.info("EquidistantSpread: N free=\(partition.free.count), anchored=\(partition.anchored.count), excluded=\(partition.excluded.count)")

        // Spread bounds: optionally shrunk for anchors.
        let marginX = vf.size.width  * config.marginPercent / 100.0
        let marginY = vf.size.height * config.marginPercent / 100.0
        let bounds = CGRect(
            x: vf.origin.x + marginX,
            y: vf.origin.y + marginY,
            width:  vf.size.width  - 2 * marginX,
            height: vf.size.height - 2 * marginY
        )

        // Compute target positions via orbit algorithm (v0.8).
        let assignments = computeAssignments(free: partition.free, bounds: bounds)

        // Apply moves with AX, snap mode + verify + retry.
        let result = applyAssignments(assignments, config: config)
        AppLogger.tracking.info("EquidistantSpread: applied moved=\(result.moved) drifted=\(result.drifted)")
        return result
    }

    // ================================================================
    // MARK: - Coordinate helpers
    // ================================================================

    /*
     Spread engine operates in Quartz (top-left origin) coordinates — same
     as CGWindowList and AXPosition. NSScreen reports Cocoa (bottom-left
     origin). Convert once at the boundary.
     */
    private func cocoaToQuartz(_ r: NSRect) -> CGRect {
        let H = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: r.origin.x,
            y: H - r.origin.y - r.height,
            width: r.size.width,
            height: r.size.height
        )
    }

    // ================================================================
    // MARK: - Candidate enumeration
    // ================================================================

    fileprivate struct Candidate {
        let windowId: CGWindowID
        let ownerPid: pid_t
        let ownerName: String
        let bundleId: String?
        let frame: CGRect       // Quartz coords
        let layer: Int
        let isFloating: Bool
        var edges: [String] = []
        var corner: String?
    }

    /*
     Snapshot live windows via CGWindowList. Minimal fields (no title/URL
     capture — this service doesn't need them; it only reads geometry).
     */
    private func enumerateCandidates(vf: CGRect, edgeThreshold: CGFloat) -> [Candidate] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        // PID → bundle ID / name map (snapshot once to avoid per-window
        // iteration — same perf lesson from WindowTrackerService).
        var appMeta: [pid_t: (bundleId: String?, name: String?)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appMeta[app.processIdentifier] = (app.bundleIdentifier, app.localizedName)
        }

        var out: [Candidate] = []
        for info in list {
            guard let wid = info[kCGWindowNumber] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID] as? pid_t,
                  let owner = info[kCGWindowOwnerName] as? String,
                  let layer = info[kCGWindowLayer] as? Int,
                  let b = info[kCGWindowBounds] as? [String: CGFloat] else { continue }
            let frame = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                               width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            // Sanity floor: tiny system overlays, popovers, etc.
            if frame.width < 100 || frame.height < 80 { continue }
            let meta = appMeta[pid]
            var c = Candidate(
                windowId: wid, ownerPid: pid, ownerName: owner,
                bundleId: meta?.bundleId,
                frame: frame, layer: layer,
                isFloating: layer > 0
            )
            annotateEdges(&c, vf: vf, edgeThreshold: edgeThreshold)
            out.append(c)
        }
        return out
    }

    private func annotateEdges(_ c: inout Candidate, vf: CGRect, edgeThreshold: CGFloat) {
        let dTop    = c.frame.origin.y - vf.origin.y
        let dLeft   = c.frame.origin.x - vf.origin.x
        let dRight  = (vf.origin.x + vf.size.width)  - (c.frame.origin.x + c.frame.size.width)
        let dBottom = (vf.origin.y + vf.size.height) - (c.frame.origin.y + c.frame.size.height)
        var edges: [String] = []
        if dTop    <= edgeThreshold { edges.append("top") }
        if dRight  <= edgeThreshold { edges.append("right") }
        if dBottom <= edgeThreshold { edges.append("bottom") }
        if dLeft   <= edgeThreshold { edges.append("left") }
        c.edges = edges
        let ct = edgeThreshold * 2
        if dTop <= ct && dLeft <= ct { c.corner = "top-left" }
        else if dTop <= ct && dRight <= ct { c.corner = "top-right" }
        else if dBottom <= ct && dLeft <= ct { c.corner = "bottom-left" }
        else if dBottom <= ct && dRight <= ct { c.corner = "bottom-right" }
    }

    // ================================================================
    // MARK: - Filtering
    // ================================================================

    fileprivate struct Partition {
        var free: [Candidate] = []
        var anchored: [Candidate] = []
        var excluded: [Candidate] = []
    }

    private func filterCandidates(_ cs: [Candidate], config: EquidistantSpreadConfig) -> Partition {
        // Merge CLI-equivalent extra exclusions with the user's existing
        // SettingsManager.excludedAppBundleIDs so both the dimming exclusions
        // and the spread exclusions share one UI affordance.
        let userExcluded = Set(SettingsManager.shared.excludedAppBundleIDs)
        let excludeBundleIds = config.extraExcludeBundleIds.union(userExcluded)
        let excludeAppNames = config.extraExcludeAppNames

        var p = Partition()
        for c in cs {
            if c.isFloating {
                // Floating windows (layer > 0) are typically utility/system
                // overlays — Magnet panels, Stickies, etc. Always leaveAlone.
                p.excluded.append(c)
                continue
            }
            if let bid = c.bundleId, excludeBundleIds.contains(bid) {
                p.excluded.append(c); continue
            }
            if excludeAppNames.contains(c.ownerName) {
                p.excluded.append(c); continue
            }
            if config.anchorEdges, c.corner != nil || !c.edges.isEmpty {
                p.anchored.append(c); continue
            }
            p.free.append(c)
        }
        return p
    }

    // ================================================================
    // MARK: - Orbit algorithm (v0.8)
    // ================================================================

    /*
     Compute orbit definitions. Always reserve ONE center position when
     N ≥ 2 so the window closest to screen center stays there.
     */
    fileprivate struct OrbitDef {
        let rect: CGRect
        let capacity: Int
    }

    private func computeOrbits(N: Int, bounds: CGRect) -> [OrbitDef] {
        if N <= 0 { return [] }
        let centerRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        let center = OrbitDef(rect: centerRect, capacity: 1)
        if N == 1 { return [center] }
        let remaining = N - 1
        if remaining <= 12 {
            return [OrbitDef(rect: bounds, capacity: remaining), center]
        }
        let innerRect = scaleRectAroundCenter(bounds, scale: 0.6)
        if remaining <= 24 {
            return [
                OrbitDef(rect: bounds,    capacity: 12),
                OrbitDef(rect: innerRect, capacity: remaining - 12),
                center
            ]
        }
        let innermostRect = scaleRectAroundCenter(bounds, scale: 0.3)
        return [
            OrbitDef(rect: bounds,        capacity: 12),
            OrbitDef(rect: innerRect,     capacity: 12),
            OrbitDef(rect: innermostRect, capacity: remaining - 24),
            center
        ]
    }

    private func scaleRectAroundCenter(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let w = rect.size.width  * scale
        let h = rect.size.height * scale
        return CGRect(x: rect.midX - w/2, y: rect.midY - h/2, width: w, height: h)
    }

    /*
     Compute equidistant perimeter positions around a rectangle. t=0 is
     top-left, going clockwise. At capacities 4, 8, 12 positions
     naturally include the 4 corners.
     */
    private func computeOrbitPositions(rect: CGRect, count: Int) -> [CGPoint] {
        if count <= 0 { return [] }
        if count == 1 { return [CGPoint(x: rect.midX, y: rect.midY)] }
        return (0..<count).map { i in perimeterPoint(rect: rect, t: Double(i) / Double(count)) }
    }

    private func perimeterPoint(rect: CGRect, t: Double) -> CGPoint {
        var s = t.truncatingRemainder(dividingBy: 1.0)
        if s < 0 { s += 1.0 }
        let x: CGFloat, y: CGFloat
        if s < 0.25 {
            let r = CGFloat(s / 0.25); x = rect.minX + r * rect.size.width; y = rect.minY
        } else if s < 0.5 {
            let r = CGFloat((s - 0.25) / 0.25); x = rect.maxX; y = rect.minY + r * rect.size.height
        } else if s < 0.75 {
            let r = CGFloat((s - 0.5) / 0.25); x = rect.maxX - r * rect.size.width; y = rect.maxY
        } else {
            let r = CGFloat((s - 0.75) / 0.25); x = rect.minX; y = rect.maxY - r * rect.size.height
        }
        return CGPoint(x: x, y: y)
    }

    /*
     Main assignment: global greedy (smallest Euclidean pair first across
     ALL orbits) + 2-opt local search. See header comment for why each
     piece exists and which bug it fixes.
     */
    private func computeAssignments(free: [Candidate], bounds: CGRect) -> [(candidate: Candidate, target: CGRect)] {
        let N = free.count
        let orbits = computeOrbits(N: N, bounds: bounds)
        var allPositions: [CGPoint] = []
        for orbit in orbits {
            allPositions.append(contentsOf: computeOrbitPositions(rect: orbit.rect, count: orbit.capacity))
        }

        // All (window, position) pairs with Euclidean distance, sorted asc.
        struct Pair { let widx: Int; let pidx: Int; let dist: Double }
        var pairs: [Pair] = []
        pairs.reserveCapacity(N * allPositions.count)
        for (widx, w) in free.enumerated() {
            let wx = Double(w.frame.midX)
            let wy = Double(w.frame.midY)
            for (pidx, pos) in allPositions.enumerated() {
                let dx = wx - Double(pos.x)
                let dy = wy - Double(pos.y)
                pairs.append(Pair(widx: widx, pidx: pidx, dist: (dx*dx + dy*dy).squareRoot()))
            }
        }
        pairs.sort { $0.dist < $1.dist }

        // Greedy claim.
        var windowAssigned = Array(repeating: false, count: N)
        var positionTaken  = Array(repeating: false, count: allPositions.count)
        var slotMap: [Int: Int] = [:]
        var remaining = N
        for p in pairs {
            if remaining == 0 { break }
            if windowAssigned[p.widx] || positionTaken[p.pidx] { continue }
            slotMap[p.widx] = p.pidx
            windowAssigned[p.widx] = true
            positionTaken[p.pidx] = true
            remaining -= 1
        }

        // 2-opt local search: swap any pair that would reduce total cost.
        // Critical for eliminating the greedy worst-case (a window making
        // a huge move because its preferred spot was taken by a closer one).
        func dist(_ widx: Int, _ pidx: Int) -> Double {
            let w = free[widx]
            let pos = allPositions[pidx]
            let dx = Double(w.frame.midX) - Double(pos.x)
            let dy = Double(w.frame.midY) - Double(pos.y)
            return (dx*dx + dy*dy).squareRoot()
        }
        let assigned = Array(slotMap.keys)
        let maxIters = 10
        let epsilon = 0.5
        for _ in 0..<maxIters {
            var improved = false
            for i in 0..<assigned.count {
                let w1 = assigned[i]; guard let p1 = slotMap[w1] else { continue }
                for j in (i+1)..<assigned.count {
                    let w2 = assigned[j]; guard let p2 = slotMap[w2] else { continue }
                    let cur  = dist(w1, p1) + dist(w2, p2)
                    let swap = dist(w1, p2) + dist(w2, p1)
                    if swap + epsilon < cur {
                        slotMap[w1] = p2; slotMap[w2] = p1; improved = true
                    }
                }
            }
            if !improved { break }
        }

        // Build (candidate, target) pairs.
        var out: [(candidate: Candidate, target: CGRect)] = []
        for (widx, c) in free.enumerated() {
            guard let pidx = slotMap[widx] else { continue }
            let pos = allPositions[pidx]
            let target = CGRect(
                x: pos.x - c.frame.size.width / 2,
                y: pos.y - c.frame.size.height / 2,
                width: c.frame.size.width,
                height: c.frame.size.height
            )
            out.append((c, target))
        }
        return out
    }

    // ================================================================
    // MARK: - AX mover (snap mode with verify + retry)
    // ================================================================

    /*
     Apply moves using the AX API. Uses _AXUIElementGetWindow for reliable
     CGWindowID → AXUIElement resolution (no frame-matching guesswork —
     the public API doesn't support this mapping so the private function
     is the only option for pile-ups).

     Snap mode (sequential final-set + settle-wait + read-back verify)
     is MUCH more reliable than animated mode for bulk moves because it
     avoids races against apps' internal resize handlers. Cursor
     (Electron), Terminal (char-grid snap), and Chrome all silently
     overrode AX positions during the animated tick loop in the
     standalone harness. Snap fixed it.
     */
    private func applyAssignments(
        _ assignments: [(candidate: Candidate, target: CGRect)],
        config: EquidistantSpreadConfig
    ) -> (moved: Int, drifted: Int) {
        var moved = 0
        var drifted = 0
        let vf = cocoaToQuartz(NSScreen.screens.first?.visibleFrame ?? .zero)

        for (c, targetRaw) in assignments {
            let target = clampToVisibleFrame(targetRaw, vf: vf)
            guard let axWin = resolveAXWindow(forWindowId: c.windowId, pid: c.ownerPid) else {
                AppLogger.tracking.warning("EquidistantSpread: AX resolve failed for #\(c.windowId) \(c.ownerName)")
                continue
            }
            var attempt = 0
            var lastDrift: CGFloat = 0
            while attempt <= config.retryOnDrift {
                setAXPosition(axWin, target.origin)
                setAXSize(axWin, target.size)
                // Some apps need another position write after size change
                // (they re-anchor during resize). Cheap insurance, same
                // pattern as the test harness.
                setAXPosition(axWin, target.origin)

                Thread.sleep(forTimeInterval: Double(config.settleMs) / 1000.0)

                if let actual = readAXFrame(axWin) {
                    let d = maxDriftPx(actual, target)
                    lastDrift = d
                    if d <= config.driftThresholdPx {
                        moved += 1
                        break
                    }
                }
                attempt += 1
            }
            if lastDrift > config.driftThresholdPx {
                drifted += 1
            }
        }
        return (moved, drifted)
    }

    // Clamp a target rect so it fits inside visibleFrame (prevents
    // windows disappearing off-screen when their orbit position plus
    // window size would land past the edge).
    private func clampToVisibleFrame(_ rect: CGRect, vf: CGRect) -> CGRect {
        var r = rect
        r.size.width  = min(r.size.width,  vf.size.width)
        r.size.height = min(r.size.height, vf.size.height)
        if r.origin.x < vf.origin.x { r.origin.x = vf.origin.x }
        if r.origin.y < vf.origin.y { r.origin.y = vf.origin.y }
        if r.maxX > vf.maxX { r.origin.x = vf.maxX - r.size.width }
        if r.maxY > vf.maxY { r.origin.y = vf.maxY - r.size.height }
        return r
    }

    private func resolveAXWindow(forWindowId wid: CGWindowID, pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        var winsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &winsRef)
        guard err == .success, let winsRef = winsRef,
              let axWindows = winsRef as? [AXUIElement] else { return nil }
        for axWin in axWindows {
            var axWid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &axWid) == .success, axWid == wid {
                return axWin
            }
        }
        return nil
    }

    @discardableResult
    private func setAXPosition(_ axWin: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    private func setAXSize(_ axWin: AXUIElement, _ s: CGSize) -> Bool {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, v) == .success
    }

    private func readAXFrame(_ axWin: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let posRef = posRef {
            AXValueGetValue(unsafeBitCast(posRef, to: AXValue.self), .cgPoint, &pos)
        }
        if let sizeRef = sizeRef {
            AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size)
        }
        if size.width == 0 && size.height == 0 { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func maxDriftPx(_ a: CGRect, _ b: CGRect) -> CGFloat {
        return max(
            abs(a.origin.x - b.origin.x),
            abs(a.origin.y - b.origin.y),
            abs(a.size.width - b.size.width),
            abs(a.size.height - b.size.height)
        )
    }
}
