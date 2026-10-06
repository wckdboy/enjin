/**
 * ENJIN 3D: a small, dependency-free 3D model viewer for live cards. The agent
 * describes a model as data and this draws it on a 2D canvas: perspective,
 * depth-sorted shading with a soft highlight, in ENJIN's whites, greys, black
 * and one accent.
 *
 * Spec:
 * - parts: shape box | sphere | cylinder | cone | torus | ring | capsule |
 *   lathe (profile [[r, y], ...]) | extrude (outline [[x, y], ...], depth) |
 *   tube (points [[x, y, z], ...], radius); position, rotation (deg), color,
 *   label, detail, group, spin {axis, rpm}, orbit {center, rpm}, explode [dx, dy, dz].
 * - groups: { name: { pivot, spin, orbit } } move their parts together.
 * - atoms [{id, element, position}] + bonds [[a, b, order]]: ball-and-stick molecules.
 * - camera {azimuth, elevation, distance}, caption, autoRotate.
 *
 * Touch: drag to turn, pinch to zoom, tap a part to inspect it, double-tap to
 * reset; "Explode" pulls the parts apart when any part has an explode offset.
 *
 * Self-contained: its source is injected into a sandboxed frame.
 */
export function mount3D(root: HTMLElement, spec: any): void {
  type V = [number, number, number];
  type Tri = [V, V, V];
  const PALETTE: Record<string, string> = {
    white: "#f6f6f5", light: "#dededc", grey: "#a6a6ab", dark: "#4a4a4f", black: "#141416", accent: "#e8590c", glass: "#ffffff",
    red: "#d64545", blue: "#2f6fbf", green: "#2f9e44", yellow: "#d9a82b",
  };
  const ELEMENTS: Record<string, { color: string; r: number }> = {
    H: { color: "#f6f6f5", r: 0.24 }, C: { color: "#3a3a3e", r: 0.36 }, N: { color: "#2f6fbf", r: 0.35 }, O: { color: "#d64545", r: 0.34 },
    S: { color: "#d9a82b", r: 0.42 }, P: { color: "#e8590c", r: 0.42 }, Cl: { color: "#2f9e44", r: 0.42 }, F: { color: "#79c27a", r: 0.3 },
    Na: { color: "#8e6fc6", r: 0.5 }, Fe: { color: "#a65b3a", r: 0.46 },
  };
  const parseHex = (h: string): V => {
    const m = /^#?([0-9a-f]{6})$/i.exec(h.trim());
    const n = m ? parseInt(m[1]!, 16) : 0xa6a6ab;
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const colorOf = (c: unknown): V => parseHex(PALETTE[String(c ?? "white")] ?? String(c ?? "#f6f6f5"));
  const rad = (d: number) => (d * Math.PI) / 180;
  const rotX = (p: V, a: number): V => [p[0], p[1] * Math.cos(a) - p[2] * Math.sin(a), p[1] * Math.sin(a) + p[2] * Math.cos(a)];
  const rotY = (p: V, a: number): V => [p[0] * Math.cos(a) + p[2] * Math.sin(a), p[1], -p[0] * Math.sin(a) + p[2] * Math.cos(a)];
  const rotZ = (p: V, a: number): V => [p[0] * Math.cos(a) - p[1] * Math.sin(a), p[0] * Math.sin(a) + p[1] * Math.cos(a), p[2]];
  const rotate = (p: V, r: V): V => rotZ(rotY(rotX(p, r[0]), r[1]), r[2]);
  const add = (a: V, b: V): V => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const sub = (a: V, b: V): V => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const scale = (a: V, k: number): V => [a[0] * k, a[1] * k, a[2] * k];
  const cross = (a: V, b: V): V => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a: V, b: V) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const norm = (a: V): V => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
  const num = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Number(x) : d);
  const vec = (x: unknown, d: V): V => (Array.isArray(x) && x.length === 3 ? [num(x[0], d[0]), num(x[1], d[1]), num(x[2], d[2])] : d);
  type Motion = { axis: string; rpm: number; center: V };
  const motion = (m: any): Motion | null =>
    m ? { axis: String(m.axis ?? "y"), rpm: Math.max(-600, Math.min(600, num(m.rpm, 10))), center: vec(m.center, [0, 0, 0]) } : null;
  const spinRot = (m: Motion | null, t: number): V => {
    if (!m) return [0, 0, 0];
    const a = (t * m.rpm * 2 * Math.PI) / 60;
    return m.axis === "x" ? [a, 0, 0] : m.axis === "z" ? [0, 0, a] : [0, a, 0];
  };

  // ---- meshes (local space) ----
  const quad = (a: V, b: V, c: V, d: V): Tri[] => [[a, b, c], [a, c, d]];
  const box = (w: number, h: number, d: number): Tri[] => {
    const x = w / 2, y = h / 2, z = d / 2;
    const p: V[] = [[-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]];
    return [
      ...quad(p[4]!, p[5]!, p[6]!, p[7]!), ...quad(p[1]!, p[0]!, p[3]!, p[2]!), ...quad(p[0]!, p[4]!, p[7]!, p[3]!),
      ...quad(p[5]!, p[1]!, p[2]!, p[6]!), ...quad(p[3]!, p[7]!, p[6]!, p[2]!), ...quad(p[0]!, p[1]!, p[5]!, p[4]!),
    ];
  };
  const lathe = (profile: [number, number][], seg: number, caps = true): Tri[] => {
    const out: Tri[] = [];
    const ring = (r: number, y: number, i: number): V => [r * Math.cos((i / seg) * 2 * Math.PI), y, r * Math.sin((i / seg) * 2 * Math.PI)];
    for (let k = 0; k < profile.length - 1; k++) {
      const [r0, y0] = profile[k]!, [r1, y1] = profile[k + 1]!;
      for (let i = 0; i < seg; i++) out.push(...quad(ring(r0, y0, i), ring(r0, y0, i + 1), ring(r1, y1, i + 1), ring(r1, y1, i)));
    }
    if (caps) {
      const [rb, yb] = profile[0]!, [rt, yt] = profile[profile.length - 1]!;
      for (let i = 0; i < seg; i++) {
        if (rb > 0.001) out.push([[0, yb, 0], ring(rb, yb, i + 1), ring(rb, yb, i)]);
        if (rt > 0.001) out.push([[0, yt, 0], ring(rt, yt, i), ring(rt, yt, i + 1)]);
      }
    }
    return out;
  };
  const arc = (r: number, y0: number, from: number, to: number, n: number): [number, number][] =>
    Array.from({ length: n + 1 }, (_, i) => { const a = from + ((to - from) * i) / n; return [r * Math.cos(a), y0 + r * Math.sin(a)] as [number, number]; });
  const sphere = (r: number) => lathe(arc(r, 0, -Math.PI / 2, Math.PI / 2, 14), 24, false);
  const capsule = (r: number, h: number) => lathe([...arc(r, -h / 2, -Math.PI / 2, 0, 5), ...arc(r, h / 2, 0, Math.PI / 2, 5)], 18, false);
  const torus = (R: number, r: number) => {
    const out: Tri[] = [];
    const P = (i: number, j: number): V => {
      const u = (i / 24) * 2 * Math.PI, v = (j / 10) * 2 * Math.PI;
      return [(R + r * Math.cos(v)) * Math.cos(u), r * Math.sin(v), (R + r * Math.cos(v)) * Math.sin(u)];
    };
    for (let i = 0; i < 24; i++) for (let j = 0; j < 10; j++) out.push(...quad(P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)));
    return out;
  };
  /** A flat outline (x, y) pushed out along z: gears, wings, plates. Caps fan from the centroid (fine for star-shaped outlines). */
  const extrude = (outline: [number, number][], depth: number): Tri[] => {
    const pts = outline.slice(0, 120);
    if (pts.length < 3) return [];
    const out: Tri[] = [];
    const z = depth / 2;
    const ox = pts.reduce((a, p) => a + p[0], 0) / pts.length, oy = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i]!, b = pts[(i + 1) % pts.length]!;
      out.push(...quad([a[0], a[1], -z], [b[0], b[1], -z], [b[0], b[1], z], [a[0], a[1], z]));
      out.push([[ox, oy, z], [a[0], a[1], z], [b[0], b[1], z]]);
      out.push([[ox, oy, -z], [b[0], b[1], -z], [a[0], a[1], -z]]);
    }
    return out;
  };
  /** A tube along a path: wires, pipes, bonds, struts. */
  const tube = (points: V[], r: number, seg = 10): Tri[] => {
    const out: Tri[] = [];
    for (let k = 0; k < points.length - 1; k++) {
      const a = points[k]!, b = points[k + 1]!;
      const dir = norm(sub(b, a));
      const helper: V = Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
      const u = norm(cross(dir, helper)), w = cross(dir, u);
      const ringAt = (c: V, i: number): V => add(c, add(scale(u, r * Math.cos((i / seg) * 2 * Math.PI)), scale(w, r * Math.sin((i / seg) * 2 * Math.PI))));
      for (let i = 0; i < seg; i++) out.push(...quad(ringAt(a, i), ringAt(a, i + 1), ringAt(b, i + 1), ringAt(b, i)));
    }
    return out;
  };
  const pairs = (x: unknown): [number, number][] =>
    Array.isArray(x) ? x.filter((q) => Array.isArray(q) && q.length >= 2).map((q: any) => [num(q[0], 0), num(q[1], 0)] as [number, number]) : [];
  const meshOf = (p: any): { tris: Tri[]; edges: boolean } => {
    const s = vec(p.size, [1, 1, 1]);
    const r = Math.max(0.001, num(p.radius, s[0] / 2)), h = num(p.height, s[1]);
    switch (p.shape) {
      case "sphere": return { tris: sphere(r), edges: false };
      case "cylinder": return { tris: lathe([[r, -h / 2], [r, h / 2]], 24), edges: false };
      case "cone": return { tris: lathe([[r, -h / 2], [0.001, h / 2]], 24), edges: false };
      case "capsule": return { tris: capsule(r, h), edges: false };
      case "torus": return { tris: torus(num(p.radius, 1), num(p.tube, 0.25)), edges: false };
      case "ring": { const inner = num(p.inner, r * 0.7); return { tris: lathe([[r, -h / 2], [r, h / 2], [inner, h / 2], [inner, -h / 2], [r, -h / 2]], 32, false), edges: false }; }
      case "lathe": { const prof = pairs(p.profile).slice(0, 40); return { tris: prof.length >= 2 ? lathe(prof, 24) : [], edges: false }; }
      case "extrude": return { tris: extrude(pairs(p.outline), num(p.depth, 0.2)), edges: true };
      case "tube": return { tris: tube((Array.isArray(p.points) ? p.points : []).slice(0, 60).map((q: unknown) => vec(q, [0, 0, 0])), Math.max(0.005, num(p.radius, 0.05))), edges: false };
      default: return { tris: box(s[0], s[1], s[2]), edges: true };
    }
  };

  // ---- the model ----
  const rawParts: any[] = (Array.isArray(spec?.parts) ? spec.parts : []).slice(0, 80);
  // Molecules: atoms as balls, bonds as sticks (double and triple bonds side by side).
  const atoms: any[] = (Array.isArray(spec?.atoms) ? spec.atoms : []).slice(0, 120);
  const atomById = new Map<string, V>();
  for (const a of atoms) {
    const pos = vec(a.position, [0, 0, 0]);
    const el = ELEMENTS[String(a.element ?? "C")] ?? { color: "#a6a6ab", r: 0.38 };
    atomById.set(String(a.id ?? ""), pos);
    rawParts.push({ shape: "sphere", radius: el.r, position: pos, color: el.color, label: a.label, detail: a.detail, group: a.group });
  }
  for (const b of (Array.isArray(spec?.bonds) ? spec.bonds : []).slice(0, 200)) {
    const pa = atomById.get(String(b?.[0])), pb = atomById.get(String(b?.[1]));
    if (!pa || !pb) continue;
    const order = Math.max(1, Math.min(3, num(b?.[2], 1)));
    const d = norm(sub(pb, pa));
    const off = norm(cross(d, Math.abs(d[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0]));
    for (let k = 0; k < order; k++) {
      const shift = scale(off, (k - (order - 1) / 2) * 0.12);
      rawParts.push({ shape: "tube", points: [add(pa, shift), add(pb, shift)], radius: 0.055, position: [0, 0, 0], color: "grey" });
    }
  }
  const groups: Record<string, { pivot: V; spin: Motion | null; orbit: Motion | null }> = {};
  for (const [name, gr] of Object.entries(spec?.groups ?? {})) {
    const gg = gr as any;
    groups[name] = { pivot: vec(gg?.pivot, [0, 0, 0]), spin: motion(gg?.spin), orbit: motion(gg?.orbit) };
  }
  const parts = rawParts.map((p: any) => ({
    ...meshOf(p),
    pos: vec(p.position, [0, 0, 0]),
    rot: vec(p.rotation, [0, 0, 0]).map(rad) as V,
    color: colorOf(p.color),
    alpha: p.color === "glass" ? 0.28 : 1,
    label: p.label ? String(p.label).slice(0, 32) : null,
    detail: p.detail ? String(p.detail).slice(0, 200) : null,
    group: p.group ? String(p.group) : null,
    spin: motion(p.spin),
    orbit: motion(p.orbit),
    explode: vec(p.explode, [0, 0, 0]),
  }));
  const explodable = parts.some((p) => p.explode.some((x: number) => x !== 0));

  // Frame the model: centre and radius of everything.
  let cx = 0, cy = 0, cz = 0, extent = 0.5;
  {
    const all: V[] = [];
    for (const p of parts) for (const t of p.tris) for (const v of t) all.push(add(rotate(v, p.rot), p.pos));
    if (all.length) {
      const lo = [0, 1, 2].map((k) => Math.min(...all.map((v) => v[k]!)));
      const hi = [0, 1, 2].map((k) => Math.max(...all.map((v) => v[k]!)));
      cx = (lo[0]! + hi[0]!) / 2; cy = (lo[1]! + hi[1]!) / 2; cz = (lo[2]! + hi[2]!) / 2;
      extent = Math.max(0.5, ...all.map((v) => Math.hypot(v[0] - cx, v[1] - cy, v[2] - cz)));
    }
  }
  const cam0 = { az: rad(num(spec?.camera?.azimuth, 35)), el: rad(num(spec?.camera?.elevation, 22)), dist: num(spec?.camera?.distance, extent * 3.2) };
  const cam = { ...cam0 };
  const autoRotate = spec?.autoRotate !== false;

  // ---- DOM ----
  const style = document.createElement("style");
  style.textContent = `.v3{position:absolute;inset:0;background:radial-gradient(ellipse at 50% 35%,#ffffff 0%,#f2f2f0 70%,#e9e9e6 100%);touch-action:none;font-family:Inter,-apple-system,sans-serif}
  .v3 canvas{width:100%;height:100%;display:block}
  .v3 .hud{position:absolute;left:14px;bottom:10px;font:600 11px ui-monospace,Menlo,monospace;letter-spacing:1.3px;text-transform:uppercase;color:#66666b;pointer-events:none}
  .v3 .btn{position:absolute;left:12px;top:10px;font:600 13px Inter,-apple-system,sans-serif;border:0;border-radius:999px;padding:7px 14px;background:rgba(255,255,255,.85);color:#0b0b0c;box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.1),0 6px 14px rgba(0,0,0,.08)}
  .v3 .btn.on{background:#0b0b0c;color:#fff}
  .v3 .info{position:absolute;right:12px;bottom:12px;max-width:52%;padding:10px 14px;border-radius:14px;background:rgba(255,255,255,.86);
    -webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.08),0 10px 24px rgba(0,0,0,.1);
    font:14px/1.4 Inter,-apple-system,sans-serif;color:#0b0b0c;transition:opacity .2s}
  .v3 .info b{display:block;margin-bottom:2px}.v3 .info.off{opacity:0;pointer-events:none}`;
  root.appendChild(style);
  const wrap = document.createElement("div");
  wrap.className = "v3";
  const canvas = document.createElement("canvas");
  const hud = document.createElement("div");
  hud.className = "hud";
  hud.textContent = spec?.caption ? String(spec.caption).slice(0, 70) : "Drag to turn · tap a part";
  const info = document.createElement("div");
  info.className = "info off";
  wrap.append(canvas, hud, info);
  let exploded = 0, explodeTarget = 0;
  if (explodable) {
    const btn = document.createElement("button");
    btn.className = "btn";
    btn.textContent = "Explode";
    btn.addEventListener("pointerdown", (e) => e.stopPropagation());
    btn.addEventListener("click", () => { explodeTarget = explodeTarget ? 0 : 1; btn.classList.toggle("on", !!explodeTarget); });
    wrap.appendChild(btn);
  }
  root.appendChild(wrap);
  const g = canvas.getContext("2d")!;

  // ---- touch ----
  const pointers = new Map<number, { x: number; y: number }>();
  let lastTouch = -1e9, pinch0 = 0, dist0 = cam.dist, lastTap = 0, moved = 0, selected = -1;
  let faceHits: { pts: { x: number; y: number }[]; part: number }[] = [];
  const pick = (x: number, y: number) => {
    const inTri = (p: { x: number; y: number }[]) => {
      const s = (a: { x: number; y: number }, b: { x: number; y: number }) => (x - b.x) * (a.y - b.y) - (a.x - b.x) * (y - b.y);
      const d1 = s(p[0]!, p[1]!), d2 = s(p[1]!, p[2]!), d3 = s(p[2]!, p[0]!);
      return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
    };
    for (let i = faceHits.length - 1; i >= 0; i--) if (inTri(faceHits[i]!.pts)) return faceHits[i]!.part;
    return -1;
  };
  wrap.addEventListener("pointerdown", (e) => {
    wrap.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    lastTouch = performance.now();
    moved = 0;
    if (pointers.size === 2) { const [a, b] = [...pointers.values()]; pinch0 = Math.hypot(a!.x - b!.x, a!.y - b!.y); dist0 = cam.dist; }
  });
  wrap.addEventListener("pointermove", (e) => {
    const prev = pointers.get(e.pointerId);
    if (!prev) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    lastTouch = performance.now();
    moved += Math.abs(e.clientX - prev.x) + Math.abs(e.clientY - prev.y);
    if (pointers.size === 1) {
      cam.az += (e.clientX - prev.x) * 0.01;
      cam.el = Math.max(-1.3, Math.min(1.3, cam.el + (e.clientY - prev.y) * 0.01));
    } else if (pointers.size === 2 && pinch0 > 0) {
      const [a, b] = [...pointers.values()];
      cam.dist = Math.max(extent * 1.2, Math.min(extent * 10, dist0 * (pinch0 / Math.max(1, Math.hypot(a!.x - b!.x, a!.y - b!.y)))));
    }
  });
  const up = (e: PointerEvent) => {
    const was = pointers.size;
    pointers.delete(e.pointerId);
    if (was !== 1 || moved >= 8) return;
    const now = performance.now();
    if (now - lastTap < 300) {
      Object.assign(cam, cam0);
      selected = -1;
      info.classList.add("off");
    } else {
      const r = wrap.getBoundingClientRect();
      selected = pick(e.clientX - r.left, e.clientY - r.top);
      const p = parts[selected];
      if (p && (p.label || p.detail)) {
        info.textContent = "";
        const b = document.createElement("b");
        b.textContent = p.label ?? "";
        info.append(b, document.createTextNode(p.detail ?? ""));
        info.classList.remove("off");
      } else {
        selected = -1;
        info.classList.add("off");
      }
    }
    lastTap = now;
  };
  wrap.addEventListener("pointerup", up);
  wrap.addEventListener("pointercancel", up);

  // ---- render ----
  const light = norm([-0.4, 0.8, 0.6]);
  const start = performance.now();
  let lastFrame = 0;
  // WebKit can withhold animation frames from a sandboxed frame (created while hidden,
  // off-screen); a watchdog keeps the model drawing at a lower rate until they return.
  setInterval(() => { if (performance.now() - lastFrame > 250) frame(performance.now(), true); }, 120);
  const frame = (now: number, fromWatchdog = false) => {
    lastFrame = now;
    const t = (now - start) / 1000;
    const dpr = devicePixelRatio || 1;
    const W = wrap.clientWidth, H = wrap.clientHeight;
    if (W < 10 || H < 10) { if (!fromWatchdog) requestAnimationFrame((n) => frame(n)); return; }
    if (canvas.width !== Math.round(W * dpr)) { canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr); }
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, W, H);
    if (autoRotate && now - lastTouch > 2500 && selected < 0) cam.az += 0.0035;
    exploded += (explodeTarget - exploded) * 0.12;

    const camPos: V = add(rotY(rotX([0, 0, cam.dist], -cam.el), cam.az), [cx, cy, cz]);
    const toCam = (p: V): V => {
      let q: V = [p[0] - cx, p[1] - cy, p[2] - cz];
      q = rotY(q, -cam.az);
      q = rotX(q, cam.el);
      return [q[0], q[1], q[2] - cam.dist];
    };
    const f = Math.min(W, H) * 1.25;
    const project = (q: V) => ({ x: W / 2 + (q[0] / -q[2]) * f, y: H / 2 - (q[1] / -q[2]) * f });

    // A soft contact shadow under the model.
    const floor = project(toCam([cx, cy - extent * 0.85, cz]));
    const sr = (f * extent) / cam.dist;
    const grd = g.createRadialGradient(floor.x, floor.y, 0, floor.x, floor.y, sr * 1.1);
    grd.addColorStop(0, "rgba(0,0,0,0.13)"); grd.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = grd;
    g.beginPath(); g.ellipse(floor.x, floor.y, sr * 1.1, sr * 0.28, 0, 0, 7); g.fill();

    const faces: { pts: { x: number; y: number }[]; z: number; fill: string; edge: string | null; alpha: number; part: number }[] = [];
    const labels: { x: number; y: number; text: string; part: number }[] = [];
    parts.forEach((p, pi) => {
      const grp = p.group ? groups[p.group] : undefined;
      const own = spinRot(p.spin, t);
      const pos0 = add(p.pos, scale(p.explode, exploded));
      const toWorld = (v: V): V => {
        let w = add(rotate(rotate(v, own), p.rot), pos0);
        if (p.orbit) { const c = p.orbit.center; w = add(rotY(sub(w, c), (t * p.orbit.rpm * 2 * Math.PI) / 60), c); }
        if (grp) {
          if (grp.spin) w = add(rotate(sub(w, grp.pivot), spinRot(grp.spin, t)), grp.pivot);
          if (grp.orbit) { const c = grp.orbit.center; w = add(rotY(sub(w, c), (t * grp.orbit.rpm * 2 * Math.PI) / 60), c); }
        }
        return w;
      };
      const sel = pi === selected;
      for (const tri of p.tris) {
        const w = tri.map(toWorld) as Tri;
        const c = w.map(toCam) as Tri;
        if (c.some((q) => q[2] > -0.05)) continue;
        const n = norm(cross(sub(c[1], c[0]), sub(c[2], c[0])));
        if (dot(n, c[0]) > 0 && p.alpha === 1) continue; // back face
        const wn = norm(cross(sub(w[1], w[0]), sub(w[2], w[0])));
        const view = norm(sub(camPos, w[0]));
        const diffuse = Math.max(0, dot(wn, light));
        const shine = Math.pow(Math.max(0, dot(wn, norm(add(light, view)))), 24) * 0.45;
        const lit = 0.4 + 0.6 * diffuse;
        const col = p.color.map((ch: number) => Math.round(Math.min(255, ch * lit + (255 - ch * lit) * shine + (sel ? 18 : 0))));
        const pts = c.map(project);
        // Degenerate slivers (sphere poles, cone tips) would show as hairlines.
        if (Math.abs((pts[1]!.x - pts[0]!.x) * (pts[2]!.y - pts[0]!.y) - (pts[2]!.x - pts[0]!.x) * (pts[1]!.y - pts[0]!.y)) < 0.4) continue;
        faces.push({
          pts, z: (c[0][2] + c[1][2] + c[2][2]) / 3, alpha: p.alpha, part: pi,
          fill: `rgb(${col[0]},${col[1]},${col[2]})`, edge: sel ? "#e8590c" : p.edges ? "rgba(11,11,12,0.55)" : null,
        });
      }
      if (p.label) {
        const q = toCam(toWorld([0, 0, 0]));
        if (q[2] < -0.05) { const s = project(q); labels.push({ x: s.x, y: s.y, text: p.label, part: pi }); }
      }
    });
    faces.sort((a, b) => a.z - b.z);
    faceHits = faces.filter((fc) => fc.alpha === 1).map((fc) => ({ pts: fc.pts, part: fc.part }));
    for (const fc of faces) {
      g.globalAlpha = fc.alpha;
      g.beginPath();
      g.moveTo(fc.pts[0]!.x, fc.pts[0]!.y);
      g.lineTo(fc.pts[1]!.x, fc.pts[1]!.y);
      g.lineTo(fc.pts[2]!.x, fc.pts[2]!.y);
      g.closePath();
      g.fillStyle = fc.fill;
      g.fill();
      // Seal hairline gaps between triangles with their own colour; boxes get crisp dark edges.
      // (Not on see-through parts: there the seams would show as a mesh.)
      if (fc.alpha === 1 || fc.edge) {
        g.strokeStyle = fc.edge ?? fc.fill;
        g.lineWidth = fc.edge ? 0.9 : 0.6;
        g.stroke();
      }
    }
    g.globalAlpha = 1;
    // Labels: a dot on the part, a leader up and out, the name on a glass pill (black when picked).
    g.font = "600 12px Inter,-apple-system,sans-serif";
    labels.sort((a, b) => a.y - b.y).forEach((l, i) => {
      const lx = l.x + (l.x > W / 2 ? 26 : -26), ly = l.y - 22 - (i % 2) * 14;
      const on = l.part === selected;
      g.strokeStyle = "#0b0b0c"; g.lineWidth = 1;
      g.beginPath(); g.moveTo(l.x, l.y); g.lineTo(lx, ly); g.stroke();
      g.fillStyle = "#0b0b0c"; g.beginPath(); g.arc(l.x, l.y, 2.5, 0, 7); g.fill();
      const tw = g.measureText(l.text).width + 16;
      const bx = l.x > W / 2 ? lx : lx - tw;
      g.fillStyle = on ? "#0b0b0c" : "rgba(255,255,255,0.88)";
      g.beginPath(); g.roundRect(bx, ly - 11, tw, 22, 11); g.fill();
      g.strokeStyle = "rgba(0,0,0,0.12)"; g.stroke();
      g.fillStyle = on ? "#ffffff" : "#0b0b0c"; g.fillText(l.text, bx + 8, ly + 4);
    });
    if (!fromWatchdog) requestAnimationFrame((n) => frame(n));
  };
  requestAnimationFrame((n) => frame(n));
}
