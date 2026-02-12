# ScreenInspect MCP

**On-demand screen region capture for LLMs — local, private, no continuous recording.**

ScreenInspect is a macOS menubar app + MCP server that lets any LLM capture a user-selected screen region on demand. The LLM calls a tool, gets back a base64 PNG and metadata. That's it — no streaming, no background processes, no cloud.

---

## Features

- **MCP Server** with 3 tools: `set_region`, `get_region`, `capture_region`
- **Visual Region Selector** — drag-to-select transparent overlay
- **Menubar App** — Select Area, Test Capture, Open Logs, Permissions Help
- **Local-first** — everything stays on your Mac
- **Multi-monitor aware** — uses macOS global coordinate space
- **Privacy by design** — on-demand only, never continuous

## Quick Start

### Prerequisites

- macOS 13 (Ventura) or later
- Node.js 18+
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

### Connect to MCP Clients

#### Claude Desktop

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

Then restart Claude Desktop.

#### Cursor

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

#### Any MCP Client

The server uses **stdio** transport. Launch with:

```bash
node /path/to/screeninspect-mcp/server/dist/index.js
```

## MCP Tools

### `set_region`

Save a screen region for future captures.

| Parameter | Type   | Description                                |
|-----------|--------|--------------------------------------------|
| `x`       | number | X coordinate of top-left corner (pixels)   |
| `y`       | number | Y coordinate of top-left corner (pixels)   |
| `width`   | number | Width of region (pixels)                   |
| `height`  | number | Height of region (pixels)                  |

Coordinates use the **macOS global coordinate space** (origin = top-left of primary display). On multi-monitor setups, secondary monitors may have negative coordinates.

### `get_region`

Returns the currently saved region from `~/.screeninspect/region.json`, or null if none is set.

### `capture_region`

Captures the saved region (or override with inline parameters) and returns:

- **base64 PNG image** (as an MCP image content block)
- **Metadata**: region, timestamp, file size, scale factor, capture method

Optional override parameters: `x`, `y`, `width`, `height` (all four required to override).

## Architecture

```
screeninspect-mcp/
├── server/                 # MCP server (Node.js TypeScript)
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
└── SECURITY.md
```

### Data Storage

All data is stored locally in `~/.screeninspect/`:

| File              | Purpose                            |
|-------------------|------------------------------------|
| `region.json`     | Saved capture region               |
| `server.log`      | Server + app logs                  |
| `crash-*.json`    | Crash reports (local only)         |
| `tmp/`            | Temporary capture files (cleaned)  |
| `bin/`            | Installed binaries                 |

## Multi-Monitor Support

macOS uses a global coordinate space where the primary display's top-left corner is (0, 0). Displays to the left or above the primary display may have negative coordinates. The Region Selector overlay appears on all connected displays and correctly converts Cocoa coordinates to the global space used by `screencapture`.

To check your display arrangement:

```bash
system_profiler SPDisplaysDataType
```

## Packaging & Distribution

### Build a release package:

```bash
bash scripts/release.sh
```

This creates in `release/`:
- `ScreenInspect.app` — standalone .app bundle
- `ScreenInspect-v1.0.0-macos.zip` — distributable archive
- `ScreenInspect-v1.0.0-macos.zip.sha256` — checksum
- `ScreenInspect-v1.0.0-macos.dmg` — disk image

### Production release checklist:
- [ ] Code sign with Developer ID
- [ ] Notarize with Apple
- [ ] Staple notarization ticket
- [ ] Add Sparkle.framework for auto-updates
- [ ] Integrate license key validation
- [ ] Set up appcast.xml for update feed

## Licensing (Placeholder)

The current build runs in "Pro" mode with all features unlocked. The licensing infrastructure is in place:

- `capture.ts` has a `LicenseState` with `free` / `pro` tiers
- Free tier: limited to 10 captures (configurable)
- Pro tier: unlimited captures
- `setLicenseTier()` function ready for license key validation

Recommended services: Gumroad, LemonSqueezy, Keygen.sh, or Paddle.

## Known Limitations

1. **Capture method**: MVP uses `screencapture -x -R` CLI. Future version should use ScreenCaptureKit for faster, more flexible captures.
2. **Permission detection**: Cannot proactively detect missing Screen Recording permission — discovered only on capture failure.
3. **No window-level capture**: Captures pixel regions, not specific windows. Window targeting requires ScreenCaptureKit.
4. **Retina scaling**: Captured images are at Retina resolution (2x) on Retina displays. Metadata includes `displayScaleFactor`.
5. **No live preview**: Region selector doesn't preview what will be captured.
6. **Not signed/notarized**: Dev build not code-signed. Right-click → Open to bypass Gatekeeper.
7. **Multi-monitor edge cases**: Non-standard arrangements (vertical stacking, mixed resolutions) may have coordinate conversion issues.
8. **No ScreenCaptureKit yet**: The #1 upgrade for v2.

## License

MIT
