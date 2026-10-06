/**
 * ENJIN 3D: a small, dependency-free 3D model viewer for live cards. The agent
 * describes a model as parts (box, sphere, cylinder, cone, torus) with sizes,
 * positions, rotations, colours, labels and simple motion (spin, orbit); this
 * draws it on a 2D canvas: perspective, depth-sorted flat shading in ENJIN's
 * whites, greys and black, crisp edges, labels. Drag to turn, pinch to zoom,
 * double-tap to reset.
 *
 * Self-contained: its source is injected into a sandboxed frame.
 */
export function mount3D(root: HTMLElement, spec: any): void {
  type V = [number, number, number];
  const PALETTE: Record<string, string> = {
    white: "#f6f6f5", light: "#dededc", grey: "#a6a6ab", dark: "#4a4a4f", black: "#141416", accent: "#e8590c", glass: "#ffffff",
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
  const sub = (a: V, b: V): V => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a: V, b: V): V => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const dot = (a: V, b: V) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const norm = (a: V): V => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
  const num = (x: unknown, d: number) => (Number.isFinite(Number(x)) ? Number(x) : d);
  const vec = (x: unknown, d: V): V => (Array.isArray(x) && x.length === 3 ? [num(x[0], d[0]), num(x[1], d[1]), num(x[2], d[2])] : d);

  // Meshes in local space: triangles as [a, b, c] vertex triples.
  type Tri = [V, V, V];
  const quad = (a: V, b: V, c: V, d: V): Tri[] => [[a, b, c], [a, c, d]];
  const box = (w: number, h: number, d: number): Tri[] => {
    const x = w / 2, y = h / 2, z = d / 2;
    const p: V[] = [[-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z], [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z]];
    return [
      ...quad(p[4]!, p[5]!, p[6]!, p[7]!), ...quad(p[1]!, p[0]!, p[3]!, p[2]!), ...quad(p[0]!, p[4]!, p[7]!, p[3]!),
      ...quad(p[5]!, p[1]!, p[2]!, p[6]!), ...quad(p[3]!, p[7]!, p[6]!, p[2]!), ...quad(p[0]!, p[1]!, p[5]!, p[4]!),
    ];
  };
  const lathe = (profile: [number, number][], seg: number, closeTop: boolean, closeBottom: boolean): Tri[] => {
    // Revolve (radius, y) points around the y axis.
    const out: Tri[] = [];
    const ring = (r: number, y: number, i: number): V => [r * Math.cos((i / seg) * 2 * Math.PI), y, r * Math.sin((i / seg) * 2 * Math.PI)];
    for (let k = 0; k < profile.length - 1; k++) {
      const [r0, y0] = profile[k]!, [r1, y1] = profile[k + 1]!;
      for (let i = 0; i < seg; i++) out.push(...quad(ring(r0, y0, i), ring(r0, y0, i + 1), ring(r1, y1, i + 1), ring(r1, y1, i)));
    }
    const [rb, yb] = profile[0]!, [rt, yt] = profile[profile.length - 1]!;
    for (let i = 0; i < seg; i++) {
      if (closeBottom && rb > 0) out.push([[0, yb, 0], ring(rb, yb, i + 1), ring(rb, yb, i)]);
      if (closeTop && rt > 0) out.push([[0, yt, 0], ring(rt, yt, i), ring(rt, yt, i + 1)]);
    }
    return out;
  };
  const sphere = (r: number) => {
    const prof: [number, number][] = [];
    for (let i = 0; i <= 10; i++) { const a = -Math.PI / 2 + (i / 10) * Math.PI; prof.push([r * Math.cos(a), r * Math.sin(a)]); }
    return lathe(prof, 18, false, false);
  };
  const torus = (R: number, r: number) => {
    const out: Tri[] = [];
    const P = (i: number, j: number): V => {
      const u = (i / 24) * 2 * Math.PI, v = (j / 10) * 2 * Math.PI;
      return [(R + r * Math.cos(v)) * Math.cos(u), r * Math.sin(v), (R + r * Math.cos(v)) * Math.sin(u)];
    };
    for (let i = 0; i < 24; i++) for (let j = 0; j < 10; j++) out.push(...quad(P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)));
    return out;
  };
  const meshOf = (p: any): { tris: Tri[]; edges: boolean } => {
    const s = vec(p.size, [1, 1, 1]);
    const r = num(p.radius, s[0] / 2), h = num(p.height, s[1]);
    switch (p.shape) {
      case "sphere": return { tris: sphere(r), edges: false };
      case "cylinder": return { tris: lathe([[r, -h / 2], [r, h / 2]], 24, true, true), edges: false };
      case "cone": return { tris: lathe([[r, -h / 2], [0.001, h / 2]], 24, false, true), edges: false };
      case "torus": return { tris: torus(num(p.radius, 1), num(p.tube, 0.25)), edges: false };
      case "ring": return { tris: lathe([[r, -h / 2], [r, h / 2], [num(p.inner, r * 0.7), h / 2], [num(p.inner, r * 0.7), -h / 2], [r, -h / 2]], 32, false, false), edges: false };
      default: return { tris: box(s[0], s[1], s[2]), edges: true };
    }
  };

  const parts = (Array.isArray(spec?.parts) ? spec.parts : []).slice(0, 60).map((p: any) => ({
    ...meshOf(p),
    pos: vec(p.position, [0, 0, 0]),
    rot: vec(p.rotation, [0, 0, 0]).map(rad) as V,
    color: colorOf(p.color),
    alpha: p.color === "glass" ? 0.28 : 1,
    label: p.label ? String(p.label).slice(0, 32) : null,
    spin: p.spin ? { axis: String(p.spin.axis ?? "y"), rpm: num(p.spin.rpm, 10) } : null,
    orbit: p.orbit ? { center: vec(p.orbit.center, [0, 0, 0]), rpm: num(p.orbit.rpm, 5) } : null,
  }));

  // Frame the model: centre and radius of everything.
  let cx = 0, cy = 0, cz = 0, extent = 1;
  if (parts.length) {
    const ps = parts.map((p: any) => p.pos as V);
    cx = ps.reduce((a: number, p: V) => a + p[0], 0) / ps.length;
    cy = ps.reduce((a: number, p: V) => a + p[1], 0) / ps.length;
    cz = ps.reduce((a: number, p: V) => a + p[2], 0) / ps.length;
    for (const p of parts) for (const t of p.tris) for (const v of t) extent = Math.max(extent, Math.hypot(v[0] + p.pos[0] - cx, v[1] + p.pos[1] - cy, v[2] + p.pos[2] - cz));
  }
  const cam0 = { az: rad(num(spec?.camera?.azimuth, 35)), el: rad(num(spec?.camera?.elevation, 22)), dist: num(spec?.camera?.distance, extent * 3.2) };
  const cam = { ...cam0 };
  const autoRotate = spec?.autoRotate !== false;

  const style = document.createElement("style");
  style.textContent = `.v3{position:absolute;inset:0;background:radial-gradient(ellipse at 50% 35%,#ffffff 0%,#f2f2f0 70%,#e9e9e6 100%);touch-action:none}
  .v3 canvas{width:100%;height:100%;display:block}
  .v3 .hud{position:absolute;left:14px;bottom:10px;font:600 11px ui-monospace,Menlo,monospace;letter-spacing:1.3px;text-transform:uppercase;color:#66666b;pointer-events:none}`;
  root.appendChild(style);
  const wrap = document.createElement("div");
  wrap.className = "v3";
  const canvas = document.createElement("canvas");
  const hud = document.createElement("div");
  hud.className = "hud";
  hud.textContent = spec?.caption ? String(spec.caption).slice(0, 60) : "Drag to turn · pinch to zoom";
  wrap.append(canvas, hud);
  root.appendChild(wrap);
  const g = canvas.getContext("2d")!;

  // Touch: one finger orbits, two pinch; double-tap resets.
  const pointers = new Map<number, { x: number; y: number }>();
  let lastTouch = 0, pinch0 = 0, dist0 = cam.dist, lastTap = 0;
  wrap.addEventListener("pointerdown", (e) => {
    wrap.setPointerCapture(e.pointerId);
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    lastTouch = performance.now();
    if (pointers.size === 2) { const [a, b] = [...pointers.values()]; pinch0 = Math.hypot(a!.x - b!.x, a!.y - b!.y); dist0 = cam.dist; }
    if (pointers.size === 1) { if (lastTouch - lastTap < 300) Object.assign(cam, cam0); lastTap = lastTouch; }
  });
  wrap.addEventListener("pointermove", (e) => {
    const prev = pointers.get(e.pointerId);
    if (!prev) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    lastTouch = performance.now();
    if (pointers.size === 1) {
      cam.az += (e.clientX - prev.x) * 0.01;
      cam.el = Math.max(-1.3, Math.min(1.3, cam.el + (e.clientY - prev.y) * 0.01));
    } else if (pointers.size === 2 && pinch0 > 0) {
      const [a, b] = [...pointers.values()];
      cam.dist = Math.max(extent * 1.2, Math.min(extent * 10, dist0 * (pinch0 / Math.max(1, Math.hypot(a!.x - b!.x, a!.y - b!.y)))));
    }
  });
  const up = (e: PointerEvent) => { pointers.delete(e.pointerId); };
  wrap.addEventListener("pointerup", up);
  wrap.addEventListener("pointercancel", up);

  const light = norm([-0.4, 0.8, 0.6]);
  const start = performance.now();
  // WebKit can withhold animation frames from a sandboxed frame (created while hidden,
  // off-screen); a watchdog keeps the model drawing at a lower rate until they return.
  let lastFrame = 0;
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
    if (autoRotate && now - lastTouch > 2500) cam.az += 0.0035;

    // World -> camera: orbit around the model's centre.
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
    const grd = g.createRadialGradient(floor.x, floor.y, 0, floor.x, floor.y, f * extent / cam.dist * 1.1);
    grd.addColorStop(0, "rgba(0,0,0,0.13)"); grd.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = grd;
    g.beginPath(); g.ellipse(floor.x, floor.y, f * extent / cam.dist * 1.1, f * extent / cam.dist * 0.28, 0, 0, 7); g.fill();

    const faces: { pts: { x: number; y: number }[]; z: number; fill: string; edge: string | null; alpha: number }[] = [];
    const labels: { x: number; y: number; z: number; text: string }[] = [];
    for (const p of parts) {
      let extra: V = [0, 0, 0];
      if (p.spin) {
        const a = (t * p.spin.rpm * 2 * Math.PI) / 60;
        extra = p.spin.axis === "x" ? [a, 0, 0] : p.spin.axis === "z" ? [0, 0, a] : [0, a, 0];
      }
      let pos = p.pos as V;
      if (p.orbit) pos = (() => { const c = p.orbit.center; const r = rotY(sub(pos, c), (t * p.orbit.rpm * 2 * Math.PI) / 60); return [r[0] + c[0], r[1] + c[1], r[2] + c[2]] as V; })();
      const world = (v: V): V => { const r = rotate(rotate(v, extra), p.rot); return [r[0] + pos[0], r[1] + pos[1], r[2] + pos[2]]; };
      for (const tri of p.tris) {
        const w = tri.map(world) as Tri;
        const c = w.map(toCam) as Tri;
        if (c.some((q) => q[2] > -0.05)) continue;
        const n = norm(cross(sub(c[1], c[0]), sub(c[2], c[0])));
        // Back-face cull (camera at origin looking down -z).
        if (dot(n, c[0]) > 0 && p.alpha === 1) continue;
        const wn = norm(cross(sub(w[1], w[0]), sub(w[2], w[0])));
        const lit = 0.42 + 0.58 * Math.max(0, dot(wn, light));
        const col = p.color.map((ch: number) => Math.round(Math.min(255, ch * lit + (255 - ch) * 0.04)));
        faces.push({
          pts: c.map(project), z: (c[0][2] + c[1][2] + c[2][2]) / 3, alpha: p.alpha,
          fill: `rgb(${col[0]},${col[1]},${col[2]})`, edge: p.edges ? "rgba(11,11,12,0.55)" : null,
        });
      }
      if (p.label) {
        const q = toCam(pos);
        if (q[2] < -0.05) { const s = project(q); labels.push({ x: s.x, y: s.y, z: q[2], text: p.label }); }
      }
    }
    faces.sort((a, b) => a.z - b.z);
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
    // Labels: a dot on the part, a leader up and out, the name on a glass pill.
    g.font = "600 12px Inter,-apple-system,sans-serif";
    labels.sort((a, b) => a.y - b.y).forEach((l, i) => {
      const lx = l.x + (l.x > W / 2 ? 26 : -26), ly = l.y - 22 - (i % 2) * 14;
      g.strokeStyle = "#0b0b0c"; g.lineWidth = 1;
      g.beginPath(); g.moveTo(l.x, l.y); g.lineTo(lx, ly); g.stroke();
      g.fillStyle = "#0b0b0c"; g.beginPath(); g.arc(l.x, l.y, 2.5, 0, 7); g.fill();
      const tw = g.measureText(l.text).width + 16;
      const bx = l.x > W / 2 ? lx : lx - tw;
      g.fillStyle = "rgba(255,255,255,0.88)";
      g.beginPath(); g.roundRect(bx, ly - 11, tw, 22, 11); g.fill();
      g.strokeStyle = "rgba(0,0,0,0.12)"; g.stroke();
      g.fillStyle = "#0b0b0c"; g.fillText(l.text, bx + 8, ly + 4);
    });
    if (!fromWatchdog) requestAnimationFrame((n) => frame(n));
  };
  requestAnimationFrame((n) => frame(n));
}
