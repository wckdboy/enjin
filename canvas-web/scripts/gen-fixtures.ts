// Writes one JSON example per bridge method to shared/bridge-fixtures/.
// Both the web (vitest) and native (XCTest) contract tests decode these, so a
// schema change that only one side picks up fails a test on the other.
import { mkdirSync, writeFileSync } from "node:fs";
import { PROTOCOL_VERSION, nativeToWeb, webToNative, type PortalScene } from "../src/bridge/schema";

const scene: PortalScene = {
  portalId: "p-legions",
  title: "Legions",
  path: [
    { portalId: "p-root", title: "Roman Empire" },
    { portalId: "p-legions", title: "Legions" },
  ],
  cards: [
    { id: "c-why-won", type: "topic", title: "Why Rome won so much", summary: "Organisation.", state: "filled", childCount: 3 },
    { id: "c-equipment", type: "topic", title: "Equipment", summary: "Gladius, pilum.", state: "stub", childCount: 0 },
  ],
  elements: [{ id: "ink:s1:1", type: "freedraw", x: 10, y: 20, points: [[0, 0], [5, 5]], customData: { role: "ink" } }],
};

export const examples: Record<string, { direction: "nativeToWeb" | "webToNative"; params: unknown; result: unknown }> = {
  "portal.load": { direction: "nativeToWeb", params: { scene, transition: "dive", focusCardId: "c-why-won" }, result: null },
  "ink.lock": { direction: "nativeToWeb", params: { locked: true }, result: null },
  "ink.commit": {
    direction: "nativeToWeb",
    params: { strokeId: "s1", tool: "pen", color: "#1e1e1e", width: 3, points: [[1, 2], [3.5, 4]], pressures: [0.2, 0.9] },
    result: { strokeId: "s1", elementId: "ink:s1:1" },
  },
  "canvas.flash": { direction: "nativeToWeb", params: { cardId: "c-why-won" }, result: null },
  "canvas.ready": { direction: "webToNative", params: { protocolVersion: PROTOCOL_VERSION, excalidrawVersion: "0.18.1" }, result: { accepted: true } },
  "canvas.changed": { direction: "webToNative", params: { portalId: "p-legions", elements: scene.elements }, result: null },
  "focus.changed": { direction: "webToNative", params: { portalId: "p-legions", cardId: null, zoom: 1.25, visibleCardIds: ["c-why-won"] }, result: null },
  "portal.enter": { direction: "webToNative", params: { portalId: "p-root", cardId: "c-legions" }, result: scene },
  "portal.exit": { direction: "webToNative", params: { portalId: "p-legions" }, result: { scene, focusCardId: "c-legions" } },
  "log.event": { direction: "webToNative", params: { level: "warn", message: "hello", data: { n: 1 } }, result: null },
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = new URL("../../shared/bridge-fixtures/", import.meta.url).pathname;
  mkdirSync(dir, { recursive: true });
  const all = { ...nativeToWeb, ...webToNative } as Record<string, { params: { parse(x: unknown): unknown }; result: { parse(x: unknown): unknown } }>;
  for (const method of Object.keys(all)) if (!examples[method]) throw new Error(`no fixture for ${method}`);
  for (const [method, ex] of Object.entries(examples)) {
    all[method]!.params.parse(ex.params);
    all[method]!.result.parse(ex.result);
    const request = { v: PROTOCOL_VERSION, id: "fx-1", method, params: ex.params };
    const response = { v: PROTOCOL_VERSION, id: "fx-1", result: ex.result };
    writeFileSync(`${dir}${method}.json`, JSON.stringify({ direction: ex.direction, request, response }, null, 2) + "\n");
  }
  console.log(`wrote ${Object.keys(examples).length} fixtures to ${dir}`);
}
