import { describe, expect, it } from "vitest";
import { exitPoint, layoutGraph, logTicks, niceTicks, tickLabel } from "../src/cards/figureMath";

describe("layoutGraph", () => {
  const box = { x: 10, y: 20, width: 650, height: 286 };
  const sizes = Array.from({ length: 6 }, () => ({ w: 120, h: 40 }));
  const edges: [number, number][] = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0], [0, 3]];

  it("keeps every node inside the box", () => {
    for (const p of layoutGraph(sizes, edges, box)) {
      expect(p.cx - 60).toBeGreaterThanOrEqual(box.x - 1e-6);
      expect(p.cx + 60).toBeLessThanOrEqual(box.x + box.width + 1e-6);
      expect(p.cy - 20).toBeGreaterThanOrEqual(box.y - 1e-6);
      expect(p.cy + 20).toBeLessThanOrEqual(box.y + box.height + 1e-6);
    }
  });

  it("is deterministic and keeps pills from overlapping", () => {
    const a = layoutGraph(sizes, edges, box);
    expect(layoutGraph(sizes, edges, box)).toEqual(a);
    for (let i = 0; i < a.length; i++)
      for (let j = i + 1; j < a.length; j++) {
        const overlap = Math.abs(a[i]!.cx - a[j]!.cx) < 120 && Math.abs(a[i]!.cy - a[j]!.cy) < 40;
        expect(overlap, `nodes ${i} and ${j}`).toBe(false);
      }
  });
});

describe("axes", () => {
  it("niceTicks covers the range with round steps", () => {
    expect(niceTicks(1971, 2021, 6)).toEqual([1970, 1980, 1990, 2000, 2010, 2020, 2030]);
    const t = niceTicks(0, 95, 5);
    expect(t[0]).toBe(0);
    expect(t[t.length - 1]).toBeGreaterThanOrEqual(95);
  });
  it("logTicks are decades", () => {
    expect(logTicks(2300, 5.7e10)).toEqual([1000, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11]);
  });
  it("tickLabel is short", () => {
    expect([tickLabel(1200), tickLabel(45000), tickLabel(3e6), tickLabel(5.7e10), tickLabel(0.005)]).toEqual(["1200", "45k", "3M", "57B", "0.005"]);
  });
  it("exitPoint leaves a rect at its edge", () => {
    expect(exitPoint({ cx: 0, cy: 0 }, 50, 20, { cx: 200, cy: 0 }, 0)).toEqual({ x: 50, y: 0 });
    expect(exitPoint({ cx: 0, cy: 0 }, 50, 20, { cx: 0, cy: -100 }, 0)).toEqual({ x: 0, y: -20 });
  });
});
