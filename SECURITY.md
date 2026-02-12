# Security & Privacy Policy

## Overview

ScreenInspect is designed with **privacy-first, local-only** architecture. It captures screen regions **only on explicit demand** from an LLM tool call — never continuously, never in the background.

## Core Security Principles

### 1. On-Demand Only — No Continuous Capture

ScreenInspect **never** runs a background capture loop. Every screen capture is triggered by:
- An explicit MCP tool call (`capture_region`) from an LLM client, or
- The user clicking "Test Capture" in the menubar app.

There is no scheduled capture, no interval-based recording, no streaming. When the tool is not being called, zero screen data is being collected.

### 2. Local-First — No Cloud, No Telemetry

- All data stays on your Mac in `~/.screeninspect/`
- No data is sent to any server, cloud service, or third party
- No analytics, no tracking, no telemetry
- Crash reports are stored locally as JSON files — they are never uploaded
- The MCP server communicates only via local stdio pipes

### 3. User-Controlled Region

The user explicitly selects which region of the screen to capture using the visual overlay tool. The LLM cannot:
- Capture outside the user-defined region (unless the user provides new coordinates)
- Access other windows, displays, or the full screen without the user's knowledge
- Change the region without the user being aware (region changes are logged)

### 4. macOS Permission Gating

ScreenInspect relies on macOS **Screen Recording permission**, which:
- Must be explicitly granted by the user in System Settings
- Shows a system-level permission dialog the first time
- Can be revoked at any time
- Is enforced by macOS at the OS level — the app cannot bypass it

### 5. Transparent Logging

All capture operations are logged to `~/.screeninspect/server.log` with:
- Timestamp
- Region coordinates
- File size
- Capture method used

Users can inspect this log at any time via the "Open Logs" menu item.

## What Data Is Captured

| Data              | When                     | Where Stored          | Retention              |
|-------------------|--------------------------|-----------------------|------------------------|
| Region coords     | On set_region / overlay  | `~/.screeninspect/region.json` | Until overwritten |
| Screenshot PNG    | On capture_region        | Returned to MCP client, temp file deleted | Not persisted |
| Test captures     | On "Test Capture" click  | `~/.screeninspect/test-capture.png` | Until next test |
| Server logs       | Always running           | `~/.screeninspect/server.log` | Grows until manual delete |
| Crash reports     | On unhandled errors      | `~/.screeninspect/crash-*.json` | Until manual delete |

## What ScreenInspect Does NOT Do

- ❌ Continuous screen recording
- ❌ Background capture loops
- ❌ Keystroke logging
- ❌ Window enumeration or tracking
- ❌ Network transmission of captures
- ❌ Cloud storage of any data
- ❌ Analytics or telemetry collection
- ❌ Access to files, clipboard, or other system data
- ❌ Capture without Screen Recording permission

## MCP Transport Security

The MCP server uses **stdio transport** — communication happens through standard input/output pipes between the MCP client process and the server process. This means:

- No network ports are opened
- No HTTP server is running
- Communication is process-local
- Only the parent MCP client can send commands

## Threat Model

| Threat                                    | Mitigation                                                |
|-------------------------------------------|-----------------------------------------------------------|
| Unauthorized screen capture               | Requires macOS Screen Recording permission                |
| LLM capturing sensitive data              | User controls the region; can revoke permission anytime   |
| Data exfiltration                          | No network access; all data local                         |
| Malicious MCP client                       | macOS permission + user-defined region limits scope       |
| Capture of credentials on screen          | User responsibility to set region away from sensitive areas|
| Temp file persistence                      | Temp files deleted immediately after base64 encoding      |

## Recommendations for Users

1. **Set your region carefully** — avoid regions that display passwords, tokens, or financial data
2. **Review logs periodically** — check `~/.screeninspect/server.log` for unexpected captures
3. **Revoke permission when not in use** — disable Screen Recording permission in System Settings
4. **Keep the app updated** — security patches will be distributed through the update mechanism
5. **Use the free tier for sensitive work** — the capture limit provides an additional safety net

## Reporting Security Issues

If you discover a security vulnerability, please email security@screeninspect.example.com (TODO: set up actual email) rather than filing a public issue.

## Compliance Notes

- ScreenInspect does not collect personal data and is not subject to GDPR data processing requirements
- No data leaves the user's machine
- The app requests only the minimum macOS permission needed (Screen Recording)
- Screen Recording permission is clearly explained to the user with the `NSScreenCaptureUsageDescription` Info.plist key
