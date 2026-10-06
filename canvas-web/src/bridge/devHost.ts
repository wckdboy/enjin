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

const portals = demo.portals as DemoPortal[];
const savedElements = new Map<string, Record<string, unknown>[]>();

function cardsIn(p: DemoPortal): Card[] {
  return p.cardIds.map((id) => {
    const c = demo.cards.find((c) => c.id === id)!;
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
  (window as unknown as { __devLog: unknown[] }).__devLog = log;
  return {
    async post(req) {
      log.push(req);
      const params = req.params as Record<string, string>;
      switch (req.method) {
        case "canvas.ready":
          setTimeout(() => getBridge().handle({ v: PROTOCOL_VERSION, id: "n1", method: "portal.load", params: { scene: sceneFor(demo.rootPortalId), transition: "jump" } }));
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
        case "canvas.changed":
          savedElements.set(params.portalId!, (req.params as { elements: Record<string, unknown>[] }).elements);
          return ok(req, null);
        default:
          return ok(req, null);
      }
    },
  };
}
