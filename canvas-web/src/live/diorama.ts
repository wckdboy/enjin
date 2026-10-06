/**
 * Dioramas: a 2.5D scene in layers. Each layer has a depth (0 far, 1 near) and
 * items in a 100 x 60 scene (y down); layers shift with your finger (and drift
 * on their own) so the scene has real depth.
 *
 * Items are either a prop from ENJIN's library, placed by name ({prop, x, y, s},
 * x/y = where it stands, s = scale), or a raw shape (rect, circle, ellipse,
 * path, text). Anything can float, pulse, spin (about its own pivot) or drift.
 * Hotspots pulse and open a note when tapped. `steps` adds a scrubber that walks
 * the scene through stages; items, layers and hotspots with `step` (or
 * `from`/`to`) show only then. An optional backdrop picture (painted on the
 * device) sits furthest back.
 *
 * Self-contained: its source is injected into a sandboxed frame.
 */
export function mountDiorama(root: HTMLElement, spec: any, backdrop: string | null): void {
  const PAL: Record<string, string> = {
    white: "#ffffff", light: "#ececea", grey: "#a6a6ab", dark: "#4a4a4f", black: "#0b0b0c", accent: "#e8590c", none: "none",
    sky: "#dfe8ef", glass: "rgba(255,255,255,0.55)", water: "#cfdde6", green: "#9bbf8a", earth: "#c9b8a0", red: "#d64545", blue: "#2f6fbf",
  };
  const col = (c: unknown, d: string) => {
    const s = String(c ?? "");
    return PAL[s] ?? (/^#[0-9a-f]{6}$/i.test(s) ? s : d);
  };
  const n = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Number(x) : d);
  const SVGNS = "http://www.w3.org/2000/svg";

  // ---- the prop library: each draws around (0, 0) = where it stands, about 10 units tall at s = 1 ----
  const K = "#0b0b0c", D = "#4a4a4f", G = "#a6a6ab", L = "#ececea", W = "#ffffff";
  const ring = (count: number, fn: (i: number) => string) => Array.from({ length: count }, (_, i) => fn(i)).join("");
  const PROPS: Record<string, (fill: string, accent: string) => string> = {
    tree: (f) => `<rect x="-0.5" y="-4" width="1" height="4" fill="${D}"/><circle cx="0" cy="-6.5" r="3.6" fill="${f === W ? "#9bbf8a" : f}"/>`,
    pine: (f) => `<rect x="-0.4" y="-2" width="0.8" height="2" fill="${D}"/><path d="M0 -11 L3.6 -2 L-3.6 -2 Z" fill="${f === W ? "#6f8f63" : f}"/>`,
    mountain: (f) => `<path d="M-14 0 L0 -16 L14 0 Z" fill="${f === W ? G : f}"/><path d="M-3.5 -12 L0 -16 L3.5 -12 L1.5 -12.8 L0 -11.5 L-1.6 -12.6 Z" fill="${W}"/>`,
    hill: (f) => `<path d="M-16 0 C -9 -9, 9 -9, 16 0 Z" fill="${f === W ? "#b7c9a8" : f}"/>`,
    cloud: (f) => `<g fill="${f}"><circle cx="-3" cy="-2" r="2.4"/><circle cx="0.5" cy="-3.2" r="3.2"/><circle cx="4" cy="-2" r="2.3"/><rect x="-5.4" y="-2" width="11.6" height="2.3" rx="1.1"/></g>`,
    sun: () => `<circle r="4" cy="-5" fill="#f2c14e"/><g stroke="#f2c14e" stroke-width="0.6">${ring(8, (i) => { const t = (i * Math.PI) / 4; return `<line x1="${(5.5 * Math.cos(t)).toFixed(2)}" y1="${(-5 + 5.5 * Math.sin(t)).toFixed(2)}" x2="${(7.2 * Math.cos(t)).toFixed(2)}" y2="${(-5 + 7.2 * Math.sin(t)).toFixed(2)}"/>`; })}</g>`,
    moon: (f) => `<path d="M1 -9 A 4.5 4.5 0 1 0 1 0 A 3.5 3.5 0 1 1 1 -9 Z" fill="${f === W ? L : f}"/>`,
    planet: (f, a) => `<circle cy="-5" r="4.2" fill="${f === W ? G : f}"/><ellipse cy="-5" rx="7.5" ry="1.6" fill="none" stroke="${a}" stroke-width="0.7"/>`,
    stars: () => `<g fill="${W}">${ring(40, (i) => `<circle cx="${((Math.sin(i * 91.7) * 0.5 + 0.5) * 100 - 50).toFixed(1)}" cy="${(-(Math.sin(i * 37.1) * 0.5 + 0.5) * 30).toFixed(1)}" r="${(0.15 + ((i * 7) % 5) * 0.06).toFixed(2)}"/>`)}</g>`,
    waves: (f) => `<path d="M-50 -2 Q -45 -4 -40 -2 T -30 -2 T -20 -2 T -10 -2 T 0 -2 T 10 -2 T 20 -2 T 30 -2 T 40 -2 T 50 -2 L50 6 L-50 6 Z" fill="${f === W ? "#cfdde6" : f}"/>`,
    strata: () => `<g>${["#c9b8a0", "#b5a389", "#d8cbb5", "#9e8c74", "#c2b29a"].map((c, i) => `<rect x="-50" y="${i * 3}" width="100" height="3.1" fill="${c}"/>`).join("")}</g>`,
    house: (f) => `<rect x="-4" y="-5" width="8" height="5" fill="${f}" stroke="${D}" stroke-width="0.3"/><path d="M-5 -5 L0 -9 L5 -5 Z" fill="${D}"/><rect x="-1" y="-2.6" width="2" height="2.6" fill="${D}"/>`,
    building: (f) => `<rect x="-3.5" y="-14" width="7" height="14" fill="${f === W ? L : f}" stroke="${D}" stroke-width="0.3"/><g fill="${G}">${ring(12, (i) => `<rect x="${-2.5 + (i % 3) * 2}" y="${-12.5 + Math.floor(i / 3) * 3}" width="1" height="1.6"/>`)}</g>`,
    factory: (f) => `<path d="M-7 0 L-7 -5 L-4 -7 L-4 -5 L-1 -7 L-1 -5 L2 -7 L2 -5 L7 -5 L7 0 Z" fill="${f === W ? L : f}" stroke="${D}" stroke-width="0.3"/><rect x="4" y="-11" width="1.6" height="6" fill="${D}"/><g fill="${G}" class="a-drift"><circle cx="5" cy="-12.5" r="1.2"/><circle cx="6.6" cy="-14" r="1.6"/></g>`,
    turbine: (f) => `<rect x="-0.35" y="-14" width="0.7" height="14" fill="${f}" stroke="${G}" stroke-width="0.2"/><g class="a-spin" style="transform-box:view-box;transform-origin:0px -14px"><path d="M0 -14 L-0.6 -21 L0.6 -21 Z M0 -14 L5.8 -10.2 L6.4 -11.2 Z M0 -14 L-6.4 -11.2 L-5.8 -10.2 Z" fill="${f}" stroke="${D}" stroke-width="0.2"/></g><circle cy="-14" r="0.7" fill="${D}"/>`,
    volcano: (f, a) => `<path d="M-15 0 L-3 -13 L3 -13 L15 0 Z" fill="${f === W ? "#8a7f75" : f}"/><path d="M-3 -13 L0 -11.5 L3 -13 Z" fill="${a}"/><path d="M-1 -12 L-2.2 -5 L-0.6 -7 L0.4 -3 L1.2 -8 L2 -6 L1 -12 Z" fill="${a}" opacity="0.85"/><g fill="${G}" class="a-drift"><circle cx="0" cy="-16" r="2"/><circle cx="2.5" cy="-18.5" r="2.6"/><circle cx="-1.5" cy="-21" r="2.2"/></g>`,
    cell: (f, a) => `<ellipse cy="-6" rx="9" ry="6" fill="${f === W ? "#eef3ea" : f}" stroke="${D}" stroke-width="0.4"/><circle cx="-1.5" cy="-6.5" r="2.4" fill="${G}" stroke="${D}" stroke-width="0.3"/><circle cx="-1.5" cy="-6.5" r="0.8" fill="${D}"/><ellipse cx="4" cy="-4" rx="1.8" ry="0.9" fill="${a}"/><ellipse cx="3.5" cy="-8.5" rx="1.4" ry="0.7" fill="${a}"/><g fill="${D}">${ring(8, (i) => `<circle cx="${(-6 + i * 1.6).toFixed(1)}" cy="${(-2.4 - (i % 2) * 0.8).toFixed(1)}" r="0.25"/>`)}</g>`,
    bacterium: (f) => `<rect x="-4" y="-3" width="8" height="3" rx="1.5" fill="${f === W ? "#d8e6cf" : f}" stroke="${D}" stroke-width="0.3"/><path d="M4 -1.5 q2 -1.5 3 0 t3 0" fill="none" stroke="${D}" stroke-width="0.3"/>`,
    atom: (_f, a) => `<circle cy="-6" r="1.4" fill="${a}"/><g fill="none" stroke="${D}" stroke-width="0.25"><ellipse cy="-6" rx="6" ry="2.2"/><ellipse cy="-6" rx="6" ry="2.2" transform="rotate(60 0 -6)"/><ellipse cy="-6" rx="6" ry="2.2" transform="rotate(-60 0 -6)"/></g><g class="a-spin" style="transform-box:view-box;transform-origin:0px -6px"><circle cx="6" cy="-6" r="0.6" fill="${K}"/></g>`,
    dna: (_f, a) => `<g stroke-width="0.45" fill="none"><path d="${ring(41, (i) => `${i ? "L" : "M"}${(Math.sin(i / 3) * 2.2).toFixed(2)} ${(-i * 0.4).toFixed(2)} `)}" stroke="${D}"/><path d="${ring(41, (i) => `${i ? "L" : "M"}${(-Math.sin(i / 3) * 2.2).toFixed(2)} ${(-i * 0.4).toFixed(2)} `)}" stroke="${a}"/></g><g stroke="${G}" stroke-width="0.3">${ring(13, (i) => { const y = -i * 1.25; const x = Math.sin((i * 1.25) / 1.2) * 2.2; return `<line x1="${x.toFixed(2)}" y1="${y}" x2="${(-x).toFixed(2)}" y2="${y}"/>`; })}</g>`,
    rocket: (f, a) => `<path d="M0 -14 C 2.2 -11, 2.2 -6, 1.8 -3 L-1.8 -3 C -2.2 -6, -2.2 -11, 0 -14 Z" fill="${f}" stroke="${D}" stroke-width="0.3"/><circle cy="-9" r="0.8" fill="${G}"/><path d="M-1.8 -5 L-3.2 -1.5 L-1.8 -3 Z M1.8 -5 L3.2 -1.5 L1.8 -3 Z" fill="${D}"/><path d="M-1 -3 L0 0.8 L1 -3 Z" fill="${a}"/>`,
    satellite: (f) => `<rect x="-1.3" y="-6.3" width="2.6" height="2.6" fill="${f}" stroke="${D}" stroke-width="0.3"/><rect x="-7" y="-5.6" width="5" height="1.2" fill="${G}" stroke="${D}" stroke-width="0.2"/><rect x="2" y="-5.6" width="5" height="1.2" fill="${G}" stroke="${D}" stroke-width="0.2"/>`,
    person: (f) => `<circle cy="-6.8" r="1.1" fill="${f === W ? D : f}"/><path d="M-1.3 -5.4 L1.3 -5.4 L1.1 -2.4 L0.7 0 L0.2 0 L0 -2.2 L-0.2 0 L-0.7 0 L-1.1 -2.4 Z" fill="${f === W ? D : f}"/>`,
    car: (f) => `<path d="M-5 -1 L-5 -2.6 L-3 -2.8 L-1.8 -4.4 L2.2 -4.4 L3.4 -2.8 L5 -2.6 L5 -1 Z" fill="${f}" stroke="${D}" stroke-width="0.3"/><circle cx="-3" cy="-0.9" r="0.9" fill="${K}"/><circle cx="3" cy="-0.9" r="0.9" fill="${K}"/>`,
    fish: (f, a) => `<path d="M-3 -2 C -1 -4, 2 -4, 3 -2 C 2 0, -1 0, -3 -2 Z M3 -2 L5 -3.4 L5 -0.6 Z" fill="${f === W ? a : f}"/><circle cx="-1.6" cy="-2.3" r="0.3" fill="${W}"/>`,
    bird: () => `<path d="M-2 -1 Q -1 -2 0 -1 Q 1 -2 2 -1" fill="none" stroke="${D}" stroke-width="0.35"/>`,
    plant: (f) => `<path d="M0 0 L0 -6" stroke="${D}" stroke-width="0.35"/><path d="M0 -3 C -3 -4, -3 -6, 0 -4.5 Z M0 -4.5 C 3 -5.5, 3 -7.5, 0 -6 Z" fill="${f === W ? "#9bbf8a" : f}"/>`,
    magnet: () => `<path d="M-3 0 L-3 -5 A 3 3 0 0 1 3 -5 L3 0 L1.4 0 L1.4 -5 A 1.4 1.4 0 0 0 -1.4 -5 L-1.4 0 Z" fill="${G}"/><rect x="-3" y="-1.4" width="1.6" height="1.4" fill="#d64545"/><rect x="1.4" y="-1.4" width="1.6" height="1.4" fill="#2f6fbf"/>`,
    gear: (f) => `<g class="a-spin" style="transform-box:view-box;transform-origin:0px -4px"><path d="${ring(24, (i) => { const t = (i / 24) * 2 * Math.PI; const r = i % 2 ? 3 : 4; return `${i ? "L" : "M"}${(r * Math.cos(t)).toFixed(2)} ${(-4 + r * Math.sin(t)).toFixed(2)} `; })}Z" fill="${f === W ? G : f}" stroke="${D}" stroke-width="0.25"/><circle cy="-4" r="1" fill="${W}"/></g>`,
  };

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
  .dio .note{position:absolute;left:14px;right:14px;bottom:12px;padding:12px 16px;border-radius:16px;background:rgba(255,255,255,.84);
    -webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.08),0 10px 24px rgba(0,0,0,.12);
    font:15px/1.4 Inter,-apple-system,sans-serif;color:#0b0b0c;transition:opacity .2s,transform .2s;z-index:3}
  .dio .note b{display:block;font-weight:700;margin-bottom:2px}
  .dio .note.off{opacity:0;transform:translateY(8px);pointer-events:none}
  .dio .cap{position:absolute;left:14px;top:10px;font:600 11px ui-monospace,Menlo,monospace;letter-spacing:1.3px;text-transform:uppercase;color:#66666b}
  .dio .steps{position:absolute;left:12px;right:12px;bottom:12px;display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:999px;
    background:rgba(255,255,255,.84);-webkit-backdrop-filter:blur(16px);backdrop-filter:blur(16px);box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.08),0 8px 20px rgba(0,0,0,.1);z-index:2}
  .dio .steps button{font:600 14px Inter,-apple-system,sans-serif;border:0;border-radius:999px;width:34px;height:30px;background:#0b0b0c;color:#fff}
  .dio .steps button.ghost{background:transparent;color:#0b0b0c;box-shadow:0 0 0 .75px rgba(0,0,0,.15)}
  .dio .steps .lab{flex:1;font:600 13px Inter,-apple-system,sans-serif;color:#0b0b0c;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dio .steps .n{font:600 11px ui-monospace,Menlo,monospace;color:#66666b;letter-spacing:1px}
  .dio.has-steps .note{bottom:62px}
  .stepped{transition:opacity .45s}
  @keyframes dio-float{50%{transform:translateY(-1.2px)}}@keyframes dio-pulse{50%{transform:scale(1.08)}}
  @keyframes dio-spin{to{transform:rotate(360deg)}}@keyframes dio-drift{50%{transform:translateX(3px)}}
  .a-float{animation:dio-float 3.2s ease-in-out infinite}.a-pulse{animation:dio-pulse 2.4s ease-in-out infinite}
  .a-spin{animation:dio-spin 8s linear infinite}.a-drift{animation:dio-drift 6s ease-in-out infinite}
  .a-float,.a-pulse,.a-drift{transform-box:fill-box;transform-origin:center}`;
  root.appendChild(style);
  const scene = document.createElement("div");
  scene.className = "dio";
  root.appendChild(scene);

  // Things that only show at some steps.
  const stepped: { el: HTMLElement | SVGElement; from: number; to: number }[] = [];
  const track = (el: HTMLElement | SVGElement, x: any) => {
    const r: [number, number] | null = x?.step !== undefined ? [n(x.step, 1), n(x.step, 1)]
      : x?.from !== undefined || x?.to !== undefined ? [n(x.from, 1), n(x.to, 999)] : null;
    if (r) { el.classList.add("stepped"); stepped.push({ el, from: r[0], to: r[1] }); }
  };

  const layers: { el: HTMLElement; depth: number }[] = [];
  if (backdrop) {
    const bd = document.createElement("div");
    bd.className = "bd";
    bd.style.backgroundImage = `url("${backdrop}")`;
    scene.appendChild(bd);
    layers.push({ el: bd, depth: 0.05 });
  }
  const specLayers = (Array.isArray(spec?.layers) ? spec.layers : []).slice(0, 7);
  specLayers.sort((a: any, b: any) => n(a.depth, 0.5) - n(b.depth, 0.5));
  for (const Ly of specLayers) {
    const layer = document.createElement("div");
    layer.className = "layer";
    track(layer, Ly);
    const svg = document.createElementNS(SVGNS, "svg");
    svg.setAttribute("viewBox", "0 0 100 60");
    svg.setAttribute("preserveAspectRatio", "xMidYMid slice");
    for (const it of (Array.isArray(Ly.items) ? Ly.items : []).slice(0, 50)) {
      const fill = col(it.fill, "#ffffff"), stroke = col(it.stroke, "none");
      let node: SVGElement;
      if (it.prop && PROPS[String(it.prop)]) {
        // A library prop, placed where it stands and scaled (negative s flips it).
        node = document.createElementNS(SVGNS, "g");
        const s = Math.max(-8, Math.min(8, n(it.s, 1)));
        node.setAttribute("transform", `translate(${n(it.x, 50)} ${n(it.y, 50)}) scale(${s} ${Math.abs(s)})`);
        node.innerHTML = PROPS[String(it.prop)]!(fill, col(it.accent, "#e8590c"));
      } else {
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
      }
      if (it.opacity !== undefined) node.setAttribute("opacity", String(Math.max(0, Math.min(1, n(it.opacity, 1)))));
      if (["float", "pulse", "spin", "drift"].includes(it.anim)) {
        const wrapG = document.createElementNS(SVGNS, "g");
        wrapG.setAttribute("class", `a-${it.anim}`);
        // Spin turns about the item's own pivot (x, y): a rotor about its hub.
        if (it.anim === "spin") { wrapG.style.transformBox = "view-box"; wrapG.style.transformOrigin = `${n(it.x, 50)}px ${n(it.y, 30)}px`; }
        wrapG.appendChild(node);
        node = wrapG;
      }
      track(node, it);
      svg.appendChild(node);
    }
    layer.appendChild(svg);
    scene.appendChild(layer);
    layers.push({ el: layer, depth: n(Ly.depth, 0.5) });
  }

  const note = document.createElement("div");
  note.className = "note off";
  // Hotspots ride a mid-depth layer, so they stay on what they point at.
  const pins = document.createElement("div");
  pins.className = "layer";
  scene.appendChild(pins);
  layers.push({ el: pins, depth: 0.6 });
  (Array.isArray(spec?.hotspots) ? spec.hotspots : []).slice(0, 10).forEach((h: any, i: number) => {
    const b = document.createElement("div");
    b.className = "hs";
    b.textContent = String(i + 1);
    b.style.left = `${n(h.x, 50)}%`;
    b.style.top = `${(n(h.y, 30) / 60) * 100}%`;
    b.addEventListener("pointerdown", (e) => {
      e.stopPropagation();
      note.textContent = "";
      const t = document.createElement("b");
      t.textContent = String(h.label ?? "");
      note.append(t, document.createTextNode(String(h.detail ?? "")));
      note.classList.remove("off");
    });
    track(b, h);
    pins.appendChild(b);
  });
  scene.addEventListener("pointerdown", () => note.classList.add("off"));
  if (spec?.caption) { const c = document.createElement("div"); c.className = "cap"; c.textContent = String(spec.caption).slice(0, 70); scene.appendChild(c); }
  scene.appendChild(note);

  // Time steps: a scrubber that walks the scene through its stages.
  const steps: any[] = (Array.isArray(spec?.steps) ? spec.steps : []).slice(0, 8);
  let at = 1;
  const showStep = () => {
    for (const s of stepped) {
      const on = at >= s.from && at <= s.to;
      s.el.style.opacity = on ? "1" : "0";
      s.el.style.pointerEvents = on ? "" : "none";
    }
  };
  if (steps.length > 1) {
    scene.classList.add("has-steps");
    const bar = document.createElement("div");
    bar.className = "steps";
    const prev = document.createElement("button");
    prev.className = "ghost"; prev.textContent = "‹";
    const lab = document.createElement("div");
    lab.className = "lab";
    const count = document.createElement("span");
    count.className = "n";
    const next = document.createElement("button");
    next.textContent = "›";
    const render = () => {
      lab.textContent = String(steps[at - 1]?.label ?? "");
      count.textContent = `${at}/${steps.length}`;
      note.classList.add("off");
      showStep();
    };
    const go = (d: number) => (e: Event) => { e.stopPropagation(); at = Math.max(1, Math.min(steps.length, at + d)); render(); };
    for (const b of [prev, next]) b.addEventListener("pointerdown", (e) => e.stopPropagation());
    prev.addEventListener("click", go(-1));
    next.addEventListener("click", go(1));
    bar.append(prev, count, lab, next);
    scene.appendChild(bar);
    render();
  } else {
    showStep();
  }

  // Parallax: near layers move most. Follows the finger, drifts gently when idle.
  let tx = 0, ty = 0, cx = 0, cy = 0, lastMove = -1e9, lastTick = 0;
  scene.addEventListener("pointermove", (e) => {
    const r = scene.getBoundingClientRect();
    tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
    ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
    lastMove = performance.now();
  });
  // WebKit can withhold animation frames from sandboxed frames; a watchdog keeps it moving.
  setInterval(() => { if (performance.now() - lastTick > 250) tick(performance.now(), true); }, 120);
  const tick = (now: number, fromWatchdog = false) => {
    lastTick = now;
    if (now - lastMove > 1800) { tx = Math.sin(now / 2600) * 0.6; ty = Math.cos(now / 3400) * 0.3; }
    cx += (tx - cx) * 0.08; cy += (ty - cy) * 0.08;
    for (const Lr of layers) Lr.el.style.transform = `translate(${-cx * Lr.depth * 16}px, ${-cy * Lr.depth * 9}px)`;
    if (!fromWatchdog) requestAnimationFrame((t) => tick(t));
  };
  requestAnimationFrame((t) => tick(t));
}
