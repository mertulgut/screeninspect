#!/usr/bin/env swift

// ScreenInspectApp.swift
// Menubar-only macOS app shell for ScreenInspect.
// Compile: swiftc ScreenInspectApp.swift -framework Cocoa -o ScreenInspectApp
// Run:     ./ScreenInspectApp

import Cocoa

// MARK: - Constants

let APP_NAME = "ScreenInspect"
let APP_VERSION = "1.0.0"
let CONFIG_DIR = NSHomeDirectory() + "/.screeninspect"
let REGION_FILE = CONFIG_DIR + "/region.json"
let LOG_FILE = CONFIG_DIR + "/server.log"

// MARK: - App Delegate

class MenuBarDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var currentRegionItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure config dir exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: CONFIG_DIR) {
            try? fm.createDirectory(atPath: CONFIG_DIR, withIntermediateDirectories: true)
        }

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Use SF Symbol if available, fallback to text
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenInspect") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "⊞"
            }
            button.toolTip = "ScreenInspect — Screen Region Capture"
        }

        // Build menu
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Title
        let titleItem = NSMenuItem(title: "ScreenInspect v\(APP_VERSION)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Current region display
        currentRegionItem = NSMenuItem(title: "Region: (not set)", action: nil, keyEquivalent: "")
        currentRegionItem.isEnabled = false
        updateRegionDisplay()
        menu.addItem(currentRegionItem)

        menu.addItem(NSMenuItem.separator())

        // Select Area
        let selectItem = NSMenuItem(title: "📐 Select Area…", action: #selector(selectArea), keyEquivalent: "s")
        selectItem.keyEquivalentModifierMask = [.command, .shift]
        selectItem.target = self
        menu.addItem(selectItem)

        // Test Capture
        let captureItem = NSMenuItem(title: "📸 Test Capture", action: #selector(testCapture), keyEquivalent: "c")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        // Open Logs
        let logsItem = NSMenuItem(title: "📋 Open Logs", action: #selector(openLogs), keyEquivalent: "l")
        logsItem.keyEquivalentModifierMask = [.command, .shift]
        logsItem.target = self
        menu.addItem(logsItem)

        // Open Config Dir
        let configItem = NSMenuItem(title: "📁 Open Config Folder", action: #selector(openConfigDir), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(NSMenuItem.separator())

        // Permissions Help
        let permItem = NSMenuItem(title: "🔐 Permissions Help…", action: #selector(showPermissionsHelp), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        // MCP Connection Help
        let mcpItem = NSMenuItem(title: "🔌 MCP Setup Help…", action: #selector(showMCPHelp), keyEquivalent: "")
        mcpItem.target = self
        menu.addItem(mcpItem)

        menu.addItem(NSMenuItem.separator())

        // License status (placeholder)
        let licenseItem = NSMenuItem(title: "⭐ Pro License: Active", action: nil, keyEquivalent: "")
        licenseItem.isEnabled = false
        menu.addItem(licenseItem)

        // TODO: Add "Enter License Key…" menu item when paywall is active
        // let enterKeyItem = NSMenuItem(title: "🔑 Enter License Key…", action: #selector(enterLicenseKey), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())

        // Check for Updates (Sparkle placeholder)
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit ScreenInspect", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Log startup
        appendLog("ScreenInspect menubar app started (v\(APP_VERSION))")
    }

    // MARK: - Region Display

    func updateRegionDisplay() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: REGION_FILE),
              let data = fm.contents(atPath: REGION_FILE),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let region = json["region"] as? [String: Any],
              let x = region["x"] as? Int,
              let y = region["y"] as? Int,
              let w = region["width"] as? Int,
              let h = region["height"] as? Int
        else {
            currentRegionItem?.title = "Region: (not set)"
            return
        }
        currentRegionItem?.title = "Region: (\(x), \(y)) \(w)×\(h)"
    }

    // MARK: - Actions

    @objc func selectArea() {
        // Find the RegionSelector binary
        let possiblePaths = [
            Bundle.main.bundlePath + "/Contents/MacOS/RegionSelector",
            Bundle.main.bundlePath + "/../RegionSelector",
            "./RegionSelector",
            NSHomeDirectory() + "/.screeninspect/bin/RegionSelector",
        ]

        var selectorPath: String?
        for p in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: p) {
                selectorPath = p
                break
            }
        }

        guard let path = selectorPath else {
            showAlert(
                title: "Region Selector Not Found",
                message: "Could not find the RegionSelector binary.\n\nExpected locations:\n• Same directory as this app\n• ~/.screeninspect/bin/RegionSelector\n\nPlease rebuild: swiftc RegionSelector.swift -framework Cocoa -o RegionSelector"
            )
            return
        }

        appendLog("Launching region selector: \(path)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateRegionDisplay()
                self?.appendLog("Region selector completed")
            }
        }

        do {
            try task.run()
        } catch {
            showAlert(title: "Error", message: "Failed to launch region selector: \(error.localizedDescription)")
        }
    }

    @objc func testCapture() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: REGION_FILE),
              let data = fm.contents(atPath: REGION_FILE),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let region = json["region"] as? [String: Any],
              let x = region["x"] as? Int,
              let y = region["y"] as? Int,
              let w = region["width"] as? Int,
              let h = region["height"] as? Int
        else {
            showAlert(title: "No Region", message: "Please select a region first using 'Select Area'.")
            return
        }

        let outputPath = CONFIG_DIR + "/test-capture.png"
        let rect = "\(x),\(y),\(w),\(h)"
        let cmd = "screencapture -x -R\(rect) -t png \"\(outputPath)\""

        appendLog("Test capture: \(cmd)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", cmd]
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 && fm.fileExists(atPath: outputPath) {
                    let fileSize = (try? fm.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
                    self?.appendLog("Capture saved: \(outputPath) (\(fileSize) bytes)")
                    // Open in Preview
                    NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
                } else {
                    self?.showAlert(
                        title: "Capture Failed",
                        message: "screencapture returned status \(process.terminationStatus).\n\nMake sure Screen Recording permission is granted in:\nSystem Settings → Privacy & Security → Screen Recording"
                    )
                }
            }
        }

        do {
            try task.run()
        } catch {
            showAlert(title: "Error", message: "Failed to run screencapture: \(error.localizedDescription)")
        }
    }

    @objc func openLogs() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: LOG_FILE) {
            // Create empty log file
            fm.createFile(atPath: LOG_FILE, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: LOG_FILE))
    }

    @objc func openConfigDir() {
        NSWorkspace.shared.open(URL(fileURLWithPath: CONFIG_DIR))
    }

    @objc func showPermissionsHelp() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission"
        alert.informativeText = """
        ScreenInspect requires Screen Recording permission to capture screen regions.

        Steps:
        1. Open System Settings
        2. Go to Privacy & Security → Screen Recording
        3. Enable permission for:
           • Terminal (if running from terminal)
           • Your IDE (Cursor, VS Code, etc.)
           • Node.js (for MCP server)
        4. Restart ScreenInspect and the MCP server

        Note: You may need to click the '+' button and manually add the application.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Privacy settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func showMCPHelp() {
        let alert = NSAlert()
        alert.messageText = "MCP Connection Setup"
        alert.informativeText = """
        To connect ScreenInspect to an MCP client:

        Claude Desktop — add to claude_desktop_config.json:
        {
          "mcpServers": {
            "screeninspect": {
              "command": "node",
              "args": ["/path/to/screeninspect-mcp/server/dist/index.js"]
            }
          }
        }

        Cursor — add to .cursor/mcp.json:
        {
          "mcpServers": {
            "screeninspect": {
              "command": "node",
              "args": ["/path/to/screeninspect-mcp/server/dist/index.js"]
            }
          }
        }

        Then restart the MCP client.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Claude Config")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let config = """
            {
              "mcpServers": {
                "screeninspect": {
                  "command": "node",
                  "args": ["\(NSHomeDirectory())/screeninspect-mcp/server/dist/index.js"]
                }
              }
            }
            """
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(config, forType: .string)
        }
    }

    @objc func checkForUpdates() {
        // TODO: Integrate Sparkle framework
        // Sparkle integration plan:
        //   1. Add Sparkle.framework to the .app bundle (Frameworks/)
        //   2. Set SUFeedURL in Info.plist to your appcast.xml URL
        //   3. Initialize SPUStandardUpdaterController in applicationDidFinishLaunching
        //   4. Wire this menu item to SPUStandardUpdaterController.checkForUpdates(_:)
        //
        // File locations:
        //   - ScreenInspect.app/Contents/Frameworks/Sparkle.framework
        //   - ScreenInspect.app/Contents/Info.plist (add SUFeedURL key)
        //   - Server: appcast.xml hosted at your update URL

        showAlert(
            title: "Updates",
            message: "Auto-update via Sparkle will be available in a future release.\n\nFor now, check https://github.com/yourname/screeninspect-mcp/releases"
        )
    }

    @objc func quit() {
        appendLog("ScreenInspect quitting")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func appendLog(_ message: String) {
        let fm = FileManager.default
        let dir = CONFIG_DIR
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [APP] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: LOG_FILE) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            fm.createFile(atPath: LOG_FILE, contents: line.data(using: .utf8))
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menubar only, no dock icon
let delegate = MenuBarDelegate()
app.delegate = delegate
app.run()
