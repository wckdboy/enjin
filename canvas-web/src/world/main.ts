import "../style.css";
import "./world.css";
import type { BinaryFiles } from "@excalidraw/excalidraw/types";
import * as THREE from "three";
import { Bridge, webkitTransport } from "../bridge/client";
import { devHost } from "../bridge/devHost";
import { PROTOCOL_VERSION, type Card, type PortalScene } from "../bridge/schema";
import { setLang } from "../i18n";
import { FRAME_KINDS, frameBody } from "../live/documents";
import { liveDocument } from "../portal/LiveLayer";
import { Director } from "./Director";
import { Look } from "./Look";
import { CssLayer, Panels } from "./Panels";
import { layoutWorld, worldFromScene, type WorldSpec } from "./spec";
import { WorldView } from "./WorldView";

/**
 * ENJIN's world: each portal as a place you fly through. It speaks the same
 * bridge as the card canvas (portal.load, canvas.applyOps, portal.enter, ...),
 * so the app, the agent and the store work unchanged.
 */
let bridge: Bridge;
bridge = new Bridge(webkitTransport() ?? devHost(() => bridge));
window.addEventListener("error", (e) => bridge.notify("log.event", { level: "error", message: e.message }));

const host = document.getElementById("world")!;
const canvas = document.createElement("canvas");
host.appendChild(canvas);
const scene = new THREE.Scene();
const look = new Look(canvas, scene);
const director = new Director(host);
// Layers, bottom to top: backdrop (CSS) · glass panels (CSS3D) · the 3D canvas · labels (CSS3D) · HUD.
const panels = new Panels(host, scene);
canvas.style.zIndex = "2";
const labels = new CssLayer(host, 3);
const view = new WorldView(scene, labels.scene);

// ---------- HUD: what you tapped, explode, Enjin at work, the white of a dive ----------
const hud = document.createElement("div");
hud.className = "hud";
const info = document.createElement("div");
info.className = "info off";
const explodeBtn = document.createElement("button");
explodeBtn.className = "explode";
explodeBtn.textContent = "Explode";
explodeBtn.hidden = true;
const busy = document.createElement("div");
busy.className = "busy off";
busy.innerHTML = `<i class="activity"></i><span></span>`;
const veil = document.createElement("div");
veil.className = "veil";
hud.append(info, explodeBtn, busy);
host.append(hud, veil);
explodeBtn.addEventListener("click", () => {
  view.explodeTarget = view.explodeTarget ? 0 : 1;
  explodeBtn.classList.toggle("on", !!view.explodeTarget);
  wake();
});

// ---------- state ----------
let current: PortalScene | null = null;
let world: WorldSpec | null = null;
const files: BinaryFiles = {};
let transitioning = false;
let selectedPart: number | null = null;

function showInfo(title: string | null, detail: string | null): void {
  info.textContent = "";
  if (!title && !detail) { info.classList.add("off"); return; }
  const b = document.createElement("b");
  b.textContent = title ?? "";
  info.append(b, document.createTextNode(detail ?? ""));
  info.classList.remove("off");
}

async function build(scene: PortalScene): Promise<void> {
  current = scene;
  world = worldFromScene(scene);
  view.clear();
  if (world.centerpiece) view.buildCenterpiece(world.centerpiece.spec);
  else view.buildPlaceholder(world.title);
  const places = layoutWorld(world.doors.length, world.panels.length);
  view.buildDoors(world.doors, places.doors);
  await panels.sync(world.panels, places.panels, files);
  explodeBtn.hidden = !view.hasExplode;
  explodeBtn.classList.remove("on");
  selectedPart = null;
  showInfo(null, null);
  wake();
}

/** Cards changed (the agent writing, a picture arriving): update the world in place. */
let rebuildTimer: number | undefined;
function refresh(): void {
  clearTimeout(rebuildTimer);
  rebuildTimer = window.setTimeout(() => { if (current) void build(current); }, 120);
}

// ---------- moving between worlds ----------
async function veilTo(opacity: number, ms: number): Promise<void> {
  veil.style.transition = `opacity ${ms}ms ease`;
  veil.style.opacity = String(opacity);
  await new Promise((r) => setTimeout(r, ms));
}

async function dive(cardId: string): Promise<void> {
  if (transitioning || !current) return;
  const door = view.door(cardId);
  transitioning = true;
  const next = bridge.request("portal.enter", { portalId: current.portalId, cardId });
  if (door) await director.flyTo(door.position.clone(), 1.6, 750);
  await veilTo(1, 220);
  const scene = await next;
  if (scene) {
    await build(scene);
    director.set({ dist: 3.5, el: 0.1, focus: new THREE.Vector3(0, 0.6, 0) });
  }
  await veilTo(0, 260);
  await director.overview(1000);
  transitioning = false;
}

async function exit(): Promise<void> {
  if (transitioning || !current || current.path.length < 2) return;
  transitioning = true;
  const res = await bridge.request("portal.exit", { portalId: current.portalId });
  if (res) {
    await director.fly({ az: director.az, el: 0.3, dist: 30, focus: director.focus.clone() }, 500);
    await veilTo(1, 200);
    await build(res.scene);
    const door = view.door(res.focusCardId);
    director.set({ dist: 2, focus: door ? door.position.clone() : new THREE.Vector3(0, 0.6, 0) });
    await veilTo(0, 240);
    await director.overview(900);
  }
  transitioning = false;
}

// ---------- touch ----------
const raycaster = new THREE.Raycaster();
director.onTap = (x, y, target) => {
  const el = target as HTMLElement | null;
  const doorLabel = el?.closest?.("[data-door]") as HTMLElement | null;
  if (doorLabel) { void dive(doorLabel.dataset.door!); return; }
  const partLabel = el?.closest?.("[data-part]") as HTMLElement | null;
  const panel = el?.closest?.(".panel") as HTMLElement | null;
  if (panel) { focusPanel(panel.dataset.cardId!); return; }
  let hit: THREE.Intersection | undefined;
  if (!partLabel) {
    const r = host.getBoundingClientRect();
    raycaster.setFromCamera(new THREE.Vector2(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1), director.camera);
    hit = raycaster.intersectObjects(view.root.children, true)[0];
  }
  const data = partLabel ? { kind: "part", index: Number(partLabel.dataset.part) } : hit?.object.userData;
  if (data?.kind === "door") { void dive(data.cardId); return; }
  if (data?.kind === "part") {
    selectedPart = selectedPart === data.index ? null : data.index;
    view.highlight(selectedPart);
    const p = selectedPart === null ? null : view.partInfo(selectedPart);
    showInfo(p?.label ?? null, p?.detail ?? null);
    wake();
    return;
  }
  // Empty space: let go of everything.
  selectedPart = null;
  view.highlight(null);
  showInfo(null, null);
  panels.setActive(null);
  bridge.notify("selection.changed", { portalId: current?.portalId ?? "", cardIds: [] });
};
director.onPullOut = () => void exit();

function focusPanel(cardId: string): void {
  const at = panels.worldPosition(cardId);
  if (!at) return;
  panels.setActive(cardId);
  bridge.notify("selection.changed", { portalId: current?.portalId ?? "", cardIds: [cardId] });
  void director.flyTo(at, 5.2, 800, true);
}

// ---------- the bridge (same protocol as the card canvas) ----------
bridge.on("portal.load", async (p) => {
  if (current && p.transition !== "jump") await veilTo(1, 160);
  await build(p.scene);
  director.set({ az: 0, el: 0.2, dist: p.transition === "jump" && current ? 15 : 22, focus: new THREE.Vector3(0, 0.6, 0) });
  await veilTo(0, 240);
  void director.overview(1100);
  return null;
});
bridge.on("canvas.applyOps", ({ portalId, ops }) => {
  if (!current || current.portalId !== portalId) return { placed: [] };
  const byId = new Map(current.cards.map((c) => [c.id, c] as [string, Card]));
  for (const o of ops) {
    if (o.op === "upsert") byId.set(o.card.id, o.card);
    else byId.delete(o.cardId);
  }
  current = { ...current, cards: [...byId.values()] };
  refresh();
  return { placed: [] };
});
bridge.on("canvas.setHeader", (p) => {
  if (current && current.portalId === p.portalId) current = { ...current, title: p.title, subtitle: p.subtitle, hero: p.hero };
  return null;
});
bridge.on("canvas.setBusy", (p) => {
  const on = !!p.message && current?.portalId === p.portalId;
  busy.querySelector("span")!.textContent = p.message ?? "";
  busy.classList.toggle("off", !on);
  return null;
});
bridge.on("canvas.setInsets", (insets) => {
  director.setInsets(insets);
  hud.style.cssText = `left:${insets.left}px;right:${insets.right}px;top:${insets.top}px;bottom:${insets.bottom}px`;
  return null;
});
bridge.on("canvas.setLanguage", ({ language }) => {
  setLang(language);
  refresh();
  return null;
});
bridge.on("canvas.addFiles", (p) => {
  for (const f of p.files) files[f.id as never] = { id: f.id, mimeType: f.mimeType, dataURL: f.dataURL, created: Date.now() } as never;
  refresh();
  return null;
});
bridge.on("canvas.frame", (p) => {
  const door = view.door(p.cardId);
  if (door) void director.flyTo(door.position.clone(), 4, 800);
  else focusPanel(p.cardId);
  return { framed: !!door || !!panels.object(p.cardId) };
});
bridge.on("canvas.flash", (p) => {
  panels.object(p.cardId)?.element.animate([{ transform: "scale(1)" }, { transform: "scale(1.04)" }, { transform: "scale(1)" }], { duration: 500, iterations: 2 });
  return null;
});
bridge.on("canvas.liveDocument", (p) => {
  const c = current?.cards.find((x) => x.id === p.cardId);
  if (!c?.visual || !FRAME_KINDS.has(c.visual.kind)) return { html: null };
  const backdrop = c.visual.kind === "diorama" && c.image ? ((files[c.image.fileId as never]?.dataURL as string | undefined) ?? null) : null;
  const body = frameBody(c.visual, backdrop);
  return { html: body ? liveDocument(body) : null };
});
// The card canvas's drawing tools have no meaning here yet (Phase 4 brings sketch panels).
bridge.on("canvas.setTool", () => null);
bridge.on("canvas.history", () => null);
bridge.on("ink.lock", () => null);
bridge.on("ink.commit", (p) => ({ strokeId: p.strokeId, elementId: `ink:${p.strokeId}` }));
bridge.install();
(window as unknown as { __enjinWorld: unknown }).__enjinWorld = { director, view, panels, get current() { return current; }, dive, exit };

// ---------- the loop: render while anything moves, rest otherwise ----------
let lastWake = performance.now();
function wake(): void { lastWake = performance.now(); }
function resize(): void {
  const w = host.clientWidth, h = host.clientHeight;
  look.resize(w, h);
  director.resize(w, h);
  panels.resize(w, h);
  labels.resize(w, h);
  wake();
}
addEventListener("resize", resize);
resize();
const t0 = performance.now();
let frames = 0;
function frame(now: number): void {
  const active = view.hasMotion || director.busy(now) || now - lastWake < 1500 || director.drifting(now);
  if (active) {
    const t = (now - t0) / 1000;
    director.update(now);
    view.update(t);
    if (++frames % 6 === 0) view.occlude(director.camera);
    look.render(scene, director.camera, t);
    panels.render(director.camera);
    labels.render(director.camera);
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
bridge.request("canvas.ready", { protocolVersion: PROTOCOL_VERSION, excalidrawVersion: "world-1" }).catch(() => undefined);
