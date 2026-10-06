// Pure geometry for figures (no Excalidraw imports, so it is unit-testable in node).

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * Concept-map layout: a deterministic force layout (Fruchterman-Reingold from a
 * fixed ring start), then scaled to fill `box` with each node fully inside.
 * Same input, same picture, every time.
 */
export function layoutGraph(sizes: { w: number; h: number }[], edges: [number, number][], box: Box): { cx: number; cy: number }[] {
  const n = sizes.length;
  if (n === 0) return [];
  if (n === 1) return [{ cx: box.x + box.width / 2, cy: box.y + box.height / 2 }];
  const W = box.width;
  const H = box.height;
  const k = Math.sqrt((W * H) / n) * 0.75;
  const p = sizes.map((_, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / n;
    return { x: W / 2 + (W / 3) * Math.cos(a), y: H / 2 + (H / 3) * Math.sin(a) };
  });
  let temp = W / 8;
  for (let it = 0; it < 300; it++) {
    const d = p.map(() => ({ x: 0, y: 0 }));
    for (let i = 0; i < n; i++)
      for (let j = i + 1; j < n; j++) {
        let dx = p[i]!.x - p[j]!.x;
        let dy = (p[i]!.y - p[j]!.y) * 1.6; // pills are wide: push apart vertically harder
        const dist = Math.max(1, Math.hypot(dx, dy));
        const f = (k * k) / dist;
        dx = (dx / dist) * f;
        dy = (dy / dist) * f;
        d[i]!.x += dx; d[i]!.y += dy;
        d[j]!.x -= dx; d[j]!.y -= dy;
      }
    for (const [a, b] of edges) {
      const dx = p[a]!.x - p[b]!.x;
      const dy = p[a]!.y - p[b]!.y;
      const dist = Math.max(1, Math.hypot(dx, dy));
      const f = (dist * dist) / k;
      d[a]!.x -= (dx / dist) * f; d[a]!.y -= (dy / dist) * f;
      d[b]!.x += (dx / dist) * f; d[b]!.y += (dy / dist) * f;
    }
    for (let i = 0; i < n; i++) {
      const len = Math.max(1e-9, Math.hypot(d[i]!.x, d[i]!.y));
      p[i]!.x += (d[i]!.x / len) * Math.min(len, temp);
      p[i]!.y += (d[i]!.y / len) * Math.min(len, temp);
    }
    temp *= 0.985;
  }
  // Fit: scale the layout so every node (with its size) sits inside the box.
  const minX = Math.min(...p.map((q) => q.x));
  const maxX = Math.max(...p.map((q) => q.x));
  const minY = Math.min(...p.map((q) => q.y));
  const maxY = Math.max(...p.map((q) => q.y));
  const maxW = Math.max(...sizes.map((s) => s.w));
  const maxH = Math.max(...sizes.map((s) => s.h));
  const sx = maxX - minX > 1e-6 ? (W - maxW) / (maxX - minX) : 0;
  const sy = maxY - minY > 1e-6 ? (H - maxH) / (maxY - minY) : 0;
  return p.map((q) => ({
    cx: box.x + maxW / 2 + (sx ? (q.x - minX) * sx : (W - maxW) / 2),
    cy: box.y + maxH / 2 + (sy ? (q.y - minY) * sy : (H - maxH) / 2),
  }));
}

/** Where the segment from a's centre toward b leaves a's rect (half sizes hw, hh). */
export function exitPoint(a: { cx: number; cy: number }, hw: number, hh: number, b: { cx: number; cy: number }, pad = 4): { x: number; y: number } {
  const dx = b.cx - a.cx;
  const dy = b.cy - a.cy;
  if (dx === 0 && dy === 0) return { x: a.cx, y: a.cy };
  const t = Math.min(dx ? (hw + pad) / Math.abs(dx) : Infinity, dy ? (hh + pad) / Math.abs(dy) : Infinity);
  return { x: a.cx + dx * Math.min(1, t), y: a.cy + dy * Math.min(1, t) };
}

/** Round axis ticks (1, 2, 5 × 10^n) covering [lo, hi], about `count` of them. */
export function niceTicks(lo: number, hi: number, count = 5): number[] {
  if (!(hi > lo)) return [lo];
  const raw = (hi - lo) / Math.max(1, count - 1);
  const mag = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? 10 * mag;
  const start = Math.floor(lo / step) * step;
  const out: number[] = [];
  // Until a tick reaches hi: the axis must cover every point.
  for (let v = start; out.length < 100; v += step) {
    out.push(Number(v.toPrecision(12)));
    if (v >= hi - step * 1e-9) break;
  }
  return out;
}

/** Decade ticks (1, 10, 100, …) covering [lo, hi] for a log axis. */
export function logTicks(lo: number, hi: number): number[] {
  const out: number[] = [];
  for (let e = Math.floor(Math.log10(lo)); e <= Math.ceil(Math.log10(hi)); e++) out.push(10 ** e);
  return out;
}

/** Short tick label: 1200 -> 1.2k, 3000000 -> 3M, 0.005 -> 0.005. */
export function tickLabel(v: number): string {
  const a = Math.abs(v);
  const trim = (x: number) => String(Number(x.toPrecision(3)));
  if (a >= 1e9) return `${trim(v / 1e9)}B`;
  if (a >= 1e6) return `${trim(v / 1e6)}M`;
  if (a >= 1e4) return `${trim(v / 1e3)}k`;
  return trim(v);
}
