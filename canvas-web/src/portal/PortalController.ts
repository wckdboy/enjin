import { CaptureUpdateAction, exportToCanvas, getSceneVersion, newElementWith, restoreElements, viewportCoordsToSceneCoords } from "@excalidraw/excalidraw";
import type { ExcalidrawElement, NonDeletedExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import type { Bridge } from "../bridge/client";
import type { Card, Params, NativeToWeb, PortalScene, Result } from "../bridge/schema";
import { buildPortalElements, cardRects, renderCards } from "../cards/render";
import { type Rect, type Viewport, centerOn, containsPoint, fitZoom, framedRect, mapRect, nearestToCenter, toView, union, visibleRect, windowIn } from "../cards/layout";
import type { InputGate } from "../inputGate";
import { cssTransition, nextPaint, setStyleNow, tween } from "./animate";
import { CardActions } from "./CardActions";
import { PreviewOverlay } from "./PreviewOverlay";

/** A card this big on screen (fraction of view width or height) dives in. */
const DIVE_AT = 0.8;
/** Zooming out below this fraction of the portal's fitted zoom exits to the parent. */
const EXIT_AT = 0.55;
const DOUBLE_TAP_MS = 300;
/** Dive/exit camera flight. Long enough to read as a zoom, short enough to feel instant. */
const DIVE_MS = 620;
const EXIT_MS = 620;
const BACKGROUND = "#fffdf8";
const DOUBLE_TAP_PX = 30;

type Zoom = { value: number };

export class PortalController {
  private scene: PortalScene | null = null;
  private fittedZoom = 1;
  private transitioning = false;
  private lastSceneVersion = -1;
  private changeTimer: number | undefined;
  private pendingFlush: (() => void) | null = null;
  private lastSelection = "";
  /** Portal being transitioned to, and a promise that settles once it's installed. */
  private loading: { portalId: string; done: Promise<void> } | null = null;
  private focusTimer: number | undefined;
  private lastTap: { t: number; x: number; y: number } | null = null;
  private unsubs: (() => void)[] = [];
  private overlay = new PreviewOverlay();
  private actions = new CardActions({
    open: (cardId) => this.bridge.notify("card.open", { cardId }),
    dive: (cardId) => void this.requestDive(cardId),
  });
  private selectedCardId: string | null = null;

  constructor(
    private api: ExcalidrawImperativeAPI,
    private bridge: Bridge,
    private gate: InputGate,
    /** Element whose CSS transform/opacity is animated during transitions. */
    private stage: HTMLElement,
  ) {
    this.unsubs.push(api.onScrollChange(() => this.onViewportChanged()));
    this.unsubs.push(api.onChange((els) => this.onElementsChanged(els)));
    // Capture phase on window: we must see double-taps before Excalidraw does,
    // because its own double-tap starts editing the card's text.
    window.addEventListener("touchstart", this.onTouchStart, { capture: true, passive: false });
    window.addEventListener("dblclick", this.onDoubleClick, { capture: true });
  }

  dispose(): void {
    this.unsubs.forEach((u) => u());
    window.removeEventListener("touchstart", this.onTouchStart, { capture: true });
    window.removeEventListener("dblclick", this.onDoubleClick, { capture: true });
  }

  get portalId(): string | null {
    return this.scene?.portalId ?? null;
  }

  // ---------- native -> web ----------

  async load({ scene, transition, focusCardId }: Params<NativeToWeb, "portal.load">): Promise<void> {
    this.flushChanges();
    this.transitioning = true;
    this.gate.block("transition");
    this.positionActions();
    try {
      if (transition === "dive" && focusCardId && this.scene) await this.diveThrough(focusCardId, Promise.resolve(scene));
      else if (transition === "exit" && this.scene) await this.exitThrough(scene, focusCardId);
      else await this.loadingInto(scene.portalId, () => this.fadeTo(scene, focusCardId));
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
      this.positionActions();
    }
  }

  /** Mark `portalId` as arriving so ops for it wait instead of being dropped. */
  private async loadingInto<T>(portalId: string, work: () => Promise<T>): Promise<T> {
    let settle!: () => void;
    this.loading = { portalId, done: new Promise<void>((r) => (settle = r)) };
    try {
      return await work();
    } finally {
      settle();
      this.loading = null;
    }
  }

  frame(cardId: string): { framed: boolean } {
    const c = cardRects(this.api.getSceneElements()).find((r) => r.cardId === cardId);
    if (!c || this.transitioning) return { framed: false };
    const vp = this.viewport();
    // Fit the card comfortably, but never zoom in far enough to trigger a dive.
    const z = Math.min(fitZoom(c.rect, vp.width, vp.height, 0.3), this.fittedZoom * 1.2);
    void this.flyToRect(c.rect, z, 450);
    return { framed: true };
  }

  async flash(cardId: string): Promise<void> {
    const recolor = (color: string) =>
      this.api.updateScene({
        elements: this.api
          .getSceneElements()
          .map((e) => (e.customData?.cardId === cardId && e.customData?.role === "frame" ? newElementWith(e, { strokeColor: color, strokeWidth: 4 }) : e)),
        captureUpdate: CaptureUpdateAction.NEVER,
      });
    for (let i = 0; i < 3; i++) {
      recolor("#f76707");
      await new Promise((r) => setTimeout(r, 220));
      recolor("#343a40");
      await new Promise((r) => setTimeout(r, 160));
    }
  }

  async applyOps(p: Params<NativeToWeb, "canvas.applyOps">): Promise<Result<NativeToWeb, "canvas.applyOps">> {
    // Ops for the portal we're diving into land once it's on screen, not never.
    if (this.loading?.portalId === p.portalId) await this.loading.done;
    return this.applyOpsNow(p);
  }

  private applyOpsNow({ portalId, ops }: Params<NativeToWeb, "canvas.applyOps">): Result<NativeToWeb, "canvas.applyOps"> {
    if (!this.scene || this.scene.portalId !== portalId) return { placed: [] };
    const upserts = ops.flatMap((o) => (o.op === "upsert" ? [o.card] : []));
    const deletes = ops.flatMap((o) => (o.op === "delete" ? [o.cardId] : []));
    // Keep our copy of the card list in sync so dive/focus logic sees new cards.
    const byId = new Map(this.scene.cards.map((c) => [c.id, c]));
    for (const c of upserts) byId.set(c.id, c);
    for (const id of deletes) byId.delete(id);
    this.scene = { ...this.scene, cards: [...byId.values()] };

    const { elements, placed } = renderCards(this.api.getSceneElementsIncludingDeleted(), upserts, deletes);
    // Agent/native ops stay out of the kid's undo stack (plan §5.3).
    this.api.updateScene({ elements, captureUpdate: CaptureUpdateAction.NEVER });
    return { placed: placed.map((p) => ({ cardId: p.cardId, ...p.rect })) };
  }

  // ---------- transitions ----------

  private viewport(): Viewport {
    const s = this.api.getAppState();
    return { scrollX: s.scrollX, scrollY: s.scrollY, zoom: s.zoom.value, width: s.width, height: s.height };
  }

  private setViewport(v: { scrollX: number; scrollY: number; zoom: number }): void {
    this.api.updateScene({
      appState: { scrollX: v.scrollX, scrollY: v.scrollY, zoom: { value: v.zoom } as Zoom as never },
      captureUpdate: CaptureUpdateAction.NEVER,
    });
  }

  /**
   * Animate the camera to `target`. Zoom is interpolated geometrically (equal
   * ratios per frame read as constant speed) and `anchor` (a scene point, the
   * thing the eye is on) moves in a straight line on screen from where it is
   * now to where it ends up. Anchoring on the card you're entering or leaving
   * keeps it under your eye instead of swinging around.
   */
  private async flyTo(target: { scrollX: number; scrollY: number; zoom: number }, anchor: { x: number; y: number }, ms: number,
                      onStep?: (t: number, vp: Viewport) => void): Promise<void> {
    const vp = this.viewport();
    const s0 = { x: (anchor.x + vp.scrollX) * vp.zoom, y: (anchor.y + vp.scrollY) * vp.zoom };
    const s1 = { x: (anchor.x + target.scrollX) * target.zoom, y: (anchor.y + target.scrollY) * target.zoom };
    const lz0 = Math.log(vp.zoom);
    const lz1 = Math.log(target.zoom);
    await tween(ms, (t) => {
      const z = Math.exp(lz0 + (lz1 - lz0) * t);
      const sx = s0.x + (s1.x - s0.x) * t;
      const sy = s0.y + (s1.y - s0.y) * t;
      const next = { zoom: z, scrollX: sx / z - anchor.x, scrollY: sy / z - anchor.y };
      this.setViewport(next);
      onStep?.(t, { ...next, width: vp.width, height: vp.height });
    });
  }

  /** Fly so `rect` ends centered at `zoom`, anchored on its center. */
  private flyToRect(rect: Rect, zoom: number, ms: number, onStep?: (t: number, vp: Viewport) => void): Promise<void> {
    const vp = this.viewport();
    return this.flyTo(centerOn(rect, zoom, vp.width, vp.height), center(rect), ms, onStep);
  }

  private static bounds(els: readonly ExcalidrawElement[]): Rect {
    return union(els.filter((e) => !e.isDeleted).map((e) => ({ x: e.x, y: e.y, width: e.width, height: e.height }))) ?? { x: 0, y: 0, width: 800, height: 600 };
  }

  private contentRect(): Rect {
    return PortalController.bounds(this.api.getSceneElements());
  }

  private buildElements(scene: PortalScene): ExcalidrawElement[] {
    return buildPortalElements(scene.title, scene.cards, restoreElements(scene.elements as never, null));
  }

  /** Swap scene contents (no animation). Clears undo so Cmd-Z can't reach across portals. */
  private install(scene: PortalScene, elements = this.buildElements(scene)): void {
    this.scene = scene;
    this.api.updateScene({ elements, captureUpdate: CaptureUpdateAction.NEVER });
    this.api.history.clear();
    this.lastSceneVersion = getSceneVersion(elements as never);
    this.api.updateScene({ appState: { selectedElementIds: {}, selectedGroupIds: {} }, captureUpdate: CaptureUpdateAction.NEVER });
    this.selectedCardId = null;
  }

  private frameAll(): { scrollX: number; scrollY: number; zoom: number } {
    const vp = this.viewport();
    const r = this.contentRect();
    const z = fitZoom(r, vp.width, vp.height);
    this.fittedZoom = z;
    return centerOn(r, z, vp.width, vp.height);
  }

  /** Render `elements` exactly as they'd look on screen when the view shows `region`. */
  private async renderRegion(elements: readonly ExcalidrawElement[], region: Rect): Promise<HTMLCanvasElement> {
    const vp = this.viewport();
    const dpr = window.devicePixelRatio || 1;
    // An invisible rect spanning the region pins the export bounds to it exactly.
    const [marker] = restoreElements(
      [{ type: "rectangle", id: "__region", x: region.x, y: region.y, width: region.width, height: region.height,
         strokeColor: "transparent", backgroundColor: "transparent", strokeWidth: 0 } as never],
      null,
    );
    return exportToCanvas({
      elements: [...elements.filter((e) => !e.isDeleted), marker!] as never,
      appState: { exportBackground: true, viewBackgroundColor: BACKGROUND },
      files: this.api.getFiles(),
      exportPadding: 0,
      getDimensions: () => ({ width: Math.round(vp.width * dpr), height: Math.round(vp.height * dpr), scale: (vp.width * dpr) / region.width }),
    });
  }

  /**
   * Dive: fly into a window inside the card while the child portal, already
   * rendered into that window, fades in over the card's own text. When the
   * window fills the screen it *is* the child's framed view, so the real scene
   * swaps in underneath with nothing visibly changing.
   */
  private async diveThrough(cardId: string, nextScene: Promise<PortalScene | null>): Promise<PortalScene | null> {
    const card = cardRects(this.api.getSceneElements()).find((c) => c.cardId === cardId);
    if (!card) {
      const scene = await nextScene;
      if (scene) await this.loadingInto(scene.portalId, () => this.fadeTo(scene));
      return scene;
    }
    const vp = this.viewport();
    const win = windowIn(card.rect, vp.width / vp.height);

    // Prepare the child (scene from native, elements, preview) during the flight.
    const prepared = nextScene.then(async (scene) => {
      if (!scene) return null;
      const elements = this.buildElements(scene);
      const region = framedRect(PortalController.bounds(elements), vp.width, vp.height);
      const preview = await this.renderRegion(elements, region).catch(() => null);
      return { scene, elements, preview };
    });
    let ready: Awaited<typeof prepared> = null;
    void prepared.then((r) => (ready = r));

    await this.flyToRect(win, vp.width / win.width, DIVE_MS, (t, v) => {
      if (!ready?.preview) return;
      this.overlay.show(ready.preview, toView(win, v), smooth((t - 0.2) / 0.45));
    });
    const child = await prepared;
    if (!child) {
      // Not divable after all: ease back out.
      this.overlay.hide();
      await this.flyTo(this.frameAll(), center(card.rect), 300);
      return null;
    }
    await this.loadingInto(child.scene.portalId, async () => {
      if (child.preview) this.overlay.show(child.preview, { x: 0, y: 0, width: vp.width, height: vp.height }, 1);
      this.install(child.scene, child.elements);
      this.setViewport(this.frameAll());
      await nextPaint();
      await this.overlay.fadeOut(90);
    });
    return child.scene;
  }

  /**
   * Exit: the reverse. The child view (as it is right now) is drawn into the
   * card's window in the parent, the parent swaps in around it, and the camera
   * pulls back while the card's own face fades back in.
   */
  private async exitThrough(parent: PortalScene, focusCardId: string | undefined): Promise<void> {
    const vp = this.viewport();
    const childEls = this.api.getSceneElements();
    const parentEls = this.buildElements(parent);
    const card = cardRects(parentEls).find((c) => c.cardId === focusCardId);
    // Only a direct parent has the card we came through.
    const direct = card && this.scene?.path.at(-2)?.portalId === parent.portalId;
    if (!card || !direct) {
      await this.loadingInto(parent.portalId, () => this.fallbackExit(parent, focusCardId));
      return;
    }
    const win = windowIn(card.rect, vp.width / vp.height);
    const framed = framedRect(PortalController.bounds(childEls), vp.width, vp.height);
    const preview = await this.renderRegion(childEls, framed).catch(() => null);
    // Where the current child view sits in the parent's coordinates.
    const start = mapRect(visibleRect(vp), framed, win);

    await this.loadingInto(parent.portalId, async () => {
      const startVp = { ...centerOn(start, vp.width / start.width, vp.width, vp.height), width: vp.width, height: vp.height };
      if (preview) this.overlay.show(preview, toView(win, startVp), 1);
      this.install(parent, parentEls);
      const target = this.frameAll();
      this.setViewport(startVp);
      await nextPaint();
      await this.flyTo(target, center(win), EXIT_MS, (t, v) => {
        if (preview) this.overlay.show(preview, toView(win, v), 1 - smooth((t - 0.15) / 0.5));
      });
      this.overlay.hide();
    });
  }

  /** Multi-level breadcrumb jumps: start zoomed into the card that leads back down, pull out. */
  private async fallbackExit(scene: PortalScene, focusCardId?: string): Promise<void> {
    this.install(scene);
    const target = this.frameAll();
    const vp = this.viewport();
    const from = cardRects(this.api.getSceneElements()).find((c) => c.cardId === focusCardId);
    if (!from) {
      this.setViewport(target);
      return;
    }
    this.setViewport(centerOn(from.rect, fitZoom(from.rect, vp.width, vp.height, 0), vp.width, vp.height));
    await nextPaint();
    await this.flyTo(target, center(from.rect), EXIT_MS);
  }

  /** Unrelated portals (map jumps, first load): a quick cross-fade. */
  private async fadeTo(scene: PortalScene, focusCardId?: string): Promise<void> {
    if (this.scene) await cssTransition(this.stage, { opacity: "0" }, 120);
    this.install(scene);
    this.setViewport(this.frameAll());
    if (focusCardId) {
      const c = cardRects(this.api.getSceneElements()).find((c) => c.cardId === focusCardId);
      if (c) this.setViewport(centerOn(c.rect, this.fittedZoom, this.viewport().width, this.viewport().height));
    }
    setStyleNow(this.stage, { transform: "none" });
    await cssTransition(this.stage, { opacity: "1" }, 160);
  }

  // ---------- web-initiated navigation ----------

  private async requestDive(cardId: string): Promise<void> {
    if (!this.scene || this.transitioning) return;
    const card = this.scene.cards.find((c) => c.id === cardId);
    if (!card || card.type !== "topic") return;
    this.flushChanges();
    this.transitioning = true;
    this.gate.block("transition");
    try {
      this.positionActions();
      // The flight starts immediately; native's answer arrives during it.
      await this.diveThrough(cardId, this.bridge.request("portal.enter", { portalId: this.scene.portalId, cardId }));
    } catch (e) {
      this.overlay.hide();
      this.bridge.notify("log.event", { level: "error", message: `dive failed: ${String(e)}` });
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
      this.positionActions();
    }
    this.emitFocus();
  }

  private async requestExit(): Promise<void> {
    if (!this.scene || this.transitioning || this.scene.path.length < 2) return;
    this.flushChanges();
    this.transitioning = true;
    this.gate.block("transition");
    this.positionActions();
    try {
      const res = await this.bridge.request("portal.exit", { portalId: this.scene.portalId });
      if (res) await this.exitThrough(res.scene, res.focusCardId);
    } catch (e) {
      this.overlay.hide();
      this.bridge.notify("log.event", { level: "error", message: `exit failed: ${String(e)}` });
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
      this.positionActions();
    }
    this.emitFocus();
  }

  // ---------- observers ----------

  private onViewportChanged(): void {
    this.positionActions();
    if (this.transitioning || !this.scene) return;
    const vp = this.viewport();

    if (vp.zoom < this.fittedZoom * EXIT_AT && this.scene.path.length > 1) {
      void this.requestExit();
      return;
    }
    const topicIds = new Set(this.scene.cards.filter((c) => c.type === "topic").map((c) => c.id));
    const cards = cardRects(this.api.getSceneElements()).filter((c) => topicIds.has(c.cardId));
    const focused = nearestToCenter(cards, vp);
    if (focused) {
      const v = toView(focused.rect, vp);
      const big = v.width >= vp.width * DIVE_AT || v.height >= vp.height * DIVE_AT;
      const centered = containsPoint(v, vp.width / 2, vp.height / 2);
      // Must have actually zoomed in, or a portal with one big card would dive on arrival.
      const zoomedIn = vp.zoom > this.fittedZoom * 1.3;
      if (big && centered && zoomedIn) {
        void this.requestDive(focused.cardId);
        return;
      }
    }
    clearTimeout(this.focusTimer);
    this.focusTimer = window.setTimeout(() => this.emitFocus(), 250);
  }

  private emitFocus(): void {
    if (!this.scene) return;
    const vp = this.viewport();
    const rects = cardRects(this.api.getSceneElements());
    const visible = rects.filter((c) => {
      const v = toView(c.rect, vp);
      return v.x < vp.width && v.y < vp.height && v.x + v.width > 0 && v.y + v.height > 0;
    });
    this.bridge.notify("focus.changed", {
      portalId: this.scene.portalId,
      cardId: nearestToCenter(visible, vp)?.cardId ?? null,
      zoom: vp.zoom,
      visibleCardIds: visible.map((c) => c.cardId),
    });
  }

  private emitSelection(): void {
    if (!this.scene) return;
    const selected = this.api.getAppState().selectedElementIds;
    const cardIds = cardRects(this.api.getSceneElements())
      .filter((c) => selected[`${c.cardId}:frame`])
      .map((c) => c.cardId);
    this.selectedCardId = cardIds.length === 1 ? cardIds[0]! : null;
    // Excalidraw's style panel (stroke, sloppiness, fonts) is for the kid's own
    // drawings; for cards it's noise. Hide it when only cards are selected.
    const ids = Object.keys(selected).filter((k) => selected[k]);
    const els = this.api.getSceneElements();
    const onlyCards = ids.length > 0 && ids.every((id) => els.find((e) => e.id === id)?.customData?.cardId);
    document.documentElement.toggleAttribute("data-card-selection", onlyCards);
    this.positionActions();
    const key = `${this.scene.portalId}|${cardIds.join(",")}`;
    if (key === this.lastSelection) return;
    this.lastSelection = key;
    this.bridge.notify("selection.changed", { portalId: this.scene.portalId, cardIds });
  }

  /** Keep the selected card's actions pinned to it (or hidden mid-transition/drag). */
  private positionActions(): void {
    const id = this.selectedCardId;
    const state = this.api.getAppState();
    const busy = this.transitioning || state.selectedElementsAreBeingDragged || state.resizingElement != null;
    const c = id && !busy ? cardRects(this.api.getSceneElements()).find((r) => r.cardId === id) : undefined;
    const card = c && this.scene?.cards.find((x) => x.id === c.cardId);
    this.actions.update(c ? c.cardId : null, c ? toView(c.rect, this.viewport()) : null, card?.type === "topic");
  }

  private onElementsChanged(elements: readonly ExcalidrawElement[]): void {
    this.emitSelection();
    if (this.transitioning || !this.scene) return;
    const version = getSceneVersion(elements as never);
    if (version === this.lastSceneVersion) return;
    this.lastSceneVersion = version;
    const portalId = this.scene.portalId;
    clearTimeout(this.changeTimer);
    this.pendingFlush = () => {
      this.pendingFlush = null;
      clearTimeout(this.changeTimer);
      const live = this.api.getSceneElementsIncludingDeleted().filter((e) => !e.isDeleted);
      this.bridge.notify("canvas.changed", { portalId, elements: JSON.parse(JSON.stringify(live)) });
    };
    this.changeTimer = window.setTimeout(() => this.pendingFlush?.(), 500);
  }

  /** Send any debounced change now. Called before leaving a portal so nothing is lost. */
  flushChanges(): void {
    this.pendingFlush?.();
  }

  private cardAt(clientX: number, clientY: number): string | null {
    const p = viewportCoordsToSceneCoords({ clientX, clientY }, this.api.getAppState());
    // Topmost card wins when cards overlap.
    const hit = cardRects(this.api.getSceneElements()).reverse().find((c) => containsPoint(c.rect, p.x, p.y));
    return hit?.cardId ?? null;
  }

  /** Second finger-tap on the same card within the window dives instead of editing text. */
  private onTouchStart = (e: TouchEvent): void => {
    if (e.touches.length !== 1 || this.transitioning || !this.scene) return;
    const t = e.touches[0] as Touch & { touchType?: string };
    if (t.touchType === "stylus") return;
    const now = performance.now();
    const prev = this.lastTap;
    this.lastTap = { t: now, x: t.clientX, y: t.clientY };
    if (!prev || now - prev.t > DOUBLE_TAP_MS || Math.hypot(t.clientX - prev.x, t.clientY - prev.y) > DOUBLE_TAP_PX) return;
    const cardId = this.cardAt(t.clientX, t.clientY);
    if (!cardId) return; // double-tap on empty canvas keeps Excalidraw's behavior (e.g. new text)
    this.lastTap = null;
    e.stopImmediatePropagation();
    if (e.cancelable) e.preventDefault();
    void this.requestDive(cardId);
  };

  /** Mouse / trackpad equivalent. */
  private onDoubleClick = (e: MouseEvent): void => {
    if (this.transitioning || !this.scene) return;
    const cardId = this.cardAt(e.clientX, e.clientY);
    if (!cardId) return;
    e.stopImmediatePropagation();
    e.preventDefault();
    void this.requestDive(cardId);
  };

  /** For ink: current elements, used by the ink service. */
  elements(): readonly NonDeletedExcalidrawElement[] {
    return this.api.getSceneElements();
  }

  cards(): Card[] {
    return this.scene?.cards ?? [];
  }
}

/** 0..1 clamp with smoothstep easing, for fades keyed to animation progress. */
function smooth(x: number): number {
  const t = Math.min(1, Math.max(0, x));
  return t * t * (3 - 2 * t);
}

function center(r: Rect): { x: number; y: number } {
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}
