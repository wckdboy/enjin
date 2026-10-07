import "../style.css";
import "./world.css";
import type { BinaryFiles } from "@excalidraw/excalidraw/types";
import { Bridge, webkitTransport } from "../bridge/client";
import { devHost } from "../bridge/devHost";
import { PROTOCOL_VERSION, type Card, type PortalScene } from "../bridge/schema";
import { onLangChange, setLang, t } from "../i18n";
import { FRAME_KINDS, frameBody } from "../live/documents";
import { liveDocument } from "../portal/LiveLayer";
import { Camera2D } from "./Camera2D";
import { Look } from "./Look";
import { Plane, type Nest } from "./Plane";
import { MODEL, type Rect } from "./spec";

/**
 * ENJIN's world: one endless plane you pan and pinch. Each portal is a world
 * on it: a model in the middle, panels around, and doors: round windows with
 * the next world already inside. Keep zooming into a door, a part of a model
 * or a panel and you go through into what's inside (Enjin builds it if it's
 * new); pinch out far enough and you rise back to the world around.
 *
 * It speaks the same bridge as the card canvas (portal.load, canvas.applyOps,
 * portal.enter, ...) plus portal.peek and portal.zoomInto.
 */
let bridge: Bridge;
bridge = new Bridge(webkitTransport() ?? devHost(() => bridge));
window.addEventListener("error", (e) => bridge.notify("log.event", { level: "error", message: e.message }));

// Layers, bottom to top: backdrop (CSS) · planes (DOM) · models (WebGL) · part labels · HUD.
const host = document.getElementById("world")!;
const stage = document.createElement("div");
stage.className = "wstage";
const canvas = document.createElement("canvas");
const labelLayer = document.createElement("div");
labelLayer.className = "labels";
host.append(stage, canvas, labelLayer);
const look = new Look(canvas);
const cam = new Camera2D();

// ---------- HUD ----------
const hud = document.createElement("div");
hud.className = "hud";
const info = document.createElement("div");
info.className = "info off";
const explodeBtn = document.createElement("button");
explodeBtn.className = "explode";
explodeBtn.hidden = true;
const busy = document.createElement("div");
busy.className = "busy off";
busy.innerHTML = `<i class="activity"></i><span></span>`;
const hint = document.createElement("div");
hint.className = "hint off";
hud.append(info, explodeBtn, busy, hint);
host.appendChild(hud);
const setWords = () => { explodeBtn.textContent = t.explode(); };
setWords();
onLangChange(setWords);
explodeBtn.addEventListener("click", () => {
  const m = anchor?.model;
  if (!m) return;
  m.explodeTarget = m.explodeTarget ? 0 : 1;
  if (m.explodeTarget) notice("explode", { cardId: anchor?.spec.centerpiece?.cardId });
  explodeBtn.classList.toggle("on", !!m.explodeTarget);
  wake();
});

// ---------- state ----------
let anchor: Plane | null = null;
const files: BinaryFiles = {};
let transitioning = false;
let selectedPart: number | null = null;
const peeking = new Set<string>();
/** Things that just refused to open: don't keep asking while you're still zoomed on them. */
const refused = new Map<string, number>();

/** Ask native, but never wait forever: a world mid-crossing must not get stuck. */
function ask<M extends "portal.enter" | "portal.exit" | "portal.peek" | "portal.zoomInto">(method: M, params: Parameters<typeof bridge.request<M>>[1]) {
  return Promise.race([
    bridge.request(method, params).catch(() => null),
    new Promise<null>((r) => setTimeout(() => r(null), 10000)),
  ]);
}

function newPlane(scene: PortalScene, live: boolean): Plane {
  const p = new Plane(scene, look.environment, live);
  p.onOpen = (cardId) => bridge.notify("card.open", { cardId });
  p.onError = (e) => bridge.notify("log.event", { level: "error", message: `world build: ${String(e)}` });
  stage.appendChild(p.el);
  return p;
}

/** Where a world inside another sits: its door (kept current as the outer world changes), or where it was entered. */
function nestOf(p: Plane): Nest {
  const up = p.up!;
  return (up.doorId && up.plane.doorNest(up.doorId)) || up.nest;
}

type Placed = { p: Plane; n: Nest; role: "outer" | "anchor" | "child" };
/** Every world on screen, with where it sits relative to the one you're in. */
function planes(): Placed[] {
  if (!anchor) return [];
  const out: Placed[] = [{ p: anchor, n: { cx: 0, cy: 0, k: 1 }, role: "anchor" }];
  if (anchor.up) {
    const n = nestOf(anchor);
    out.unshift({ p: anchor.up.plane, n: { cx: -n.cx / n.k, cy: -n.cy / n.k, k: 1 / n.k }, role: "outer" });
  }
  for (const c of anchor.children.values()) out.push({ p: c, n: nestOf(c), role: "child" });
  return out;
}

const screenRect = (n: Nest, r: Rect): Rect => cam.rectToScreen({ x: n.cx + n.k * r.x, y: n.cy + n.k * r.y, w: r.w * n.k, h: r.h * n.k });

// ---------- drawing ----------
const t0 = performance.now();
let frames = 0;
let lastWake = performance.now();
function wake(): void { lastWake = performance.now(); }

function draw(now: number): void {
  const time = (now - t0) / 1000;
  if (!anchor) { look.render([], time); return; }
  const f = cam.free();
  const bounds = cam.rectToScreen(anchor.layout.bounds);
  const size = Math.max(bounds.w / f.w, bounds.h / f.h);
  // Pulling back toward the world around: this one folds back behind its door's glass.
  const folded = !!anchor.up?.doorId && size < 0.7;
  if (anchor.up?.doorId) anchor.clip(folded);
  const views = [];
  for (const { p, n, role } of planes()) {
    p.el.style.transform = `translate(${cam.tx + cam.s * n.cx}px, ${cam.ty + cam.s * n.cy}px) scale(${cam.s * n.k})`;
    p.el.style.zIndex = role === "outer" ? "0" : role === "anchor" ? "1" : "2";
    // The world around fades in as you pull back toward it; worlds in doors show once you can see them.
    let opacity = 1;
    if (role === "outer") opacity = Math.max(0, Math.min(1, (0.78 - size) / 0.26));
    if (role === "child" && (screenRect(n, p.layout.model).w < 30 || folded)) opacity = 0;
    p.el.style.opacity = String(opacity);
    p.el.style.visibility = opacity > 0 ? "visible" : "hidden";
    if (p.model && opacity > 0.5) {
      const rect = screenRect(n, p.layout.model);
      if (rect.w > 12) {
        p.model.update(time);
        p.model.aim(rect.w / rect.h);
        views.push({ scene: p.model.scene, camera: p.model.camera, rect });
      }
    }
  }
  look.render(views, time);
  drawLabels(++frames % 8 === 0);
}

/** The model's part labels, for the world you're in, once it's big enough to read them. */
const labelEls: HTMLDivElement[] = [];
let hiddenParts = new Set<number>();
function drawLabels(occlusion: boolean): void {
  const m = anchor?.model;
  const rect = anchor ? cam.rectToScreen(anchor.layout.model) : null;
  const list = m && rect && rect.w > 420 ? m.labels(occlusion) : [];
  if (occlusion) hiddenParts = new Set(list.filter((l) => l.hidden).map((l) => l.i));
  list.forEach((l, k) => {
    let el = labelEls[k];
    if (!el) {
      el = document.createElement("div");
      el.className = "plabel";
      labelLayer.appendChild(el);
      labelEls.push(el);
    }
    if (el.textContent !== l.label) el.textContent = l.label;
    el.dataset.part = String(l.i);
    el.style.display = "";
    el.style.transform = `translate(${rect!.x + l.u * rect!.w}px, ${rect!.y + l.v * rect!.h}px) translate(-50%, -100%)`;
    el.style.opacity = hiddenParts.has(l.i) ? "0.12" : "1";
    el.classList.toggle("on", l.i === selectedPart);
  });
  for (let k = list.length; k < labelEls.length; k++) labelEls[k]!.style.display = "none";
}

// ---------- going through: thresholds checked as you zoom ----------
function check(now: number): void {
  if (!anchor || transitioning) return;
  const f = cam.free();
  const minD = Math.min(f.w, f.h);
  const cx = f.x + f.w / 2, cy = f.y + f.h / 2;
  const fresh = (id: string) => now - (refused.get(id) ?? -1e9) > 2500;
  let hintText: string | null = null;

  // Doors: a look inside once they're big enough to see into; through, once one fills the view.
  for (const card of anchor.spec.doors) {
    const dr = anchor.doorRect(card.id);
    if (!dr) continue;
    const r = cam.rectToScreen(dr);
    const onScreen = r.x < cam.w && r.y < cam.h && r.x + r.w > 0 && r.y + r.h > 0;
    if (onScreen && r.w > 56 && card.childCount > 0 && !anchor.children.has(card.id) && !peeking.has(card.id)) void peek(anchor, card.id);
    const centred = Math.abs(r.x + r.w / 2 - cx) < r.w / 2 && Math.abs(r.y + r.h / 2 - cy) < r.h / 2;
    if (r.w >= 0.9 * minD && centred && fresh(card.id)) { void dive(card.id); return; }
  }

  // Pulled back far enough: rise to the world around.
  const b = cam.rectToScreen(anchor.layout.bounds);
  const size = Math.max(b.w / f.w, b.h / f.h);
  const isRoot = !anchor.up && anchor.scene.path.length < 2;
  if (size < 0.42 && !isRoot && fresh("exit")) { void rise(); return; }
  if (isRoot && size < 0.5 && !pointers.size) cam.zoomAt(cx, cy, 0.5 / size);

  // A part of the model: keep zooming into it to go inside.
  const m = anchor.model;
  const mr = cam.rectToScreen(anchor.layout.model);
  if (m && mr.h > 1.5 * f.h && cx > mr.x && cx < mr.x + mr.w && cy > mr.y && cy < mr.y + mr.h) {
    const i = m.pick(((cx - mr.x) / mr.w) * 2 - 1, -(((cy - mr.y) / mr.h) * 2 - 1));
    const part = i === null ? null : m.partInfo(i);
    if (part?.label) {
      const id = `part:${part.label}`;
      if (mr.h > 2.6 * f.h && fresh(id)) { void zoomInto({ title: part.label, detail: part.detail ?? undefined }, id); return; }
      hintText = t.keepZooming(part.label);
    } else if (mr.h > 2.6 * f.h && !pointers.size) {
      cam.zoomAt(cx, cy, (2.6 * f.h) / mr.h); // nothing named here to go into
    }
  }

  // A panel: the same.
  for (const card of anchor.spec.panels) {
    const pr = anchor.panelRect(card.id);
    if (!pr) continue;
    const r = cam.rectToScreen(pr);
    if (!(cx > r.x && cx < r.x + r.w && cy > r.y && cy < r.y + r.h)) continue;
    const big = Math.max(r.w / f.w, r.h / f.h);
    if (big > 2.2 && fresh(card.id)) { void zoomInto({ title: card.title, detail: card.summary, cardId: card.id }, card.id); return; }
    if (big > 1.4) hintText = t.keepZooming(card.title);
  }

  // Nowhere deeper to go: don't zoom into empty space forever.
  if (cam.s > 14 && !pointers.size) cam.zoomAt(cx, cy, 14 / cam.s);
  showHint(hintText);
}

function showHint(text: string | null): void {
  if (text && hint.textContent !== text) hint.textContent = text;
  hint.classList.toggle("off", !text);
}

/** Look inside a door without going in, so the world there shows through it. */
async function peek(from: Plane, cardId: string): Promise<void> {
  peeking.add(cardId);
  try {
    const scene = await ask("portal.peek", { cardId });
    if (!scene || anchor !== from || from.children.has(cardId) || !from.doorNest(cardId)) return;
    const child = newPlane(scene, false);
    child.up = { plane: from, nest: from.doorNest(cardId)!, doorId: cardId };
    child.clip(true);
    await child.build(scene, files);
    if (anchor !== from || from.children.has(cardId)) { child.dispose(); return; }
    from.children.set(cardId, child);
    from.markPeeked(cardId, true);
    wake();
  } finally {
    peeking.delete(cardId);
  }
}

/** Through a door into the world inside. */
async function dive(cardId: string): Promise<void> {
  const from = anchor!;
  transitioning = true;
  showHint(null);
  try {
    const scene = await ask("portal.enter", { portalId: from.portalId, cardId });
    if (!scene || anchor !== from) { refused.set(cardId, performance.now()); return; }
    let child = from.children.get(cardId);
    if (!child) {
      child = newPlane(scene, true);
      child.up = { plane: from, nest: from.doorNest(cardId)!, doorId: cardId };
      child.clip(true);
      from.children.set(cardId, child);
      from.markPeeked(cardId, true);
    }
    await child.build(scene, files);
    notice("dive", { cardId });
    sendAttention();
    enter(child);
  } finally {
    transitioning = false;
  }
}

/** Into whatever is at the centre of the view (a part, a panel): Enjin makes it a topic, and builds it if it's new. */
async function zoomInto(what: { title: string; detail?: string; cardId?: string }, id: string): Promise<void> {
  const from = anchor!;
  transitioning = true;
  showHint(null);
  try {
    const res = await ask("portal.zoomInto", { portalId: from.portalId, ...what });
    if (!res || anchor !== from) { refused.set(id, performance.now()); return; }
    // The new world opens where you were looking, its centrepiece filling the view.
    const f = cam.free();
    const [px, py] = cam.toPlane(f.x + f.w / 2, f.y + f.h / 2);
    const k = (Math.min(f.w, f.h * (MODEL.w / MODEL.h)) * 0.9) / cam.s / MODEL.w;
    const child = newPlane(res.scene, true);
    child.up = { plane: from, nest: { cx: px, cy: py, k }, doorId: null };
    child.el.classList.add("arriving");
    from.children.set(res.cardId, child);
    await child.build(res.scene, files);
    notice("zoomInto", { cardId: what.cardId, label: what.cardId ? undefined : what.title });
    sendAttention();
    enter(child);
    requestAnimationFrame(() => requestAnimationFrame(() => child.el.classList.remove("arriving")));
  } finally {
    transitioning = false;
  }
}

/** Make a world inside the current one the world you're in. */
function enter(child: Plane): void {
  const from = anchor!;
  const n = nestOf(child);
  cam.rebase(n.cx, n.cy, n.k);
  // Keep only the world you came from (around you now); drop the rest.
  const around = from.up?.plane;
  if (around) {
    for (const [id, c] of around.children) if (c === from) around.children.delete(id);
    around.dispose();
  }
  from.up = null;
  for (const [id, c] of from.children) if (c !== child) { c.dispose(); from.children.delete(id); from.markPeeked(id, false); }
  anchor = child;
  child.clip(false);
  void child.setLive(true, files);
  void from.setLive(false, files);
  from.setActive(null);
  afterMove();
  if (!pointers.size) void cam.flyTo(overview(child), 950);
}

/** Back out to the world around this one. */
async function rise(): Promise<void> {
  const from = anchor!;
  transitioning = true;
  showHint(null);
  try {
    const res = await ask("portal.exit", { portalId: from.portalId });
    if (!res || anchor !== from) { refused.set("exit", performance.now()); return; }
    let parent = from.up?.plane;
    if (!parent) {
      // Opened deep (from the map, or the app): the world around is new to us; we came out of its door.
      parent = newPlane(res.scene, false);
      const doorId = res.scene.cards.some((c) => c.id === res.focusCardId) ? res.focusCardId : null;
      from.up = { plane: parent, nest: { cx: 0, cy: 0, k: 0.24 }, doorId };
      parent.children.set(res.focusCardId, from);
    }
    await parent.build(res.scene, files);
    const n = nestOf(from);
    cam.rebase(-n.cx / n.k, -n.cy / n.k, 1 / n.k);
    for (const c of from.children.values()) c.dispose();
    from.children.clear();
    sendAttention();
    anchor = parent;
    notice("rise", { cardId: from.up?.doorId ?? undefined });
    const door = from.up!.doorId;
    // A world entered through a door goes back behind its glass; one entered through a part fades away.
    if (door) {
      from.clip(true);
      parent.markPeeked(door, true);
    } else {
      from.el.classList.add("leaving");
      setTimeout(() => {
        for (const [id, c] of parent!.children) if (c === from) { parent!.children.delete(id); parent!.markPeeked(id, false); }
        from.dispose();
      }, 500);
    }
    parent.up = null;
    void from.setLive(false, files);
    void parent.setLive(true, files);
    afterMove();
  } finally {
    transitioning = false;
  }
}

/** The whole world in view; in a narrow (portrait) view, its middle, with the panels just in reach either side. */
function overview(p: Plane) {
  const f = cam.free();
  return f.w < f.h ? cam.fit(p.layout.core, 0.96) : cam.fit(p.layout.bounds);
}

/** A new world on screen: reset what belonged to the last one. */
function afterMove(): void {
  selectedPart = null;
  showInfo(null, null);
  afterBuild();
  explodeBtn.classList.toggle("on", !!anchor?.model?.explodeTarget);
  busy.classList.add("off");
  wake();
}
function afterBuild(): void {
  explodeBtn.hidden = !anchor?.model?.hasExplode;
}

// ---------- touch ----------
const pointers = new Map<number, { x: number; y: number }>();
let gesture: { mode: "pan" | "turn" | "pinch" | null; moved: number; t0: number } = { mode: null, moved: 0, t0: 0 };
let lastTap = { t: -1e9, x: 0, y: 0 };

/** A drag that starts on the model turns it, while the whole model is in view and big enough to handle; otherwise drags pan. */
const inModel = (x: number, y: number) => {
  if (!anchor?.model) return false;
  const r = cam.rectToScreen(anchor.layout.model);
  const f = cam.free();
  return x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h && r.w > 0.3 * f.w && r.w < 0.95 * f.w && r.h < 0.95 * f.h;
};

host.addEventListener("pointerdown", (e) => {
  if ((e.target as HTMLElement).closest?.(".hud button, .hud .info, .panel .open")) return;
  pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
  lastInput = performance.now();
  cam.stop();
  if (pointers.size === 1) gesture = { mode: null, moved: 0, t0: performance.now() };
  if (pointers.size === 2) gesture.mode = "pinch";
  wake();
});
host.addEventListener("pointermove", (e) => {
  const prev = pointers.get(e.pointerId);
  if (!prev) return;
  const now = performance.now();
  if (gesture.mode === "pinch" && pointers.size >= 2) {
    const [a0, b0] = [...pointers.values()];
    const mid0 = { x: (a0!.x + b0!.x) / 2, y: (a0!.y + b0!.y) / 2 };
    const d0 = Math.hypot(a0!.x - b0!.x, a0!.y - b0!.y);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const [a, b] = [...pointers.values()];
    const mid = { x: (a!.x + b!.x) / 2, y: (a!.y + b!.y) / 2 };
    const d = Math.hypot(a!.x - b!.x, a!.y - b!.y);
    cam.panBy(mid.x - mid0.x, mid.y - mid0.y, now);
    if (d0 > 0) cam.zoomAt(mid.x, mid.y, d / d0);
    gesture.moved += 99;
  } else {
    const dx = e.clientX - prev.x, dy = e.clientY - prev.y;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    gesture.moved += Math.abs(dx) + Math.abs(dy);
    if (!gesture.mode && gesture.moved > 6) gesture.mode = inModel(e.clientX, e.clientY) ? "turn" : "pan";
    if (gesture.mode === "turn") anchor?.model?.turn(dx, dy);
    else if (gesture.mode === "pan") cam.panBy(dx, dy, now);
  }
  wake();
});
const up = (e: PointerEvent) => {
  if (!pointers.has(e.pointerId)) return;
  pointers.delete(e.pointerId);
  if (pointers.size === 0) {
    if (gesture.mode === "turn") notice("turn", { cardId: anchor?.spec.centerpiece?.cardId });
    if (gesture.mode === "pan" || gesture.mode === "pinch") cam.release();
    else if (gesture.moved < 8 && performance.now() - gesture.t0 < 500) tap(e.clientX, e.clientY, e.target);
    gesture.mode = null;
  } else if (gesture.mode === "pinch") {
    gesture.mode = "pan"; // one finger left: carry on panning
  }
  wake();
};
host.addEventListener("pointerup", up);
host.addEventListener("pointercancel", up);
host.addEventListener("wheel", (e) => {
  e.preventDefault();
  lastInput = performance.now();
  if (e.ctrlKey) cam.zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.01));
  else cam.panBy(-e.deltaX, -e.deltaY);
  wake();
}, { passive: false });

function tap(x: number, y: number, target: EventTarget | null): void {
  if (!anchor || transitioning) return;
  const el = target as HTMLElement | null;
  const now = performance.now();
  const double = now - lastTap.t < 320 && Math.hypot(x - lastTap.x, y - lastTap.y) < 40;
  lastTap = double ? { t: -1e9, x, y } : { t: now, x, y };

  const partEl = el?.closest?.(".plabel") as HTMLElement | null;
  if (partEl) { selectPart(Number(partEl.dataset.part)); return; }
  // A door, or anything in a world seen through one: fly through it.
  const planeEl = el?.closest?.(".plane") as HTMLElement | null;
  const child = [...anchor.children.values()].find((c) => c.el === planeEl);
  if (child?.up?.doorId) { flyThrough(child.up.doorId); return; }
  const doorEl = el?.closest?.("[data-door]") as HTMLElement | null;
  if (doorEl && planeEl === anchor.el) { flyThrough(doorEl.dataset.door!); return; }
  const panelEl = el?.closest?.(".panel") as HTMLElement | null;
  if (panelEl && planeEl === anchor.el) { focusPanel(panelEl.dataset.cardId!); return; }
  if (anchor.model && !double) {
    const r = cam.rectToScreen(anchor.layout.model);
    if (x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h) {
      const i = anchor.model.pick(((x - r.x) / r.w) * 2 - 1, -(((y - r.y) / r.h) * 2 - 1));
      if (i !== null) { selectPart(i); return; }
    }
  }
  if (double) { void cam.flyTo(zoomedAt(x, y, 2.4), 380); return; }
  // Empty space: let go of everything.
  selectPart(null);
  anchor.setActive(null);
  bridge.notify("selection.changed", { portalId: anchor.portalId, cardIds: [] });
}

function zoomedAt(x: number, y: number, factor: number) {
  return { s: cam.s * factor, tx: x - (x - cam.tx) * factor, ty: y - (y - cam.ty) * factor };
}

function flyThrough(cardId: string): void {
  const r = anchor?.doorRect(cardId);
  if (!r) return;
  refused.delete(cardId);
  void cam.flyTo(cam.fit(r, 1.02), 900);
}

function focusPanel(cardId: string): void {
  const r = anchor?.panelRect(cardId);
  if (!anchor || !r) return;
  anchor.setActive(cardId);
  notice("tap", { cardId });
  bridge.notify("selection.changed", { portalId: anchor.portalId, cardIds: [cardId] });
  void cam.flyTo(cam.fit(r, 0.86), 650);
}

function selectPart(i: number | null): void {
  const m = anchor?.model;
  if (!m) return;
  selectedPart = i === null || selectedPart === i ? null : i;
  m.highlight(selectedPart);
  const p = selectedPart === null ? null : m.partInfo(selectedPart);
  if (p?.label) notice("tap", { label: p.label });
  showInfo(p?.label ?? null, p?.detail ?? null);
  wake();
}

function showInfo(title: string | null, detail: string | null): void {
  info.textContent = "";
  if (!title && !detail) { info.classList.add("off"); return; }
  const b = document.createElement("b");
  b.textContent = title ?? "";
  info.append(b, document.createTextNode(detail ?? ""));
  if (title) {
    const go = document.createElement("button");
    go.textContent = t.goInside();
    go.addEventListener("click", () => { if (!transitioning && anchor) void zoomInto({ title, detail: detail ?? undefined }, `part:${title}`); });
    info.appendChild(go);
  }
  info.classList.remove("off");
}

// ---------- what the explorer does: Enjin notices (Companion, in EnjinKit, decides when to chime in) ----------
type Noticed = { kind: "look" | "tap" | "explode" | "turn" | "play" | "zoomInto" | "dive" | "rise"; cardId?: string; label?: string; ms?: number };
const noticed: Noticed[] = [];
let lastInput = -1e9;
function notice(kind: Noticed["kind"], what: Omit<Noticed, "kind"> = {}): void {
  noticed.push({ kind, ...Object.fromEntries(Object.entries(what).filter(([, v]) => v !== undefined)) });
}
function sendAttention(): void {
  flushLook();
  if (noticed.length && anchor) bridge.notify("attention", { portalId: anchor.portalId, events: noticed.splice(0) });
}

/** What's in the middle of the view, if they're close enough to be looking at it (or playing with it). */
type Subject = { key: string; cardId?: string; label?: string; kind: "look" | "play" };
function subject(): Subject | null {
  if (!anchor) return null;
  const active = document.activeElement as HTMLElement | null;
  if (active?.tagName === "IFRAME") {
    const id = (active.closest(".panel") as HTMLElement | null)?.dataset.cardId;
    if (id) return { key: id, cardId: id, kind: "play" };
  }
  const f = cam.free();
  const cx = f.x + f.w / 2, cy = f.y + f.h / 2, minD = Math.min(f.w, f.h);
  const inside = (r: Rect) => cx > r.x && cx < r.x + r.w && cy > r.y && cy < r.y + r.h;
  for (const card of anchor.spec.panels) {
    const r0 = anchor.panelRect(card.id);
    const r = r0 && cam.rectToScreen(r0);
    if (r && inside(r) && Math.max(r.w, r.h) > 0.3 * minD) return { key: card.id, cardId: card.id, kind: "look" };
  }
  for (const card of anchor.spec.doors) {
    const r0 = anchor.doorRect(card.id);
    const r = r0 && cam.rectToScreen(r0);
    if (r && inside(r) && r.w > 0.22 * minD) return { key: card.id, cardId: card.id, kind: "look" };
  }
  const m = anchor.model, mr = cam.rectToScreen(anchor.layout.model);
  if (m && inside(mr) && mr.h > 0.45 * f.h) {
    const i = m.pick(((cx - mr.x) / mr.w) * 2 - 1, -(((cy - mr.y) / mr.h) * 2 - 1));
    const label = i === null ? null : m.partInfo(i)?.label;
    if (label) return { key: `part:${label}`, label, kind: "look" };
    const id = anchor.spec.centerpiece?.cardId;
    if (id) return { key: id, cardId: id, kind: "look" };
  }
  return null;
}
let looking: (Subject & { ms: number }) | null = null;
let lastLookTick = performance.now();
function flushLook(): void {
  if (looking && looking.ms >= 800) notice(looking.kind, { cardId: looking.cardId, label: looking.label, ms: Math.round(looking.ms) });
  if (looking) looking.ms = 0;
}
setInterval(() => {
  const now = performance.now();
  const dt = Math.min(1000, now - lastLookTick);
  lastLookTick = now;
  // Moving around isn't looking; playing with a live panel is, even with a finger down in it.
  const s = transitioning ? null : cam.moving(now) || pointers.size ? (looking?.kind === "play" ? subject() : null) : subject();
  if (s && looking && s.key === looking.key) looking.ms += dt;
  else { flushLook(); looking = s ? { ...s, ms: 0 } : null; }
}, 250);
setInterval(sendAttention, 3000);

// ---------- watching Enjin build: new cards arrive in place, and the view follows while you're hands-off ----------
let followNext: string | null = null;
let backToAll: number | undefined;
const handsOff = () => performance.now() - lastInput > 3000 && !pointers.size;
function follow(): void {
  const id = followNext;
  followNext = null;
  if (!id || !anchor || transitioning || !handsOff()) return;
  const r = anchor.panelRect(id) ?? anchor.doorRect(id);
  if (!r) return;
  // The new card with some of what's around it, so you see where it goes.
  void cam.flyTo(cam.fit({ x: r.x - 320, y: r.y - 220, w: r.w + 640, h: r.h + 440 }, 0.95), 900);
  clearTimeout(backToAll);
  backToAll = window.setTimeout(() => { if (anchor && handsOff() && !transitioning) void cam.flyTo(overview(anchor), 1200); }, 4000);
}

// ---------- the bridge (same protocol as the card canvas) ----------
/** Cards change many times a second while Enjin writes: show them as they grow, a few times a second. */
const rebuilds = new Set<Plane>();
function rebuild(p: Plane): void {
  if (rebuilds.has(p)) return;
  rebuilds.add(p);
  window.setTimeout(() => {
    rebuilds.delete(p);
    void p.build(p.scene, files).then(() => { if (p === anchor) { afterBuild(); follow(); } wake(); });
  }, 160);
}
function planeFor(portalId: string): Plane | undefined {
  return planes().find(({ p }) => p.portalId === portalId)?.p;
}

bridge.on("portal.load", async (p) => {
  for (const { p: old } of planes()) old.dispose();
  peeking.clear();
  refused.clear();
  const plane = newPlane(p.scene, true);
  plane.el.classList.add("arriving");
  await plane.build(p.scene, files);
  anchor = plane;
  afterMove();
  const fit = overview(plane);
  const c = cam.free();
  const cx = c.x + c.w / 2, cy = c.y + c.h / 2;
  // Arrive with a little zoom: in from above when diving, back from close when rising.
  const k = p.transition === "exit" ? 1.6 : 0.8;
  cam.set({ s: fit.s * k, tx: cx - (cx - fit.tx) * k, ty: cy - (cy - fit.ty) * k });
  requestAnimationFrame(() => requestAnimationFrame(() => plane.el.classList.remove("arriving")));
  void cam.flyTo(fit, 900);
  return null;
});
bridge.on("canvas.applyOps", ({ portalId, ops }) => {
  const p = planeFor(portalId);
  if (!p) return { placed: [] };
  const byId = new Map(p.scene.cards.map((c) => [c.id, c] as [string, Card]));
  const fresh: string[] = [];
  for (const o of ops) {
    if (o.op === "upsert") { if (!byId.has(o.card.id)) fresh.push(o.card.id); byId.set(o.card.id, o.card); }
    else byId.delete(o.cardId);
  }
  p.scene = { ...p.scene, cards: [...byId.values()] };
  if (fresh.length) {
    p.markBorn(fresh);
    if (p === anchor) followNext = fresh.at(-1)!;
  }
  rebuild(p);
  return { placed: [] };
});
bridge.on("canvas.setHeader", (h) => {
  const p = planeFor(h.portalId);
  if (p) { p.scene = { ...p.scene, title: h.title, subtitle: h.subtitle, hero: h.hero }; rebuild(p); }
  return null;
});
bridge.on("canvas.setBusy", (b) => {
  const on = !!b.message && anchor?.portalId === b.portalId;
  busy.querySelector("span")!.textContent = b.message ?? "";
  busy.classList.toggle("off", !on);
  return null;
});
bridge.on("canvas.setInsets", (insets) => {
  cam.insets = insets;
  hud.style.cssText = `left:${insets.left}px;right:${insets.right}px;top:${insets.top}px;bottom:${insets.bottom}px`;
  wake();
  return null;
});
bridge.on("canvas.setLanguage", ({ language }) => {
  setLang(language);
  for (const { p } of planes()) rebuild(p);
  return null;
});
bridge.on("canvas.addFiles", (a) => {
  for (const f of a.files) files[f.id as never] = { id: f.id, mimeType: f.mimeType, dataURL: f.dataURL, created: Date.now() } as never;
  for (const { p } of planes()) rebuild(p);
  return null;
});
bridge.on("canvas.frame", ({ cardId }) => {
  const door = anchor?.doorRect(cardId);
  if (door) void cam.flyTo(cam.fit(door, 0.6), 800);
  else focusPanel(cardId);
  return { framed: !!door || !!anchor?.panelRect(cardId) };
});
bridge.on("canvas.flash", ({ cardId }) => {
  const el = anchor?.panelElement(cardId) ?? (anchor?.el.querySelector(`.door[data-door="${CSS.escape(cardId)}"]`) as HTMLElement | null);
  el?.animate([{ transform: "scale(1)" }, { transform: "scale(1.04)" }, { transform: "scale(1)" }], { duration: 500, iterations: 2 });
  return null;
});
bridge.on("canvas.liveDocument", ({ cardId }) => {
  const c = anchor?.card(cardId);
  if (!c?.visual || !FRAME_KINDS.has(c.visual.kind)) return { html: null };
  const backdrop = c.visual.kind === "diorama" && c.image ? ((files[c.image.fileId as never]?.dataURL as string | undefined) ?? null) : null;
  const body = frameBody(c.visual, backdrop);
  return { html: body ? liveDocument(body) : null };
});
// The card canvas's drawing tools have no meaning here (sketch panels come later).
bridge.on("canvas.setTool", () => null);
bridge.on("canvas.history", () => null);
bridge.on("ink.lock", () => null);
bridge.on("ink.commit", (p) => ({ strokeId: p.strokeId, elementId: `ink:${p.strokeId}` }));
bridge.install();

// ---------- what you're looking at (native prepares the topic you're closest to) ----------
let settledAt = 0;
let lastFocus: string | null | undefined;
function reportFocus(now: number): void {
  if (!anchor || now - settledAt < 400) return;
  const f = cam.free();
  const cx = f.x + f.w / 2, cy = f.y + f.h / 2;
  let best: string | null = null, bestD = Infinity;
  for (const card of anchor.spec.doors) {
    const dr = anchor.doorRect(card.id);
    if (!dr) continue;
    const r = cam.rectToScreen(dr);
    const d = Math.hypot(r.x + r.w / 2 - cx, r.y + r.h / 2 - cy);
    if (r.w > 0.25 * Math.min(f.w, f.h) && d < bestD) { best = card.id; bestD = d; }
  }
  if (best === lastFocus) return;
  lastFocus = best;
  bridge.notify("focus.changed", { portalId: anchor.portalId, cardId: best, zoom: cam.s, visibleCardIds: [] });
}

// ---------- the loop: draw while anything moves, rest otherwise ----------
function resize(): void {
  const w = host.clientWidth, h = host.clientHeight;
  cam.resize(w, h);
  look.resize(w, h);
  wake();
}
addEventListener("resize", resize);
resize();
let lastError = 0;
function frame(now: number): void {
  // Whatever happens in one frame, the next one comes: a world must never freeze.
  requestAnimationFrame(frame);
  try {
    const moving = cam.update(now) || pointers.size > 0;
    if (moving) settledAt = now;
    const animating = planes().some(({ p }) => p.model?.hasMotion);
    if (moving || animating || now - lastWake < 1500) {
      draw(now);
      check(now);
    }
    reportFocus(now);
  } catch (e) {
    if (now - lastError > 5000) { lastError = now; bridge.notify("log.event", { level: "error", message: `world frame: ${String(e)}` }); }
  }
}
requestAnimationFrame(frame);

(window as unknown as { __enjinWorld: unknown }).__enjinWorld = {
  cam,
  get anchor() { return anchor; },
  get transitioning() { return transitioning; },
  flyThrough,
  zoomBy: (f: number) => { const c = cam.free(); return cam.flyTo(zoomedAt(c.x + c.w / 2, c.y + c.h / 2, f), 500); },
  focusPanel,
};
bridge.request("canvas.ready", { protocolVersion: PROTOCOL_VERSION, excalidrawVersion: "world-2" }).catch(() => undefined);
