import { describe, expect, it } from "vitest";
import { layoutWorld, worldFromScene } from "../src/world/spec";

describe("world layout", () => {
  it("keeps the front open: nothing between you and the centrepiece", () => {
    const { doors, panels } = layoutWorld(5, 6);
    for (const p of [...doors, ...panels]) {
      const az = Math.atan2(p.x, p.z); // 0 = straight in front
      expect(Math.abs(az), `at ${JSON.stringify(p)}`).toBeGreaterThan((50 * Math.PI) / 180);
    }
  });
  it("puts panels behind and above the doors, and spaces them", () => {
    const { doors, panels } = layoutWorld(3, 4);
    expect(Math.min(...panels.map((p) => p.y))).toBeGreaterThan(Math.max(...doors.map((d) => d.y)));
    for (let i = 1; i < panels.length; i++) expect(Math.hypot(panels[i]!.x - panels[i - 1]!.x, panels[i]!.z - panels[i - 1]!.z)).toBeGreaterThan(5);
  });
  it("turns a portal's cards into a world", () => {
    const w = worldFromScene({ portalId: "p", title: "Motors", cards: [
      { id: "a", type: "topic", title: "Door", summary: "", state: "stub", childCount: 0 },
      { id: "m", type: "note", title: "Model", summary: "", state: "filled", childCount: 0, visual: { kind: "model3d", spec: { parts: [] } } },
      { id: "n", type: "note", title: "Note", summary: "", state: "filled", childCount: 0 },
    ] });
    expect(w.doors.map((c) => c.id)).toEqual(["a"]);
    expect(w.centerpiece?.cardId).toBe("m");
    expect(w.panels.map((c) => c.id)).toEqual(["n"]);
  });
});
