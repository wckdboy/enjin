import { exportToSvg } from "@excalidraw/excalidraw";
import type { BinaryFiles } from "@excalidraw/excalidraw/types";
import type * as THREE from "three";
import type { Card, PortalScene } from "../bridge/schema";
import { cardRects, enjinData, renderCards } from "../cards/render";
import { t } from "../i18n";
import { FRAME_KINDS, frameBody } from "../live/documents";
import { liveDocument } from "../portal/LiveLayer";
import { ModelView } from "./ModelView";
import { DOOR, DOOR_SCALE, freeSpot, layoutPlane, worldFromScene, type Layout, type Rect, type WorldSpec } from "./spec";

/** Where a world sits inside the one around it: its origin at (cx, cy), at scale k. */
export interface Nest { cx: number; cy: number; k: number }

interface Panel { el: HTMLDivElement; key: string; frame: HTMLIFrameElement | null; w: number; h: number }

/**
 * One world on the plane, as DOM: the title, the centrepiece's place (the
 * model itself is drawn by Look), doors (round windows onto the worlds inside
 * topics) and panels (cards drawn exactly as the canvas draws them, on glass).
 * Its origin is the centre of the centrepiece; main.ts places it on screen.
 * A world can sit inside another's door, clipped to the circle, until you
 * zoom through.
 */
export class Plane {
  readonly el = document.createElement("div");
  scene: PortalScene;
  spec: WorldSpec;
  layout: Layout = layoutPlane([], 0);
  model: ModelView | null = null;
  /** The world around this one, and where this one sits in it. */
  up: { plane: Plane; nest: Nest; doorId: string | null } | null = null;
  /** Worlds seen through this one's doors, by card id. */
  readonly children = new Map<string, Plane>();
  private modelKey = "";
  private panels = new Map<string, Panel>();
  private doors = new Map<string, { door: HTMLDivElement; label: HTMLDivElement; key: string }>();
  private titleEl = document.createElement("div");
  private building: Promise<void> = Promise.resolve();
  private pending: { scene: PortalScene; files: BinaryFiles } | null = null;
  private running = false;
  onError: ((e: unknown) => void) | null = null;
  /** Cards that just arrived: their panel or door appears with a little arrival. */
  private born = new Set<string>();

  markBorn(ids: string[]): void {
    for (const id of ids) this.born.add(id);
  }

  private arrive(id: string, el: HTMLElement): void {
    if (!this.born.delete(id)) return;
    el.classList.add("born");
    // A drawing that just landed offers to come alive for a while.
    if (el.classList.contains("sketch")) { el.classList.add("fresh"); setTimeout(() => el.classList.remove("fresh"), 20000); }
    el.addEventListener("animationend", () => el.classList.remove("born"), { once: true });
  }
  private active: string | null = null;
  onOpen: ((cardId: string) => void) | null = null;
  /** The explorer asked for their drawing to be brought to life. */
  onBringToLife: ((cardId: string) => void) | null = null;
  /** Cards placed by hand (sketches, and what grew from them), where they stand. */
  private placed = new Map<string, Rect>();

  constructor(scene: PortalScene, private env: THREE.Texture, private live: boolean) {
    this.scene = scene;
    this.spec = worldFromScene(scene);
    this.el.className = "plane";
    this.el.dataset.portalId = scene.portalId;
    this.titleEl.className = "wtitle";
    this.el.appendChild(this.titleEl);
  }

  get portalId(): string {
    return this.scene.portalId;
  }

  /**
   * Show this scene. Unchanged panels and models are kept. While one build runs,
   * newer scenes replace each other: at most one waits, so streaming never piles up work.
   */
  build(scene: PortalScene, files: BinaryFiles): Promise<void> {
    this.pending = { scene, files };
    if (!this.running) this.building = this.drain();
    return this.building;
  }

  private async drain(): Promise<void> {
    this.running = true;
    try {
      while (this.pending) {
        const { scene, files } = this.pending;
        this.pending = null;
        try {
          await this.doBuild(scene, files);
        } catch (e) {
          this.onError?.(e);
        }
      }
    } finally {
      this.running = false;
    }
  }

  private async doBuild(scene: PortalScene, files: BinaryFiles): Promise<void> {
    this.scene = scene;
    // The new spec goes live together with its layout (at the end): in between, the
    // world on screen still answers questions about its doors and panels consistently.
    const spec = worldFromScene(scene);

    // The centrepiece (a glass orb until there's a model; a model still being written may not build yet).
    const key = spec.centerpiece ? JSON.stringify(spec.centerpiece.spec) : "orb";
    if (key !== this.modelKey) {
      let model: ModelView;
      try {
        model = new ModelView(spec.centerpiece?.spec ?? null, this.env);
      } catch {
        model = new ModelView(null, this.env);
      }
      this.model?.dispose();
      this.model = model;
      this.modelKey = key;
    }

    // Panels: (re)draw the ones that changed.
    const keep = new Set(spec.panels.map((c) => c.id));
    for (const [id, p] of this.panels) if (!keep.has(id)) { p.el.remove(); this.panels.delete(id); }
    for (const card of spec.panels) {
      const k = panelKey(card, files, this.live);
      const old = this.panels.get(card.id);
      if (old?.key === k) continue;
      const built = await this.buildPanel(card, files, k);
      old?.el.remove();
      this.panels.set(card.id, built);
      this.el.appendChild(built.el);
      this.arrive(card.id, built.el);
    }

    // Panels flow in columns; cards placed by hand stand where they were put.
    const flowing = spec.panels.filter((c) => !c.place);
    const L = layoutPlane(flowing.map((c) => this.panels.get(c.id)!), spec.doors.length);
    // Sketches stand exactly where they were drawn. What grew from one (no size given) goes to the
    // nearest free spot from where it asked to be, so it never covers the model, a door or a panel.
    this.placed = new Map();
    const taken: Rect[] = [L.model, L.title, ...L.doors, ...L.doorLabels, ...L.panels];
    const placedCards = spec.panels.filter((c) => c.place);
    for (const c of placedCards.filter((c) => c.place!.w > 0)) {
      const p = c.place!;
      const r = { x: p.x, y: p.y, w: p.w, h: p.h };
      this.placed.set(c.id, r);
      taken.push(r);
    }
    for (const c of placedCards.filter((c) => !(c.place!.w > 0))) {
      const natural = this.panels.get(c.id)!;
      const r = freeSpot({ x: c.place!.x, y: c.place!.y, w: natural.w, h: natural.h }, taken);
      this.placed.set(c.id, r);
      taken.push(r);
    }
    for (const r of this.placed.values()) {
      const b = L.bounds, x1 = Math.max(b.x + b.w, r.x + r.w + 100), y1 = Math.max(b.y + b.h, r.y + r.h + 100);
      b.x = Math.min(b.x, r.x - 100); b.y = Math.min(b.y, r.y - 100); b.w = x1 - b.x; b.h = y1 - b.y;
    }
    this.spec = spec;
    this.layout = L;
    flowing.forEach((c, i) => place(this.panels.get(c.id)!.el, L.panels[i]!));
    for (const [id, r] of this.placed) place(this.panels.get(id)!.el, r);

    // Doors.
    const doorIds = new Set(spec.doors.map((c) => c.id));
    for (const [id, d] of this.doors) if (!doorIds.has(id)) { d.door.remove(); d.label.remove(); this.doors.delete(id); }
    spec.doors.forEach((card, i) => {
      const k = JSON.stringify([card.title, card.state, card.childCount, card.image?.fileId, card.image && !!files[card.image.fileId as never]]);
      let d = this.doors.get(card.id);
      if (!d || d.key !== k) {
        d?.door.remove();
        d?.label.remove();
        d = { ...buildDoor(card, files), key: k };
        this.doors.set(card.id, d);
        this.el.append(d.door, d.label);
        this.arrive(card.id, d.door);
      }
      d.door.classList.toggle("peeked", this.children.has(card.id));
      place(d.door, L.doors[i]!);
      place(d.label, L.doorLabels[i]!);
    });

    // The title over the centrepiece.
    this.titleEl.textContent = "";
    const h = document.createElement("h1");
    h.textContent = spec.title;
    this.titleEl.appendChild(h);
    if (spec.subtitle) {
      const p = document.createElement("p");
      p.textContent = spec.subtitle;
      this.titleEl.appendChild(p);
    }
    place(this.titleEl, L.title);
    this.setActive(this.active);
  }

  /** Make one panel interactive (its live frame takes touches, and it offers Open). */
  setActive(cardId: string | null): void {
    this.active = cardId;
    for (const [id, p] of this.panels) {
      p.el.classList.toggle("on", id === cardId);
      if (p.frame) p.frame.style.pointerEvents = id === cardId ? "auto" : "none";
    }
  }

  get activePanel(): string | null {
    return this.active;
  }

  /** Live frames run only in the world you're in; worlds seen through doors are still pictures. */
  setLive(on: boolean, files: BinaryFiles): Promise<void> {
    if (on === this.live) return this.building;
    this.live = on;
    return this.build(this.scene, files);
  }

  doorRect(cardId: string): Rect | null {
    const i = this.spec.doors.findIndex((c) => c.id === cardId);
    return i < 0 ? null : this.layout.doors[i]!;
  }

  /** Where a world inside this door sits. */
  doorNest(cardId: string): Nest | null {
    const r = this.doorRect(cardId);
    return r ? { cx: r.x + r.w / 2, cy: r.y + r.h / 2, k: DOOR_SCALE } : null;
  }

  panelRect(cardId: string): Rect | null {
    const placed = this.placed.get(cardId);
    if (placed) return placed;
    const i = this.spec.panels.filter((c) => !c.place).findIndex((c) => c.id === cardId);
    return i < 0 ? null : this.layout.panels[i]!;
  }

  panelElement(cardId: string): HTMLElement | null {
    return this.panels.get(cardId)?.el ?? null;
  }

  card(cardId: string): Card | undefined {
    return this.scene.cards.find((c) => c.id === cardId);
  }

  /** Seen through a door: clip to its circle. null = open (you're in it). */
  private clipped: boolean | null = null;
  clip(inDoor: boolean): void {
    if (this.clipped === inDoor) return;
    this.clipped = inDoor;
    // Open = a circle too big to see, so the change animates (world.css) both ways.
    const r = inDoor ? DOOR / 2 / DOOR_SCALE : 40000;
    this.el.style.clipPath = `circle(${r}px at 0px 0px)`;
    this.el.classList.toggle("nested", inDoor);
  }

  markPeeked(cardId: string, on: boolean): void {
    this.doors.get(cardId)?.door.classList.toggle("peeked", on);
  }

  dispose(): void {
    this.model?.dispose();
    this.model = null;
    for (const c of this.children.values()) c.dispose();
    this.children.clear();
    this.el.remove();
  }

  /** The explorer's drawing: just their ink where they drew it, and the offer to bring it to life. */
  private buildSketch(card: Card, files: BinaryFiles, key: string): Panel {
    const el = document.createElement("div");
    el.className = "sketch";
    el.dataset.cardId = card.id;
    const src = card.image ? (files[card.image.fileId as never]?.dataURL as string | undefined) : undefined;
    if (src) {
      const img = document.createElement("img");
      img.src = src;
      img.alt = card.summary || card.title;
      el.appendChild(img);
    }
    const go = document.createElement("button");
    go.className = "alive";
    go.textContent = t.bringToLife();
    go.addEventListener("click", (e) => {
      e.stopPropagation();
      go.disabled = true;
      go.textContent = t.enjinBuilding();
      this.onBringToLife?.(card.id);
    });
    el.appendChild(go);
    return { el, key, frame: null, w: card.place?.w || 300, h: card.place?.h || 200 };
  }

  private async buildPanel(card: Card, files: BinaryFiles, key: string): Promise<Panel> {
    if (card.sketch) return this.buildSketch(card, files, key);
    const { elements } = renderCards([], [card], []);
    const frame = cardRects(elements)[0]!.rect;
    const svg = await exportToSvg({
      // Fonts inlined: this page never mounts Excalidraw, so its faces aren't loaded here.
      elements: elements as never, files, exportPadding: 0,
      appState: { exportBackground: false, viewBackgroundColor: "transparent" } as never,
    });
    svg.setAttribute("width", String(frame.width));
    svg.setAttribute("height", String(frame.height));
    svg.style.display = "block";
    const el = document.createElement("div");
    el.className = card.state === "filling" ? "panel writing" : "panel";
    el.dataset.cardId = card.id;
    el.appendChild(svg);
    let live: HTMLIFrameElement | null = null;
    if (this.live && card.visual && FRAME_KINDS.has(card.visual.kind)) {
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
    const open = document.createElement("button");
    open.className = "open";
    open.textContent = t.actionOpen();
    open.addEventListener("click", (e) => { e.stopPropagation(); this.onOpen?.(card.id); });
    el.appendChild(open);
    return { el, key, frame: live, w: frame.width, h: frame.height };
  }
}

function panelKey(card: Card, files: BinaryFiles, live: boolean): string {
  const hasFrame = !!card.visual && FRAME_KINDS.has(card.visual.kind);
  return JSON.stringify(card) + (card.image ? (files[card.image.fileId as never] ? "+img" : "-img") : "") + (live && hasFrame ? "+live" : "");
}

function place(el: HTMLElement, r: Rect): void {
  Object.assign(el.style, { left: `${r.x}px`, top: `${r.y}px`, width: `${r.w}px`, height: `${r.h}px` });
}

/** A door: a glass circle showing the topic (its picture, or its name), its title underneath. */
function buildDoor(card: Card, files: BinaryFiles): { door: HTMLDivElement; label: HTMLDivElement } {
  const door = document.createElement("div");
  door.className = `door${card.state === "stub" ? " stub" : ""}${card.state === "filling" ? " writing" : ""}`;
  door.dataset.door = card.id;
  const peek = document.createElement("div");
  peek.className = "peek";
  const pic = card.image ? (files[card.image.fileId as never]?.dataURL as string | undefined) : undefined;
  if (pic) {
    peek.style.backgroundImage = `url("${pic}")`;
    peek.classList.add("pic");
  } else {
    const name = document.createElement("b");
    name.textContent = card.title;
    peek.appendChild(name);
  }
  door.appendChild(peek);
  const label = document.createElement("div");
  label.className = "dlabel";
  label.dataset.door = card.id;
  const title = document.createElement("b");
  title.textContent = card.title;
  const sub = document.createElement("span");
  sub.textContent = card.childCount > 0 ? t.inside(card.childCount).toUpperCase() : t.diveIn().toUpperCase();
  label.append(title, sub);
  return { door, label };
}
