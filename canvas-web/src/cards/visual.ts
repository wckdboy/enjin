import { FONT_FAMILY, type convertToExcalidrawElements } from "@excalidraw/excalidraw";
import type { Visual, VisualItem } from "../bridge/schema";
import { t } from "../i18n";
import { exitPoint, layoutGraph, logTicks, niceTicks, tickLabel } from "./figureMath";
import { CARD_W, GAP, type Rect } from "./layout";

// Figures: process flows, cycles, timelines, comparisons, labelled parts, big
// numbers, formulas and code, drawn as clean canvas geometry in the ENJIN look
// (ink lines, white pills, hairlines, monospace readouts). Each kind has a fixed
// height so a figure that streams in item by item never makes its card reflow.

type Skeleton = NonNullable<Parameters<typeof convertToExcalidrawElements>[0]>[number];

import { EDGE, EDGE_STRONG, EMBER, FACE, FACE_LOW, FG, MUTED, RAISED, SIGNAL, TRACK } from "./palette";

const INK = FG; // lines and type on a dark card
const HAIR = EDGE_STRONG;
const SOFT = TRACK;
const SANS = FONT_FAMILY.Helvetica; // Inter, see style.css
const MONO = FONT_FAMILY.Cascadia;

/** Two columns wide: room for steps side by side. */
export const WIDE_W = 2 * CARD_W + GAP;
const FIG_LABEL_H = 22;

const MAX_ITEMS: Record<Visual["kind"], number> = { flow: 5, cycle: 6, timeline: 6, bars: 6, parts: 6, stat: 0, formula: 4, code: 0, live: 0, graph: 8, table: 0, chart: 0, model3d: 0, diorama: 0, ui: 0 };
const ACCENT = SIGNAL;
const TABLE_COLS = 5;
const TABLE_ROWS = 6;
const TABLE_ROW_H = 32;
const SERIES_STYLE = [
  { color: FG, dash: "solid" },
  { color: EMBER, dash: "solid" },
  { color: MUTED, dash: "dashed" },
] as const;
/** Live models run in an iframe laid over this slot (see LiveLayer). */
export const LIVE_H = 380;
const CODE_LINES = 10;
const CODE_LINE_H = 20;

export function isWide(v: Visual): boolean {
  return v.kind !== "stat" && v.kind !== "formula";
}

function items(v: Visual): VisualItem[] {
  return (v.items ?? []).filter((i) => i.label?.trim()).slice(0, MAX_ITEMS[v.kind]);
}

function codeLines(v: Visual): string[] {
  return (v.text ?? "").replace(/\t/g, "  ").split("\n").slice(0, CODE_LINES).map((l) => l.slice(0, 64));
}

/** Height of the figure area (label included) for a card of width `w`. */
export function visualHeight(v: Visual): number {
  const body = {
    flow: 16 + 72 + 6 + 40,
    cycle: 280,
    timeline: 136,
    bars: 214,
    parts: 244,
    stat: 84,
    formula: 52 + 4 * 26,
    code: Math.max(1, codeLines(v).length) * CODE_LINE_H + 24,
    live: LIVE_H,
    model3d: 400,
    diorama: 400,
    ui: 420,
    graph: 290,
    table: 30 + TABLE_ROWS * TABLE_ROW_H,
    chart: 262,
  }[v.kind];
  return FIG_LABEL_H + body;
}

interface Base {
  groupIds: readonly string[];
  roughness: 0;
  strokeColor: string;
}

/** The figure's elements inside `box` (x, y, width; height from visualHeight). */
export function visualSkeletons(v: Visual, box: Rect, cardId: string, base: Base): Skeleton[] {
  const data = { cardId, role: "figure" };
  const out: Skeleton[] = [];
  const id = (s: string) => `${cardId}:fig:${s}`;
  const text = (key: string, x: number, y: number, s: string, size: number, family = SANS, color = INK): Skeleton => ({
    ...base, type: "text", id: id(key), x, y, text: s, fontSize: size, fontFamily: family, strokeColor: color, customData: data,
  });
  /** Text wrapped and aligned inside an invisible box. */
  const label = (key: string, r: Rect, s: string, size: number, opts: { align?: "left" | "center" | "right"; color?: string; family?: number; v?: "top" | "middle" } = {}): Skeleton => ({
    ...base, type: "rectangle", id: id(key), ...r, strokeColor: "transparent", backgroundColor: "transparent", customData: data,
    label: { text: s, fontSize: size, fontFamily: opts.family ?? SANS, strokeColor: opts.color ?? INK, textAlign: opts.align ?? "center", verticalAlign: opts.v ?? "middle", customData: { cardId, role: "label" } } as never,
  });
  /** A white pill with an ink edge and a label: a step, a part, a stage. */
  /** A raised node: a slightly lighter panel with a fine edge. */
  const pill = (key: string, r: Rect, s: string, size = 15, fill = RAISED): Skeleton => ({
    ...base, type: "rectangle", id: id(key), ...r, backgroundColor: fill, fillStyle: "solid", strokeColor: EDGE_STRONG, strokeWidth: 1.5,
    roundness: { type: 3 }, customData: data,
    label: { text: s, fontSize: size, fontFamily: SANS, strokeColor: INK, textAlign: "center", verticalAlign: "middle", customData: { cardId, role: "label" } } as never,
  });
  const arrow = (key: string, x1: number, y1: number, x2: number, y2: number, color = INK): Skeleton => ({
    // Explicit points: a zero width or height would otherwise fall back to a default size.
    ...base, type: "arrow", id: id(key), x: x1, y: y1, points: [[0, 0], [x2 - x1, y2 - y1]], strokeColor: color, strokeWidth: 1.5,
    startArrowhead: null, endArrowhead: "triangle", customData: data,
  } as Skeleton);
  const line = (key: string, x1: number, y1: number, x2: number, y2: number, color = HAIR, width = 1.5): Skeleton => ({
    ...base, type: "line", id: id(key), x: x1, y: y1, points: [[0, 0], [x2 - x1, y2 - y1]], strokeColor: color, strokeWidth: width, customData: data,
  } as Skeleton);
  const dot = (key: string, cx: number, cy: number, r: number, fill = INK): Skeleton => ({
    ...base, type: "ellipse", id: id(key), x: cx - r, y: cy - r, width: 2 * r, height: 2 * r, backgroundColor: fill, fillStyle: "solid", strokeWidth: 1.5, customData: data,
  });

  out.push(text("kind", box.x, box.y, `FIG · ${t.fig(v.kind).toUpperCase()}`, 11, MONO, MUTED));
  const x0 = box.x;
  const y0 = box.y + FIG_LABEL_H;
  const W = box.width;
  const list = items(v);
  const n = list.length;

  switch (v.kind) {
    case "flow": {
      if (!n) break;
      const gap = 36;
      const bw = (W - (n - 1) * gap) / n;
      list.forEach((it, i) => {
        const bx = x0 + i * (bw + gap);
        out.push(text(`n${i}`, bx, y0, String(i + 1).padStart(2, "0"), 11, MONO, MUTED));
        out.push(pill(`s${i}`, { x: bx, y: y0 + 16, width: bw, height: 72 }, it.label, n > 4 ? 14 : 15));
        if (it.detail) out.push(label(`d${i}`, { x: bx - 4, y: y0 + 94, width: bw + 8, height: 40 }, it.detail, 13, { color: MUTED, v: "top" }));
        if (i < n - 1) out.push(arrow(`a${i}`, bx + bw + 6, y0 + 52, bx + bw + gap - 6, y0 + 52));
      });
      break;
    }
    case "cycle": {
      if (!n) break;
      const cx = x0 + W / 2;
      const cy = y0 + 140;
      const rx = Math.min(W / 2 - 90, 220);
      const ry = 104;
      out.push({ ...base, type: "ellipse", id: id("ring"), x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry, strokeColor: HAIR, strokeWidth: 1.5, backgroundColor: "transparent", customData: data });
      if (v.center) out.push(label("center", { x: cx - rx + 40, y: cy - 30, width: 2 * rx - 80, height: 60 }, v.center, 16, { color: MUTED }));
      const at = (a: number) => ({ x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) });
      list.forEach((it, i) => {
        const a = -Math.PI / 2 + (i * 2 * Math.PI) / n;
        // Arrowhead on the ring, half way to the next stage: the direction of travel.
        const m = a + Math.PI / n;
        const p = at(m - 0.09);
        const q = at(m + 0.09);
        out.push(arrow(`a${i}`, p.x, p.y, q.x, q.y));
        const c = at(a);
        out.push(pill(`s${i}`, { x: c.x - 70, y: c.y - 22, width: 140, height: 44 }, it.label, 14));
      });
      break;
    }
    case "timeline": {
      if (!n) break;
      const ly = y0 + 34;
      out.push(line("axis", x0, ly, x0 + W, ly, INK, 1.5));
      const col = W / n;
      list.forEach((it, i) => {
        const cx = x0 + col * (i + 0.5);
        if (it.tag) out.push(label(`t${i}`, { x: cx - col / 2, y: y0, width: col, height: 22 }, it.tag, 13, { family: MONO }));
        out.push(dot(`p${i}`, cx, ly, 6));
        out.push(label(`l${i}`, { x: cx - col / 2 + 4, y: ly + 14, width: col - 8, height: 40 }, it.label, 14, { v: "top" }));
        if (it.detail) out.push(label(`d${i}`, { x: cx - col / 2 + 4, y: ly + 56, width: col - 8, height: 44 }, it.detail, 12, { color: MUTED, v: "top" }));
      });
      break;
    }
    case "bars": {
      if (!n) break;
      const labelW = 170;
      const valueW = 170;
      const track = W - labelW - valueW - 16;
      const values = list.map((i) => Math.abs(i.value ?? 0));
      const max = Math.max(...values, 1e-9);
      const min = Math.min(...values.filter((x) => x > 0), max);
      // Values a thousand times apart: a log scale, or the small ones vanish.
      const log = max / min >= 1000;
      const lo = Math.log10(min) - 1;
      const share = (x: number) => (log ? (x > 0 ? (Math.log10(x) - lo) / (Math.log10(max) - lo) : 0) : x / max);
      if (log) out.push(text("log", x0 + W - 90, box.y, "LOG SCALE", 11, MONO, MUTED));
      const row = Math.min(44, 210 / n);
      list.forEach((it, i) => {
        const ry = y0 + i * row;
        const value = values[i]!;
        out.push(label(`l${i}`, { x: x0, y: ry, width: labelW - 8, height: row - 6 }, it.label, 14, { align: "left" }));
        out.push({ ...base, type: "rectangle", id: id(`track${i}`), x: x0 + labelW, y: ry + (row - 6) / 2 - 7, width: track, height: 14, backgroundColor: SOFT, fillStyle: "solid", strokeColor: "transparent", roundness: { type: 3 }, customData: data });
        out.push({ ...base, type: "rectangle", id: id(`bar${i}`), x: x0 + labelW, y: ry + (row - 6) / 2 - 7, width: Math.max(4, track * share(value)), height: 14, backgroundColor: value === max ? SIGNAL : MUTED, fillStyle: "solid", strokeColor: "transparent", roundness: { type: 3 }, customData: data });
        out.push(label(`v${i}`, { x: x0 + labelW + track + 12, y: ry, width: valueW, height: row - 6 }, `${fmt(it.value ?? 0)}${v.unit ? ` ${v.unit}` : ""}`, 12, { align: "left", family: MONO }));
      });
      break;
    }
    case "parts": {
      const cx = x0 + W / 2;
      const cy = y0 + 112;
      out.push(pill("center", { x: cx - 90, y: cy - 34, width: 180, height: 68 }, v.center ?? "", 16, SOFT));
      const left = list.filter((_, i) => i % 2 === 0);
      const right = list.filter((_, i) => i % 2 === 1);
      const side = (group: VisualItem[], onLeft: boolean) =>
        group.forEach((it, j) => {
          const k = onLeft ? j * 2 : j * 2 + 1;
          const py = y0 + ((j + 0.5) * 224) / Math.max(group.length, 1);
          const px = onLeft ? x0 : x0 + W - 190;
          out.push(pill(`p${k}`, { x: px, y: py - 20, width: 190, height: 40 }, it.label, 14));
          const ex = onLeft ? px + 190 : px;
          out.push(line(`l${k}`, ex, py, onLeft ? cx - 90 : cx + 90, cy + (py - cy) * 0.35));
          out.push(dot(`e${k}`, ex, py, 3));
        });
      side(left, true);
      side(right, false);
      break;
    }
    case "stat": {
      const value = (v.value ?? "").slice(0, 12);
      out.push(text("value", x0, y0, value, 60, SANS, INK));
      if (v.unit) out.push(text("unit", x0 + value.length * 60 * 0.58 + 10, y0 + 34, v.unit.slice(0, 16).toUpperCase(), 20, MONO, MUTED));
      break;
    }
    case "formula": {
      out.push(label("expr", { x: x0, y: y0, width: W, height: 44 }, (v.text ?? "").slice(0, 40), 30, { align: "left" }));
      list.forEach((it, i) => {
        const ry = y0 + 52 + i * 26;
        out.push(text(`s${i}`, x0, ry, it.label.slice(0, 6), 15, MONO, INK));
        if (it.detail) out.push(text(`d${i}`, x0 + 64, ry + 1, it.detail.slice(0, 34), 14, SANS, MUTED));
      });
      break;
    }
    case "live":
    case "model3d":
    case "diorama":
    case "ui": {
      // The slot: what exports, previews and the dive animation show; the running model sits on top of it.
      out.push({
        ...base, type: "rectangle", id: id("live"), x: x0, y: y0, width: W, height: visualHeight(v) - FIG_LABEL_H, backgroundColor: SOFT, fillStyle: "solid",
        strokeColor: HAIR, strokeWidth: 1, roundness: { type: 3 }, customData: { cardId, role: "live" },
        label: { text: v.html || v.spec ? "" : t.building(), fontSize: 14, fontFamily: MONO, strokeColor: MUTED, customData: { cardId, role: "label" } } as never,
      });
      break;
    }
    case "graph": {
      if (!n) break;
      const sizes = list.map((it) => ({ w: Math.min(190, Math.max(96, it.label.length * 8 + 34)), h: 40 }));
      const index = new Map(list.map((it, i) => [it.label.trim().toLowerCase(), i]));
      const links = (v.links ?? [])
        .map((l) => ({ a: index.get(l.from.trim().toLowerCase()), b: index.get(l.to.trim().toLowerCase()), label: l.label }))
        .filter((l): l is { a: number; b: number; label: string | undefined } => l.a !== undefined && l.b !== undefined && l.a !== l.b)
        .slice(0, 12);
      const pos = layoutGraph(sizes, links.map((l) => [l.a, l.b]), { x: x0, y: y0, width: W, height: 286 });
      // Edges first so the pills sit on top of them.
      links.forEach((l, i) => {
        const A = pos[l.a]!;
        const B = pos[l.b]!;
        const p = exitPoint(A, sizes[l.a]!.w / 2, sizes[l.a]!.h / 2, B);
        const q = exitPoint(B, sizes[l.b]!.w / 2, sizes[l.b]!.h / 2, A, 7);
        out.push(arrow(`e${i}`, p.x, p.y, q.x, q.y, MUTED));
        if (l.label) {
          const lw = Math.min(150, l.label.length * 6.6 + 12);
          // Steep edges are short between stacked pills: label beside the arrow, not over it.
          const steep = Math.abs(q.x - p.x) < Math.abs(q.y - p.y);
          out.push({
            ...base, type: "rectangle", id: id(`el${i}`), x: steep ? (p.x + q.x) / 2 + 6 : (p.x + q.x) / 2 - lw / 2, y: (p.y + q.y) / 2 - 10,
            width: lw, height: 20, backgroundColor: steep ? "transparent" : FACE, fillStyle: "solid", strokeColor: "transparent",
            roundness: { type: 3 }, customData: data,
            label: { text: l.label, fontSize: 11, fontFamily: MONO, strokeColor: MUTED, textAlign: steep ? "left" : "center", customData: { cardId, role: "label" } } as never,
          });
        }
      });
      list.forEach((it, i) => {
        const P = pos[i]!;
        const z = sizes[i]!;
        out.push(pill(`n${i}`, { x: P.cx - z.w / 2, y: P.cy - z.h / 2, width: z.w, height: z.h }, it.label, 14, i === 0 ? SOFT : RAISED));
      });
      break;
    }
    case "table": {
      const cols = (v.columns ?? []).slice(0, TABLE_COLS);
      const rows = (v.rows ?? []).slice(0, TABLE_ROWS).map((r) => r.slice(0, Math.max(cols.length, 1)));
      const nc = Math.max(cols.length, ...rows.map((r) => r.length), 1);
      // The first column names the row: a little wider.
      const firstW = W * (nc > 1 ? 0.28 : 1);
      const colW = nc > 1 ? (W - firstW) / (nc - 1) : 0;
      const cx = (c: number) => (c === 0 ? x0 : x0 + firstW + (c - 1) * colW);
      const cw = (c: number) => (c === 0 ? firstW : colW);
      // Numbers line up on the right; words read from the left. A column is numeric if all its cells are.
      const isNum = (cell: string) => /^[-+~≈<>]?\s*[\d.,]+\s*\S{0,6}$/.test(cell.trim());
      const numericCol = (c: number) => c > 0 && rows.length > 0 && rows.every((r) => !r[c] || isNum(r[c]!));
      const align = (c: number) => (numericCol(c) ? "right" : "left");
      cols.forEach((h, c) => out.push(label(`h${c}`, { x: cx(c) + 4, y: y0, width: cw(c) - 8, height: 24 }, h.toUpperCase(), 11, { align: align(c), family: MONO, color: MUTED })));
      out.push(line("hr", x0, y0 + 28, x0 + W, y0 + 28, INK, 1.5));
      rows.forEach((row, r) => {
        const ry = y0 + 30 + r * TABLE_ROW_H;
        row.forEach((cell, c) => {
          out.push(label(`c${r}_${c}`, { x: cx(c) + 4, y: ry, width: cw(c) - 8, height: TABLE_ROW_H }, cell, c === 0 ? 14 : 13,
            { align: align(c), family: numericCol(c) ? MONO : SANS, color: INK }));
        });
        if (r < rows.length - 1) out.push(line(`r${r}`, x0, ry + TABLE_ROW_H, x0 + W, ry + TABLE_ROW_H, SOFT, 1));
      });
      break;
    }
    case "chart": {
      const series = (v.series ?? []).slice(0, 3).map((s) => ({ ...s, points: s.points.filter((p) => p.every(Number.isFinite)).slice(0, 40) }))
        .filter((s) => s.points.length > 0);
      if (!series.length) break;
      const pts = series.flatMap((s) => s.points);
      const log = !!v.logY && pts.every(([, y]) => y > 0);
      const xs = pts.map(([x]) => x);
      const ys = pts.map(([, y]) => y);
      const xT = niceTicks(Math.min(...xs), Math.max(...xs), 6);
      const yT = log ? logTicks(Math.min(...ys), Math.max(...ys)) : niceTicks(Math.min(0, ...ys), Math.max(...ys), 5);
      const [xa, xb] = [xT[0]!, xT[xT.length - 1]!];
      const [ya, yb] = [yT[0]!, yT[yT.length - 1]!];
      const left = x0 + 52;
      const right = x0 + W - 8;
      const top = y0 + 26;
      const bottom = y0 + 214;
      const px = (x: number) => left + ((x - xa) / (xb - xa || 1)) * (right - left);
      const py = (y: number) => bottom - (log ? (Math.log10(y) - Math.log10(ya)) / (Math.log10(yb) - Math.log10(ya) || 1) : (y - ya) / (yb - ya || 1)) * (bottom - top);
      // Grid and ticks.
      yT.forEach((t, i) => {
        out.push(line(`gy${i}`, left, py(t), right, py(t), i === 0 ? INK : SOFT, i === 0 ? 1.5 : 1));
        out.push(label(`ty${i}`, { x: x0, y: py(t) - 9, width: 46, height: 18 }, tickLabel(t), 11, { align: "right", family: MONO, color: MUTED }));
      });
      out.push(line("ax", left, top - 6, left, bottom, INK, 1.5));
      xT.forEach((t, i) => out.push(label(`tx${i}`, { x: px(t) - 30, y: bottom + 4, width: 60, height: 18 }, tickLabel(t), 11, { family: MONO, color: MUTED })));
      if (v.xLabel) out.push(label("xl", { x: left, y: bottom + 22, width: right - left, height: 18 }, v.xLabel.toUpperCase(), 11, { family: MONO, color: MUTED }));
      if (v.yLabel) out.push(text("yl", left + 6, y0, `${v.yLabel.toUpperCase()}${log ? " · LOG" : ""}`, 11, MONO, MUTED));
      // Series: a polyline (line plot) or dots (scatter), and a legend top-right.
      series.forEach((s, si) => {
        const st = SERIES_STYLE[si]!;
        const sorted = v.plot === "scatter" ? s.points : [...s.points].sort((a, b) => a[0] - b[0]);
        if (v.plot !== "scatter" && sorted.length > 1) {
          const [fx, fy] = [px(sorted[0]![0]), py(sorted[0]![1])];
          out.push({
            ...base, type: "line", id: id(`s${si}`), x: fx, y: fy, strokeColor: st.color, strokeWidth: 2, strokeStyle: st.dash,
            points: sorted.map(([x, y]) => [px(x) - fx, py(y) - fy]), customData: data,
          } as Skeleton);
        }
        sorted.forEach(([x, y], pi) => {
          if (v.plot === "scatter" || sorted.length <= 12) out.push(dot(`p${si}_${pi}`, px(x), py(y), v.plot === "scatter" ? 4 : 3, st.color));
        });
        if (series.length > 1 || s.label) {
          const ly = y0 + 2 + si * 16;
          out.push(line(`lg${si}`, right - 150, ly + 8, right - 130, ly + 8, st.color, 2));
          out.push(text(`lt${si}`, right - 124, ly, s.label.slice(0, 20), 12, SANS, INK));
        }
      });
      break;
    }
    case "code": {
      const lines = codeLines(v);
      out.push({ ...base, type: "rectangle", id: id("block"), x: x0, y: y0, width: W, height: Math.max(1, lines.length) * CODE_LINE_H + 24, backgroundColor: FACE_LOW, fillStyle: "solid", strokeColor: EDGE, roundness: { type: 3 }, customData: data });
      out.push({ ...base, type: "text", id: id("code"), x: x0 + 16, y: y0 + 12, text: lines.join("\n") || " ", fontSize: 14, fontFamily: MONO, strokeColor: SIGNAL, lineHeight: (CODE_LINE_H / 14) as never, customData: data });
      break;
    }
  }
  return out;
}

export function fmt(n: number): string {
  const a = Math.abs(n);
  if (a >= 1000) return Math.round(n).toLocaleString("en-US");
  if (a > 0 && a < 1) return String(Number(n.toPrecision(2)));
  return String(Math.round(n * 100) / 100);
}
