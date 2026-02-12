import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

const CONFIG_DIR = path.join(os.homedir(), ".screeninspect");
const LOG_FILE = path.join(CONFIG_DIR, "server.log");

function ensureConfigDir(): void {
  if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
  }
}

export enum LogLevel {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

function formatMessage(level: LogLevel, msg: string, meta?: unknown): string {
  const ts = new Date().toISOString();
  const metaStr = meta ? ` | ${JSON.stringify(meta)}` : "";
  return `[${ts}] [${level}] ${msg}${metaStr}`;
}

export function log(level: LogLevel, msg: string, meta?: unknown): void {
  ensureConfigDir();
  const line = formatMessage(level, msg, meta);
  // Always write to log file
  fs.appendFileSync(LOG_FILE, line + "\n");
  // Also write to stderr (MCP servers must not write to stdout)
  process.stderr.write(line + "\n");
}

export function logInfo(msg: string, meta?: unknown): void {
  log(LogLevel.INFO, msg, meta);
}

export function logError(msg: string, meta?: unknown): void {
  log(LogLevel.ERROR, msg, meta);
}

export function logWarn(msg: string, meta?: unknown): void {
  log(LogLevel.WARN, msg, meta);
}

export function logDebug(msg: string, meta?: unknown): void {
  log(LogLevel.DEBUG, msg, meta);
}

// ── Crash report placeholder ──
// TODO: Wire to Sentry, Crashlytics, or custom endpoint
export function reportCrash(error: Error): void {
  logError("CRASH", {
    name: error.name,
    message: error.message,
    stack: error.stack,
  });
  // Placeholder: write crash dump
  const crashFile = path.join(
    CONFIG_DIR,
    `crash-${Date.now()}.json`
  );
  fs.writeFileSync(
    crashFile,
    JSON.stringify(
      {
        timestamp: new Date().toISOString(),
        error: {
          name: error.name,
          message: error.message,
          stack: error.stack,
        },
        platform: process.platform,
        arch: process.arch,
        nodeVersion: process.version,
      },
      null,
      2
    )
  );
}

export { CONFIG_DIR, LOG_FILE };
