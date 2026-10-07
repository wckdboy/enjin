import type { Visual } from "../bridge/schema";
import { mountDiorama } from "./diorama";
import { mount3D } from "./engine3d";
import { compileExpr } from "./expr";
import { mountSim } from "./sim";
import { mountUI } from "./uiKit";

/** JSON that can sit inside a <script> without closing it. */
const safeJSON = (x: unknown) => JSON.stringify(x ?? {}).replace(/</g, "\\u003c").replace(/[\u2028\u2029]/g, " ");

/** Start a runtime in the frame: its own source, injected, called with the root and its arguments. */
const boot = (fn: (...a: never[]) => void, args: string) =>
  `<div id="root" style="position:absolute;inset:0"></div><script>(${fn.toString()})(document.getElementById("root"), ${args});</script>`;

/**
 * The modules that run in a sandboxed frame on a card (see LiveLayer): ENJIN's
 * own runtimes, started from the spec the agent wrote, and `live`, the agent's
 * own HTML. Adding a module: write its runtime (self-contained, like sim.ts),
 * register it here, and give it a Skill in EnjinKit (Skills/SkillRegistry.swift),
 * which teaches Enjin its grammar. shared/skills.json keeps the two in step.
 */
export const FRAME_MODULES: Partial<Record<Visual["kind"], { height: number; body(v: Visual, backdrop: string | null): string | null }>> = {
  live: { height: 380, body: (v) => v.html ?? null },
  model3d: { height: 400, body: (v) => (v.spec ? boot(mount3D, safeJSON(v.spec)) : null) },
  diorama: { height: 400, body: (v, backdrop) => (v.spec ? boot(mountDiorama, `${safeJSON(v.spec)}, ${backdrop ? safeJSON(backdrop) : "null"}`) : null) },
  ui: { height: 420, body: (v) => (v.spec ? boot(mountUI, `${safeJSON(v.spec)}, ${compileExpr.toString()}`) : null) },
  sim: { height: 420, body: (v) => (v.spec ? boot(mountSim, `${safeJSON(v.spec)}, ${compileExpr.toString()}`) : null) },
};

/** Kinds that run in a sandboxed frame on the card. */
export const FRAME_KINDS = new Set(Object.keys(FRAME_MODULES) as Visual["kind"][]);

/** The page body for a frame figure, or null if there's nothing to run yet. */
export function frameBody(v: Visual, backdrop: string | null): string | null {
  return FRAME_MODULES[v.kind]?.body(v, backdrop) ?? null;
}
