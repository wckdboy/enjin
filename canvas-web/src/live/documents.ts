import type { Visual } from "../bridge/schema";
import { mountDiorama } from "./diorama";
import { mount3D } from "./engine3d";
import { compileExpr } from "./expr";
import { mountUI } from "./uiKit";

/** Kinds that run in a sandboxed frame on the card (see LiveLayer). */
export const FRAME_KINDS = new Set<Visual["kind"]>(["live", "model3d", "diorama", "ui"]);

/** JSON that can sit inside a <script> without closing it. */
const safeJSON = (x: unknown) => JSON.stringify(x ?? {}).replace(/</g, "\\u003c").replace(/[\u2028\u2029]/g, " ");

/**
 * The page body for a frame figure, or null if there's nothing to run yet. Skill
 * kinds (model3d, diorama, ui) carry a spec and run ENJIN's own runtime, injected
 * from its source here; `live` is the agent's own HTML.
 */
export function frameBody(v: Visual, backdrop: string | null): string | null {
  const boot = (fn: string, args: string) =>
    `<div id="root" style="position:absolute;inset:0"></div><script>(${fn})(document.getElementById("root"), ${args});</script>`;
  switch (v.kind) {
    case "live":
      return v.html ?? null;
    case "model3d":
      return v.spec ? boot(mount3D.toString(), safeJSON(v.spec)) : null;
    case "diorama":
      return v.spec ? boot(mountDiorama.toString(), `${safeJSON(v.spec)}, ${backdrop ? safeJSON(backdrop) : "null"}`) : null;
    case "ui":
      return v.spec ? boot(mountUI.toString(), `${safeJSON(v.spec)}, ${compileExpr.toString()}`) : null;
    default:
      return null;
  }
}
