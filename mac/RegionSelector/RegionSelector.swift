#!/usr/bin/env swift

// RegionSelector.swift — Multi-Monitor Region Selector
//
// Creates a transparent overlay on EVERY connected display.
// User drags to select a rectangle on ANY monitor.
// Saves to ~/.screeninspect/region.json in GLOBAL top-left coordinates
// compatible with `screencapture -R x,y,w,h`.
//
// Compile: swiftc RegionSelector.swift -framework Cocoa -o RegionSelector
// Run:     ./RegionSelector
//
// ═══════════════════════════════════════════════════════════════════
// COORDINATE SYSTEMS REFERENCE
// ═══════════════════════════════════════════════════════════════════
//
//  Cocoa (NSScreen / NSView / NSWindow):
//    - Origin = BOTTOM-LEFT of the primary display
//    - Y increases UPWARD
//    - Secondary monitors to the left -> negative X
//    - Secondary monitors below primary -> negative Y
//    - NSScreen.frame is in this global Cocoa space
//    - NSView coordinates are LOCAL to the view (origin 0,0 bottom-left)
//
//  screencapture -R (what the MCP server uses):
//    - Origin = TOP-LEFT of the primary display
//    - Y increases DOWNWARD
//    - Same X axis as Cocoa
//    - Conversion: screencapture_y = primaryHeight - cocoa_global_y - rect_height
//
//  Retina / HiDPI:
//    - All coordinates here are in POINTS (logical pixels), not hardware pixels.
//    - screencapture operates in points. Output PNG is 2x on Retina.
//    - NSScreen.backingScaleFactor tells you the multiplier (1.0 or 2.0).
//
// ═══════════════════════════════════════════════════════════════════

import Cocoa

// MARK: - Data Model

struct RegionFile: Codable {
    struct Region: Codable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
    struct DisplayInfo: Codable {
        let displayID: UInt32
        let localizedName: String
        let frameOriginX: Double
        let frameOriginY: Double
        let frameWidth: Double
        let frameHeight: Double
        let backingScaleFactor: Double
    }
    let region: Region
    let displayInfo: DisplayInfo
    let updatedAt: String
    let source: String
}

// MARK: - Overlay View

class SelectionOverlayView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?

    var selectionRect: NSRect? {
        guard let s = dragStart, let c = dragCurrent else { return nil }
        return NSRect(
            x: min(s.x, c.x),
            y: min(s.y, c.y),
            width: abs(c.x - s.x),
            height: abs(c.y - s.y)
        )
    }

    var onSelectionComplete: ((NSRect) -> Void)?
    var displayLabel: String = ""

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.3).setFill()
        bounds.fill()

        if let rect = selectionRect, rect.width > 2, rect.height > 2 {
            // Clear hole for selected area
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            rect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            // Blue border
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2.0
            NSColor.systemBlue.setStroke()
            border.stroke()

            // Dashed inner border
            let inner = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            inner.lineWidth = 1.0
            inner.setLineDash([4, 4], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.6).setStroke()
            inner.stroke()

            // Corner handles
            let hs: CGFloat = 8
            NSColor.white.setFill()
            NSColor.systemBlue.setStroke()
            for c in [
                NSPoint(x: rect.minX, y: rect.minY),
                NSPoint(x: rect.maxX, y: rect.minY),
                NSPoint(x: rect.minX, y: rect.maxY),
                NSPoint(x: rect.maxX, y: rect.maxY),
            ] {
                let hr = NSRect(x: c.x - hs/2, y: c.y - hs/2, width: hs, height: hs)
                let p = NSBezierPath(ovalIn: hr)
                p.fill(); p.lineWidth = 1.5; p.stroke()
            }

            // Dimensions label with background pill
            let dimText = "\(Int(rect.width)) \u{00D7} \(Int(rect.height)) pt"
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let dimSize = (dimText as NSString).size(withAttributes: dimAttrs)
            let pad: CGFloat = 6
            let pillRect = NSRect(
                x: rect.midX - dimSize.width/2 - pad,
                y: rect.maxY + 6,
                width: dimSize.width + pad*2,
                height: dimSize.height + pad
            )
            NSColor(white: 0, alpha: 0.75).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()
            (dimText as NSString).draw(
                at: NSPoint(x: pillRect.origin.x + pad, y: pillRect.origin.y + pad/2),
                withAttributes: dimAttrs
            )
        }

        // Instruction text
        let instr = "Drag to select a region \u{00B7} Press ESC to cancel"
        let instrAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let instrSize = (instr as NSString).size(withAttributes: instrAttrs)
        (instr as NSString).draw(
            at: NSPoint(x: bounds.midX - instrSize.width/2, y: bounds.height - 50),
            withAttributes: instrAttrs
        )

        // Display label at bottom-left
        if !displayLabel.isEmpty {
            let la: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.5),
            ]
            (displayLabel as NSString).draw(at: NSPoint(x: 12, y: 12), withAttributes: la)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        if let rect = selectionRect, rect.width > 5, rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApplication.shared.terminate(nil) }
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Overlay Window

class OverlayWindow: NSWindow {
    /// We override canBecomeKey so that EVERY overlay window can accept
    /// keyboard events (ESC) and mouse events, not just the "key" one.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(for screen: NSScreen) {
        // NSWindow's DESIGNATED initializer is the 4-parameter version:
        //   init(contentRect:styleMask:backing:defer:)
        // The 5-parameter version with `screen:` is a CONVENIENCE initializer
        // and cannot be called from a subclass via super.init().
        //
        // Instead we call the designated init, then position the window
        // onto the correct screen using setFrame().
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Place window exactly on this screen's frame (global Cocoa coords)
        self.setFrame(screen.frame, display: false)
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindows: [OverlayWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            fputs("ERROR: No screens found.\n", stderr)
            NSApplication.shared.terminate(nil)
            return
        }

        let primaryH = screens[0].frame.height
        fputs("== ScreenInspect RegionSelector ==\n", stderr)
        fputs("Detected \(screens.count) display(s). Primary height: \(primaryH) pt\n", stderr)

        for (i, screen) in screens.enumerated() {
            let f = screen.frame
            let did = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
            let name = screenName(for: screen, index: i)
            let scale = screen.backingScaleFactor
            fputs("  Display \(i+1): \"\(name)\" id=\(did) " +
                  "frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))) " +
                  "scale=\(scale)x\n", stderr)

            let window = OverlayWindow(for: screen)

            // VIEW frame is LOCAL: origin (0,0), size = screen size
            let overlay = SelectionOverlayView(frame: NSRect(origin: .zero, size: f.size))
            overlay.displayLabel = "Display \(i+1): \(name) [\(did)]"

            let capturedScreen = screen
            let capturedIndex = i
            overlay.onSelectionComplete = { [weak self] viewLocalRect in
                self?.handleSelection(
                    viewLocalRect: viewLocalRect,
                    screen: capturedScreen,
                    displayIndex: capturedIndex
                )
            }

            window.contentView = overlay
            window.orderFrontRegardless()
            window.makeFirstResponder(overlay)
            overlayWindows.append(window)
        }

        // Make the primary window key for initial focus
        overlayWindows.first?.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    // MARK: - Coordinate Conversion & Save

    func handleSelection(viewLocalRect: NSRect, screen: NSScreen, displayIndex: Int) {
        let screenFrame = screen.frame
        let primaryH = NSScreen.screens[0].frame.height

        // Step 1: View-local -> Cocoa global
        // View (0,0) maps to screenFrame.origin in Cocoa global space.
        let cocoaGlobalX = screenFrame.origin.x + viewLocalRect.origin.x
        let cocoaGlobalY = screenFrame.origin.y + viewLocalRect.origin.y
        let w = viewLocalRect.width
        let h = viewLocalRect.height

        // Step 2: Cocoa global -> screencapture global (top-left origin)
        // sc_y = primaryHeight - cocoaGlobalY - rectHeight
        let scX = Int(round(cocoaGlobalX))
        let scY = Int(round(primaryH - cocoaGlobalY - h))
        let scW = Int(round(w))
        let scH = Int(round(h))

        // Display metadata
        let did = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
        let dname = screenName(for: screen, index: displayIndex)
        let scale = screen.backingScaleFactor

        // Log
        fputs("\n-- Selection Complete --\n", stderr)
        fputs("  Display: \(displayIndex+1) \"\(dname)\" (id \(did))\n", stderr)
        fputs("  View-local: (\(Int(viewLocalRect.origin.x)),\(Int(viewLocalRect.origin.y))) \(Int(w))x\(Int(h))\n", stderr)
        fputs("  Cocoa global: (\(Int(cocoaGlobalX)),\(Int(cocoaGlobalY)))\n", stderr)
        fputs("  screencapture: x=\(scX) y=\(scY) w=\(scW) h=\(scH)\n", stderr)
        fputs("  Scale: \(scale)x -> PNG will be \(scW*Int(scale))x\(scH*Int(scale)) px\n", stderr)

        // Build region.json
        let regionData = RegionFile(
            region: RegionFile.Region(x: scX, y: scY, width: scW, height: scH),
            displayInfo: RegionFile.DisplayInfo(
                displayID: did,
                localizedName: dname,
                frameOriginX: Double(screenFrame.origin.x),
                frameOriginY: Double(screenFrame.origin.y),
                frameWidth: Double(screenFrame.width),
                frameHeight: Double(screenFrame.height),
                backingScaleFactor: Double(scale)
            ),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            source: "overlay"
        )

        // Save
        let configDir = NSHomeDirectory() + "/.screeninspect"
        let regionFile = configDir + "/region.json"
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(regionData)
            try jsonData.write(to: URL(fileURLWithPath: regionFile))
        } catch {
            fputs("ERROR: Failed to write region.json: \(error)\n", stderr)
        }

        // stdout for callers
        print("Region selected: x=\(scX) y=\(scY) w=\(scW) h=\(scH)")
        print("Display: \(displayIndex+1) \"\(dname)\" (id \(did), scale \(scale)x)")
        print("Saved to: \(regionFile)")

        // Exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSCursor.pop()
            NSApplication.shared.terminate(nil)
        }
    }

    func screenName(for screen: NSScreen, index: Int) -> String {
        if #available(macOS 10.15, *) { return screen.localizedName }
        return index == 0 ? "Primary Display" : "Display \(index + 1)"
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
