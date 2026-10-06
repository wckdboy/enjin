// In-browser stand-in for the native app, so canvas-web runs under `vite dev`
// and Playwright. Mirrors the portal logic in EnjinKit's DemoNotebook.
import demo from "../../../shared/demo-notebook.json";
import motors from "../../../shared/sample-motors.json";
import type { Bridge, NativeTransport } from "./client";
import { PROTOCOL_VERSION, type Card, type PortalScene, type Request, type Response } from "./schema";

interface DemoPortal {
  portalId: string;
  title: string;
  ownerCardId: string | null;
  parentPortalId: string | null;
  cardIds: string[];
}

interface DemoData {
  rootPortalId: string;
  portals: DemoPortal[];
  cards: { id: string; type: string; title: string; summary: string; state: string; visual?: unknown }[];
}

/** `?fixture=figures`: one card per figure kind, for looking at and testing figures. */
function figuresFixture(): DemoData {
  const cards: DemoData["cards"] = [
    { id: "f-flow", type: "note", state: "filled", title: "How a robot decides", summary: "Every robot runs the same loop, many times a second.",
      visual: { kind: "flow", items: [{ label: "Sense", detail: "cameras, lidar, touch" }, { label: "Think", detail: "where am I? what's next?" }, { label: "Act", detail: "motors move" }, { label: "Check", detail: "did it work?" }] } },
    { id: "f-stat", type: "note", state: "filled", title: "Speed of light", summary: "Nothing with mass can reach it.", visual: { kind: "stat", value: "299,792", unit: "km/s" } },
    { id: "f-cycle", type: "note", state: "filled", title: "The cell cycle", summary: "How one cell becomes two.",
      visual: { kind: "cycle", center: "one cell → two", items: [{ label: "Grow (G1)" }, { label: "Copy DNA (S)" }, { label: "Check (G2)" }, { label: "Divide (M)" }] } },
    { id: "f-formula", type: "note", state: "filled", title: "Newton's second law", summary: "Push harder, speed up faster.",
      visual: { kind: "formula", text: "F = m × a", items: [{ label: "F", detail: "force, newtons" }, { label: "m", detail: "mass, kg" }, { label: "a", detail: "acceleration, m/s²" }] } },
    { id: "f-bars", type: "note", state: "filled", title: "How fast can it compute?", summary: "Operations per second, roughly.",
      visual: { kind: "bars", unit: "GFLOPS", items: [{ label: "Calculator", value: 0.001 }, { label: "Phone", value: 2000 }, { label: "Gaming PC", value: 80000 }, { label: "Supercomputer", value: 1200000 }] } },
    { id: "f-timeline", type: "note", state: "filled", title: "Robots, a short history", summary: "From factory arms to Mars rovers.",
      visual: { kind: "timeline", items: [{ tag: "1961", label: "Unimate", detail: "first factory robot arm" }, { tag: "1997", label: "Sojourner", detail: "first Mars rover" }, { tag: "2002", label: "Roomba", detail: "robots move in" }, { tag: "2021", label: "Ingenuity", detail: "flight on Mars" }] } },
    { id: "f-parts", type: "note", state: "filled", title: "Inside a drone", summary: "Four motors, one brain.",
      visual: { kind: "parts", center: "Quadcopter", items: [{ label: "Brushless motors" }, { label: "Flight controller" }, { label: "Propellers" }, { label: "Battery" }, { label: "GPS + compass" }, { label: "Camera" }] } },
    { id: "f-code", type: "note", state: "filled", title: "A loop in Python", summary: "Repeat until the job is done.",
      visual: { kind: "code", text: "for step in range(4):\n    sense()\n    think()\n    act()" } },
  ];
  return { rootPortalId: "p-root", portals: [{ portalId: "p-root", title: "Figures", ownerCardId: null, parentPortalId: null, cardIds: cards.map((c) => c.id) }], cards };
}

/** `?fixture=big`: 20 portals x 15 cards (300 cards), for performance tests. */
function bigFixture(): DemoData {
  const cards: DemoData["cards"] = [];
  const portals: DemoPortal[] = [{ portalId: "p-root", title: "Big notebook", ownerCardId: null, parentPortalId: null, cardIds: [] }];
  for (let i = 0; i < 20; i++) {
    const owner = `c-${i}`;
    cards.push({ id: owner, type: "topic", title: `Topic ${i}`, summary: "A topic with fifteen cards inside it.", state: "filled" });
    portals[0]!.cardIds.push(owner);
    const p: DemoPortal = { portalId: `p-${i}`, title: `Topic ${i}`, ownerCardId: owner, parentPortalId: "p-root", cardIds: [] };
    for (let j = 0; j < 15; j++) {
      const id = `c-${i}-${j}`;
      cards.push({ id, type: "topic", title: `Card ${i}.${j}`, summary: "Some words about this card so the label wraps onto two lines.", state: j % 3 ? "filled" : "stub" });
      p.cardIds.push(id);
    }
    portals.push(p);
  }
  return { rootPortalId: "p-root", portals, cards };
}

const fixture = new URLSearchParams(location.search).get("fixture");
const data: DemoData =
  fixture === "big" ? bigFixture() : fixture === "figures" ? figuresFixture() : fixture === "motors" ? (motors as DemoData) : (demo as DemoData);
const portals = data.portals;
const savedElements = new Map<string, Record<string, unknown>[]>();

function cardsIn(p: DemoPortal): Card[] {
  return p.cardIds.map((id) => {
    const c = data.cards.find((c) => c.id === id)!;
    const childCount = portals.find((q) => q.ownerCardId === id)?.cardIds.length ?? 0;
    return { ...c, childCount } as Card;
  });
}

export function sceneFor(portalId: string): PortalScene {
  const path: { portalId: string; title: string }[] = [];
  for (let p = portals.find((q) => q.portalId === portalId); p; p = portals.find((q) => q.portalId === p!.parentPortalId)) {
    path.unshift({ portalId: p.portalId, title: p.title });
  }
  const p = portals.find((q) => q.portalId === portalId)!;
  return { portalId, title: p.title, path, cards: cardsIn(p), elements: savedElements.get(portalId) ?? [] };
}

export function devHost(getBridge: () => Bridge): NativeTransport {
  const ok = (req: Request, result: unknown): Response => ({ v: PROTOCOL_VERSION, id: req.id, result });
  const log: unknown[] = [];
  (window as unknown as { __devLog: unknown[]; __devScene: typeof sceneFor }).__devLog = log;
  (window as unknown as { __devScene: typeof sceneFor }).__devScene = sceneFor;
  return {
    async post(req) {
      log.push(req);
      const params = req.params as Record<string, string>;
      switch (req.method) {
        case "canvas.ready":
          setTimeout(() => getBridge().handle({ v: PROTOCOL_VERSION, id: "n1", method: "portal.load", params: { scene: sceneFor(data.rootPortalId), transition: "jump" } }));
          return ok(req, { accepted: true });
        case "portal.enter": {
          const p = portals.find((q) => q.ownerCardId === params.cardId);
          return ok(req, p ? sceneFor(p.portalId) : null);
        }
        case "portal.exit": {
          const p = portals.find((q) => q.portalId === params.portalId);
          if (!p?.parentPortalId) return ok(req, null);
          return ok(req, { scene: sceneFor(p.parentPortalId), focusCardId: p.ownerCardId });
        }
        case "media.stylize":
          // The browser has no Metal shader; mark the data so tests can see the swap.
          return ok(req, { dataURL: (req.params as { dataURL: string }).dataURL, mimeType: "image/png" });
        case "canvas.changed":
          savedElements.set(params.portalId!, (req.params as { elements: Record<string, unknown>[] }).elements);
          return ok(req, null);
        default:
          return ok(req, null);
      }
    },
  };
}
