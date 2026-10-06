import { describe, expect, it } from "vitest";
import { frameBody } from "../src/live/documents";

describe("frameBody", () => {
  it("runs ENJIN's runtime for skills, the agent's html for live", () => {
    expect(frameBody({ kind: "live", html: "<p>hi</p>" }, null)).toBe("<p>hi</p>");
    const ui = frameBody({ kind: "ui", spec: { blocks: [{ type: "heading", text: "x" }] } }, null)!;
    expect(ui).toContain("mountUI");
    expect(ui).toContain("compileExpr");
    expect(frameBody({ kind: "model3d", spec: { parts: [] } }, null)).toContain("mount3D");
  });
  it("waits while the spec is still being written", () => {
    expect(frameBody({ kind: "model3d" }, null)).toBeNull();
    expect(frameBody({ kind: "live" }, null)).toBeNull();
  });
  it("can't be broken out of by text in the spec", () => {
    const body = frameBody({ kind: "ui", spec: { blocks: [{ type: "text", text: "</script><script>alert(1)</script>" }] } }, null)!;
    expect(body.match(/<\/script>/g)).toHaveLength(1); // only the runtime's own closing tag
  });
});
