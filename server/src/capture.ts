import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { execSync } from "node:child_process";
import { logInfo, logError, logWarn, CONFIG_DIR } from "./logger.js";

// ── Types ──

export interface Region {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CaptureResult {
  base64: string;
  region: Region;
  timestamp: string;
  sizeBytes: number;
  format: "png";
  displayScaleFactor: number;
  captureMethod: "screencapture-cli";
}

export interface RegionFile {
  region: Region;
  updatedAt: string;
  source: "manual" | "overlay";
}

// ── Paths ──

const REGION_FILE = path.join(CONFIG_DIR, "region.json");
const TEMP_DIR = path.join(CONFIG_DIR, "tmp");

function ensureDirs(): void {
  for (const dir of [CONFIG_DIR, TEMP_DIR]) {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }
}

// ── Licensing / Feature Gate ──
// TODO: Replace with real license key validation (Gumroad, LemonSqueezy, Keygen, etc.)

interface LicenseState {
  tier: "free" | "pro";
  capturesRemaining: number; // -1 = unlimited
}

let _license: LicenseState = {
  tier: "pro", // Default: allow all for MVP. Change to "free" to test gate.
  capturesRemaining: -1,
};

export function getLicenseState(): LicenseState {
  return { ..._license };
}

export function setLicenseTier(tier: "free" | "pro"): void {
  _license.tier = tier;
  _license.capturesRemaining = tier === "pro" ? -1 : 10;
  logInfo("License tier changed", { tier, capturesRemaining: _license.capturesRemaining });
}

function checkCaptureAllowed(): void {
  if (_license.tier === "free" && _license.capturesRemaining === 0) {
    throw new Error(
      "Free tier capture limit reached. Upgrade to Pro for unlimited captures."
    );
  }
}

function decrementCapture(): void {
  if (_license.tier === "free" && _license.capturesRemaining > 0) {
    _license.capturesRemaining--;
    logInfo("Capture decremented", { remaining: _license.capturesRemaining });
  }
}

// ── Region Persistence ──

export function saveRegion(region: Region, source: "manual" | "overlay" = "manual"): void {
  ensureDirs();
  validateRegion(region);
  const data: RegionFile = {
    region,
    updatedAt: new Date().toISOString(),
    source,
  };
  fs.writeFileSync(REGION_FILE, JSON.stringify(data, null, 2));
  logInfo("Region saved", data);
}

export function loadRegion(): RegionFile | null {
  if (!fs.existsSync(REGION_FILE)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(REGION_FILE, "utf-8");
    const data = JSON.parse(raw) as RegionFile;
    validateRegion(data.region);
    return data;
  } catch (err) {
    logError("Failed to load region file", { error: String(err) });
    return null;
  }
}

function validateRegion(r: Region): void {
  if (
    typeof r.x !== "number" ||
    typeof r.y !== "number" ||
    typeof r.width !== "number" ||
    typeof r.height !== "number"
  ) {
    throw new Error("Region must have numeric x, y, width, height");
  }
  if (r.width <= 0 || r.height <= 0) {
    throw new Error("Region width and height must be positive");
  }
  if (r.width > 10000 || r.height > 10000) {
    throw new Error("Region dimensions unreasonably large (>10000px)");
  }
}

// ── Screen Capture ──
// MVP: Uses macOS `screencapture` CLI tool.
// This requires "Screen Recording" permission in System Settings > Privacy & Security.
//
// TODO (v2): Migrate to ScreenCaptureKit via a native Swift helper for:
//   - Faster captures
//   - Window-level targeting
//   - No temporary file needed
//   - Better multi-monitor support

export function captureRegion(regionOverride?: Region): CaptureResult {
  ensureDirs();

  // Check license gate
  checkCaptureAllowed();

  // Determine region
  const stored = loadRegion();
  const region = regionOverride ?? stored?.region;

  if (!region) {
    throw new Error(
      "No region set. Use set_region tool or the overlay selector first."
    );
  }

  validateRegion(region);

  // Check platform
  if (process.platform !== "darwin") {
    throw new Error("ScreenInspect only works on macOS");
  }

  // Build screencapture command
  // -x: no sound  -R: region  -t png: format
  const tmpFile = path.join(TEMP_DIR, `capture-${Date.now()}.png`);
  const rect = `${region.x},${region.y},${region.width},${region.height}`;
  const cmd = `screencapture -x -R${rect} -t png "${tmpFile}"`;

  logInfo("Executing capture", { cmd, region });

  try {
    execSync(cmd, { timeout: 10000, stdio: "pipe" });
  } catch (err: any) {
    // Check common failures
    const stderr = err?.stderr?.toString() || "";
    if (stderr.includes("permission") || err.status === 1) {
      throw new Error(
        "Screen Recording permission denied. Go to:\n" +
        "  System Settings → Privacy & Security → Screen Recording\n" +
        "and enable permission for Terminal / your IDE / Node.js.\n" +
        "Then restart the MCP server."
      );
    }
    throw new Error(`screencapture failed: ${stderr || err.message}`);
  }

  // Read result
  if (!fs.existsSync(tmpFile)) {
    throw new Error(
      "Capture file not created. Screen Recording permission may be missing.\n" +
      "Go to: System Settings → Privacy & Security → Screen Recording"
    );
  }

  const buffer = fs.readFileSync(tmpFile);
  const base64 = buffer.toString("base64");
  const sizeBytes = buffer.length;

  // Clean up temp file
  try {
    fs.unlinkSync(tmpFile);
  } catch {
    logWarn("Failed to clean temp file", { tmpFile });
  }

  // Decrement license counter if applicable
  decrementCapture();

  // Get display scale factor (best effort)
  let scaleFactor = 2; // Retina default
  try {
    const scaleOutput = execSync(
      "system_profiler SPDisplaysDataType 2>/dev/null | grep -i resolution | head -1",
      { encoding: "utf-8", timeout: 5000 }
    );
    if (scaleOutput.includes("Retina")) {
      scaleFactor = 2;
    } else {
      scaleFactor = 1;
    }
  } catch {
    // Keep default
  }

  const result: CaptureResult = {
    base64,
    region,
    timestamp: new Date().toISOString(),
    sizeBytes,
    format: "png",
    displayScaleFactor: scaleFactor,
    captureMethod: "screencapture-cli",
  };

  logInfo("Capture successful", {
    sizeBytes,
    region,
    scaleFactor,
  });

  return result;
}
