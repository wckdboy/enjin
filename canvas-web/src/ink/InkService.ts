import { CaptureUpdateAction, restoreElements, viewportCoordsToSceneCoords } from "@excalidraw/excalidraw";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import type { NativeToWeb, Params, Result } from "../bridge/schema";
import { nextPaint } from "../portal/animate";

/** perfect-freehand in Excalidraw renders freedraw at roughly strokeWidth * 4.25 px wide. */
const FREEDRAW_SIZE_FACTOR = 4.25;

let seq = 0;

/**
 * Turns a finished PencilKit stroke (view coordinates) into an Excalidraw freedraw element.
 * Web does the conversion because only web knows the exact viewport at this instant.
 */
export async function commitStroke(api: ExcalidrawImperativeAPI, p: Params<NativeToWeb, "ink.commit">): Promise<Result<NativeToWeb, "ink.commit">> {
  const state = api.getAppState();
  // Points arrive relative to the web view; Excalidraw wants client coords (it subtracts offsetLeft/Top).
  const scene = p.points.map(([x, y]) => viewportCoordsToSceneCoords({ clientX: x + state.offsetLeft, clientY: y + state.offsetTop }, state));
  const ox = scene[0]!.x;
  const oy = scene[0]!.y;
  const rel = scene.map((pt) => [pt.x - ox, pt.y - oy] as [number, number]);
  const xs = rel.map((r) => r[0]);
  const ys = rel.map((r) => r[1]);
  const highlighter = p.tool === "highlighter";
  const id = `ink:${p.strokeId}:${++seq}`;

  const [el] = restoreElements(
    [
      {
        type: "freedraw",
        id,
        x: ox,
        y: oy,
        width: Math.max(...xs) - Math.min(...xs),
        height: Math.max(...ys) - Math.min(...ys),
        points: rel,
        pressures: p.pressures.length === p.points.length ? p.pressures : [],
        simulatePressure: p.pressures.length !== p.points.length,
        strokeColor: p.color,
        strokeWidth: p.width / state.zoom.value / FREEDRAW_SIZE_FACTOR,
        opacity: highlighter ? 35 : 100,
        roughness: 0,
        customData: { role: "ink", tool: p.tool },
      } as never,
    ],
    null,
  );
  // Kid ink is a kid action: it belongs on the undo stack.
  api.updateScene({ elements: [...api.getSceneElementsIncludingDeleted(), el!], captureUpdate: CaptureUpdateAction.IMMEDIATELY });
  // Reply only once it's on screen, so native can drop its copy without a flicker.
  await nextPaint();
  return { strokeId: p.strokeId, elementId: id };
}
