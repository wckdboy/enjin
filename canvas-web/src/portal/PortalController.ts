import { CaptureUpdateAction, getSceneVersion, newElementWith, restoreElements, viewportCoordsToSceneCoords } from "@excalidraw/excalidraw";
import type { ExcalidrawElement, NonDeletedExcalidrawElement } from "@excalidraw/excalidraw/element/types";
import type { ExcalidrawImperativeAPI } from "@excalidraw/excalidraw/types";
import type { Bridge } from "../bridge/client";
import type { Card, Params, NativeToWeb, PortalScene } from "../bridge/schema";
import { buildPortalElements, cardRects } from "../cards/render";
import { type Rect, type Viewport, centerOn, containsPoint, fitZoom, nearestToCenter, toView, union } from "../cards/layout";
import type { InputGate } from "../inputGate";
import { cssTransition, nextPaint, setStyleNow, tween } from "./animate";

/** A card this big on screen (fraction of view width or height) dives in. */
const DIVE_AT = 0.8;
/** Zooming out below this fraction of the portal's fitted zoom exits to the parent. */
const EXIT_AT = 0.55;
const DOUBLE_TAP_MS = 300;
const DOUBLE_TAP_PX = 30;

type Zoom = { value: number };

export class PortalController {
  private scene: PortalScene | null = null;
  private fittedZoom = 1;
  private transitioning = false;
  private lastSceneVersion = -1;
  private changeTimer: number | undefined;
  private pendingFlush: (() => void) | null = null;
  private focusTimer: number | undefined;
  private lastTap: { t: number; x: number; y: number } | null = null;
  private unsubs: (() => void)[] = [];

  constructor(
    private api: ExcalidrawImperativeAPI,
    private bridge: Bridge,
    private gate: InputGate,
    /** Element whose CSS transform/opacity is animated during transitions. */
    private stage: HTMLElement,
  ) {
    this.unsubs.push(api.onScrollChange(() => this.onViewportChanged()));
    this.unsubs.push(api.onChange((els) => this.onElementsChanged(els)));
    stage.addEventListener("pointerup", this.onPointerUp);
  }

  dispose(): void {
    this.unsubs.forEach((u) => u());
    this.stage.removeEventListener("pointerup", this.onPointerUp);
  }

  get portalId(): string | null {
    return this.scene?.portalId ?? null;
  }

  // ---------- native -> web ----------

  async load({ scene, transition, focusCardId }: Params<NativeToWeb, "portal.load">): Promise<void> {
    this.flushChanges();
    this.transitioning = true;
    this.gate.block("transition");
    try {
      if (transition === "dive") await this.diveIn(scene);
      else if (transition === "exit") await this.exitTo(scene, focusCardId);
      else await this.jumpTo(scene, focusCardId);
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
    }
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

  /** Animate the camera so `rect` is centered at `zoom`. Interpolates in scene space so the motion feels like a camera move. */
  private async flyTo(rect: Rect, zoom: number, ms: number): Promise<void> {
    const vp = this.viewport();
    const fromCx = vp.width / (2 * vp.zoom) - vp.scrollX;
    const fromCy = vp.height / (2 * vp.zoom) - vp.scrollY;
    const toCx = rect.x + rect.width / 2;
    const toCy = rect.y + rect.height / 2;
    // Interpolate zoom geometrically: equal ratios per frame feel linear to the eye.
    const lz0 = Math.log(vp.zoom);
    const lz1 = Math.log(zoom);
    await tween(ms, (t) => {
      const z = Math.exp(lz0 + (lz1 - lz0) * t);
      const c = { x: fromCx + (toCx - fromCx) * t, y: fromCy + (toCy - fromCy) * t, width: 0, height: 0 };
      this.setViewport(centerOn(c, z, vp.width, vp.height));
    });
  }

  private contentRect(): Rect {
    const els = this.api.getSceneElements();
    return union(els.map((e) => ({ x: e.x, y: e.y, width: e.width, height: e.height }))) ?? { x: 0, y: 0, width: 800, height: 600 };
  }

  /** Swap scene contents (no animation). Clears undo so Cmd-Z can't reach across portals. */
  private install(scene: PortalScene): void {
    this.scene = scene;
    const persisted = restoreElements(scene.elements as never, null);
    const elements = buildPortalElements(scene.title, scene.cards, persisted);
    this.api.updateScene({ elements, captureUpdate: CaptureUpdateAction.NEVER });
    this.api.history.clear();
    this.lastSceneVersion = getSceneVersion(elements as never);
  }

  private frameAll(): { scrollX: number; scrollY: number; zoom: number } {
    const vp = this.viewport();
    const r = this.contentRect();
    const z = fitZoom(r, vp.width, vp.height);
    this.fittedZoom = z;
    return centerOn(r, z, vp.width, vp.height);
  }

  private async diveIn(scene: PortalScene): Promise<void> {
    // Old scene: keep pushing into the card while fading out.
    await cssTransition(this.stage, { transform: "scale(1.6)", opacity: "0" }, 180);
    this.install(scene);
    this.setViewport(this.frameAll());
    // New scene grows from small, as if we came through the card.
    setStyleNow(this.stage, { transform: "scale(0.7)", opacity: "0" });
    await nextPaint();
    await cssTransition(this.stage, { transform: "scale(1)", opacity: "1" }, 260);
  }

  private async exitTo(scene: PortalScene, focusCardId?: string): Promise<void> {
    await cssTransition(this.stage, { transform: "scale(0.6)", opacity: "0" }, 180);
    this.install(scene);
    const target = this.frameAll();
    const vp = this.viewport();
    const from = cardRects(this.api.getSceneElements()).find((c) => c.cardId === focusCardId);
    // Start zoomed into the card we came from, then pull back to the whole portal.
    if (from) this.setViewport(centerOn(from.rect, fitZoom(from.rect, vp.width, vp.height, 0), vp.width, vp.height));
    else this.setViewport(target);
    setStyleNow(this.stage, { transform: "scale(1)", opacity: "1" });
    await nextPaint();
    if (from) {
      const r = this.contentRect();
      await this.flyTo(r, target.zoom, 420);
    }
  }

  private async jumpTo(scene: PortalScene, focusCardId?: string): Promise<void> {
    if (this.scene) await cssTransition(this.stage, { opacity: "0" }, 120);
    this.install(scene);
    this.setViewport(this.frameAll());
    if (focusCardId) {
      const c = cardRects(this.api.getSceneElements()).find((c) => c.cardId === focusCardId);
      if (c) this.setViewport(centerOn(c.rect, this.fittedZoom, this.viewport().width, this.viewport().height));
    }
    setStyleNow(this.stage, { transform: "scale(1)" });
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
      const rect = cardRects(this.api.getSceneElements()).find((c) => c.cardId === cardId)?.rect;
      const vp = this.viewport();
      // Fly into the card while native fetches the next scene, hiding the round-trip.
      const [next] = await Promise.all([
        this.bridge.request("portal.enter", { portalId: this.scene.portalId, cardId }),
        rect ? this.flyTo(rect, fitZoom(rect, vp.width, vp.height, 0.02), 160) : Promise.resolve(),
      ]);
      if (next) await this.diveIn(next);
    } catch (e) {
      this.bridge.notify("log.event", { level: "error", message: `dive failed: ${String(e)}` });
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
    }
    this.emitFocus();
  }

  private async requestExit(): Promise<void> {
    if (!this.scene || this.transitioning || this.scene.path.length < 2) return;
    this.flushChanges();
    this.transitioning = true;
    this.gate.block("transition");
    try {
      const res = await this.bridge.request("portal.exit", { portalId: this.scene.portalId });
      if (res) await this.exitTo(res.scene, res.focusCardId);
    } catch (e) {
      this.bridge.notify("log.event", { level: "error", message: `exit failed: ${String(e)}` });
    } finally {
      this.transitioning = false;
      this.gate.unblock("transition");
    }
    this.emitFocus();
  }

  // ---------- observers ----------

  private onViewportChanged(): void {
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

  private onElementsChanged(elements: readonly ExcalidrawElement[]): void {
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

  private onPointerUp = (e: PointerEvent): void => {
    if (e.pointerType === "pen" || this.transitioning || !this.scene) return;
    const now = performance.now();
    const prev = this.lastTap;
    this.lastTap = { t: now, x: e.clientX, y: e.clientY };
    if (!prev || now - prev.t > DOUBLE_TAP_MS || Math.hypot(e.clientX - prev.x, e.clientY - prev.y) > DOUBLE_TAP_PX) return;
    this.lastTap = null;
    const s = this.api.getAppState();
    const p = viewportCoordsToSceneCoords({ clientX: e.clientX, clientY: e.clientY }, s);
    const hit = cardRects(this.api.getSceneElements()).find((c) => containsPoint(c.rect, p.x, p.y));
    if (hit) void this.requestDive(hit.cardId);
  };

  /** For ink: current elements, used by the ink service. */
  elements(): readonly NonDeletedExcalidrawElement[] {
    return this.api.getSceneElements();
  }

  cards(): Card[] {
    return this.scene?.cards ?? [];
  }
}
