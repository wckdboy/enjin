/**
 * Dioramas: a 2.5D scene in layers. Each layer has a depth (0 far, 1 near) and
 * props drawn as simple vector shapes in a 100 x 60 scene; layers shift with
 * your finger (and drift on their own) so the scene has real depth. Props can
 * float, spin, pulse or drift. Hotspots pulse and open a note when tapped. An
 * optional backdrop picture (generated on the device) sits furthest back.
 *
 * Self-contained: its source is injected into a sandboxed frame.
 */
export function mountDiorama(root: HTMLElement, spec: any, backdrop: string | null): void {
  const PAL: Record<string, string> = {
    white: "#ffffff", light: "#ececea", grey: "#a6a6ab", dark: "#4a4a4f", black: "#0b0b0c", accent: "#e8590c", none: "none",
    sky: "#dfe8ef", glass: "rgba(255,255,255,0.55)",
  };
  const col = (c: unknown, d: string) => {
    const s = String(c ?? "");
    return PAL[s] ?? (/^#[0-9a-f]{6}$/i.test(s) ? s : d);
  };
  const n = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Number(x) : d);
  const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
  const SVGNS = "http://www.w3.org/2000/svg";

  const style = document.createElement("style");
  style.textContent = `
  .dio{position:absolute;inset:0;overflow:hidden;background:linear-gradient(#f7f7f5,#e9e9e6);touch-action:none}
  .dio .layer{position:absolute;inset:-6%;will-change:transform}
  .dio .layer svg{width:100%;height:100%;display:block}
  .dio .bd{position:absolute;inset:-6%;background-size:cover;background-position:center;filter:saturate(.9)}
  .dio .hs{position:absolute;width:30px;height:30px;margin:-15px 0 0 -15px;border-radius:50%;background:#0b0b0c;color:#fff;border:3px solid #fff;
    font:700 13px Inter,-apple-system,sans-serif;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,.25);cursor:pointer}
  .dio .hs::after{content:"";position:absolute;inset:-9px;border-radius:50%;border:1.5px solid rgba(11,11,12,.5);animation:dio-ping 2s ease-out infinite}
  @keyframes dio-ping{from{transform:scale(.6);opacity:1}to{transform:scale(1.5);opacity:0}}
  .dio .note{position:absolute;left:14px;right:14px;bottom:12px;padding:12px 16px;border-radius:16px;background:rgba(255,255,255,.82);
    -webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.08),0 10px 24px rgba(0,0,0,.12);
    font:15px/1.4 Inter,-apple-system,sans-serif;color:#0b0b0c;transition:opacity .2s,transform .2s}
  .dio .note b{display:block;font-weight:700;margin-bottom:2px}
  .dio .note.off{opacity:0;transform:translateY(8px);pointer-events:none}
  .dio .cap{position:absolute;left:14px;top:10px;font:600 11px ui-monospace,Menlo,monospace;letter-spacing:1.3px;text-transform:uppercase;color:#66666b}
  @keyframes dio-float{50%{transform:translateY(-1.2px)}}@keyframes dio-pulse{50%{transform:scale(1.08)}}
  @keyframes dio-spin{to{transform:rotate(360deg)}}@keyframes dio-drift{50%{transform:translateX(3px)}}
  .a-float{animation:dio-float 3.2s ease-in-out infinite}.a-pulse{animation:dio-pulse 2.4s ease-in-out infinite}
  .a-spin{animation:dio-spin 8s linear infinite}.a-drift{animation:dio-drift 6s ease-in-out infinite}
  .a-float,.a-pulse,.a-spin,.a-drift{transform-box:fill-box;transform-origin:center}`;
  root.appendChild(style);
  const scene = document.createElement("div");
  scene.className = "dio";
  root.appendChild(scene);

  const layers: { el: HTMLElement; depth: number }[] = [];
  if (backdrop) {
    const bd = document.createElement("div");
    bd.className = "bd";
    bd.style.backgroundImage = `url("${backdrop}")`;
    scene.appendChild(bd);
    layers.push({ el: bd, depth: 0.05 });
  }
  const specLayers = (Array.isArray(spec?.layers) ? spec.layers : []).slice(0, 6);
  specLayers.sort((a: any, b: any) => n(a.depth, 0.5) - n(b.depth, 0.5));
  for (const L of specLayers) {
    const layer = document.createElement("div");
    layer.className = "layer";
    const svg = document.createElementNS(SVGNS, "svg");
    svg.setAttribute("viewBox", "0 0 100 60");
    svg.setAttribute("preserveAspectRatio", "xMidYMid slice");
    for (const it of (Array.isArray(L.items) ? L.items : []).slice(0, 40)) {
      const fill = col(it.fill, "#ffffff"), stroke = col(it.stroke, "none");
      let node: SVGElement;
      switch (it.shape) {
        case "circle":
          node = document.createElementNS(SVGNS, "circle");
          node.setAttribute("cx", String(n(it.x, 50))); node.setAttribute("cy", String(n(it.y, 30))); node.setAttribute("r", String(n(it.r, 5)));
          break;
        case "ellipse":
          node = document.createElementNS(SVGNS, "ellipse");
          node.setAttribute("cx", String(n(it.x, 50))); node.setAttribute("cy", String(n(it.y, 30)));
          node.setAttribute("rx", String(n(it.w, 10) / 2)); node.setAttribute("ry", String(n(it.h, 6) / 2));
          break;
        case "path":
          node = document.createElementNS(SVGNS, "path");
          // Only path data characters: no URLs, no script.
          node.setAttribute("d", String(it.d ?? "").replace(/[^MLHVCSQTAZmlhvcsqtaz0-9.,\s-]/g, "").slice(0, 2000));
          break;
        case "text":
          node = document.createElementNS(SVGNS, "text");
          node.setAttribute("x", String(n(it.x, 50))); node.setAttribute("y", String(n(it.y, 30)));
          node.setAttribute("font-size", String(n(it.size, 3.2)));
          node.setAttribute("font-family", "Inter,-apple-system,sans-serif");
          node.setAttribute("font-weight", "600");
          node.setAttribute("text-anchor", "middle");
          node.textContent = String(it.text ?? "").slice(0, 40);
          break;
        default:
          node = document.createElementNS(SVGNS, "rect");
          node.setAttribute("x", String(n(it.x, 0))); node.setAttribute("y", String(n(it.y, 0)));
          node.setAttribute("width", String(n(it.w, 10))); node.setAttribute("height", String(n(it.h, 10)));
          node.setAttribute("rx", String(n(it.rx, 0.8)));
      }
      node.setAttribute("fill", it.shape === "text" ? col(it.fill, "#0b0b0c") : fill);
      if (stroke !== "none") { node.setAttribute("stroke", stroke); node.setAttribute("stroke-width", String(n(it.strokeWidth, 0.4))); }
      if (it.opacity !== undefined) node.setAttribute("opacity", String(Math.max(0, Math.min(1, n(it.opacity, 1)))));
      if (["float", "pulse", "spin", "drift"].includes(it.anim)) {
        node.setAttribute("class", `a-${it.anim}`);
        // A path can name its pivot (x, y): a rotor turns about its hub, not its bounding box.
        if (it.shape === "path" && it.x !== undefined && it.y !== undefined) {
          (node as SVGElement).style.transformBox = "view-box";
          (node as SVGElement).style.transformOrigin = `${n(it.x, 50)}px ${n(it.y, 30)}px`;
        }
      }
      svg.appendChild(node);
    }
    layer.appendChild(svg);
    scene.appendChild(layer);
    layers.push({ el: layer, depth: n(L.depth, 0.5) });
  }

  const note = document.createElement("div");
  note.className = "note off";
  // Hotspots ride a mid-depth layer, so they stay on what they point at.
  const pins = document.createElement("div");
  pins.className = "layer";
  scene.appendChild(pins);
  layers.push({ el: pins, depth: 0.6 });
  (Array.isArray(spec?.hotspots) ? spec.hotspots : []).slice(0, 8).forEach((h: any, i: number) => {
    const b = document.createElement("div");
    b.className = "hs";
    b.textContent = String(i + 1);
    b.style.left = `${n(h.x, 50)}%`;
    b.style.top = `${(n(h.y, 30) / 60) * 100}%`;
    b.addEventListener("pointerdown", (e) => {
      e.stopPropagation();
      note.innerHTML = `<b>${esc(h.label)}</b>${esc(h.detail)}`;
      note.classList.remove("off");
    });
    pins.appendChild(b);
  });
  scene.addEventListener("pointerdown", () => note.classList.add("off"));
  if (spec?.caption) { const c = document.createElement("div"); c.className = "cap"; c.textContent = String(spec.caption).slice(0, 60); scene.appendChild(c); }
  scene.appendChild(note);

  // Parallax: near layers move most. Follows the finger, drifts gently when idle.
  let tx = 0, ty = 0, cx = 0, cy = 0, lastMove = -1e9;
  scene.addEventListener("pointermove", (e) => {
    const r = scene.getBoundingClientRect();
    tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
    ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    lastMove = performance.now();
  });
  let lastTick = 0;
  setInterval(() => { if (performance.now() - lastTick > 250) tick(performance.now(), true); }, 120);
  const tick = (now: number, fromWatchdog = false) => {
    lastTick = now;
    if (now - lastMove > 1800) { tx = Math.sin(now / 2600) * 0.6; ty = Math.cos(now / 3400) * 0.3; }
    cx += (tx - cx) * 0.08; cy += (ty - cy) * 0.08;
    for (const L of layers) L.el.style.transform = `translate(${-cx * L.depth * 16}px, ${-cy * L.depth * 9}px)`;
    if (!fromWatchdog) requestAnimationFrame((n) => tick(n));
  };
  requestAnimationFrame((n) => tick(n));
}
