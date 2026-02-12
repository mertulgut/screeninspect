#!/usr/bin/env node

/**
 * ScreenInspect MCP Server
 *
 * Tools:
 *   set_region(x, y, width, height) — Save a screen region for future captures
 *   get_region()                    — Read the currently saved region
 *   capture_region()                — Capture the saved region → base64 PNG + metadata
 *
 * Transport: stdio (standard MCP transport)
 * Platform:  macOS 13+ only
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import {
  saveRegion,
  loadRegion,
  captureRegion,
  getLicenseState,
  type Region,
} from "./capture.js";
import { logInfo, logError, reportCrash } from "./logger.js";

// ── Server Setup ──

const server = new Server(
  {
    name: "screeninspect-mcp",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// ── Tool Definitions ──

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "set_region",
        description:
          "Set the screen region to capture. Coordinates are in macOS global coordinate space " +
          "(origin top-left of primary display). For multi-monitor setups, secondary displays " +
          "may have negative x or y values.",
        inputSchema: {
          type: "object" as const,
          properties: {
            x: {
              type: "number",
              description: "X coordinate of top-left corner (pixels)",
            },
            y: {
              type: "number",
              description: "Y coordinate of top-left corner (pixels)",
            },
            width: {
              type: "number",
              description: "Width of the region (pixels, must be > 0)",
            },
            height: {
              type: "number",
              description: "Height of the region (pixels, must be > 0)",
            },
          },
          required: ["x", "y", "width", "height"],
        },
      },
      {
        name: "get_region",
        description:
          "Get the currently saved screen region. Returns null if no region has been set.",
        inputSchema: {
          type: "object" as const,
          properties: {},
        },
      },
      {
        name: "capture_region",
        description:
          "Capture the currently saved screen region and return a base64-encoded PNG image " +
          "with metadata. Requires Screen Recording permission on macOS. " +
          "This is an ON-DEMAND capture — no continuous recording occurs.",
        inputSchema: {
          type: "object" as const,
          properties: {
            x: {
              type: "number",
              description: "Optional: override x (pixels). If omitted, uses saved region.",
            },
            y: {
              type: "number",
              description: "Optional: override y (pixels). If omitted, uses saved region.",
            },
            width: {
              type: "number",
              description: "Optional: override width (pixels). If omitted, uses saved region.",
            },
            height: {
              type: "number",
              description: "Optional: override height (pixels). If omitted, uses saved region.",
            },
          },
        },
      },
    ],
  };
});

// ── Tool Handlers ──

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      // ── set_region ──
      case "set_region": {
        const region: Region = {
          x: Number(args?.x),
          y: Number(args?.y),
          width: Number(args?.width),
          height: Number(args?.height),
        };
        saveRegion(region, "manual");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  success: true,
                  message: `Region saved: (${region.x}, ${region.y}) ${region.width}×${region.height}`,
                  region,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      // ── get_region ──
      case "get_region": {
        const data = loadRegion();
        if (!data) {
          return {
            content: [
              {
                type: "text",
                text: JSON.stringify({
                  success: true,
                  region: null,
                  message:
                    "No region set. Use set_region or the overlay selector app.",
                }),
              },
            ],
          };
        }
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  success: true,
                  region: data.region,
                  updatedAt: data.updatedAt,
                  source: data.source,
                },
                null,
                2
              ),
            },
          ],
        };
      }

      // ── capture_region ──
      case "capture_region": {
        // Check license
        const license = getLicenseState();
        logInfo("capture_region called", { license, argsProvided: !!args?.x });

        // Build optional override region
        let override: Region | undefined;
        if (
          args?.x !== undefined &&
          args?.y !== undefined &&
          args?.width !== undefined &&
          args?.height !== undefined
        ) {
          override = {
            x: Number(args.x),
            y: Number(args.y),
            width: Number(args.width),
            height: Number(args.height),
          };
        }

        const result = captureRegion(override);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({
                success: true,
                region: result.region,
                timestamp: result.timestamp,
                sizeBytes: result.sizeBytes,
                format: result.format,
                displayScaleFactor: result.displayScaleFactor,
                captureMethod: result.captureMethod,
                license: {
                  tier: license.tier,
                  capturesRemaining: license.capturesRemaining,
                },
              }, null, 2),
            },
            {
              type: "image",
              data: result.base64,
              mimeType: "image/png",
            },
          ],
        };
      }

      default:
        return {
          content: [
            {
              type: "text",
              text: `Unknown tool: ${name}`,
            },
          ],
          isError: true,
        };
    }
  } catch (err: any) {
    logError(`Tool error [${name}]`, { error: err.message });
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            success: false,
            error: err.message,
            tool: name,
          }),
        },
      ],
      isError: true,
    };
  }
});

// ── Start Server ──

async function main() {
  logInfo("ScreenInspect MCP server starting", {
    version: "1.0.0",
    platform: process.platform,
    node: process.version,
    pid: process.pid,
  });

  if (process.platform !== "darwin") {
    logError("This server only works on macOS");
    process.stderr.write(
      "ERROR: ScreenInspect MCP server requires macOS.\n"
    );
    process.exit(1);
  }

  const transport = new StdioServerTransport();
  await server.connect(transport);

  logInfo("MCP server connected via stdio");
}

// Global error handlers
process.on("uncaughtException", (err) => {
  reportCrash(err);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  const err =
    reason instanceof Error ? reason : new Error(String(reason));
  reportCrash(err);
});

main().catch((err) => {
  reportCrash(err);
  process.exit(1);
});
