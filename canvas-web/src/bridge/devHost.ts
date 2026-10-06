// In-browser stand-in for the native app, so canvas-web runs under `vite dev`
// and Playwright. Mirrors the portal logic in EnjinKit's DemoNotebook.
import demo from "../../../shared/demo-notebook.json";
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
  cards: { id: string; type: string; title: string; summary: string; state: string }[];
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

const data: DemoData = new URLSearchParams(location.search).get("fixture") === "big" ? bigFixture() : (demo as DemoData);
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
