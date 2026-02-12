#!/usr/bin/env swift

// RegionSelector.swift — Multi-Monitor Region Selector + Persistent Draggable Frame
//
// FLOW:
//   Phase 1: Dark overlay on all monitors. Drag to select region. Saves region.json.
//   Phase 2: Overlay closes. A persistent, interactive frame stays:
//            - Drag the border to MOVE the frame
//            - Drag corner/edge handles to RESIZE (crop from any side)
//            - Interior is CLICK-THROUGH (use apps underneath)
//            - ✕ button or ESC to close
//            - region.json updates LIVE on every move/resize
//
// Compile: swiftc RegionSelector.swift -framework Cocoa -o RegionSelector
// Run:     ./RegionSelector
//
// COORDINATES:
//   Cocoa:         bottom-left origin, Y up
//   screencapture: top-left origin,    Y down
//   sc_y = primaryHeight - cocoa_y - height

import Cocoa

// ═══════════════════════════════════════════════════════════════
// MARK: - Data Model
// ═══════════════════════════════════════════════════════════════

struct RegionFile: Codable {
    struct Region: Codable { let x: Int; let y: Int; let width: Int; let height: Int }
    struct DisplayInfo: Codable {
        let displayID: UInt32; let localizedName: String
        let frameOriginX: Double; let frameOriginY: Double
        let frameWidth: Double; let frameHeight: Double
        let backingScaleFactor: Double
    }
    let region: Region; let displayInfo: DisplayInfo
    let updatedAt: String; let source: String
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Coordinate Helpers
// ═══════════════════════════════════════════════════════════════

/// Convert a Cocoa-global rect to screencapture coordinates.
func cocoaToScreencapture(_ rect: NSRect) -> (x: Int, y: Int, w: Int, h: Int) {
    let primaryH = NSScreen.screens.first?.frame.height ?? rect.height
    let x = Int(round(rect.origin.x))
    let y = Int(round(primaryH - rect.origin.y - rect.height))
    return (x, y, Int(round(rect.width)), Int(round(rect.height)))
}

/// Find which screen contains the center of a rect.
func screenContaining(_ rect: NSRect) -> (screen: NSScreen, index: Int) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    for (i, screen) in NSScreen.screens.enumerated() {
        if screen.frame.contains(center) { return (screen, i) }
    }
    return (NSScreen.screens[0], 0)
}

/// Save region.json from a Cocoa-global rect.
func saveRegionJSON(cocoaRect: NSRect) {
    let sc = cocoaToScreencapture(cocoaRect)
    let (screen, idx) = screenContaining(cocoaRect)
    let did = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    var dname = "Display \(idx + 1)"
    if #available(macOS 10.15, *) { dname = screen.localizedName }
    let sf = screen.frame

    let data = RegionFile(
        region: RegionFile.Region(x: sc.x, y: sc.y, width: sc.w, height: sc.h),
        displayInfo: RegionFile.DisplayInfo(
            displayID: did, localizedName: dname,
            frameOriginX: Double(sf.origin.x), frameOriginY: Double(sf.origin.y),
            frameWidth: Double(sf.width), frameHeight: Double(sf.height),
            backingScaleFactor: Double(screen.backingScaleFactor)),
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        source: "overlay"
    )

    let configDir = NSHomeDirectory() + "/.screeninspect"
    let regionFile = configDir + "/region.json"
    let fm = FileManager.default
    if !fm.fileExists(atPath: configDir) {
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    }
    do {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(data).write(to: URL(fileURLWithPath: regionFile))
    } catch {
        fputs("ERROR: region.json write failed: \(error)\n", stderr)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Phase 1: Full-Screen Selection Overlay
// ═══════════════════════════════════════════════════════════════

class SelectionOverlayView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    var selectionRect: NSRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(c.x - s.x), height: abs(c.y - s.y))
    }
    var onSelectionComplete: ((NSRect) -> Void)?
    var displayLabel: String = ""

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.3).setFill(); bounds.fill()

        if let rect = selectionRect, rect.width > 2, rect.height > 2 {
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill(); rect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSColor.systemCyan.setStroke()
            let border = NSBezierPath(rect: rect); border.lineWidth = 2; border.stroke()

            let hs: CGFloat = 8; NSColor.white.setFill(); NSColor.systemCyan.setStroke()
            for c in [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                       NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)] {
                let p = NSBezierPath(ovalIn: NSRect(x: c.x-hs/2, y: c.y-hs/2, width: hs, height: hs))
                p.fill(); p.lineWidth = 1.5; p.stroke()
            }

            let dimText = "\(Int(rect.width)) \u{00D7} \(Int(rect.height))"
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white ]
            let dimSize = (dimText as NSString).size(withAttributes: dimAttrs)
            let pad: CGFloat = 6
            let pillRect = NSRect(x: rect.midX - dimSize.width/2 - pad, y: rect.maxY + 6,
                                  width: dimSize.width + pad*2, height: dimSize.height + pad)
            NSColor(white: 0, alpha: 0.75).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()
            (dimText as NSString).draw(at: NSPoint(x: pillRect.origin.x + pad, y: pillRect.origin.y + pad/2),
                                       withAttributes: dimAttrs)
        }

        let instr = "Drag to select a region \u{00B7} ESC to cancel"
        let instrAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85) ]
        let s = (instr as NSString).size(withAttributes: instrAttrs)
        (instr as NSString).draw(at: NSPoint(x: bounds.midX - s.width/2, y: bounds.height - 50),
                                  withAttributes: instrAttrs)

        if !displayLabel.isEmpty {
            let a: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.4) ]
            (displayLabel as NSString).draw(at: NSPoint(x: 12, y: 12), withAttributes: a)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil); dragCurrent = dragStart; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        if let r = selectionRect, r.width > 5, r.height > 5 { onSelectionComplete?(r) }
        else { dragStart = nil; dragCurrent = nil; needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApplication.shared.terminate(nil) }
    }
    override var acceptsFirstResponder: Bool { true }
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    init(for screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver; isOpaque = false; backgroundColor = .clear
        hasShadow = false; ignoresMouseEvents = false; acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Phase 2: Interactive Persistent Frame
// ═══════════════════════════════════════════════════════════════

/// Which part of the frame the user is interacting with.
enum HandleZone {
    case none
    case move          // drag the border band to move
    case topLeft, topRight, bottomLeft, bottomRight  // corner resize
    case top, bottom, left, right                    // edge resize
}

/// The view that draws the frame border + handles and processes
/// all drag interactions (move, resize from corners/edges).
/// The INTERIOR is transparent and click-through.
class FrameBorderView: NSView {
    /// Thickness of the draggable border band (points)
    let band: CGFloat = 6
    /// Size of corner/edge handle hit targets
    let handleHit: CGFloat = 14
    /// Size of visual handle circles
    let handleVis: CGFloat = 8

    /// Current interaction
    private var zone: HandleZone = .none
    private var dragAnchor: NSPoint = .zero
    private var dragOrigFrame: NSRect = .zero  // window frame at drag start

    /// Called after every move/resize so the window can reposition and save.
    var onFrameChanged: ((NSRect) -> Void)?
    var onCloseRequest: (() -> Void)?

    // The region rect in window-local coords (the clear interior)
    var regionInset: NSRect {
        bounds.insetBy(dx: band, dy: band)
    }

    // ── Drawing ──

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds
        let inner = regionInset

        // Draw the border band (the area between outer and inner)
        let borderColor = NSColor.systemCyan.withAlphaComponent(0.55)
        borderColor.setFill()

        // Top band
        NSRect(x: outer.minX, y: inner.maxY, width: outer.width, height: band).fill()
        // Bottom band
        NSRect(x: outer.minX, y: outer.minY, width: outer.width, height: band).fill()
        // Left band
        NSRect(x: outer.minX, y: inner.minY, width: band, height: inner.height).fill()
        // Right band
        NSRect(x: inner.maxX, y: inner.minY, width: band, height: inner.height).fill()

        // Thin bright edge on inner boundary
        let edgePath = NSBezierPath(rect: inner)
        edgePath.lineWidth = 1.0
        NSColor.systemCyan.withAlphaComponent(0.9).setStroke()
        edgePath.stroke()

        // Corner handles (visual circles)
        let corners: [(NSPoint, HandleZone)] = [
            (NSPoint(x: inner.minX, y: inner.minY), .bottomLeft),
            (NSPoint(x: inner.maxX, y: inner.minY), .bottomRight),
            (NSPoint(x: inner.minX, y: inner.maxY), .topLeft),
            (NSPoint(x: inner.maxX, y: inner.maxY), .topRight),
        ]
        for (pt, _) in corners {
            let r = NSRect(x: pt.x - handleVis/2, y: pt.y - handleVis/2, width: handleVis, height: handleVis)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.systemCyan.setStroke()
            let p = NSBezierPath(ovalIn: r); p.lineWidth = 1.5; p.stroke()
        }

        // Edge midpoint handles
        let edges: [(NSPoint, HandleZone)] = [
            (NSPoint(x: inner.midX, y: inner.maxY), .top),
            (NSPoint(x: inner.midX, y: inner.minY), .bottom),
            (NSPoint(x: inner.minX, y: inner.midY), .left),
            (NSPoint(x: inner.maxX, y: inner.midY), .right),
        ]
        for (pt, _) in edges {
            let r = NSRect(x: pt.x - handleVis/2, y: pt.y - handleVis/2, width: handleVis, height: handleVis)
            NSColor.white.withAlphaComponent(0.7).setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.systemCyan.withAlphaComponent(0.6).setStroke()
            let p = NSBezierPath(ovalIn: r); p.lineWidth = 1; p.stroke()
        }

        // Dimension label at bottom center
        let sc = cocoaToScreencapture(window?.frame.insetBy(dx: band, dy: band) ?? inner)
        let label = "\(sc.w) \u{00D7} \(sc.h)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white ]
        let ls = (label as NSString).size(withAttributes: attrs)
        let lpad: CGFloat = 4
        let pillR = NSRect(x: bounds.midX - ls.width/2 - lpad, y: 0,
                           width: ls.width + lpad*2, height: ls.height + lpad)
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: pillR, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(at: NSPoint(x: pillR.origin.x + lpad, y: pillR.origin.y + lpad/2),
                                  withAttributes: attrs)
    }

    // ── Hit Testing: only the border band and handles respond ──

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if hitZone(at: local) != .none { return self }
        return nil  // interior is click-through
    }

    // ── Determine which zone a point is in ──

    func hitZone(at p: NSPoint) -> HandleZone {
        let inner = regionInset
        let hh = handleHit / 2

        // Corner checks (highest priority)
        let corners: [(NSPoint, HandleZone)] = [
            (NSPoint(x: inner.minX, y: inner.maxY), .topLeft),
            (NSPoint(x: inner.maxX, y: inner.maxY), .topRight),
            (NSPoint(x: inner.minX, y: inner.minY), .bottomLeft),
            (NSPoint(x: inner.maxX, y: inner.minY), .bottomRight),
        ]
        for (cp, z) in corners {
            if abs(p.x - cp.x) <= hh && abs(p.y - cp.y) <= hh { return z }
        }

        // Edge midpoint handles
        let edges: [(NSPoint, HandleZone)] = [
            (NSPoint(x: inner.midX, y: inner.maxY), .top),
            (NSPoint(x: inner.midX, y: inner.minY), .bottom),
            (NSPoint(x: inner.minX, y: inner.midY), .left),
            (NSPoint(x: inner.maxX, y: inner.midY), .right),
        ]
        for (ep, z) in edges {
            if abs(p.x - ep.x) <= hh && abs(p.y - ep.y) <= hh { return z }
        }

        // General border band → move
        if bounds.contains(p) && !inner.insetBy(dx: -2, dy: -2).contains(p) {
            return .move
        }

        // Edge strips (slightly wider than the band for easy grabbing)
        let edgeTol: CGFloat = band + 4
        if p.y >= inner.maxY - 2 && p.y <= bounds.maxY { return .top }
        if p.y >= bounds.minY && p.y <= inner.minY + 2 { return .bottom }
        if p.x >= bounds.minX && p.x <= inner.minX + 2 { return .left }
        if p.x >= inner.maxX - 2 && p.x <= bounds.maxX { return .right }

        // Still in the border area
        let expanded = inner.insetBy(dx: -edgeTol, dy: -edgeTol)
        if expanded.contains(p) && !inner.contains(p) { return .move }

        return .none
    }

    // ── Mouse Interaction ──

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        zone = hitZone(at: local)
        dragAnchor = NSEvent.mouseLocation  // global screen coords
        dragOrigFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard zone != .none, let win = window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragAnchor.x
        let dy = mouse.y - dragAnchor.y
        let orig = dragOrigFrame
        let minSize: CGFloat = 30 + band * 2  // minimum window size

        var newFrame = orig

        switch zone {
        case .move:
            newFrame.origin.x = orig.origin.x + dx
            newFrame.origin.y = orig.origin.y + dy

        case .topLeft:
            newFrame.origin.x = orig.origin.x + dx
            newFrame.size.width = max(minSize, orig.width - dx)
            newFrame.size.height = max(minSize, orig.height + dy)
            if newFrame.size.width == minSize { newFrame.origin.x = orig.maxX - minSize }

        case .topRight:
            newFrame.size.width = max(minSize, orig.width + dx)
            newFrame.size.height = max(minSize, orig.height + dy)

        case .bottomLeft:
            newFrame.origin.x = orig.origin.x + dx
            newFrame.origin.y = orig.origin.y + dy
            newFrame.size.width = max(minSize, orig.width - dx)
            newFrame.size.height = max(minSize, orig.height - dy)
            if newFrame.size.width == minSize { newFrame.origin.x = orig.maxX - minSize }
            if newFrame.size.height == minSize { newFrame.origin.y = orig.maxY - minSize }

        case .bottomRight:
            newFrame.origin.y = orig.origin.y + dy
            newFrame.size.width = max(minSize, orig.width + dx)
            newFrame.size.height = max(minSize, orig.height - dy)
            if newFrame.size.height == minSize { newFrame.origin.y = orig.maxY - minSize }

        case .top:
            newFrame.size.height = max(minSize, orig.height + dy)

        case .bottom:
            newFrame.origin.y = orig.origin.y + dy
            newFrame.size.height = max(minSize, orig.height - dy)
            if newFrame.size.height == minSize { newFrame.origin.y = orig.maxY - minSize }

        case .left:
            newFrame.origin.x = orig.origin.x + dx
            newFrame.size.width = max(minSize, orig.width - dx)
            if newFrame.size.width == minSize { newFrame.origin.x = orig.maxX - minSize }

        case .right:
            newFrame.size.width = max(minSize, orig.width + dx)

        case .none:
            break
        }

        win.setFrame(newFrame, display: true)
        needsDisplay = true
        onFrameChanged?(newFrame)
    }

    override func mouseUp(with event: NSEvent) {
        if zone != .none, let win = window {
            onFrameChanged?(win.frame)
        }
        zone = .none
    }

    // ── Cursor management ──

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(for: event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func updateCursor(for event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let z = hitZone(at: local)
        switch z {
        case .move:                                NSCursor.openHand.set()
        case .topLeft, .bottomRight:               NSCursor.crosshair.set()
        case .topRight, .bottomLeft:               NSCursor.crosshair.set()
        case .top, .bottom:                        NSCursor.resizeUpDown.set()
        case .left, .right:                        NSCursor.resizeLeftRight.set()
        case .none:                                NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCloseRequest?() }
    }
    override var acceptsFirstResponder: Bool { true }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Frame Window (the persistent highlight)
// ═══════════════════════════════════════════════════════════════

class FrameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(cocoaRegionRect: NSRect) {
        let band: CGFloat = 6
        let windowRect = cocoaRegionRect.insetBy(dx: -band, dy: -band)
        super.init(contentRect: windowRect, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(windowRect, display: false)
        level = .floating
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Close Button (separate small window)
// ═══════════════════════════════════════════════════════════════

class CloseButtonWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?

    init() {
        let sz: CGFloat = 24
        super.init(contentRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                   styleMask: .borderless, backing: .buffered, defer: false)
        level = .floating + 1; isOpaque = false; backgroundColor = .clear
        hasShadow = true; ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: sz, height: sz))
        btn.bezelStyle = .circular; btn.title = "\u{2715}"
        btn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.15, alpha: 0.95).cgColor
        btn.layer?.cornerRadius = sz / 2
        btn.contentTintColor = .white
        btn.target = self; btn.action = #selector(closeTap)
        btn.toolTip = "Close region frame (ESC)"
        contentView = btn
    }

    @objc func closeTap() { onClose?() }

    /// Position relative to a frame window's top-right corner.
    func anchor(to frameWindow: NSWindow) {
        let fFrame = frameWindow.frame
        let pos = NSPoint(x: fFrame.maxX + 4, y: fFrame.maxY - 28)
        setFrameOrigin(pos)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Global ESC Monitor
// ═══════════════════════════════════════════════════════════════

class GlobalKeyMonitor {
    private var monitor: Any?
    var onEscape: (() -> Void)?
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.onEscape?(); return nil }
            return event
        }
    }
    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - App Delegate
// ═══════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindows: [OverlayWindow] = []
    private var frameWindow: FrameWindow?
    private var closeBtn: CloseButtonWindow?
    private var keyMonitor = GlobalKeyMonitor()

    // Debounce timer for saving region.json during live drag
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            fputs("ERROR: No screens.\n", stderr)
            NSApplication.shared.terminate(nil); return
        }

        fputs("== ScreenInspect RegionSelector ==\n", stderr)
        fputs("Displays: \(screens.count). Primary: \(Int(screens[0].frame.width))x\(Int(screens[0].frame.height))\n", stderr)

        for (i, screen) in screens.enumerated() {
            let f = screen.frame
            let did = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
            var name = "Display \(i+1)"
            if #available(macOS 10.15, *) { name = screen.localizedName }
            fputs("  \(i+1): \"\(name)\" id=\(did) (\(Int(f.origin.x)),\(Int(f.origin.y))) \(Int(f.width))x\(Int(f.height)) @\(screen.backingScaleFactor)x\n", stderr)

            let window = OverlayWindow(for: screen)
            let overlay = SelectionOverlayView(frame: NSRect(origin: .zero, size: f.size))
            overlay.displayLabel = "\(name) [\(did)]"

            let cs = screen; let ci = i
            overlay.onSelectionComplete = { [weak self] r in
                self?.handleSelection(viewLocalRect: r, screen: cs, displayIndex: ci)
            }
            window.contentView = overlay
            window.orderFrontRegardless(); window.makeFirstResponder(overlay)
            overlayWindows.append(window)
        }

        overlayWindows.first?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    // ── Phase 1 → Phase 2 transition ──

    func handleSelection(viewLocalRect: NSRect, screen: NSScreen, displayIndex: Int) {
        let sf = screen.frame

        // View-local → Cocoa global
        let cocoaRect = NSRect(
            x: sf.origin.x + viewLocalRect.origin.x,
            y: sf.origin.y + viewLocalRect.origin.y,
            width: viewLocalRect.width,
            height: viewLocalRect.height
        )

        let sc = cocoaToScreencapture(cocoaRect)
        fputs("\n-- Selected: x=\(sc.x) y=\(sc.y) w=\(sc.w) h=\(sc.h) --\n", stderr)

        // Save initial region.json
        saveRegionJSON(cocoaRect: cocoaRect)
        print("Region: x=\(sc.x) y=\(sc.y) w=\(sc.w) h=\(sc.h)")

        // Close overlays, show interactive frame
        showInteractiveFrame(cocoaRect: cocoaRect)
    }

    func showInteractiveFrame(cocoaRect: NSRect) {
        // 1. Remove selection overlays
        NSCursor.pop()
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()

        // 2. Create frame window
        let fw = FrameWindow(cocoaRegionRect: cocoaRect)
        let borderView = FrameBorderView(frame: NSRect(origin: .zero, size: fw.frame.size))
        borderView.autoresizingMask = [.width, .height]

        borderView.onFrameChanged = { [weak self] newWindowFrame in
            self?.onFrameMoved(newWindowFrame)
        }
        borderView.onCloseRequest = { [weak self] in self?.dismissAndExit() }

        fw.contentView = borderView
        fw.makeKeyAndOrderFront(nil)
        fw.makeFirstResponder(borderView)
        frameWindow = fw

        // 3. Close button
        let cb = CloseButtonWindow()
        cb.onClose = { [weak self] in self?.dismissAndExit() }
        cb.anchor(to: fw)
        cb.orderFrontRegardless()
        closeBtn = cb

        // 4. ESC monitor
        keyMonitor.onEscape = { [weak self] in self?.dismissAndExit() }
        keyMonitor.start()

        fputs("Frame active. Drag border to move, handles to resize, \u{2715}/ESC to close.\n", stderr)
    }

    /// Called on every frame move/resize. Debounces region.json saves.
    func onFrameMoved(_ windowFrame: NSRect) {
        // Reposition close button
        closeBtn?.anchor(to: frameWindow!)

        // Debounce: save at most every 150ms during live drag
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let fw = self?.frameWindow else { return }
            let band: CGFloat = 6
            let regionRect = fw.frame.insetBy(dx: band, dy: band)
            saveRegionJSON(cocoaRect: regionRect)
            let sc = cocoaToScreencapture(regionRect)
            fputs("  Updated: x=\(sc.x) y=\(sc.y) w=\(sc.w) h=\(sc.h)\n", stderr)
        }
    }

    func dismissAndExit() {
        fputs("Frame dismissed.\n", stderr)
        saveTimer?.invalidate()
        keyMonitor.stop()
        frameWindow?.orderOut(nil)
        closeBtn?.orderOut(nil)
        NSApplication.shared.terminate(nil)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Entry Point
// ═══════════════════════════════════════════════════════════════

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
