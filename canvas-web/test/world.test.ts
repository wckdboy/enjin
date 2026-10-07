import { describe, expect, it } from "vitest";
import type { Card } from "../src/bridge/schema";
import { DOOR, DOOR_SCALE, MODEL, freeSpot, layoutPlane, overlaps, worldFromScene } from "../src/world/spec";

const card = (id: string, extra: Partial<Card> = {}): Card => ({ id, type: "note", title: id, summary: "", state: "filled", childCount: 0, ...extra });

describe("the world's plane", () => {
  const sizes = [
    { w: 340, h: 260 }, { w: 600, h: 420 }, { w: 340, h: 520 }, { w: 600, h: 300 },
    { w: 340, h: 380 }, { w: 340, h: 700 }, { w: 600, h: 500 }, { w: 340, h: 260 },
  ];

  it("nothing overlaps: centrepiece, title, doors, their labels, panels", () => {
    for (const doors of [0, 1, 4, 7, 12]) {
      for (let n = 0; n <= sizes.length; n++) {
        const L = layoutPlane(sizes.slice(0, n), doors);
        const all = [L.model, L.title, ...L.doors, ...L.doorLabels, ...L.panels];
        for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) {
          expect(overlaps(all[i]!, all[j]!), `doors ${doors}, panels ${n}: ${i} vs ${j}`).toBe(false);
        }
        for (const r of all) {
          expect(r.x).toBeGreaterThanOrEqual(L.bounds.x);
          expect(r.x + r.w).toBeLessThanOrEqual(L.bounds.x + L.bounds.w);
        }
      }
    }
  });

  it("cards arriving one by one only ever add: earlier ones stay put", () => {
    const before = layoutPlane(sizes.slice(0, 4), 3);
    const after = layoutPlane(sizes, 3);
    expect(after.panels.slice(0, 4)).toEqual(before.panels);
    expect(after.doors).toEqual(before.doors);
  });

  it("panels sit either side of the centrepiece, doors beneath it", () => {
    const L = layoutPlane(sizes.slice(0, 2), 3);
    expect(L.panels[0]!.x + L.panels[0]!.w).toBeLessThan(L.model.x);
    expect(L.panels[1]!.x).toBeGreaterThan(L.model.x + L.model.w);
    for (const d of L.doors) expect(d.y).toBeGreaterThan(L.model.y + L.model.h);
  });

  it("a world inside a door shows its whole centrepiece within the circle", () => {
    const halfDiag = Math.hypot(MODEL.w / 2, MODEL.h / 2) * DOOR_SCALE;
    expect(halfDiag).toBeLessThanOrEqual(DOOR / 2);
  });

  it("maps a portal: first 3D model in the middle, topics become doors, the rest panels", () => {
    const w = worldFromScene({
      portalId: "p", title: "Motors",
      cards: [
        card("t1", { type: "topic" }),
        card("m", { type: "topic", visual: { kind: "model3d", spec: { parts: [] } } }),
        card("n1"),
        card("t2", { type: "topic", visual: { kind: "flow", items: [] } }),
      ],
    });
    expect(w.centerpiece?.cardId).toBe("m");
    expect(w.doors.map((c) => c.id)).toEqual(["t1"]);
    expect(w.panels.map((c) => c.id)).toEqual(["n1", "t2"]);
  });
});

describe("placing what grew from a sketch", () => {
  it("goes as close as it can to where it asked, without covering anything", () => {
    const taken = [{ x: 0, y: 0, w: 400, h: 300 }, { x: 500, y: 0, w: 200, h: 200 }];
    expect(freeSpot({ x: 900, y: 0, w: 100, h: 100 }, taken)).toEqual({ x: 900, y: 0, w: 100, h: 100 }); // already free
    const r = freeSpot({ x: 100, y: 100, w: 300, h: 200 }, taken);
    for (const t of taken) expect(r.x < t.x + t.w + 40 && t.x < r.x + r.w + 40 && r.y < t.y + t.h + 40 && t.y < r.y + r.h + 40).toBe(false);
    expect(Math.hypot(r.x - 100, r.y - 100)).toBeLessThan(700);
  });
});
