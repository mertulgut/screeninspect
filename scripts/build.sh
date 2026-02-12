#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════
# ScreenInspect MCP — Build Script
# ═══════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
SERVER_DIR="$ROOT_DIR/server"
MAC_DIR="$ROOT_DIR/mac"

echo "╔════════════════════════════════════════╗"
echo "║   ScreenInspect MCP — Build           ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── Preflight checks ──
echo "▸ Checking requirements..."

if [[ "$(uname)" != "Darwin" ]]; then
    echo "✗ This build script requires macOS"
    exit 1
fi

command -v node >/dev/null 2>&1 || { echo "✗ Node.js required (brew install node)"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "✗ npm required"; exit 1; }
command -v swiftc >/dev/null 2>&1 || { echo "✗ Xcode Command Line Tools required (xcode-select --install)"; exit 1; }

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
    echo "✗ Node.js 18+ required (current: $(node -v))"
    exit 1
fi

echo "  ✓ macOS $(sw_vers -productVersion)"
echo "  ✓ Node.js $(node -v)"
echo "  ✓ Swift $(swiftc -version 2>&1 | head -1)"
echo ""

# ── Clean ──
echo "▸ Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/bin"
echo ""

# ── 1. Build MCP Server ──
echo "▸ Building MCP server (TypeScript)..."
cd "$SERVER_DIR"
npm install --silent 2>&1 | tail -1 || npm install
npx tsc
echo "  ✓ Server compiled to $SERVER_DIR/dist/"
echo ""

# ── 2. Build Region Selector ──
echo "▸ Building Region Selector (Swift)..."
swiftc "$MAC_DIR/RegionSelector/RegionSelector.swift" \
    -framework Cocoa \
    -O \
    -o "$BUILD_DIR/bin/RegionSelector"
echo "  ✓ RegionSelector binary built"
echo ""

# ── 3. Build Menubar App ──
echo "▸ Building Menubar App (Swift)..."
swiftc "$MAC_DIR/ScreenInspect/ScreenInspectApp.swift" \
    -framework Cocoa \
    -O \
    -o "$BUILD_DIR/bin/ScreenInspectApp"
echo "  ✓ ScreenInspectApp binary built"
echo ""

# ── 4. Install to ~/.screeninspect/bin ──
echo "▸ Installing binaries to ~/.screeninspect/bin..."
INSTALL_DIR="$HOME/.screeninspect/bin"
mkdir -p "$INSTALL_DIR"
cp "$BUILD_DIR/bin/RegionSelector" "$INSTALL_DIR/"
cp "$BUILD_DIR/bin/ScreenInspectApp" "$INSTALL_DIR/"
echo "  ✓ Installed to $INSTALL_DIR"
echo ""

# ── Summary ──
echo "╔════════════════════════════════════════╗"
echo "║   Build Complete!                      ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "  MCP Server:        $SERVER_DIR/dist/index.js"
echo "  Region Selector:   $BUILD_DIR/bin/RegionSelector"
echo "  Menubar App:       $BUILD_DIR/bin/ScreenInspectApp"
echo ""
echo "  Quick start:"
echo "    1. Run menubar app:  $BUILD_DIR/bin/ScreenInspectApp &"
echo "    2. Or connect MCP:   node $SERVER_DIR/dist/index.js"
echo ""
echo "  See README.md for MCP client configuration."
