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
    { id: "c-why-won", type: "topic", title: "Why Rome won so much", summary: "Organisation.", state: "filled", childCount: 3, image: { fileId: "img-1", width: 800, height: 533 } },
    { id: "c-equipment", type: "topic", title: "Equipment", summary: "Gladius, pilum.", state: "filling", childCount: 0, imagePending: true },
    {
      id: "c-march", type: "note", title: "A day's march", summary: "Up before dawn, camp built by dusk.", state: "filled", childCount: 0,
      visual: { kind: "flow", items: [{ label: "Break camp", detail: "at dawn" }, { label: "March", detail: "about 30 km" }, { label: "Build camp", detail: "ditch and wall" }] },
    },
    { id: "c-pace", type: "note", title: "Marching pace", summary: "With 30 kg on their backs.", state: "filled", childCount: 0, visual: { kind: "stat", value: "30", unit: "km/day" } },
  ],
  files: [{ id: "img-1", mimeType: "image/png", dataURL: "data:image/png;base64,iVBORw0KGgo=" }],
  hero: { fileId: "img-1", width: 800, height: 533 },
  subtitle: "Rome's professional heavy infantry.",
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
  "canvas.applyOps": {
    direction: "nativeToWeb",
    params: {
      portalId: "p-legions",
      ops: [
        { op: "upsert", card: { id: "c-new", type: "topic", title: "Testudo", summary: "Shields locked like a tortoise shell.", state: "filling", childCount: 0 } },
        { op: "delete", cardId: "c-equipment" },
      ],
    },
    result: { placed: [{ cardId: "c-new", x: 368, y: 110, width: 320, height: 180 }] },
  },
  "canvas.setHeader": { direction: "nativeToWeb", params: { portalId: "p-legions", title: "Legions", subtitle: "Heavy infantry.", hero: { fileId: "img-1", width: 800, height: 533 } }, result: null },
  "canvas.setBusy": { direction: "nativeToWeb", params: { portalId: "p-legions", message: "Enjin is exploring Legions…" }, result: null },
  "canvas.setInsets": { direction: "nativeToWeb", params: { top: 80, left: 100, bottom: 150, right: 24 }, result: null },
  "canvas.setTool": { direction: "nativeToWeb", params: { tool: "highlighter", color: "#e8590c" }, result: null },
  "canvas.history": { direction: "nativeToWeb", params: { action: "undo" }, result: null },
  "canvas.setLanguage": { direction: "nativeToWeb", params: { language: "da" }, result: null },
  "canvas.addFiles": { direction: "nativeToWeb", params: { files: [{ id: "img-2", mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,/9j/" }] }, result: null },
  "canvas.frame": { direction: "nativeToWeb", params: { cardId: "c-why-won" }, result: { framed: true } },
  "canvas.flash": { direction: "nativeToWeb", params: { cardId: "c-why-won" }, result: null },
  "canvas.liveDocument": { direction: "nativeToWeb", params: { cardId: "c-march" }, result: { html: "<!doctype html><html><body><p>model</p></body></html>" } },
  "canvas.ready": { direction: "webToNative", params: { protocolVersion: PROTOCOL_VERSION, excalidrawVersion: "0.18.1" }, result: { accepted: true } },
  "canvas.changed": { direction: "webToNative", params: { portalId: "p-legions", elements: scene.elements }, result: null },
  "focus.changed": { direction: "webToNative", params: { portalId: "p-legions", cardId: null, zoom: 1.25, visibleCardIds: ["c-why-won"] }, result: null },
  "card.open": { direction: "webToNative", params: { cardId: "c-why-won" }, result: null },
  "card.visualize": { direction: "webToNative", params: { cardId: "c-why-won" }, result: null },
  "media.stylize": {
    direction: "webToNative",
    params: { dataURL: "data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png" },
    result: { dataURL: "data:image/jpeg;base64,/9j/", mimeType: "image/jpeg" },
  },
  "selection.changed": { direction: "webToNative", params: { portalId: "p-legions", cardIds: ["c-why-won"] }, result: null },
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
