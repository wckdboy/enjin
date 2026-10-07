import type { Card, PortalScene } from "../bridge/schema";

/**
 * A world: what one portal looks like as a place on the plane. Built from the
 * portal's cards, so every notebook (old or new) is already a world:
 * - the centrepiece: the portal's first 3D model (a model3d figure);
 * - doors: its topic cards, round windows you zoom through into their worlds;
 * - panels: everything else (notes, figures, widgets, live models), on glass.
 */
export interface WorldSpec {
  portalId: string;
  title: string;
  subtitle?: string;
  centerpiece: { cardId: string; spec: Record<string, unknown> } | null;
  doors: Card[];
  panels: Card[];
}

export function worldFromScene(scene: Pick<PortalScene, "portalId" | "title" | "subtitle" | "cards">): WorldSpec {
  const cards = scene.cards;
  const model = cards.find((c) => c.visual?.kind === "model3d" && c.visual.spec);
  return {
    portalId: scene.portalId,
    title: scene.title,
    subtitle: scene.subtitle,
    centerpiece: model ? { cardId: model.id, spec: model.visual!.spec as Record<string, unknown> } : null,
    doors: cards.filter((c) => c.type === "topic" && !c.visual),
    panels: cards.filter((c) => c !== model && !(c.type === "topic" && !c.visual)),
  };
}

export interface Rect { x: number; y: number; w: number; h: number }

/** Plane units are CSS px at zoom 1. The centrepiece sits on the origin. */
export const MODEL = { w: 960, h: 720 };
export const DOOR = 280;
const GAP = 56;
const DOOR_STEP = 340;
/** Rows of three fit under the centrepiece, so the panels beside it never meet them. */
const DOORS_PER_ROW = 3;

export interface Layout {
  model: Rect;
  title: Rect;
  doors: Rect[];
  /** The door's label sits under it. */
  doorLabels: Rect[];
  panels: Rect[];
  bounds: Rect;
  /** Title, centrepiece and doors: what a narrow (portrait) view frames first. */
  core: Rect;
}

/**
 * Where things go on the plane: the title over the centrepiece, panels in
 * columns either side of it (each to the shorter one), doors in rows beneath.
 * Pure and deterministic, so cards streaming in only ever add to the picture.
 */
export function layoutPlane(panelSizes: { w: number; h: number }[], doors: number): Layout {
  const model: Rect = { x: -MODEL.w / 2, y: -MODEL.h / 2, w: MODEL.w, h: MODEL.h };
  const title: Rect = { x: -800, y: model.y - 250, w: 1600, h: 200 };

  // Doors: rows of up to three under the centrepiece, centred.
  const doorRects: Rect[] = [];
  const doorLabels: Rect[] = [];
  for (let i = 0; i < doors; i++) {
    const row = Math.floor(i / DOORS_PER_ROW);
    const inRow = Math.min(DOORS_PER_ROW, doors - row * DOORS_PER_ROW);
    const col = i % DOORS_PER_ROW;
    const cx = (col - (inRow - 1) / 2) * DOOR_STEP;
    const y = model.y + model.h + 110 + row * (DOOR + 170);
    doorRects.push({ x: cx - DOOR / 2, y, w: DOOR, h: DOOR });
    doorLabels.push({ x: cx - 160, y: y + DOOR + 18, w: 320, h: 80 });
  }

  // Panels: columns left and right of the centrepiece, from its top edge down.
  // A column that would grow past the doors starts a new one further out.
  const maxH = Math.max(1500, (doorRects.at(-1)?.y ?? 0) + DOOR + 120 - model.y);
  type Column = { side: -1 | 1; edge: number; y: number; width: number };
  const columns: Column[] = [
    { side: -1, edge: model.x - GAP * 1.5, y: model.y, width: 0 },
    { side: 1, edge: model.x + model.w + GAP * 1.5, y: model.y, width: 0 },
  ];
  const panels: Rect[] = panelSizes.map(({ w, h }) => {
    // The shorter of the two outermost columns (one per side).
    const outer = (side: -1 | 1) => columns.filter((c) => c.side === side).at(-1)!;
    let col = [outer(-1), outer(1)].sort((a, b) => a.y - b.y || a.side - b.side)[0]!;
    if (col.y > model.y && col.y + h - model.y > maxH) {
      col = { side: col.side, edge: col.edge + col.side * (col.width + GAP), y: model.y, width: 0 };
      columns.push(col);
    }
    const x = col.side === 1 ? col.edge : col.edge - w;
    const r = { x, y: col.y, w, h };
    col.y += h + GAP;
    col.width = Math.max(col.width, w);
    return r;
  });

  const union = (rs: Rect[], m: number): Rect => {
    const x0 = Math.min(...rs.map((r) => r.x)), y0 = Math.min(...rs.map((r) => r.y));
    const x1 = Math.max(...rs.map((r) => r.x + r.w)), y1 = Math.max(...rs.map((r) => r.y + r.h));
    return { x: x0 - m, y: y0 - m, w: x1 - x0 + 2 * m, h: y1 - y0 + 2 * m };
  };
  return {
    model, title, doors: doorRects, doorLabels, panels,
    bounds: union([model, title, ...doorRects, ...doorLabels, ...panels], 100),
    core: union([model, { ...title, x: model.x, w: model.w }, ...doorRects, ...doorLabels], 60),
  };
}

/** How big a world is drawn inside its door: its centrepiece fills most of the circle. */
export const DOOR_SCALE = (DOOR * 0.78) / MODEL.w;

export const overlaps = (a: Rect, b: Rect) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;

/** The nearest spot to `want` (spiralling out) that overlaps none of `taken`, with a margin. */
export function freeSpot(want: Rect, taken: Rect[], margin = 40): Rect {
  const hits = (r: Rect) => taken.some((t) => r.x < t.x + t.w + margin && t.x < r.x + r.w + margin && r.y < t.y + t.h + margin && t.y < r.y + r.h + margin);
  if (!hits(want)) return want;
  const step = 80;
  for (let ring = 1; ring < 60; ring++) {
    let best: Rect | null = null, bestD = Infinity;
    for (let i = -ring; i <= ring; i++) for (const [dx, dy] of [[i, -ring], [i, ring], [-ring, i], [ring, i]] as const) {
      const r = { ...want, x: want.x + dx * step, y: want.y + dy * step };
      const d = Math.hypot(dx, dy);
      if (d < bestD && !hits(r)) { best = r; bestD = d; }
    }
    if (best) return best;
  }
  return want;
}
