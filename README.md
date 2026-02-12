# ScreenInspect MCP

**On-demand screen region capture for LLMs — local, private, no continuous recording.**

ScreenInspect is a macOS menubar app + MCP server that lets any LLM capture a user-selected screen region on demand.  
The LLM calls a tool, gets back a base64 PNG and metadata. That's it — no streaming, no background processes, no cloud.

ScreenInspect never captures the screen unless explicitly requested by an LLM tool call.

---

## Features

- **MCP Server** with 3 tools: `set_region`, `get_region`, `capture_region`
- **Visual Region Selector** — drag-to-select transparent overlay
- **Menubar App** — Select Area, Test Capture, Open Logs, Permissions Help
- **Local-first** — everything stays on your Mac
- **Multi-monitor aware** — uses macOS global coordinate space
- **Privacy by design** — on-demand only, never continuous

---

## Quick Start

### Prerequisites

- macOS 13 (Ventura) or later
- Node.js 18+ (tested with Node 20 and 24)
- Xcode Command Line Tools (`xcode-select --install`)

### Build

```bash
git clone https://github.com/yourname/screeninspect-mcp.git
cd screeninspect-mcp
bash scripts/build.sh
```

### Grant Screen Recording Permission

1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable permission for **Terminal** (or your IDE: Cursor, VS Code, etc.)
3. If using the MCP server directly, also enable for the app running Node.js
4. **Restart** Terminal / IDE after granting permission

### Run the Menubar App

```bash
./build/bin/ScreenInspectApp &
```

The camera viewfinder icon appears in your menubar with options:
- **Select Area** — opens the overlay to drag-select a region
- **Test Capture** — captures the saved region and opens in Preview
- **Open Logs** — view `~/.screeninspect/server.log`
- **Permissions Help** — direct link to Screen Recording settings

---

## Connect to LLM Clients

### Claude Desktop (MCP)

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "screeninspect": {
      "command": "node",
      "args": ["/absolute/path/to/screeninspect-mcp/server/dist/index.js"]
    }
  }
}
```

Restart Claude Desktop.

### Cursor (MCP)

Edit `.cursor/mcp.json` in your project root (or globally):

```json
{
  "mcpServers": {
    "screeninspect": {
      "command": "node",
      "args": ["/absolute/path/to/screeninspect-mcp/server/dist/index.js"]
    }
  }
}
```

### Any MCP Client

The server uses **stdio** transport. Launch with:

```bash
node /path/to/screeninspect-mcp/server/dist/index.js
```

---

## HTTP Tool (Non-MCP Clients)

For agents that do **not** support MCP (e.g. Antigravity + Gemini), ScreenInspect exposes an optional HTTP endpoint:

```
POST http://localhost:4545/capture
```

This endpoint returns the same payload as `capture_region`  
(base64 PNG image + metadata).

Recommended tool name for LLMs: `screeninspect_capture`

---

## MCP Tools

### `set_region`

Save a screen region for future captures.

| Parameter | Type   | Description                            |
|----------|--------|----------------------------------------|
| `x`      | number | X coordinate (global, may be negative) |
| `y`      | number | Y coordinate (global, may be negative) |
| `width`  | number | Width of region (points)               |
| `height` | number | Height of region (points)              |

Coordinates use the **macOS global coordinate space**  
(origin = bottom-left of the primary display).  
On multi-monitor setups, secondary monitors may have negative coordinates.

### `get_region`

Returns the currently saved region from `~/.screeninspect/region.json`,  
or `null` if none is set.

### `capture_region`

Captures the saved region (or override with inline parameters) and returns:

- **Base64 PNG image** (as an MCP image content block)
- **Metadata**: region, timestamp, file size, scale factor, capture method

Optional override parameters: `x`, `y`, `width`, `height`  
(all four required to override).

---

## Architecture

```
screeninspect-mcp/
├── server/                 # MCP + HTTP server (Node.js TypeScript)
│   ├── src/
│   │   ├── index.ts        # MCP protocol + tool handlers
│   │   ├── capture.ts      # Region persistence + screencapture
│   │   └── logger.ts       # File + stderr logging, crash reports
│   ├── package.json
│   └── tsconfig.json
├── mac/                    # macOS native code (Swift)
│   ├── RegionSelector/     # Transparent overlay drag-to-select
│   └── ScreenInspect/      # Menubar app shell
├── scripts/
│   ├── build.sh            # Build everything
│   └── release.sh          # Package .app, .zip, .dmg, checksums
├── README.md
├── SECURITY.md
└── LICENSE
```

---

## Data Storage

All data is stored locally in `~/.screeninspect/`:

| File              | Purpose                            |
|-------------------|------------------------------------|
| `region.json`     | Saved capture region               |
| `server.log`      | Server + app logs                  |
| `crash-*.json`    | Crash reports (local only)         |
| `tmp/`            | Temporary capture files            |
| `bin/`            | Installed binaries                 |

Note: `build/` and `release/` directories are not committed to git.

---

## Multi-Monitor Support

macOS uses a global coordinate space where the primary display’s bottom-left
corner is `(0, 0)`. Displays to the left or above the primary display may have
negative coordinates.

The Region Selector overlay appears on **all connected displays** and correctly
converts Cocoa coordinates to the global space used by `screencapture`.

To inspect your display layout:

```bash
system_profiler SPDisplaysDataType
```

---

## Packaging & Distribution

### Build a release package

```bash
bash scripts/release.sh
```

Creates in `release/`:
- `ScreenInspect.app`
- `ScreenInspect-v1.0.0-macos.zip`
- `ScreenInspect-v1.0.0-macos.zip.sha256`
- `ScreenInspect-v1.0.0-macos.dmg`

### Production release checklist

- [ ] Code sign with Developer ID
- [ ] Notarize with Apple
- [ ] Staple notarization ticket
- [ ] Add Sparkle.framework for auto-updates
- [ ] Integrate license key validation
- [ ] Publish appcast.xml

---

## Known Limitations

1. **Capture method**: MVP uses `screencapture -x -R`.  
   ScreenCaptureKit is planned for v2.
2. **Permission detection**: Missing Screen Recording permission is detected
   only on capture failure.
3. **No window-level capture**: Pixel regions only (not window IDs).
4. **Retina scaling**: Captures are at Retina resolution; metadata includes scale factor.
5. **No live preview**: Region selector does not preview capture output.
6. **Not signed/notarized**: Dev builds require Right-click → Open.
7. **Complex multi-monitor layouts** may require further testing.

---

## License

MIT
