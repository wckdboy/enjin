/**
 * A safe arithmetic expression compiler for generative UI: numbers, variables,
 * + - * / % ^, parentheses, comparisons, `cond ? a : b`, and math functions.
 * No property access, no calls except the whitelist, no strings: model-written
 * formulas can't do anything but compute a number.
 *
 * Self-contained on purpose: its source is injected into sandboxed live frames
 * (`compileExpr.toString()`), so it must not reference anything outside itself.
 */
export function compileExpr(src: string): (vars: Record<string, number>) => number {
  const FUNCS: Record<string, (...a: number[]) => number> = {
    sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan, atan2: Math.atan2,
    sqrt: Math.sqrt, abs: Math.abs, exp: Math.exp, ln: Math.log, log: Math.log10, log2: Math.log2,
    min: Math.min, max: Math.max, pow: Math.pow, floor: Math.floor, ceil: Math.ceil, round: Math.round, sign: Math.sign,
    clamp: (x, lo, hi) => Math.min(hi, Math.max(lo, x)),
  };
  const CONSTS: Record<string, number> = { pi: Math.PI, e: Math.E, g: 9.81, c: 299792458 };
  type Tok = { t: "num"; v: number } | { t: "id"; v: string } | { t: "op"; v: string };
  const toks: Tok[] = [];
  let i = 0;
  while (i < src.length) {
    const ch = src[i]!;
    if (/\s/.test(ch)) { i++; continue; }
    const num = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(src.slice(i));
    if (num) { toks.push({ t: "num", v: parseFloat(num[0]) }); i += num[0].length; continue; }
    const id = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i));
    if (id) { toks.push({ t: "id", v: id[0] }); i += id[0].length; continue; }
    const op = /^(<=|>=|==|!=|&&|\|\||[-+*/%^()?:,<>!×·÷−])/.exec(src.slice(i));
    if (!op) throw new Error(`unexpected "${ch}"`);
    const norm: Record<string, string> = { "×": "*", "·": "*", "÷": "/", "−": "-" };
    toks.push({ t: "op", v: norm[op[0]] ?? op[0] });
    i += op[0].length;
  }
  let p = 0;
  const peek = () => toks[p];
  const eat = (v?: string) => {
    const tk = toks[p];
    if (!tk || (v !== undefined && (tk.t !== "op" || tk.v !== v))) throw new Error(`expected ${v ?? "a value"}`);
    p++;
    return tk;
  };
  type Node = (vars: Record<string, number>) => number;
  const BIN: Record<string, [number, (a: number, b: number) => number]> = {
    "||": [1, (a, b) => (a || b ? 1 : 0)], "&&": [2, (a, b) => (a && b ? 1 : 0)],
    "==": [3, (a, b) => (a === b ? 1 : 0)], "!=": [3, (a, b) => (a !== b ? 1 : 0)],
    "<": [4, (a, b) => (a < b ? 1 : 0)], ">": [4, (a, b) => (a > b ? 1 : 0)], "<=": [4, (a, b) => (a <= b ? 1 : 0)], ">=": [4, (a, b) => (a >= b ? 1 : 0)],
    "+": [5, (a, b) => a + b], "-": [5, (a, b) => a - b],
    "*": [6, (a, b) => a * b], "/": [6, (a, b) => a / b], "%": [6, (a, b) => a % b],
  };
  const primary = (): Node => {
    const tk = eat();
    if (tk.t === "num") return () => tk.v;
    if (tk.t === "op" && tk.v === "(") { const n = ternary(); eat(")"); return n; }
    if (tk.t === "op" && tk.v === "-") { const n = power(); return (v) => -n(v); }
    if (tk.t === "op" && tk.v === "+") return power();
    if (tk.t === "op" && tk.v === "!") { const n = power(); return (v) => (n(v) ? 0 : 1); }
    if (tk.t === "id") {
      const name = tk.v;
      const next = peek();
      if (next && next.t === "op" && next.v === "(") {
        const f = FUNCS[name];
        if (!f) throw new Error(`unknown function ${name}`);
        eat("(");
        const args: Node[] = [];
        if (!(peek()?.t === "op" && peek()?.v === ")")) {
          args.push(ternary());
          while (peek()?.t === "op" && peek()?.v === ",") { eat(","); args.push(ternary()); }
        }
        eat(")");
        return (v) => f(...args.map((a) => a(v)));
      }
      if (name in CONSTS) { const k = CONSTS[name]!; return (v) => (name in v ? v[name]! : k); }
      return (v) => v[name] ?? 0;
    }
    throw new Error("unexpected token");
  };
  const power = (): Node => {
    const base = primary();
    if (peek()?.t === "op" && peek()?.v === "^") { eat("^"); const ex = power(); return (v) => Math.pow(base(v), ex(v)); }
    return base;
  };
  const binary = (minPrec: number): Node => {
    let left = power();
    for (;;) {
      const tk = peek();
      const entry = tk && tk.t === "op" ? BIN[tk.v] : undefined;
      if (!entry || entry[0] < minPrec) return left;
      eat();
      const right = binary(entry[0] + 1);
      const l = left, fn = entry[1];
      left = (v) => fn(l(v), right(v));
    }
  };
  const ternary = (): Node => {
    const cond = binary(1);
    if (peek()?.t === "op" && peek()?.v === "?") {
      eat("?"); const a = ternary(); eat(":"); const b = ternary();
      return (v) => (cond(v) ? a(v) : b(v));
    }
    return cond;
  };
  const root = ternary();
  if (p < toks.length) throw new Error("unexpected trailing input");
  return (vars) => {
    const r = root(vars);
    return Number.isFinite(r) ? r : NaN;
  };
}
