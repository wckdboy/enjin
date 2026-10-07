/**
 * Simulations: a small 2D physics world from a declarative spec, running live.
 * Bodies (circles, boxes; fixed ones are anchors) move under gravity, springs,
 * rods, ropes, drag and any force written as a formula; they bounce off the
 * floor and walls and off each other. Sliders change parameters while it runs,
 * readouts and a plot show quantities over time, and any body can be grabbed
 * and thrown with a finger.
 *
 * Units are SI, y points up. Every number may instead be a formula (a string)
 * over the parameters and t; forces and readouts also see each body's state as
 * <id>_x, <id>_y, <id>_vx, <id>_vy (and x, y, vx, vy, m for the body itself).
 *
 * Self-contained: its source is injected into a sandboxed frame, with
 * compileExpr (the same safe formula compiler as the UI kit).
 */
export function mountSim(root: HTMLElement, spec: any, compile: (src: string) => (vars: Record<string, number>) => number): void {
  const PAL: Record<string, string> = {
    white: "#ffffff", light: "#ececea", grey: "#a6a6ab", dark: "#4a4a4f", black: "#0b0b0c", accent: "#e8590c",
    red: "#d64545", blue: "#2f6fbf", green: "#2f9e44", yellow: "#d9a82b",
  };
  const col = (c: unknown, d: string) => {
    const s = String(c ?? "");
    return PAL[s] ?? (/^#[0-9a-f]{6}$/i.test(s) ? s : d);
  };
  const INK = "#0b0b0c", MUTED = "#66666b", FAINT = "rgba(11,11,12,0.07)";
  const FONT = "Inter, -apple-system, sans-serif";

  // ---------- formulas ----------
  type Num = (v: Record<string, number>) => number;
  const bad = new Set<string>();
  const num = (x: unknown, d: number): Num => {
    if (typeof x === "number" && Number.isFinite(x)) return () => x;
    if (typeof x === "string" && x.trim()) {
      try {
        const f = compile(x);
        return (v) => { const r = f(v); return Number.isFinite(r) ? r : d; };
      } catch { bad.add(x); }
    }
    return () => d;
  };
  const mentions = (x: unknown, name: string) => typeof x === "string" && new RegExp(`\\b${name}\\b`).test(x);

  // ---------- the world ----------
  const params: { name: string; value: number; min: number; max: number; step: number; label: string; unit: string }[] =
    Object.entries(spec?.params ?? {}).slice(0, 4).map(([name, p]: [string, any]) => {
      const min = Number(p?.min ?? 0), max = Number(p?.max ?? 10);
      return { name, value: Math.min(max, Math.max(min, Number(p?.value ?? min))), min, max, step: Number(p?.step ?? (max - min) / 100), label: String(p?.label ?? name), unit: String(p?.unit ?? "") };
    });
  const view = Array.isArray(spec?.view) && spec.view.length === 4 ? spec.view.map(Number) : [-5, 0, 5, 6];
  const [vx0, vy0, vx1, vy1] = view as [number, number, number, number];
  const gravity = [num(spec?.gravity?.[0], 0), num(spec?.gravity?.[1], -9.81)];
  const floor = spec?.floor !== false;
  const walls = !!spec?.walls;
  const drag = num(spec?.drag, 0);
  const speed = Math.max(0.05, Math.min(4, Number(spec?.speed ?? 1)));

  type Body = {
    id: string; shape: "circle" | "box"; r: number; w: number; h: number; m: number; fixed: boolean; color: string;
    label: string; trail: boolean; bounce: number; init: { x: Num; y: Num; vx: Num; vy: Num; m: Num }; raw: any;
    x: number; y: number; vx: number; vy: number; fx: number; fy: number; path: [number, number][];
  };
  const bodies: Body[] = (Array.isArray(spec?.bodies) ? spec.bodies : []).slice(0, 24).map((b: any, i: number): Body => ({
    id: String(b?.id ?? `b${i}`).replace(/[^A-Za-z0-9_]/g, "_"),
    shape: b?.shape === "box" ? "box" : "circle",
    r: Math.max(0.02, Number(b?.r ?? 0.25)), w: Math.max(0.04, Number(b?.w ?? 0.5)), h: Math.max(0.04, Number(b?.h ?? 0.5)),
    m: 1, fixed: !!b?.fixed, color: col(b?.color, b?.fixed ? INK : "#ffffff"),
    label: b?.label ? String(b.label).slice(0, 24) : "", trail: !!b?.trail, bounce: Math.min(1, Math.max(0, Number(b?.bounce ?? 0.6))),
    init: { x: num(b?.x, 0), y: num(b?.y, 1), vx: num(b?.vx, 0), vy: num(b?.vy, 0), m: num(b?.mass, 1) }, raw: b,
    x: 0, y: 0, vx: 0, vy: 0, fx: 0, fy: 0, path: [],
  }));
  const byId = new Map(bodies.map((b) => [b.id, b]));
  type Link = { type: "spring" | "rod" | "rope"; a: Body; b: Body; k: Num; rest: number; damping: Num; raw: any };
  const links: Link[] = (Array.isArray(spec?.links) ? spec.links : []).slice(0, 24).flatMap((l: any): Link[] => {
    const a = byId.get(String(l?.a ?? "")), b = byId.get(String(l?.b ?? ""));
    if (!a || !b || a === b) return [];
    const type = l?.type === "rod" || l?.type === "rope" ? l.type : "spring";
    return [{ type, a, b, k: num(l?.k, 20), rest: -1, damping: num(l?.damping, 0.05), raw: l }];
  });
  const forces: { on: string; fx: Num; fy: Num }[] = (Array.isArray(spec?.forces) ? spec.forces : []).slice(0, 8).map((f: any) => ({
    on: String(f?.on ?? "all"), fx: num(f?.fx, 0), fy: num(f?.fy, 0),
  }));
  const readouts: { label: string; f: Num; unit: string; digits: number }[] = (Array.isArray(spec?.readouts) ? spec.readouts : []).slice(0, 4).map((r: any) => ({
    label: String(r?.label ?? "").slice(0, 20), f: num(r?.expr, 0), unit: String(r?.unit ?? ""), digits: Math.min(4, Math.max(0, Number(r?.digits ?? 2))),
  }));
  const plots: { label: string; unit: string; f: Num; color: string; data: [number, number][] }[] = (Array.isArray(spec?.plot) ? spec.plot : spec?.plot ? [spec.plot] : []).slice(0, 2).map((p: any, i: number) => ({
    label: String(p?.label ?? p?.expr ?? "").slice(0, 20), unit: String(p?.unit ?? ""), f: num(p?.expr, 0), color: i ? "#2f6fbf" : "#e8590c",
    data: [] as [number, number][],
  }));
  let t = 0;

  const vars = (): Record<string, number> => {
    const v: Record<string, number> = { t };
    for (const p of params) v[p.name] = p.value;
    for (const b of bodies) { v[`${b.id}_x`] = b.x; v[`${b.id}_y`] = b.y; v[`${b.id}_vx`] = b.vx; v[`${b.id}_vy`] = b.vy; }
    return v;
  };

  function reset(): void {
    t = 0;
    const v0: Record<string, number> = { t: 0 };
    for (const p of params) v0[p.name] = p.value;
    for (const b of bodies) {
      b.m = Math.max(1e-6, b.init.m(v0));
      b.x = b.init.x(v0); b.y = b.init.y(v0); b.vx = b.fixed ? 0 : b.init.vx(v0); b.vy = b.fixed ? 0 : b.init.vy(v0);
      b.path = [];
    }
    for (const l of links) {
      const given = Number(l.raw?.rest);
      l.rest = Number.isFinite(given) && given > 0 ? given : Math.hypot(l.b.x - l.a.x, l.b.y - l.a.y) || 1;
    }
    for (const p of plots) p.data = [];
  }

  // ---------- physics: semi-implicit Euler, small fixed steps, then constraints and collisions ----------
  const DT = 1 / 240;
  let held: Body | null = null;
  function step(): void {
    const v = vars();
    const gx = gravity[0]!(v), gy = gravity[1]!(v), c = drag(v);
    for (const b of bodies) {
      b.fx = 0; b.fy = 0;
      if (b.fixed || b === held) continue;
      b.fx = b.m * gx - c * b.vx;
      b.fy = b.m * gy - c * b.vy;
    }
    for (const f of forces) {
      for (const b of bodies) {
        if (b.fixed || b === held || (f.on !== "all" && f.on !== b.id)) continue;
        const own = { ...v, x: b.x, y: b.y, vx: b.vx, vy: b.vy, m: b.m };
        b.fx += f.fx(own); b.fy += f.fy(own);
      }
    }
    for (const l of links) {
      if (l.type !== "spring") continue;
      const dx = l.b.x - l.a.x, dy = l.b.y - l.a.y, d = Math.hypot(dx, dy) || 1e-9;
      const ux = dx / d, uy = dy / d;
      const rel = (l.b.vx - l.a.vx) * ux + (l.b.vy - l.a.vy) * uy;
      const f = l.k(v) * (d - l.rest) + l.damping(v) * rel;
      l.a.fx += f * ux; l.a.fy += f * uy; l.b.fx -= f * ux; l.b.fy -= f * uy;
    }
    for (const b of bodies) {
      if (b.fixed || b === held) continue;
      b.vx += (b.fx / b.m) * DT; b.vy += (b.fy / b.m) * DT;
      b.x += b.vx * DT; b.y += b.vy * DT;
    }
    // Rods keep their length; ropes only stop stretching.
    for (let it = 0; it < 4; it++) {
      for (const l of links) {
        if (l.type === "spring") continue;
        const dx = l.b.x - l.a.x, dy = l.b.y - l.a.y, d = Math.hypot(dx, dy) || 1e-9;
        if (l.type === "rope" && d <= l.rest) continue;
        const wa = l.a.fixed || l.a === held ? 0 : 1 / l.a.m, wb = l.b.fixed || l.b === held ? 0 : 1 / l.b.m;
        if (wa + wb === 0) continue;
        const ux = dx / d, uy = dy / d, err = d - l.rest;
        l.a.x += (ux * err * wa) / (wa + wb); l.a.y += (uy * err * wa) / (wa + wb);
        l.b.x -= (ux * err * wb) / (wa + wb); l.b.y -= (uy * err * wb) / (wa + wb);
        const rel = (l.b.vx - l.a.vx) * ux + (l.b.vy - l.a.vy) * uy;
        if (l.type === "rope" && rel < 0) continue;
        l.a.vx += (ux * rel * wa) / (wa + wb); l.a.vy += (uy * rel * wa) / (wa + wb);
        l.b.vx -= (ux * rel * wb) / (wa + wb); l.b.vy -= (uy * rel * wb) / (wa + wb);
      }
    }
    const half = (b: Body) => (b.shape === "box" ? [b.w / 2, b.h / 2] : [b.r, b.r]) as [number, number];
    for (const b of bodies) {
      if (b.fixed || b === held) continue;
      const [hx, hy] = half(b);
      if (floor && b.y - hy < vy0) { b.y = vy0 + hy; if (b.vy < 0) b.vy = -b.vy * b.bounce; b.vx *= 0.995; }
      if (walls) {
        if (b.x - hx < vx0) { b.x = vx0 + hx; if (b.vx < 0) b.vx = -b.vx * b.bounce; }
        if (b.x + hx > vx1) { b.x = vx1 - hx; if (b.vx > 0) b.vx = -b.vx * b.bounce; }
        if (b.y + hy > vy1) { b.y = vy1 - hy; if (b.vy > 0) b.vy = -b.vy * b.bounce; }
      }
    }
    // Bodies bump into each other (as circles; boxes by their inner circle).
    for (let i = 0; i < bodies.length; i++) for (let j = i + 1; j < bodies.length; j++) {
      const a = bodies[i]!, b = bodies[j]!;
      if (a.fixed && b.fixed) continue;
      if (links.some((l) => (l.a === a && l.b === b) || (l.a === b && l.b === a))) continue;
      const ra = a.shape === "box" ? Math.min(a.w, a.h) / 2 : a.r, rb = b.shape === "box" ? Math.min(b.w, b.h) / 2 : b.r;
      const dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy);
      if (d === 0 || d >= ra + rb) continue;
      const ux = dx / d, uy = dy / d;
      const wa = a.fixed || a === held ? 0 : 1 / a.m, wb = b.fixed || b === held ? 0 : 1 / b.m;
      if (wa + wb === 0) continue;
      const pen = ra + rb - d;
      a.x -= (ux * pen * wa) / (wa + wb); a.y -= (uy * pen * wa) / (wa + wb);
      b.x += (ux * pen * wb) / (wa + wb); b.y += (uy * pen * wb) / (wa + wb);
      const rel = (b.vx - a.vx) * ux + (b.vy - a.vy) * uy;
      if (rel >= 0) continue;
      const e = Math.min(a.bounce, b.bounce);
      const jn = (-(1 + e) * rel) / (wa + wb);
      a.vx -= jn * ux * wa; a.vy -= jn * uy * wa; b.vx += jn * ux * wb; b.vy += jn * uy * wb;
    }
    t += DT;
  }

  // ---------- the page ----------
  root.style.cssText += ";background:#fff;font-family:" + FONT + ";color:" + INK + ";user-select:none;-webkit-user-select:none;touch-action:none;overflow:hidden";
  const canvas = document.createElement("canvas");
  canvas.style.cssText = "position:absolute;left:0;top:0;width:100%;display:block";
  root.appendChild(canvas);
  const g = canvas.getContext("2d")!;
  const bar = document.createElement("div");
  bar.style.cssText = "position:absolute;left:0;right:0;bottom:0;display:flex;align-items:center;gap:14px;padding:8px 12px;border-top:1px solid rgba(11,11,12,0.08);background:rgba(255,255,255,0.94);font-size:12px";
  root.appendChild(bar);
  let running = true;
  const button = (text: string, onClick: () => void) => {
    const b = document.createElement("button");
    b.textContent = text;
    b.style.cssText = `font:600 12px ${FONT};border:0;border-radius:999px;padding:6px 12px;background:${INK};color:#fff`;
    b.addEventListener("click", onClick);
    bar.appendChild(b);
    return b;
  };
  const playBtn = button("Pause", () => { running = !running; playBtn.textContent = running ? "Pause" : "Play"; });
  const resetBtn = button("Reset", () => reset());
  resetBtn.style.background = "#ececea";
  resetBtn.style.color = INK;
  const dependsOnStart = (name: string) => bodies.some((b) => ["x", "y", "vx", "vy", "mass"].some((k) => mentions(b.raw?.[k], name)));
  for (const p of params) {
    const wrap = document.createElement("label");
    wrap.style.cssText = "display:flex;flex-direction:column;gap:2px;min-width:0;flex:1";
    const head = document.createElement("span");
    head.style.cssText = `font:600 10px ui-monospace,Menlo,monospace;letter-spacing:.06em;color:${MUTED};white-space:nowrap;overflow:hidden;text-overflow:ellipsis`;
    const input = document.createElement("input");
    input.type = "range";
    input.min = String(p.min); input.max = String(p.max); input.step = String(p.step); input.value = String(p.value);
    input.style.cssText = `width:100%;accent-color:${INK}`;
    const show = () => { head.textContent = `${p.label.toUpperCase()} ${+p.value.toFixed(3)} ${p.unit}`; };
    show();
    input.addEventListener("input", () => { p.value = Number(input.value); show(); });
    input.addEventListener("change", () => { if (dependsOnStart(p.name)) reset(); });
    wrap.append(head, input);
    bar.appendChild(wrap);
  }
  const chips = document.createElement("div");
  chips.style.cssText = "position:absolute;right:10px;top:10px;display:flex;flex-direction:column;gap:6px;align-items:flex-end;pointer-events:none";
  root.appendChild(chips);
  const chipEls = readouts.map((r) => {
    const el = document.createElement("div");
    el.style.cssText = `font:600 12px ${FONT};padding:5px 10px;border-radius:999px;background:rgba(255,255,255,0.92);box-shadow:0 0 0 0.75px rgba(11,11,12,0.12)`;
    chips.appendChild(el);
    return { r, el };
  });
  if (spec?.caption) {
    const cap = document.createElement("div");
    cap.textContent = String(spec.caption).slice(0, 120);
    cap.style.cssText = `position:absolute;left:12px;top:10px;max-width:60%;font:500 12px/1.35 ${FONT};color:${MUTED};pointer-events:none`;
    root.appendChild(cap);
  }

  // ---------- drawing ----------
  let W = 0, H = 0, S = 1, ox = 0, oy = 0;
  const toPx = (x: number, y: number): [number, number] => [ox + (x - vx0) * S, oy - (y - vy0) * S];
  const toWorld = (px: number, py: number): [number, number] => [vx0 + (px - ox) / S, vy0 + (oy - py) / S];
  function layout(): void {
    const r = root.getBoundingClientRect();
    W = Math.max(1, r.width);
    H = Math.max(1, r.height - bar.offsetHeight);
    const dpr = Math.min(2, devicePixelRatio || 1);
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    canvas.style.height = H + "px";
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    // A clear band at the top for the caption and readouts, so the world never runs under them.
    const pad = 18, top = spec?.caption || readouts.length ? 46 : pad;
    S = Math.min((W - 2 * pad) / (vx1 - vx0), (H - pad - top) / (vy1 - vy0));
    ox = (W - (vx1 - vx0) * S) / 2;
    oy = H - pad - (H - pad - top - (vy1 - vy0) * S) / 2;
  }
  function draw(): void {
    g.clearRect(0, 0, W, H);
    // A faint metre grid, so sizes and speeds read as real.
    g.strokeStyle = FAINT; g.lineWidth = 1;
    const stepM = Math.pow(10, Math.floor(Math.log10((vx1 - vx0) / 2)));
    for (let x = Math.ceil(vx0 / stepM) * stepM; x <= vx1; x += stepM) { const [px] = toPx(x, 0); g.beginPath(); g.moveTo(px, 0); g.lineTo(px, H); g.stroke(); }
    for (let y = Math.ceil(vy0 / stepM) * stepM; y <= vy1; y += stepM) { const [, py] = toPx(0, y); g.beginPath(); g.moveTo(0, py); g.lineTo(W, py); g.stroke(); }
    if (floor) { const [, py] = toPx(0, vy0); g.strokeStyle = INK; g.lineWidth = 2; g.beginPath(); g.moveTo(0, py); g.lineTo(W, py); g.stroke(); }
    if (walls) { const [a, b] = toPx(vx0, vy1), [c, d] = toPx(vx1, vy0); g.strokeStyle = INK; g.lineWidth = 2; g.strokeRect(a, b, c - a, d - b); }
    // Trails.
    for (const b of bodies) {
      if (!b.trail || b.path.length < 2) continue;
      g.strokeStyle = "rgba(232,89,12,0.45)"; g.lineWidth = 2; g.beginPath();
      b.path.forEach(([x, y], i) => { const [px, py] = toPx(x, y); if (i) g.lineTo(px, py); else g.moveTo(px, py); });
      g.stroke();
    }
    // Links: springs zig-zag, rods are solid, ropes thin.
    for (const l of links) {
      const [ax, ay] = toPx(l.a.x, l.a.y), [bx, by] = toPx(l.b.x, l.b.y);
      g.strokeStyle = l.type === "spring" ? MUTED : INK;
      g.lineWidth = l.type === "rod" ? 3 : l.type === "rope" ? 1.2 : 1.6;
      g.beginPath();
      if (l.type === "spring") {
        const n = 14, dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1, nx = -dy / len, ny = dx / len;
        g.moveTo(ax, ay);
        for (let i = 1; i < n; i++) { const s = i / n, w = (i % 2 ? 1 : -1) * 6; g.lineTo(ax + dx * s + nx * w, ay + dy * s + ny * w); }
        g.lineTo(bx, by);
      } else { g.moveTo(ax, ay); g.lineTo(bx, by); }
      g.stroke();
    }
    // Bodies.
    for (const b of bodies) {
      const [px, py] = toPx(b.x, b.y);
      g.fillStyle = b.color; g.strokeStyle = INK; g.lineWidth = 2;
      if (b.fixed && b.shape === "circle" && b.r <= 0.12) {
        g.beginPath(); g.arc(px, py, 5, 0, Math.PI * 2); g.fillStyle = INK; g.fill();
      } else if (b.shape === "box") {
        g.beginPath(); g.rect(px - (b.w * S) / 2, py - (b.h * S) / 2, b.w * S, b.h * S); g.fill(); g.stroke();
      } else {
        g.beginPath(); g.arc(px, py, Math.max(3, b.r * S), 0, Math.PI * 2); g.fill(); g.stroke();
      }
      if (b.label) {
        g.font = `600 12px ${FONT}`; g.fillStyle = INK; g.textAlign = "center";
        const above = (b.shape === "box" ? (b.h * S) / 2 : b.r * S) + 8;
        g.fillText(b.label, px, py - above);
      }
    }
    // The plot: the last 10 seconds.
    if (plots.length) {
      const pw = Math.min(220, W * 0.36), ph = 96, x0 = W - pw - 10, y0 = H - ph - 10;
      g.fillStyle = "rgba(255,255,255,0.92)"; g.strokeStyle = "rgba(11,11,12,0.12)"; g.lineWidth = 1;
      g.beginPath(); g.roundRect(x0, y0, pw, ph, 10); g.fill(); g.stroke();
      const all = plots.flatMap((p) => p.data.map((d) => d[1]));
      const lo = Math.min(0, ...all), hi = Math.max(1e-9, ...all);
      const tEnd = Math.max(10, t), tStart = tEnd - 10;
      plots.forEach((p, k) => {
        g.strokeStyle = p.color; g.lineWidth = 1.8; g.beginPath();
        p.data.forEach(([tt, y], i) => {
          const X = x0 + 8 + ((tt - tStart) / 10) * (pw - 16), Y = y0 + ph - 18 - ((y - lo) / (hi - lo || 1)) * (ph - 30);
          if (i) g.lineTo(X, Y); else g.moveTo(X, Y);
        });
        g.stroke();
        g.font = `600 10px ${FONT}`; g.fillStyle = p.color; g.textAlign = "left";
        g.fillText(`${p.label}${p.unit ? ` (${p.unit})` : ""}`, x0 + 8 + k * (pw / 2), y0 + ph - 5);
      });
    }
    if (bad.size) { g.font = `500 11px ${FONT}`; g.fillStyle = "#d64545"; g.textAlign = "left"; g.fillText(`Couldn't read: ${[...bad][0]}`, 10, H - 10); }
  }
  function readOut(): void {
    const v = vars();
    for (const { r, el } of chipEls) el.textContent = `${r.label} ${r.f(v).toFixed(r.digits)}${r.unit ? " " + r.unit : ""}`;
  }

  // ---------- grab and throw ----------
  let grab: { b: Body; last: [number, number]; at: number; v: [number, number] } | null = null;
  canvas.addEventListener("pointerdown", (e) => {
    const r = canvas.getBoundingClientRect();
    const [wx, wy] = toWorld(e.clientX - r.left, e.clientY - r.top);
    let best: Body | null = null, bestD = 0.6;
    for (const b of bodies) {
      if (b.fixed) continue;
      const d = Math.hypot(b.x - wx, b.y - wy) - (b.shape === "box" ? Math.max(b.w, b.h) / 2 : b.r);
      if (d < bestD) { best = b; bestD = d; }
    }
    if (!best) return;
    held = best;
    grab = { b: best, last: [wx, wy], at: performance.now(), v: [0, 0] };
    canvas.setPointerCapture(e.pointerId);
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!grab) return;
    const r = canvas.getBoundingClientRect();
    const [wx, wy] = toWorld(e.clientX - r.left, e.clientY - r.top);
    const now = performance.now(), dt = Math.max(0.008, (now - grab.at) / 1000);
    grab.v = [(wx - grab.last[0]) / dt, (wy - grab.last[1]) / dt];
    grab.b.x = wx; grab.b.y = wy; grab.last = [wx, wy]; grab.at = now;
    grab.b.path = [];
  });
  const release = () => {
    if (!grab) return;
    grab.b.vx = Math.max(-40, Math.min(40, grab.v[0])); grab.b.vy = Math.max(-40, Math.min(40, grab.v[1]));
    grab = null; held = null;
  };
  canvas.addEventListener("pointerup", release);
  canvas.addEventListener("pointercancel", release);

  // ---------- the loop (with a watchdog: sandboxed frames may get no animation frames) ----------
  reset();
  let lastFrame = performance.now(), lastSample = 0;
  function frame(now: number): void {
    const elapsed = Math.min(0.05, (now - lastFrame) / 1000);
    lastFrame = now;
    if (running) {
      const n = Math.min(40, Math.round((elapsed * speed) / DT));
      for (let i = 0; i < n; i++) step();
      for (const b of bodies) if (b.trail) { b.path.push([b.x, b.y]); if (b.path.length > 240) b.path.shift(); }
      if (t - lastSample > 0.05 || t < lastSample) {
        lastSample = t;
        const v = vars();
        for (const p of plots) { p.data.push([t, p.f(v)]); while (p.data.length && p.data[0]![0] < t - 10) p.data.shift(); }
      }
    }
    draw();
    readOut();
  }
  layout();
  new ResizeObserver(() => { layout(); draw(); }).observe(root);
  const loop = (now: number) => { frame(now); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
  setInterval(() => { const now = performance.now(); if (now - lastFrame > 120) frame(now); }, 50);
}
