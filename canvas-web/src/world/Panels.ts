import { exportToSvg } from "@excalidraw/excalidraw";
import type { BinaryFiles } from "@excalidraw/excalidraw/types";
import * as THREE from "three";
import { COLOR_ONLY } from "./Look";
import { CSS3DObject, CSS3DRenderer } from "three/examples/jsm/renderers/CSS3DRenderer.js";
import type { Card } from "../bridge/schema";
import { cardRects, enjinData, renderCards } from "../cards/render";
import { FRAME_KINDS, frameBody } from "../live/documents";
import { liveDocument } from "../portal/LiveLayer";

/**
 * Scene pixels per world unit: a 320 px card is 3.2 units wide. CSS3D works in
 * pixels, so its scene is the world scaled up by this, seen by a scaled twin of
 * the camera (see `render`).
 */
export const PX_PER_UNIT = 100;

/**
 * Glass panels in 3D. Each card is drawn exactly as the canvas draws it (the
 * same renderer, exported to SVG), on frosted glass, placed in space with
 * CSS3D. Live figures (widgets, 3D models, dioramas, live code) run in their
 * sandboxed frame inside the panel, and take touches once the panel is chosen.
 */
export class Panels {
  readonly renderer = new CSS3DRenderer();
  readonly scene = new THREE.Scene();
  private panels = new Map<string, { obj: CSS3DObject; key: string; frame: HTMLIFrameElement | null; hole: THREE.Mesh }>();
  private active: string | null = null;
  private cssCamera = new THREE.PerspectiveCamera();
  /** Invisible planes in the 3D scene, one per panel, that punch through to it where it's nearer. */
  private holes = new THREE.Group();
  onTap: ((cardId: string) => void) | null = null;

  constructor(host: HTMLElement, world: THREE.Scene) {
    const el = this.renderer.domElement;
    Object.assign(el.style, { position: "absolute", inset: "0", pointerEvents: "none", zIndex: "1" });
    host.appendChild(el);
    this.holes.name = "holes";
    world.add(this.holes);
  }

  resize(w: number, h: number): void {
    this.renderer.setSize(w, h);
  }

  render(camera: THREE.PerspectiveCamera): void {
    // The same camera, in pixel units.
    this.cssCamera.copy(camera);
    this.cssCamera.position.multiplyScalar(PX_PER_UNIT);
    this.cssCamera.near = camera.near * PX_PER_UNIT;
    this.cssCamera.far = camera.far * PX_PER_UNIT;
    this.cssCamera.updateProjectionMatrix();
    this.cssCamera.updateMatrixWorld(true);
    this.renderer.render(this.scene, this.cssCamera);
  }

  /** A panel's position in world units. */
  worldPosition(cardId: string): THREE.Vector3 | undefined {
    return this.panels.get(cardId)?.obj.position.clone().divideScalar(PX_PER_UNIT);
  }

  object(cardId: string): CSS3DObject | undefined {
    return this.panels.get(cardId)?.obj;
  }

  /** Make one panel interactive (its live frame takes touches); the rest stay glass. */
  setActive(cardId: string | null): void {
    this.active = cardId;
    for (const [id, p] of this.panels) {
      p.obj.element.classList.toggle("on", id === cardId);
      if (p.frame) p.frame.style.pointerEvents = id === cardId ? "auto" : "none";
    }
  }

  /** Show exactly these cards at these places; unchanged cards are kept as they are. */
  async sync(cards: Card[], places: { x: number; y: number; z: number }[], files: BinaryFiles): Promise<void> {
    const keep = new Set(cards.map((c) => c.id));
    for (const [id, p] of this.panels) if (!keep.has(id)) { this.scene.remove(p.obj); this.holes.remove(p.hole); this.panels.delete(id); }
    await Promise.all(cards.map(async (card, i) => {
      const at = places[i]!;
      const key = JSON.stringify(card) + (card.image ? (files[card.image.fileId as never] ? "+img" : "-img") : "");
      let p = this.panels.get(card.id);
      if (!p || p.key !== key) {
        const built = await this.build(card, files);
        if (p) { this.scene.remove(p.obj); this.holes.remove(p.hole); }
        p = { obj: built.obj, key, frame: built.frame, hole: hole(built.width / PX_PER_UNIT, built.height / PX_PER_UNIT) };
        this.panels.set(card.id, p);
        this.scene.add(p.obj);
        this.holes.add(p.hole);
      }
      p.obj.position.set(at.x * PX_PER_UNIT, at.y * PX_PER_UNIT, at.z * PX_PER_UNIT);
      p.obj.lookAt(0, at.y * PX_PER_UNIT, 0);
      p.hole.position.set(at.x, at.y, at.z);
      p.hole.lookAt(0, at.y, 0);
    }));
    this.setActive(this.active);
  }

  private async build(card: Card, files: BinaryFiles): Promise<{ obj: CSS3DObject; frame: HTMLIFrameElement | null; width: number; height: number }> {
    const { elements } = renderCards([], [card], []);
    const frame = cardRects(elements)[0]!.rect;
    const svg = await exportToSvg({
      // Fonts inlined: this page never mounts Excalidraw, so its faces (Cascadia, Excalifont) aren't loaded here.
      elements: elements as never, files, exportPadding: 0,
      appState: { exportBackground: false, viewBackgroundColor: "transparent" } as never,
    });
    svg.setAttribute("width", String(frame.width));
    svg.setAttribute("height", String(frame.height));
    svg.style.display = "block";
    const el = document.createElement("div");
    el.className = "panel";
    el.dataset.cardId = card.id;
    Object.assign(el.style, { width: `${frame.width}px`, height: `${frame.height}px` });
    el.appendChild(svg);
    let live: HTMLIFrameElement | null = null;
    if (card.visual && FRAME_KINDS.has(card.visual.kind)) {
      const backdrop = card.visual.kind === "diorama" && card.image ? ((files[card.image.fileId as never]?.dataURL as string | undefined) ?? null) : null;
      const body = frameBody(card.visual, backdrop);
      const slot = elements.find((e) => enjinData(e)?.role === "live");
      if (body && slot) {
        live = document.createElement("iframe");
        live.setAttribute("sandbox", "allow-scripts");
        live.setAttribute("referrerpolicy", "no-referrer");
        live.srcdoc = liveDocument(body);
        Object.assign(live.style, {
          position: "absolute", left: `${slot.x - frame.x}px`, top: `${slot.y - frame.y}px`, width: `${slot.width}px`, height: `${slot.height}px`,
          border: "0", borderRadius: "14px", pointerEvents: "none", background: "#fff",
        });
        el.appendChild(live);
      }
    }
    el.addEventListener("pointerup", () => this.onTap?.(card.id));
    return { obj: new CSS3DObject(el), frame: live, width: frame.width, height: frame.height };
  }
}

/** A transparent "hole" the panel's size: writes clear pixels (and depth), so the CSS panel below shows through. */
const HOLE = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0, blending: THREE.NoBlending, side: THREE.FrontSide });
function hole(w: number, h: number): THREE.Mesh {
  const r = 0.22;
  const s = new THREE.Shape();
  s.moveTo(-w / 2 + r, -h / 2);
  s.lineTo(w / 2 - r, -h / 2); s.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + r);
  s.lineTo(w / 2, h / 2 - r); s.quadraticCurveTo(w / 2, h / 2, w / 2 - r, h / 2);
  s.lineTo(-w / 2 + r, h / 2); s.quadraticCurveTo(-w / 2, h / 2, -w / 2, h / 2 - r);
  s.lineTo(-w / 2, -h / 2 + r); s.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + r, -h / 2);
  const m = new THREE.Mesh(new THREE.ShapeGeometry(s, 6), HOLE);
  m.layers.set(COLOR_ONLY);
  return m;
}

/** A CSS3D layer in world units (scaled to pixels internally): labels above the 3D canvas. */
export class CssLayer {
  readonly renderer = new CSS3DRenderer();
  readonly scene = new THREE.Scene();
  private cam = new THREE.PerspectiveCamera();

  constructor(host: HTMLElement, z: number) {
    Object.assign(this.renderer.domElement.style, { position: "absolute", inset: "0", pointerEvents: "none", zIndex: String(z) });
    host.appendChild(this.renderer.domElement);
  }

  resize(w: number, h: number): void {
    this.renderer.setSize(w, h);
  }

  render(camera: THREE.PerspectiveCamera): void {
    this.cam.copy(camera);
    this.cam.position.multiplyScalar(PX_PER_UNIT);
    this.cam.updateMatrixWorld(true);
    this.renderer.render(this.scene, this.cam);
  }
}
