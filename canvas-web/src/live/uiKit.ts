/**
 * Generative UI: the agent describes an interactive learning widget as a spec
 * (state + blocks) and this kit builds it, in ENJIN's white/black/glass look.
 * Blocks: heading, text ({{expr}} interpolation), slider, toggle, choice,
 * readout, meter, plot, quiz, steps, flashcards, order, row.
 *
 * Self-contained (its source is injected into a sandboxed frame); `compile` is
 * compileExpr from expr.ts, passed in.
 */
export function mountUI(root: HTMLElement, spec: any, compile: (src: string) => (vars: Record<string, number>) => number): void {
  const state: Record<string, number> = {};
  for (const [k, v] of Object.entries(spec?.state ?? {})) state[k] = typeof v === "boolean" ? (v ? 1 : 0) : Number(v) || 0;
  const updaters: (() => void)[] = [];
  const refresh = () => updaters.forEach((u) => { try { u(); } catch { /* one bad block never stops the rest */ } });
  const cache = new Map<string, (v: Record<string, number>) => number>();
  const evalExpr = (src: string): number => {
    let f = cache.get(src);
    if (!f) { try { f = compile(src); } catch { f = () => NaN; } cache.set(src, f); }
    return f(state);
  };
  const fmt = (x: number, digits?: number) => {
    if (!Number.isFinite(x)) return "–";
    if (digits !== undefined) return x.toFixed(digits);
    const a = Math.abs(x);
    if (a >= 1e6 || (a > 0 && a < 1e-3)) return x.toExponential(2);
    return String(Math.round(x * 1000) / 1000);
  };
  const interp = (s: string) => String(s ?? "").replace(/\{\{([^}]+)\}\}/g, (_, e: string) => {
    const [expr, d] = e.split("|");
    return fmt(evalExpr(expr!.trim()), d ? Number(d) : undefined);
  });
  const el = (tag: string, cls?: string, text?: string) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
  };

  const css = el("style");
  css.textContent = `
  .ui{box-sizing:border-box;height:100%;overflow:auto;padding:22px 24px 26px;display:flex;flex-direction:column;gap:16px;
    font:15px/1.45 Inter,-apple-system,system-ui,sans-serif;color:#0b0b0c;background:linear-gradient(#fff,#f7f7f6);-webkit-user-select:none;user-select:none}
  .ui *{box-sizing:border-box}
  .h{font:700 20px/1.2 Inter,-apple-system,sans-serif;letter-spacing:-.2px;margin:0}
  .t{color:#3a3a3e;margin:0}
  .lab{font:600 11px ui-monospace,Menlo,monospace;letter-spacing:1.4px;text-transform:uppercase;color:#66666b}
  .row{display:flex;gap:14px;flex-wrap:wrap}.row>*{flex:1 1 160px}
  .glass{background:rgba(255,255,255,.7);border-radius:16px;box-shadow:inset 0 1px 0 #fff,0 0 0 .75px rgba(0,0,0,.08),0 8px 22px rgba(0,0,0,.06);padding:14px 16px}
  .sl{display:flex;flex-direction:column;gap:8px}.slh{display:flex;justify-content:space-between;align-items:baseline}
  .val{font:600 15px ui-monospace,Menlo,monospace}
  input[type=range]{-webkit-appearance:none;appearance:none;width:100%;height:4px;border-radius:4px;background:#e0e0de;outline:none}
  input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:26px;height:26px;border-radius:50%;background:#0b0b0c;box-shadow:0 3px 8px rgba(0,0,0,.25),inset 0 0 0 3px #fff}
  .big{font:700 30px/1.1 Inter,-apple-system,sans-serif;letter-spacing:-.5px}.unit{font:600 13px ui-monospace,Menlo,monospace;color:#66666b;margin-left:6px}
  .meter{height:10px;border-radius:6px;background:#ececea;overflow:hidden}.meter>i{display:block;height:100%;background:#0b0b0c;border-radius:6px;transition:width .15s}
  .pill{font:600 14px Inter,-apple-system,sans-serif;border:0;border-radius:999px;padding:9px 16px;background:#f4f4f3;color:#0b0b0c;box-shadow:0 0 0 .75px rgba(0,0,0,.1)}
  .pill.on,.pill.primary{background:#0b0b0c;color:#fff;box-shadow:0 4px 10px rgba(0,0,0,.18)}
  .pill:active{transform:scale(.96)}
  .opts{display:flex;flex-wrap:wrap;gap:8px}
  .opt{text-align:left;font:500 15px Inter,-apple-system,sans-serif;border:0;border-radius:14px;padding:12px 14px;background:#f4f4f3;color:#0b0b0c;box-shadow:0 0 0 .75px rgba(0,0,0,.08);flex:1 1 200px}
  .opt.right{background:#0b0b0c;color:#fff}.opt.wrong{box-shadow:0 0 0 1.5px #d63b3b;color:#d63b3b}
  .note{font-size:14px;color:#3a3a3e;padding-top:4px}
  .card{min-height:120px;display:flex;align-items:center;justify-content:center;text-align:center;font:600 19px/1.3 Inter,-apple-system,sans-serif;cursor:pointer}
  .nav{display:flex;align-items:center;justify-content:space-between;gap:10px}
  .ord{display:flex;flex-direction:column;gap:8px}.ord .opt{display:flex;gap:10px;align-items:center}
  .ord .n{font:600 12px ui-monospace,Menlo,monospace;color:#66666b;width:22px}
  canvas.plot{width:100%;height:180px;display:block}
  `;
  root.appendChild(css);
  const ui = el("div", "ui");
  root.appendChild(ui);

  const block = (b: any): HTMLElement => {
    switch (b?.type) {
      case "heading": return el("h2", "h", String(b.text ?? ""));
      case "text": {
        const p = el("p", "t");
        const up = () => { p.textContent = interp(b.text); };
        updaters.push(up); up();
        return p;
      }
      case "slider": {
        const wrap = el("div", "sl glass");
        const head = el("div", "slh");
        const lab = el("span", "lab", String(b.label ?? b.var));
        const val = el("span", "val");
        head.append(lab, val);
        const input = document.createElement("input");
        input.type = "range";
        const min = Number(b.min ?? 0), max = Number(b.max ?? 100);
        input.min = String(min); input.max = String(max); input.step = String(b.step ?? (max - min) / 100);
        if (!(b.var in state)) state[b.var] = Number(b.value ?? min);
        input.value = String(state[b.var]);
        input.oninput = () => { state[b.var] = Number(input.value); refresh(); };
        const up = () => { val.textContent = `${fmt(state[b.var]!)}${b.unit ? ` ${b.unit}` : ""}`; };
        updaters.push(up); up();
        wrap.append(head, input);
        return wrap;
      }
      case "toggle": {
        const btn = el("button", "pill", String(b.label ?? b.var)) as HTMLButtonElement;
        const up = () => btn.classList.toggle("on", !!state[b.var]);
        btn.onclick = () => { state[b.var] = state[b.var] ? 0 : 1; refresh(); };
        updaters.push(up); up();
        return btn;
      }
      case "choice": {
        const wrap = el("div", "opts");
        if (b.label) wrap.appendChild(el("span", "lab", String(b.label)));
        for (const o of b.options ?? []) {
          const btn = el("button", "pill", String(o.label)) as HTMLButtonElement;
          btn.onclick = () => { state[b.var] = Number(o.value); refresh(); };
          updaters.push(() => btn.classList.toggle("on", state[b.var] === Number(o.value)));
          wrap.appendChild(btn);
        }
        refresh();
        return wrap;
      }
      case "readout": {
        const wrap = el("div", "glass");
        const lab = el("div", "lab", String(b.label ?? ""));
        const line = el("div");
        const big = el("span", "big");
        const unit = el("span", "unit", b.unit ? String(b.unit) : "");
        line.append(big, unit);
        wrap.append(lab, line);
        const up = () => { big.textContent = fmt(evalExpr(String(b.expr)), b.digits); };
        updaters.push(up); up();
        return wrap;
      }
      case "meter": {
        const wrap = el("div", "sl");
        const head = el("div", "slh");
        const lab = el("span", "lab", String(b.label ?? ""));
        const val = el("span", "val");
        head.append(lab, val);
        const bar = el("div", "meter");
        const fill = el("i");
        bar.appendChild(fill);
        wrap.append(head, bar);
        const up = () => {
          const x = evalExpr(String(b.expr));
          const max = Number(b.max ?? 1);
          fill.style.width = `${Math.max(0, Math.min(1, x / max)) * 100}%`;
          val.textContent = `${fmt(x)}${b.unit ? ` ${b.unit}` : ""}`;
        };
        updaters.push(up); up();
        return wrap;
      }
      case "plot": {
        const wrap = el("div", "glass");
        if (b.label) wrap.appendChild(el("div", "lab", String(b.label)));
        const c = document.createElement("canvas");
        c.className = "plot";
        wrap.appendChild(c);
        const draw = () => {
          const dpr = devicePixelRatio || 1;
          const W = c.clientWidth || 400, H = c.clientHeight || 180;
          c.width = W * dpr; c.height = H * dpr;
          const g = c.getContext("2d")!;
          g.setTransform(dpr, 0, 0, dpr, 0, 0);
          g.clearRect(0, 0, W, H);
          const x0 = Number(b.xmin ?? 0), x1 = Number(b.xmax ?? 10);
          const pts: [number, number][] = [];
          for (let i = 0; i <= 160; i++) {
            const x = x0 + ((x1 - x0) * i) / 160;
            const y = (() => { const f = compileSafe(String(b.expr)); return f({ ...state, x }); })();
            if (Number.isFinite(y)) pts.push([x, y]);
          }
          const ys = pts.map((p) => p[1]);
          const y0 = b.ymin !== undefined ? Number(b.ymin) : Math.min(0, ...ys);
          const y1 = b.ymax !== undefined ? Number(b.ymax) : Math.max(...ys, y0 + 1e-9);
          const L = 34, R = 8, T = 8, B = 22;
          const px = (x: number) => L + ((x - x0) / (x1 - x0 || 1)) * (W - L - R);
          const py = (y: number) => H - B - ((y - y0) / (y1 - y0 || 1)) * (H - T - B);
          g.strokeStyle = "#e0e0de"; g.lineWidth = 1;
          g.beginPath(); g.moveTo(L, T); g.lineTo(L, H - B); g.lineTo(W - R, H - B); g.stroke();
          g.fillStyle = "#66666b"; g.font = "600 10px ui-monospace,Menlo,monospace";
          g.fillText(fmt(y1), 2, T + 8); g.fillText(fmt(y0), 2, H - B);
          g.fillText(fmt(x0), L, H - 6); const xr = fmt(x1); g.fillText(xr, W - R - g.measureText(xr).width, H - 6);
          if (b.xLabel) { const t = String(b.xLabel).toUpperCase(); g.fillText(t, (W - g.measureText(t).width) / 2, H - 6); }
          g.strokeStyle = "#0b0b0c"; g.lineWidth = 2; g.lineJoin = "round";
          g.beginPath();
          pts.forEach(([x, y], i) => (i ? g.lineTo(px(x), py(y)) : g.moveTo(px(x), py(y))));
          g.stroke();
          if (b.marker) {
            const mx = evalExpr(String(b.marker));
            const f = compileSafe(String(b.expr));
            const my = f({ ...state, x: mx });
            if (Number.isFinite(mx) && Number.isFinite(my)) {
              g.fillStyle = "#e8590c"; g.beginPath(); g.arc(px(mx), py(my), 5, 0, 7); g.fill();
            }
          }
        };
        updaters.push(draw);
        requestAnimationFrame(draw);
        return wrap;
      }
      case "quiz": {
        const wrap = el("div", "glass");
        wrap.appendChild(el("div", "lab", "Check yourself"));
        wrap.appendChild(el("p", "h", String(b.question ?? "")));
        const opts = el("div", "opts");
        const note = el("div", "note");
        (b.options ?? []).forEach((o: string, i: number) => {
          const btn = el("button", "opt", String(o)) as HTMLButtonElement;
          btn.onclick = () => {
            const right = i === Number(b.answer);
            btn.classList.add(right ? "right" : "wrong");
            if (right) note.textContent = String(b.explain ?? "");
          };
          opts.appendChild(btn);
        });
        wrap.append(opts, note);
        return wrap;
      }
      case "steps": {
        const items: any[] = b.items ?? [];
        let at = 0;
        const wrap = el("div", "glass");
        const lab = el("div", "lab");
        const title = el("p", "h");
        const text = el("p", "t");
        const nav = el("div", "nav");
        const prev = el("button", "pill", "‹ Back") as HTMLButtonElement;
        const next = el("button", "pill primary", "Next ›") as HTMLButtonElement;
        nav.append(prev, next);
        const show = () => {
          const it = items[at] ?? {};
          lab.textContent = `Step ${at + 1} / ${items.length}`;
          title.textContent = String(it.title ?? "");
          text.textContent = interp(it.text ?? "");
          prev.style.visibility = at > 0 ? "visible" : "hidden";
          next.style.visibility = at < items.length - 1 ? "visible" : "hidden";
        };
        prev.onclick = () => { at = Math.max(0, at - 1); show(); };
        next.onclick = () => { at = Math.min(items.length - 1, at + 1); show(); };
        wrap.append(lab, title, text, nav);
        show();
        return wrap;
      }
      case "flashcards": {
        const cards: any[] = b.cards ?? [];
        let at = 0, flipped = false;
        const wrap = el("div", "sl");
        const card = el("div", "glass card");
        const nav = el("div", "nav");
        const lab = el("span", "lab");
        const next = el("button", "pill primary", "Next ›") as HTMLButtonElement;
        nav.append(lab, next);
        const show = () => {
          const c = cards[at] ?? {};
          card.textContent = String(flipped ? c.back : c.front);
          card.style.background = flipped ? "#0b0b0c" : "";
          card.style.color = flipped ? "#fff" : "";
          lab.textContent = `${at + 1} / ${cards.length} · tap to flip`;
        };
        card.onclick = () => { flipped = !flipped; show(); };
        next.onclick = () => { at = (at + 1) % Math.max(1, cards.length); flipped = false; show(); };
        wrap.append(card, nav);
        show();
        return wrap;
      }
      case "order": {
        // Tap items in the right order (e.g. steps of a process); wrong taps shake.
        const items: string[] = (b.items ?? []).map(String);
        const shuffled = items.map((s, i) => ({ s, i, k: Math.sin(i * 12.9898 + items.length) })).sort((a, z) => a.k - z.k);
        let next = 0;
        const wrap = el("div", "glass");
        wrap.appendChild(el("div", "lab", String(b.prompt ?? "Put these in order")));
        const list = el("div", "ord");
        for (const it of shuffled) {
          const btn = el("button", "opt") as HTMLButtonElement;
          const n = el("span", "n", "·");
          btn.append(n, document.createTextNode(it.s));
          btn.onclick = () => {
            if (it.i === next) { btn.classList.add("right"); n.textContent = String(++next); }
            else { btn.classList.add("wrong"); setTimeout(() => btn.classList.remove("wrong"), 500); }
          };
          list.appendChild(btn);
        }
        wrap.appendChild(list);
        return wrap;
      }
      case "row": {
        const r = el("div", "row");
        for (const c of b.blocks ?? []) r.appendChild(block(c));
        return r;
      }
      default:
        return el("div");
    }
  };
  const compileSafe = (src: string) => {
    try { return compile(src); } catch { return () => NaN; }
  };
  for (const b of spec?.blocks ?? []) ui.appendChild(block(b));
  refresh();
}
