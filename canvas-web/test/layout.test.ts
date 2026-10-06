import { describe, expect, it } from "vitest";
import { CARD_W, centerOn, fitZoom, intersects, placeCards, toView, viewCoverage } from "../src/cards/layout";

describe("placeCards", () => {
  it("never overlaps existing content or itself", () => {
    const occupied = [{ x: 0, y: 110, width: 500, height: 200 }];
    const placed = placeCards(7, occupied);
    expect(placed).toHaveLength(7);
    for (const p of placed) expect(occupied.some((o) => intersects(o, p))).toBe(false);
    for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) expect(intersects(placed[i]!, placed[j]!)).toBe(false);
  });
  it("is deterministic", () => {
    expect(placeCards(5, [])).toEqual(placeCards(5, []));
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
