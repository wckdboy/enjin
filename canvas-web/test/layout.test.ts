import { describe, expect, it } from "vitest";
import { CARD_W, centerOn, fitZoom, intersects, placeCards, toView, viewCoverage } from "../src/cards/layout";

describe("placeCards", () => {
  it("never overlaps existing content or itself", () => {
    const occupied = [{ x: 0, y: 110, width: 500, height: 200 }];
    const placed = placeCards([180, 370, 180, 370, 370, 180, 180].map((h) => ({ width: CARD_W, height: h })), occupied);
    expect(placed).toHaveLength(7);
    for (const p of placed) expect(occupied.some((o) => intersects(o, p))).toBe(false);
    for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) expect(intersects(placed[i]!, placed[j]!)).toBe(false);
  });
  it("is deterministic", () => {
    const sizes = [1, 2, 3, 4, 5].map((i) => ({ width: CARD_W, height: i % 2 ? 196 : 386 }));
    expect(placeCards(sizes, [])).toEqual(placeCards(sizes, []));
  });
  it("fills the shortest column first (masonry)", () => {
    const [a, b, c, d] = placeCards([370, 180, 180, 180].map((h) => ({ width: CARD_W, height: h })), []);
    expect([a!.y, b!.y, c!.y]).toEqual([110, 110, 110]);
    // The 4th goes under a short card, not under the tall one.
    expect(d!.x).not.toBe(a!.x);
  });
});

describe("viewport math", () => {
  it("centerOn puts the rect center at the view center", () => {
    const r = { x: 100, y: 50, width: CARD_W, height: 180 };
    const vp = { ...centerOn(r, 2.5, 1000, 800), width: 1000, height: 800 };
    const v = toView(r, vp);
    expect(v.x + v.width / 2).toBeCloseTo(500);
    expect(v.y + v.height / 2).toBeCloseTo(400);
  });
  it("fitZoom fits with padding and clamps to Excalidraw's range", () => {
    expect(fitZoom({ x: 0, y: 0, width: 100, height: 100 }, 1000, 1000, 0)).toBe(10);
    expect(fitZoom({ x: 0, y: 0, width: 1, height: 1 }, 1000, 1000)).toBe(30);
  });
  it("viewCoverage clips to the view", () => {
    const vp = { scrollX: 0, scrollY: 0, zoom: 1, width: 100, height: 100 };
    expect(viewCoverage({ x: -50, y: 0, width: 100, height: 100 }, vp)).toBeCloseTo(0.5);
  });
});

import { framedRect, mapRect, visibleRect, windowIn } from "../src/cards/layout";

describe("dive geometry", () => {
  const card = { x: 100, y: 200, width: 320, height: 180 };
  it("windowIn keeps the screen aspect and stays inside the card", () => {
    for (const aspect of [834 / 1194, 1194 / 834, 1]) {
      const w = windowIn(card, aspect);
      expect(w.width / w.height).toBeCloseTo(aspect);
      expect(w.x).toBeGreaterThanOrEqual(card.x);
      expect(w.y).toBeGreaterThanOrEqual(card.y);
      expect(w.x + w.width).toBeLessThanOrEqual(card.x + card.width + 1e-9);
      expect(w.y + w.height).toBeLessThanOrEqual(card.y + card.height + 1e-9);
    }
  });
  it("framedRect is exactly what centerOn+fitZoom shows", () => {
    const content = { x: 0, y: 0, width: 1100, height: 600 };
    const f = framedRect(content, 834, 1194);
    const z = 834 / f.width;
    const vp = { ...centerOn(content, z, 834, 1194), width: 834, height: 1194 };
    const v = visibleRect(vp);
    expect(v.x).toBeCloseTo(f.x);
    expect(v.y).toBeCloseTo(f.y);
    expect(v.width).toBeCloseTo(f.width);
    expect(v.height).toBeCloseTo(f.height);
  });
  it("mapRect maps the whole source onto the target", () => {
    const from = { x: -50, y: -100, width: 1000, height: 1432 };
    const to = windowIn(card, 1000 / 1432);
    expect(mapRect(from, from, to)).toEqual(to);
    const inner = mapRect({ x: 450, y: 616, width: 0, height: 0 }, from, to);
    expect(inner.x).toBeCloseTo(to.x + to.width / 2);
  });
});

import { coverCrop } from "../src/cards/layout";

describe("coverCrop", () => {
  it("keeps the box aspect and stays inside the image", () => {
    for (const [w, h] of [[800, 1067], [800, 300], [640, 384]] as const) {
      const c = coverCrop(w, h, 300 / 180);
      expect(c.width / c.height).toBeCloseTo(300 / 180);
      expect(c.x).toBeGreaterThanOrEqual(0);
      expect(c.y).toBeGreaterThanOrEqual(0);
      expect(c.x + c.width).toBeLessThanOrEqual(w + 1e-9);
      expect(c.y + c.height).toBeLessThanOrEqual(h + 1e-9);
    }
  });
});
