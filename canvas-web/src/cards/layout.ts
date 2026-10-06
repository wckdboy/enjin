// Pure geometry: no Excalidraw imports, so it is unit-testable in node.

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export const CARD_W = 320;
export const CARD_H = 180;
export const GAP = 48;
export const COLUMNS = 3;
export const HEADER_H = 110;

/**
 * Place `count` new cards in a grid below the portal header, skipping any
 * slot that overlaps an existing rect (kid content or earlier cards).
 */
export function placeCards(count: number, occupied: Rect[]): Rect[] {
  const placed: Rect[] = [];
  for (let slot = 0; placed.length < count; slot++) {
    const col = slot % COLUMNS;
    const row = Math.floor(slot / COLUMNS);
    const r = { x: col * (CARD_W + GAP), y: HEADER_H + row * (CARD_H + GAP), width: CARD_W, height: CARD_H };
    if (![...occupied, ...placed].some((o) => intersects(o, r, GAP / 2))) placed.push(r);
    if (slot > 10_000) throw new Error("placeCards: no free slot");
  }
  return placed;
}

export function intersects(a: Rect, b: Rect, margin = 0): boolean {
  return a.x < b.x + b.width + margin && b.x < a.x + a.width + margin && a.y < b.y + b.height + margin && b.y < a.y + a.height + margin;
}

export function union(rects: Rect[]): Rect | null {
  if (rects.length === 0) return null;
  const x1 = Math.min(...rects.map((r) => r.x));
  const y1 = Math.min(...rects.map((r) => r.y));
  const x2 = Math.max(...rects.map((r) => r.x + r.width));
  const y2 = Math.max(...rects.map((r) => r.y + r.height));
  return { x: x1, y: y1, width: x2 - x1, height: y2 - y1 };
}

export interface Viewport {
  scrollX: number;
  scrollY: number;
  zoom: number;
  width: number;
  height: number;
}

/** Excalidraw maps scene -> view as (p + scroll) * zoom. */
export function centerOn(rect: Rect, zoom: number, viewW: number, viewH: number): Pick<Viewport, "scrollX" | "scrollY" | "zoom"> {
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  return { zoom, scrollX: viewW / (2 * zoom) - cx, scrollY: viewH / (2 * zoom) - cy };
}

/** Zoom at which `rect` fits in the view with `padding` (fraction of view) on each side. */
export function fitZoom(rect: Rect, viewW: number, viewH: number, padding = 0.08, min = 0.1, max = 30): number {
  const z = Math.min((viewW * (1 - 2 * padding)) / rect.width, (viewH * (1 - 2 * padding)) / rect.height);
  return Math.min(max, Math.max(min, z));
}

export function toView(rect: Rect, vp: Viewport): Rect {
  return {
    x: (rect.x + vp.scrollX) * vp.zoom,
    y: (rect.y + vp.scrollY) * vp.zoom,
    width: rect.width * vp.zoom,
    height: rect.height * vp.zoom,
  };
}

/** Fraction of the viewport (0..1) covered by `rect`, clipped to the view. */
export function viewCoverage(rect: Rect, vp: Viewport): number {
  const v = toView(rect, vp);
  const w = Math.max(0, Math.min(v.x + v.width, vp.width) - Math.max(v.x, 0));
  const h = Math.max(0, Math.min(v.y + v.height, vp.height) - Math.max(v.y, 0));
  return (w * h) / (vp.width * vp.height);
}

/** Rect whose center is closest to the view center, among those at least partly visible. */
export function nearestToCenter<T extends { rect: Rect }>(items: T[], vp: Viewport): T | null {
  let best: T | null = null;
  let bestD = Infinity;
  for (const it of items) {
    if (viewCoverage(it.rect, vp) === 0) continue;
    const v = toView(it.rect, vp);
    const d = Math.hypot(v.x + v.width / 2 - vp.width / 2, v.y + v.height / 2 - vp.height / 2);
    if (d < bestD) {
      bestD = d;
      best = it;
    }
  }
  return best;
}

export function containsPoint(rect: Rect, x: number, y: number): boolean {
  return x >= rect.x && x <= rect.x + rect.width && y >= rect.y && y <= rect.y + rect.height;
}

// ---------- dive geometry ----------
//
// Diving zooms the camera into a "window" inside the card (a rect with the
// screen's aspect ratio). The child portal's framed view is drawn into that
// window, so when the window fills the screen the child scene can be swapped
// in at exactly the same pixels: no fade, no pop.

/** Largest rect with `aspect` (w/h) centered inside `card`, inset by `margin` x its short side. */
export function windowIn(card: Rect, aspect: number, margin = 0.06): Rect {
  const inset = Math.min(card.width, card.height) * margin;
  const inner = { x: card.x + inset, y: card.y + inset, width: card.width - 2 * inset, height: card.height - 2 * inset };
  const w = inner.width / inner.height > aspect ? inner.height * aspect : inner.width;
  const h = w / aspect;
  return { x: inner.x + (inner.width - w) / 2, y: inner.y + (inner.height - h) / 2, width: w, height: h };
}

/** The scene rect visible when `content` is framed by fitZoom in a viewW x viewH view. */
export function framedRect(content: Rect, viewW: number, viewH: number, padding = 0.08): Rect {
  const z = fitZoom(content, viewW, viewH, padding);
  const w = viewW / z;
  const h = viewH / z;
  return { x: content.x + content.width / 2 - w / 2, y: content.y + content.height / 2 - h / 2, width: w, height: h };
}

/** Map `r` from the `from` rect's space into the `to` rect's space (uniform scale; same aspect). */
export function mapRect(r: Rect, from: Rect, to: Rect): Rect {
  const s = to.width / from.width;
  return { x: to.x + (r.x - from.x) * s, y: to.y + (r.y - from.y) * s, width: r.width * s, height: r.height * s };
}

/** The scene rect currently on screen. */
export function visibleRect(vp: Viewport): Rect {
  return { x: -vp.scrollX, y: -vp.scrollY, width: vp.width / vp.zoom, height: vp.height / vp.zoom };
}
